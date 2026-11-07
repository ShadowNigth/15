# Native audio integration

## Inventory and provenance

All **649 audio files** from `zh667/ScCsgoKnives`, pinned to
`1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`, are included byte-for-byte in
`assets/sounds/native/`, preserving module, language and team directories:

- ScCsgoKnives: 436 (weapons, utilities, knife effects, movement, hits, casings,
  chicken sounds and kill confirmation).
- ScCsgoVoice: 204 (17 commands × three takes × CT/T × English/Chinese).
- ScCsgoTactical: seven shield impacts.
- ScCsgoDeathmatch: respawn and match-end effects.

`data/native_audio_manifest.json` records every original path, Git blob hash,
SHA-256 and byte count. Files retain their original OGG/WAV encoding; there is
no lossy re-encoding, synthetic replacement or change to the upstream waveform.
`native_audio_levels.json` contains decoded peak/duration measurements with the
same SHA-256 identities. Non-destructive per-file playback gains reserve 6 dB
of headroom (Vorbis peaks can exceed 0 dBFS); a master limiter protects overlaps.
Quiet recordings are never boosted.
See `KNIFE_ASSET_NOTICES.md` for attribution and rights limitations, including
Valve assets and the upstream BF1/EA/DICE kill-confirmation recordings.

## Production routing

`data/native_audio.json` is a sound-only overlay applied by `GameData` before
loadout selection. The original gameplay databases and animation GLBs are not
re-exported. All 35 firearm families and the knife use native firing/swing
recordings, with the shipped numbered takes selected randomly. M4A4 and M4A1-S
remain distinct; suppressor and Glock burst routes use the corresponding native
recordings. Draw, magazine, bolt, pump and inspection events use native sound
event times from the previously verified animation reports and the upstream
`cs2_sounds.json` asset mapping. Existing action-time retiming is applied equally
to the animation and its sound schedule. A gunshot is played by the weapon
controller, never a second time from animation foley.

The 22 converted knives use the available source knife deploy/slash recordings;
Butterfly also uses its dedicated draw and inspection effects, triggered at
the authored draw01/draw02 and lookXX_a/lookXX_b phases rather than treating
the short effect as one full inspection recording.
The repository does not contain dedicated foley for every knife or granular
liquid/ring/inspection cue. Unavailable event names are listed explicitly under
`unresolved_events`; we do not substitute unrelated firearm clicks. Previously
installed matching sounds remain fallbacks where no source replacement exists.

Grenades have model-specific draw/pin/throw/bounce recordings where supplied.
HE, flash, smoke, Molotov and incendiary detonations use distinct world effects.
Molotov preparation has an explicit action-start cue because its native clip
has no separate lighter/pin sound event. Each procedural fire owns its crackle
player, restarts it only while burning, stops it at extinction, and plays the
extinguish sound once. It cannot leave a pooled looping sound behind after the
area or map is freed. Smoke plays its clear effect on expiry. C4 now distinguishes
activation, countdown beeps, last-ten-second beeps, defuse start/completion and
its explosion instead of reusing keypresses and HE blasts for these actions.

Body/head/armor hits, brass/shotgun-shell impacts, human respawn and enemy-kill
confirmation also use their source effects. Spatial sounds preserve the existing
bot-hearing events/radii and teams. First-person foley is owned by the current
player action: switching/restarting clips, rebuilding the viewmodel or dying
cancels old playback instead of leaving a previous inspection/reload audible.

English/Chinese voice takes are selected by both speaker team and command.
Configuration → **Radio voices** switches language. Unmatched classic radio
messages and unrelated map ambience/footsteps remain unchanged.

## Audition and unrepresented mechanics

The Arsenal has an audio selector with **all 649 recordings**, plus Listen/Stop.
This includes both voice languages and files for mechanics not present in this
classic game: chicken voices, shield hits and the deathmatch match-end jingle.
Importing these sounds does not invent chicken actors, shields or a deathmatch
mode, nor play them on unrelated impacts. They are available for editing and
individual audition. The old audio tree remains for precise fallback coverage;
it is not an additional simultaneous firing layer.

## Rebuild and validation

The editable project already contains everything required to open/play; no
source-repository download is needed by the game. For conversion development:

```
python -m tools.source.fetch_native_audio
python -m tools.source.build_native_audio
python tests/check_native_audio.py
godot --headless --path . --import
godot --headless --path . res://tests/NativeAudioTest.tscn
```

The downloader uses authenticated `gh`, a pinned complete Git tree and Git blob
verification. The builder uses the small upstream timing table cached by the
downloader, not a second animation conversion. The static test checks the whole
inventory, hashes, native source-event times and all referenced paths. The
Godot test exercises decoding, nonzero durations, every configured cue, distinct
weapon firing routes, language/team selection, first-person cancellation and
AI perception emission. The normal native gun/cosmetic/world regressions remain
in CI. All 649 files were also fully decoded locally and checked for non-silent
sample data; original source formats were retained.

To regenerate decoded levels, install NumPy/SoundFile and run
`python -m tools.source.analyze_native_audio` before rebuilding routes.
