#!/usr/bin/env python3
"""Decode every original waveform and derive non-destructive playback headroom.
Development-only dependencies: numpy, soundfile. No waveform is overwritten.
Vorbis decoding can overshoot 0 dBFS, even when the source encoder was normalized.
"""
import hashlib
import json
import math
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT/'data/native_audio_manifest.json').read_text())
levels = {}
for entry in manifest['files']:
    path = ROOT/'assets/sounds'/entry['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
    samples, rate = sf.read(path, dtype='float32')
    assert samples.size and np.isfinite(samples).all(), path
    peak = float(np.abs(samples).max())
    assert peak > 0.00001 and len(samples)/rate > 0.01, path
    peak_db = 20.0*math.log10(peak)
    levels[entry['path']] = dict(sha256=entry['sha256'], duration=round(len(samples)/rate,6),
        peak_dbfs=round(peak_db,4), gain_db=round(min(0.0,-6.0-peak_db),4))
(ROOT/'data/native_audio_levels.json').write_text(json.dumps(levels,indent=2)+'\n')
print(f'PASS: {len(levels)} original waveforms decoded, finite and non-silent; playback peaks <= -6 dBFS, no quiet-file boost')
