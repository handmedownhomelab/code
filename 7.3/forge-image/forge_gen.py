#!/usr/bin/env python3
"""forge_gen.py — Hand-Me-Down Homelab, section 7.3. Part of the forge-image skill.
Drive a local Forge / AUTOMATIC1111 API for txt2img and img2img.

Examples:
  # list available checkpoints + samplers, confirm the API is up
  python3 forge_gen.py --list

  # text-to-image
  python3 forge_gen.py --prompt "a red fox in snow" --out out/fox.png

  # reuse a seed (lock the look, tweak the prompt)
  python3 forge_gen.py --prompt "..." --seed 3894309182 --out out/v2.png

  # photo as an example/reference (img2img). denoise: low=stay close, high=creative
  python3 forge_gen.py --prompt "..." --init ~/Pictures/ref.jpg \
      --denoise 0.6 --out out/from_ref.png

Flux models: leave cfg at 1 and use --dcfg (distilled CFG, ~3.5). The script
defaults are already Flux-correct. For SDXL/SD1.5 pass --cfg 6 --dcfg 0.
"""
import argparse, base64, json, sys, time, urllib.request

def api(host, path, payload=None, timeout=600):
    url = f"http://{host}{path}"
    if payload is None:
        req = urllib.request.Request(url)
    else:
        req = urllib.request.Request(
            url, data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1:7860",
                   help="Forge API host:port (default localhost tunnel)")
    p.add_argument("--prompt")
    p.add_argument("--neg", default="", help="negative prompt (ignored by Flux)")
    p.add_argument("--out", default="forge_out/img.png")
    p.add_argument("--seed", type=int, default=-1)
    p.add_argument("--steps", type=int, default=22)
    p.add_argument("--width", type=int, default=1024)
    p.add_argument("--height", type=int, default=1024)
    p.add_argument("--cfg", type=float, default=1.0)
    p.add_argument("--dcfg", type=float, default=3.5, help="distilled CFG (Flux)")
    p.add_argument("--sampler", default="Euler")
    p.add_argument("--scheduler", default="Simple")
    p.add_argument("--n", type=int, default=1, help="batch size")
    p.add_argument("--model", help="checkpoint title to switch to (optional)")
    p.add_argument("--init", help="path to a photo for img2img reference")
    p.add_argument("--denoise", type=float, default=0.6,
                   help="img2img denoising strength (0=copy, 1=ignore photo)")
    p.add_argument("--list", action="store_true",
                   help="list checkpoints + samplers and exit")
    p.add_argument("--show", action="store_true",
                   help="open the saved image in the system viewer")
    args = p.parse_args()

    if args.list:
        models = api(args.host, "/sdapi/v1/sd-models", timeout=15)
        samplers = api(args.host, "/sdapi/v1/samplers", timeout=15)
        print("CHECKPOINTS:")
        for m in models:
            print("  ", m["title"])
        print("SAMPLERS:")
        print("  ", ", ".join(s["name"] for s in samplers))
        return

    if not args.prompt:
        sys.exit("error: --prompt is required (or use --list)")

    payload = {
        "prompt": args.prompt,
        "negative_prompt": args.neg,
        "seed": args.seed,
        "steps": args.steps,
        "width": args.width,
        "height": args.height,
        "cfg_scale": args.cfg,
        "distilled_cfg_scale": args.dcfg,
        "sampler_name": args.sampler,
        "scheduler": args.scheduler,
        "batch_size": args.n,
    }
    if args.model:
        payload["override_settings"] = {"sd_model_checkpoint": args.model}
        payload["override_settings_restore_afterwards"] = False

    if args.init:
        with open(args.init, "rb") as f:
            payload["init_images"] = [base64.b64encode(f.read()).decode()]
        payload["denoising_strength"] = args.denoise
        endpoint = "/sdapi/v1/img2img"
        mode = f"img2img (denoise {args.denoise}) from {args.init}"
    else:
        endpoint = "/sdapi/v1/txt2img"
        mode = "txt2img"

    t0 = time.time()
    resp = api(args.host, endpoint, payload)
    img_b64 = resp["images"][0].split(",", 1)[-1]
    import os
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(base64.b64decode(img_b64))

    if args.show:
        import subprocess
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        subprocess.run([opener, args.out], check=False)

    info = json.loads(resp.get("info", "{}"))
    print(f"mode:    {mode}")
    print(f"saved:   {args.out}")
    print(f"seed:    {info.get('seed')}")
    print(f"params:  sampler={info.get('sampler_name')} steps={info.get('steps')} "
          f"cfg={info.get('cfg_scale')} dcfg={args.dcfg} "
          f"size={info.get('width')}x{info.get('height')}")
    print(f"model:   {info.get('sd_model_name', '?')}")
    print(f"elapsed: {time.time()-t0:.1f}s")

if __name__ == "__main__":
    main()
