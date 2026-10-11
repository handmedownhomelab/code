#!/usr/bin/env python3
"""acestep_batch.py — Hand-Me-Down Homelab, section 7.6. Runs on the GPU box.

Generate several tracks from a job file without the web interface. Run it with
ACE-Step's own Python, from the ACE-Step folder, with the GPU free (stop the
chat model and the other GPU apps first, as acestep-run.sh does):

  cd ~/ACE-Step && ./.venv/bin/python ~/acestep_batch.py job.json

job.json:
  {"name": "theme", "duration": 120,
   "lyrics": "[verse]\\nOld machines in the basement hum\\n[chorus]\\nHand me down",
   "variants": [
     {"id": "a", "prompt": "upbeat, synth-pop, female vocals, 120 bpm", "seed": 41207},
     {"id": "b", "prompt": "upbeat, synth-pop, male vocals, 120 bpm", "seed": 77310,
      "lyrics": "...this variant's own lyrics..."}]}

"prompt" is the style tags. "lyrics" (for the job, or per variant) uses
structure markers; leave it out for an instrumental, which gets intro, verse,
chorus, bridge and outro sections marked [inst]. Writes <out_dir>/<name>_<id>.wav,
by default ~/ACE-Step/bench/. Not outputs/: the web interface parses the
names of outputs/*.json at startup and dies on any file it didn't write.

(ACE-Step's own infer.py, run without arguments, plays a random demo preset:
a smoke test, not a way to make your own tracks.)
"""
import json, os, sys

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
from acestep.pipeline_ace_step import ACEStepPipeline

INSTRUMENTAL = "\n\n".join(f"[{s}]\n[inst]" for s in
                           ("intro", "verse", "chorus", "verse", "bridge", "chorus", "outro"))

job = json.load(open(sys.argv[1]))
out_dir = os.path.expanduser(job.get("out_dir", "~/ACE-Step/bench"))
os.makedirs(out_dir, exist_ok=True)

# Offload is faster AND safer on a 16 GB card (see acestep-run.sh).
pipe = ACEStepPipeline(checkpoint_dir="", dtype="bfloat16", torch_compile=False,
                       cpu_offload=True, overlapped_decode=True)
for v in job["variants"]:
    out = os.path.join(out_dir, f"{job['name']}_{v['id']}.wav")
    pipe(audio_duration=float(v.get("duration", job["duration"])), prompt=v["prompt"],
         lyrics=v.get("lyrics") or job.get("lyrics") or INSTRUMENTAL,
         infer_step=60, guidance_scale=15, scheduler_type="euler", cfg_type="apg",
         omega_scale=10, manual_seeds=str(v.get("seed", "")),
         guidance_interval=0.5, guidance_interval_decay=0, min_guidance_scale=3,
         use_erg_tag=True, use_erg_lyric=True, use_erg_diffusion=True, oss_steps="",
         guidance_scale_text=0.0, guidance_scale_lyric=0.0, save_path=out)
    print("DONE", v["id"], out, flush=True)
