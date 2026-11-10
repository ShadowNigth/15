# Modern agents — runtime activation

## Source and reproducibility

Source: 3kh0/cs2go, pinned fb970df0ee8175d9b212d310f6a928f9f61014f2.
Target bodies: roster/ctm-sas.glb and roster/tm-phoenix.glb. Source bodies have
embedded images/skinned meshes but no animation tracks. The importer decodes
Meshopt/BasisU into ordinary geometry and embedded PNG and transfers separate
native animation packs to their skeletons. No upstream TypeScript is copied.

Rebuild:

```
npm ci --prefix tools/source/modern_agents
python tools/source/import_modern_agents.py
```

The importer needs numpy/scipy and authenticated gh. Runtime needs neither Python,
npm, gh, ktx, network access nor WASM. Provenance and SHA256 hashes are recorded
in `data/modern_agents_import.json`. The earlier external ktx conversion failure
was superseded by the bundled WASM texture decoder.

Each body currently exposes 341 clips/aliases from default locomotion and
weapon-specific packs. Unused source animation variants are omitted. Non-root
translation keys are converted to the rig's inch coordinates; root displacement
is suppressed. The imported forward-axis wrapper is shared by gameplay/previews.
Animation track bindings are cached per appearance, not rebuilt for every bot.

## Runtime behavior

Combat class aliases resolve to SAS (CT) / Phoenix (T) throughout gameplay,
the team chooser, circular buy preview and Arsenal. Automatic random internal
class selection remains; there is no manual class-selection step. VIP and
hostages stay classic. Original classic files remain on disk as reference and
fallback; they are not default CT/T combatants.

ModernAgentPose selects native directional walk/run/crouch/air poses, weapon holds
and draw/reload/fire upper layers, resets sparse tracks on transitions and applies
aim pitch/recoil. Legacy firearm aliases (P228/P250, M3/Nova, SG550/SCAR, etc.) use
the corresponding available pack. Sockets are calibrated per appearance/weapon
against established p_ meshes. Root scale cancellation preserves their world scale.
An original two-bone support-arm correction adapts settled rifle holds to the
existing weapons in gameplay/previews; native draw/reload actions remain unpinned.
Animated skeletal bullet regions use the modern bone names.

Deaths use an original bounded procedural fall from the current pose, with existing
corpse grounding and normal weapon drops. They are **not CS2 death clips or a full
joint-by-joint physics ragdoll**. No death GLB clips were found in the inspected
source. Respawning rebuilds the rig and clears the fall state.

GoldSrc movement, first-person weapons/animations/gloves/skins, collision hulls,
round rules and existing mission behavior are preserved.

## Independently implemented AI

The preceding AI delivery introduced coordinated team roles/rotation choices,
burst discipline and objective-aware combat. Actual shots, independently of the
recoil counter, govern finite distance-based bursts. Empty/reload/cooldown triggers
are not counted. Distant threats do not continually derail an urgent objective's
safe route; nearby threats and reload cover still interrupt. Existing hostage
obstacle recovery and VIP escort/extraction paths remain active. No upstream AI
source was copied and no unseen opponent locations are used.

## Verification

- `ModernAgentImportTest`: imported rig, textures, native clips and deforming poses.
- `ModernAgentGameplayTest`: production bots, all 43 weapon holds, root/world
  scale, native actions, movement, aim, damage/death, respawn and classic VIP.
- Rendered team, buy, Arsenal, idle/movement/death and combat regression tests.
- Mission and tactical physics regressions run headlessly, separately from
  framebuffer evidence, to avoid software-rendering timeouts.
- Broad weapon/world smoke tests retain first-person/native-casing coverage.

Automated evidence and logs are attached to the corresponding GitHub Actions run.
Passing structural checks alone is not a claim of perfect visual equivalence to CS2.

## Rights

`roster/source.json` attributes artwork to Valve. No general root license was
identified for cs2go. Public availability is not redistribution permission;
original conversion tooling does not change the artwork's rights.
