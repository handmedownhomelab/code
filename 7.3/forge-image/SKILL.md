---
name: forge-image
description: Generate images on the local Forge (Stable Diffusion WebUI Forge) running on the GPU box, reached through an SSH tunnel on localhost:7860. Use when the user asks to generate, create, make or render an image, draw something "in Forge", iterate on a generated image, or use a photo as a reference to base a generation on (img2img). The agent runs each generation, looks at the result, and iterates.
---

# Forge image generation

<!-- Hand-Me-Down Homelab, section 7.3. Install: copy this folder to
     ~/.claude/skills/forge-image/ on your workstation, and set GPU_HOST in
     ensure_forge.sh. Change the output folder below to one of yours. -->

Drive the local **Forge** to generate images, then **look at each result** and
refine. The whole value of doing this through the agent, rather than the user
typing into Forge, is the loop: generate → open the PNG → critique → adjust
prompt, seed or settings → generate again. Always close that loop; never hand
back a path without having looked at the image yourself.

## Setup

- Forge runs on the GPU box and is reached at **`127.0.0.1:7860`** through an
  SSH tunnel, with its API on. The script defaults to that address.
- The loaded model is **FLUX.1 [dev] fp8**. The script's defaults (`cfg 1`,
  `dcfg 3.5`, Euler / Simple) are tuned for it.
- The script is next to this file: `forge_gen.py`. Save generations in
  `~/forge_out/` unless the user says otherwise; pass `--out`.

## First, run the preflight (starts Forge if needed)

```
~/.claude/skills/forge-image/ensure_forge.sh
```

It checks the API and, if Forge is down, opens the tunnel, starts
`forge-run.sh` on the GPU box in the background and waits up to about 120 s.
The first call after a cold start is slow (model load).

- **Exit 0**: the API is ready.
- **Non-zero**: Forge didn't start. Say so plainly and point the user at
  `forge-run.log` next to this file. Do **not** draw an SVG instead and pass
  it off as a Forge image.

`python3 forge_gen.py --list` shows the loaded checkpoints and samplers.

## Model settings (important)

| Model family | `--cfg` | `--dcfg` (distilled CFG) | Sampler | Notes |
|---|---|---|---|---|
| **FLUX** (default) | 1 | ~3.5 | Euler / Simple | the negative prompt is **ignored**; short text renders well |
| SDXL | 6–7 | 0 | DPM++ 2M Karras | use a real negative prompt |
| SD 1.5 | 6–7 | 0 | DPM++ 2M Karras | smaller native size (512–768) |

Only override the defaults when the loaded model isn't FLUX.

## Workflow

### Text to image
1. Turn the request into a clear prompt. FLUX prefers natural, descriptive
   sentences to comma-separated tags. Put wanted **text in quotes**
   (`a banner reading "OPEN"`). Say what you *don't* want as plainly as what
   you do (`plain unbranded, no text, no letters, no logos`).
2. Generate with `--show`, so the user sees it as soon as it's saved:
   ```
   python3 ~/.claude/skills/forge-image/forge_gen.py --show \
       --prompt "..." --out ~/forge_out/<name>_001.png
   ```
3. **Open the PNG yourself** and critique it honestly against the request.
4. Iterate (below).

### A photo as a reference (img2img)
1. **Look at the photo first**, then say in the prompt what to keep and what
   to change.
2. Pass it with `--init` and pick a denoising strength:
   - `--denoise 0.3–0.45`: stay very close to the photo (recolor, light edits)
   - `--denoise 0.5–0.65`: keep the composition and subject, restyle (default)
   - `--denoise 0.7–0.85`: loose inspiration, mostly the prompt
3. The script needs a **file path**. If the user only pasted an image, ask
   where it is on disk.

### Iterating
- **Composition right, details wrong:** reuse its `--seed` (printed after each
  run) and change the wording.
- **Exploring:** leave the seed at `-1`, run 3–4 seeds, look at each, present
  the best. For placement or count problems, new seeds beat rewording.
- Generate **one or two at a time**; FLUX takes about 40–50 s per 1024² image
  on a 16 GB card. Don't run large batches.

## Reporting back
After each image, say briefly what matches and what's off, then offer the next
concrete move (same seed or new ones, a setting, another model). Be specific:
"the wolf faces right, it should face left", not "looks pretty good".

## Limits
- This only works while Forge and the tunnel are up. If the API can't be
  reached, say so.
- Text in images is best-effort; long phrases garble.
- Exact counts ("three hoops") and strict left/right placement are
  unreliable. Say so and explore seeds rather than promising precision.
- Before an image goes into anything published or sold, check the model's
  current license and note which model and seed made it.
