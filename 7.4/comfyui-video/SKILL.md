---
name: comfyui-video
description: Generate short videos on the local ComfyUI running on the GPU box, reached through an SSH tunnel on localhost:8188. Use when the user asks to generate, create or make a video or clip, animate a still photo, turn an image into video, or iterate on a generated clip. Two models, Wan 2.2 (quality, minutes per clip) and LTX-Video 0.9.5 (fast drafts, about a minute); ASK the user which unless they say. Handles text-to-video and image-to-video; the agent runs each render, pulls a frame to look at, and iterates.
---

# ComfyUI video generation

<!-- Hand-Me-Down Homelab, section 7.4. Install: copy this folder to
     ~/.claude/skills/comfyui-video/ on your workstation and set GPU_HOST in
     ensure_comfyui.sh. The templates name the model files the playbook
     downloads; change them if yours differ. -->

Drive the local **ComfyUI** to make short clips, then **look at frames of each
result** and refine: describe → render → pull a frame → critique → adjust →
render again. Sibling of the `forge-image` skill (Forge for stills, ComfyUI for
video). They **share one GPU**, and only one can hold it at a time.

## Choose the model: ASK FIRST

Unless the user already said, **ask which model to use** before rendering:

| `--model` | Model | Speed (16 GB card) | Quality, size | Use when |
|---|---|---|---|---|
| `wan` (default) | Wan 2.2 TI2V-5B | **8–14 min** a clip | best motion, 1280×704 | the clip matters |
| `ltx` | LTX-Video 0.9.5 (2B) | **about 1 min** a clip | softer, 768×512 | drafts, trying ideas |

Both do **text-to-video** and **image-to-video**. A good flow: draft with `ltx`
until composition and motion are right, then re-render the keeper with `wan`.

## Length: pick the method from the seconds asked for

Pass the length as **`--seconds N`**; the driver chooses one pass or chaining.
Your job is to pick the model:

| Asked for | Method (driver does it) | Model |
|---|---|---|
| up to ~5 s | one pass | either (ask) |
| ~5–9 s | one pass (LTX reaches ~9 s; Wan stops at ~5 s) | **ltx**, or wan if ≤ 5 s |
| over ~9 s | **chaining**: segments, each continuing from the last frame of the one before, stitched | **ltx** (a Wan chain is minutes per segment) |

Tell the user the plan and the rough time (an LTX chain is about 45 s per
segment). **Say the caveats for long requests:** the setting stays consistent
but the subject can drift; seams are smooth but motion may hitch; and one
prompt for the whole length makes the same shot over and over. Give each
segment something to happen. The `.segNN.mp4` files are kept next to the
stitched result. Use `--length` only for an exact frame count in one clip.

## Setup

- ComfyUI runs on the GPU box and is reached at **`127.0.0.1:8188`** through
  an SSH tunnel. Native ComfyUI nodes only, no custom nodes.
- Model files (in ComfyUI's `models/`):
  - **Wan:** `diffusion_models/wan2.2_ti2v_5B_fp16.safetensors`,
    `text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors`,
    `vae/wan2.2_vae.safetensors`
  - **LTX:** `checkpoints/ltx-video-2b-v0.9.5.safetensors` (VAE included),
    `text_encoders/t5xxl_fp16.safetensors`
- The driver `comfy_video.py` and four API-format templates
  (`templates/wan22_5b_{t2v,i2v}.json`, `templates/ltx095_{t2v,i2v}.json`)
  are next to this file. Save results in `~/forge_out/` unless the user says
  otherwise.

## First, run the preflight (starts ComfyUI if needed)

```
~/.claude/skills/comfyui-video/ensure_comfyui.sh
```

**Exit 0**: ready. **Non-zero**: say so plainly and point at
`comfyui-run.log` next to this file; never invent a result.
`python3 comfy_video.py --check` confirms the API and free VRAM and lists the
loaded models.

## Sharing the GPU (important)

`comfyui-run.sh` frees the card first: it unloads Ollama's models and stops
Forge and ACE-Step. Starting Forge stops ComfyUI in turn, so **starting an
image job kills a video render in progress**. If a render fails for lack of
memory, look at `nvidia-smi` on the GPU box for another app still holding it.
ComfyUI gives its memory back after every job (`--disable-smart-memory`), but
the server stays up until it is stopped.

## Workflow

### Text to video
```
python3 ~/.claude/skills/comfyui-video/comfy_video.py --model <wan|ltx> --seconds <N> --show \
    --prompt "..." --out ~/forge_out/<name>_001.mp4
```
Describe the subject, the setting, the light **and the camera motion**. **LTX
wants long, very descriptive prompts**; Wan does well with shorter natural
ones.

### Image to video (animate a still)
The prompt describes the **motion**, not the scene; the image fixes the scene.
Pass a real file path with `--init`:
```
python3 ~/.claude/skills/comfyui-video/comfy_video.py --model <wan|ltx> --show \
    --init "/path/still.png" --prompt "slow push-in, leaves stirring in the wind" \
    --out ~/forge_out/anim_001.mp4
```
A natural bridge: animate a still made with `forge-image`. Use stock or
generated images, not photos of people who haven't agreed to it.

### Look at each result
Pull frames from the middle and the end, and open them:
```
ffmpeg -y -v error -i <file>.mp4 -vf "select=eq(n\,40)" -vframes 1 <file>_frame.png
```
You can judge composition, subject and artifacts from frames. You can't judge
motion (flicker, morphing); ask the user to watch it.

### Settings (defaults depend on the model)
| Flag | wan | ltx | Notes |
|---|---|---|---|
| `--seconds` | — | — | target length; one pass or chained. **Preferred.** |
| `--length` | 121 (~5 s) | 97 (~3.9 s) | exact frames for one clip; overrides `--seconds` |
| `--width`/`--height` | 1280×704 | 768×512 | portrait: swap them |
| `--fps` | 24 | 25 | |
| `--steps` | 30 | 30 | |
| `--cfg` | 5.0 | 3.0 | |
| `--seed` | random | random | printed after each run; reuse it to keep a look |

### Iterating
- **Keep a good clip, change details:** reuse its `--seed`, change the wording.
- **Explore:** a new seed each run, two or three renders, compare frames.
- One render at a time. Keep tests short (`--length 61`) while dialing in.

## Changing a graph
To add a model or a step, **derive the new graph from a working template**
rather than inventing one, and check every node's name and inputs against the
installed ComfyUI (`/object_info`), because nodes get renamed between
releases.

## Reporting back
Say what matches and what's off (from the frames), give the seed and model,
and offer the next concrete move. Be specific.

## Limits
- Works only while ComfyUI and the tunnel are up. If unreachable, say so.
- 16 GB holds both models only at short clips. LTX-2's weights are over 40 GB
  and don't fit.
- Check each model's license before its output goes into anything published
  or sold.
