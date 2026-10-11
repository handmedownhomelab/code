#!/usr/bin/env python3
"""comfy_video.py — Hand-Me-Down Homelab, section 7.4. Part of the comfyui-video skill.
Drive a local ComfyUI API to generate video. Two models, pick with --model:

  * wan  -> Wan 2.2 TI2V-5B   : best motion quality; ~8 min/clip; 1280x704 @ 24fps
  * ltx  -> LTX-Video 0.9.5   : fast draft / quick iteration; ~1 min; 768x512 @ 25fps

Length: pass EITHER --length (exact frames for one clip) OR --seconds (target
duration; the script picks single-pass vs. multi-segment chaining automatically).

Chaining (long videos): when --seconds exceeds what one clip can do, the script
renders several segments, each continuing from the previous segment's LAST FRAME
(image-to-video), then stitches them with ffmpeg. VRAM stays flat (one segment at
a time); render time is N x one segment, so LTX is the sensible engine for long.

Each model has a text-to-video template (describe a scene) and an image-to-video
template (animate a photo via --init). Talks to ComfyUI over the SSH tunnel at
127.0.0.1:8188. Loads an API-format workflow template, patches in prompt/params,
queues it, waits, pulls the .mp4 back, optionally opens it in the system player.

Examples:
  python3 comfy_video.py --check
  python3 comfy_video.py --model wan --show --prompt "a red fox in snow" \
      --out ~/forge_out/fox.mp4
  python3 comfy_video.py --model ltx --seconds 20 --show \
      --prompt "a paper boat drifting down a rain-slicked gutter, neon reflections" \
      --out ~/forge_out/boat.mp4          # auto-chains ~5 LTX segments
  python3 comfy_video.py --model ltx --init photo.jpg --seconds 12 --show \
      --prompt "slow push-in, snow falling, she smiles" --out ~/forge_out/a.mp4
"""
import argparse, json, math, os, subprocess, sys, time, uuid
import urllib.request, urllib.parse, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))

# Per-model templates, defaults, and length characteristics.
#   seg_len    = frames per chained segment (a comfortable native clip)
#   frame_step = valid frame counts are frame_step*k + 1 (VAE temporal compression)
#   single_max = most frames we trust in ONE pass before chaining is better
MODELS = {
    "wan": {
        "t2v": "wan22_5b_t2v.json", "i2v": "wan22_5b_i2v.json",
        "width": 1280, "height": 704, "fps": 24, "steps": 30, "cfg": 5.0,
        "seg_len": 121, "frame_step": 4, "single_max": 121,
    },
    "ltx": {
        "t2v": "ltx095_t2v.json", "i2v": "ltx095_i2v.json",
        "width": 768, "height": 512, "fps": 25, "steps": 30, "cfg": 3.0,
        "seg_len": 97, "frame_step": 8, "single_max": 233,
    },
}
DIM_NODES = ["Wan22ImageToVideoLatent", "EmptyLTXVLatentVideo", "LTXVImgToVideo"]


def api_get(host, path, timeout=30):
    with urllib.request.urlopen(f"http://{host}{path}", timeout=timeout) as r:
        return json.loads(r.read().decode())


def api_post(host, path, payload, timeout=60):
    req = urllib.request.Request(
        f"http://{host}{path}", data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def upload_image(host, path):
    fn = os.path.basename(path)
    with open(path, "rb") as f:
        data = f.read()
    b = "----comfyvid" + uuid.uuid4().hex
    body = b"".join([
        f"--{b}\r\n".encode(),
        f'Content-Disposition: form-data; name="image"; filename="{fn}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n", data, b"\r\n",
        f"--{b}\r\n".encode(),
        b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n',
        f"--{b}--\r\n".encode(),
    ])
    req = urllib.request.Request(
        f"http://{host}/upload/image", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={b}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        info = json.loads(r.read().decode())
    name = info["name"]
    return (info["subfolder"] + "/" + name) if info.get("subfolder") else name


def node_by(graph, class_type, title_contains=None):
    for nid, n in graph.items():
        if n.get("class_type") != class_type:
            continue
        if title_contains is None or title_contains.lower() in \
                n.get("_meta", {}).get("title", "").lower():
            return nid
    return None


def set_input(graph, nid, key, value):
    if nid is not None and nid in graph:
        graph[nid]["inputs"][key] = value


def collect_files(outputs):
    for node_out in outputs.values():
        for val in node_out.values():
            if isinstance(val, list):
                for item in val:
                    if isinstance(item, dict) and item.get("filename"):
                        yield item


def round_frames(frames, step):
    """Nearest valid frame count of the form step*k + 1 (>= step+1)."""
    k = max(1, round((frames - 1) / step))
    return step * k + 1


def render(host, model, prompt, neg, init, length, width, height, fps,
           steps, cfg, seed, out, timeout):
    """Render ONE segment to `out`. Returns elapsed seconds."""
    md = MODELS[model]
    tmpl = os.path.join(HERE, "templates", md["i2v" if init else "t2v"])
    with open(tmpl) as f:
        graph = json.load(f)
    set_input(graph, node_by(graph, "CLIPTextEncode", "Positive"), "text", prompt)
    set_input(graph, node_by(graph, "CLIPTextEncode", "Negative"), "text", neg)
    ks = node_by(graph, "KSampler")
    set_input(graph, ks, "seed", seed)
    set_input(graph, ks, "steps", steps)
    set_input(graph, ks, "cfg", cfg)
    for cls in DIM_NODES:
        nid = node_by(graph, cls)
        if nid:
            set_input(graph, nid, "width", width)
            set_input(graph, nid, "height", height)
            set_input(graph, nid, "length", length)
    set_input(graph, node_by(graph, "CreateVideo"), "fps", fps)
    set_input(graph, node_by(graph, "LTXVConditioning"), "frame_rate", fps)
    if init:
        set_input(graph, node_by(graph, "LoadImage"), "image",
                  upload_image(host, os.path.expanduser(init)))

    resp = api_post(host, "/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex})
    if resp.get("node_errors"):
        sys.exit("WORKFLOW ERROR:\n" + json.dumps(resp["node_errors"], indent=2))
    pid = resp["prompt_id"]
    t0 = time.time()
    hist = None
    while time.time() - t0 < timeout:
        h = api_get(host, f"/history/{pid}", timeout=15)
        if pid in h:
            hist = h[pid]
            break
        time.sleep(4)
    if hist is None:
        sys.exit(f"error: segment did not finish within {timeout}s")
    if hist.get("status", {}).get("status_str") == "error":
        sys.exit("EXECUTION ERROR:\n"
                 + json.dumps(hist["status"].get("messages", []), indent=2))
    vid = next((it for it in collect_files(hist.get("outputs", {}))
                if it["filename"].lower().endswith((".mp4", ".webm", ".mkv"))), None)
    if vid is None:
        sys.exit("error: no video in outputs:\n"
                 + json.dumps(hist.get("outputs", {}), indent=2))
    q = urllib.parse.urlencode({"filename": vid["filename"],
                                "subfolder": vid.get("subfolder", ""),
                                "type": vid.get("type", "output")})
    out = os.path.expanduser(out)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with urllib.request.urlopen(f"http://{host}/view?{q}", timeout=180) as r:
        open(out, "wb").write(r.read())
    return time.time() - t0


def last_frame(mp4, png):
    n = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                        "-show_entries", "stream=nb_frames", "-of",
                        "default=nk=1:nw=1", mp4], capture_output=True, text=True)
    idx = max(0, int(n.stdout.strip() or "1") - 1)
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", mp4, "-vf",
                    f"select=eq(n\\,{idx})", "-frames:v", "1", png], check=True)


def stitch(segments, out, fps):
    """Concat segments; drop frame 0 of continuations (it duplicates the init)."""
    prepared, tmp = [], []
    for i, seg in enumerate(segments):
        if i == 0:
            prepared.append(seg)
            continue
        t = seg.replace(".mp4", ".trim.mp4")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", seg, "-vf",
                        "select=gte(n\\,1),setpts=PTS-STARTPTS", "-r", str(fps),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", t], check=True)
        prepared.append(t); tmp.append(t)
    lst = out + ".concat.txt"
    with open(lst, "w") as f:
        for p in prepared:
            f.write(f"file '{os.path.abspath(p)}'\n")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", lst, "-r", str(fps), "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", out], check=True)
    for t in tmp + [lst]:
        try: os.remove(t)
        except OSError: pass


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1:8188")
    p.add_argument("--model", choices=list(MODELS), default="wan")
    p.add_argument("--prompt")
    p.add_argument("--neg", default=("low quality, worst quality, blurry, jpeg "
                   "artifacts, distorted, deformed, static, watermark, text"))
    p.add_argument("--init", help="photo to animate (image-to-video)")
    p.add_argument("--out", default=os.path.expanduser("~/forge_out/video.mp4"))
    p.add_argument("--seed", type=int, default=-1)
    p.add_argument("--seconds", type=float, help="target duration; auto single/chain")
    p.add_argument("--length", type=int, help="exact frames for ONE clip (overrides --seconds)")
    p.add_argument("--steps", type=int)
    p.add_argument("--cfg", type=float)
    p.add_argument("--width", type=int)
    p.add_argument("--height", type=int)
    p.add_argument("--fps", type=int)
    p.add_argument("--check", action="store_true")
    p.add_argument("--show", action="store_true")
    p.add_argument("--timeout", type=int, default=1800)
    args = p.parse_args()

    if args.check:
        stats = api_get(args.host, "/system_stats", timeout=10)
        dev = (stats.get("devices") or [{}])[0]
        print("comfyui: up |", dev.get("name"), "| vram_free_mb:",
              int(dev.get("vram_free", 0)) // (1024 * 1024))
        for cls, key in [("UNETLoader", "unet_name"),
                         ("CheckpointLoaderSimple", "ckpt_name")]:
            names = api_get(args.host, f"/object_info/{cls}")[cls]["input"]["required"][key][0]
            print(f"{key}:", ", ".join(names) or "(none)")
        return

    if not args.prompt:
        sys.exit("error: --prompt is required (or use --check)")

    md = MODELS[args.model]
    for k in ("steps", "cfg", "width", "height", "fps"):
        if getattr(args, k) is None:
            setattr(args, k, md[k])
    if args.seed < 0:
        args.seed = uuid.uuid4().int % (2 ** 32)
    out = os.path.expanduser(args.out)

    # ---- plan length: explicit --length, else --seconds, else one native clip ----
    if args.length:
        n_seg, seg_len = 1, round_frames(args.length, md["frame_step"])
    elif args.seconds:
        want = args.seconds * args.fps
        if want <= md["single_max"]:
            n_seg, seg_len = 1, round_frames(want, md["frame_step"])
        else:
            seg_len = md["seg_len"]
            usable = seg_len - 1          # each continuation drops its dup first frame
            n_seg = max(2, math.ceil((want - 1) / usable))
    else:
        n_seg, seg_len = 1, md["seg_len"]

    seg_sec = seg_len / args.fps
    t_start = time.time()

    if n_seg == 1:
        print(f"model:   {args.model}  ({'i2v' if args.init else 't2v'}), single pass")
        print(f"plan:    {seg_len}f @ {args.fps}fps (~{seg_sec:.1f}s), "
              f"{args.width}x{args.height}, seed {args.seed}")
        el = render(args.host, args.model, args.prompt, args.neg, args.init, seg_len,
                    args.width, args.height, args.fps, args.steps, args.cfg,
                    args.seed, out, args.timeout)
        print(f"saved:   {out}\nseed:    {args.seed}\nelapsed: {el:.1f}s")
    else:
        total_sec = (1 + n_seg * (seg_len - 1)) / args.fps
        print(f"model:   {args.model}  CHAINED {n_seg} segments "
              f"(~{seg_sec:.1f}s each -> ~{total_sec:.1f}s total)")
        print(f"plan:    {args.width}x{args.height} @ {args.fps}fps; each segment "
              f"continues from the previous last frame")
        base = out[:-4] if out.endswith(".mp4") else out
        segs = []
        for i in range(n_seg):
            seg_out = f"{base}.seg{i+1:02d}.mp4"
            init = args.init if i == 0 else f"{base}.seg{i:02d}.last.png"
            seed = (args.seed + i) % (2 ** 32)
            print(f"  seg {i+1}/{n_seg}: {'i2v' if init else 't2v'} seed {seed} ...",
                  end="", flush=True)
            el = render(args.host, args.model, args.prompt, args.neg, init, seg_len,
                        args.width, args.height, args.fps, args.steps, args.cfg,
                        seed, seg_out, args.timeout)
            print(f" {el:.0f}s")
            if i < n_seg - 1:
                last_frame(seg_out, f"{base}.seg{i+1:02d}.last.png")
            segs.append(seg_out)
        print("stitch:  concatenating segments ...")
        stitch(segs, out, args.fps)
        print(f"saved:   {out}\nsegments: {len(segs)} "
              f"({base}.segNN.mp4 kept)\nseed:    {args.seed}")
        print(f"elapsed: {time.time()-t_start:.0f}s total")

    if args.show:
        subprocess.run(["open" if sys.platform == "darwin" else "xdg-open", out], check=False)


if __name__ == "__main__":
    main()
