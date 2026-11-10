# First graffiti batch

Three offline inventory images: Blood Boiler, Chabo and Flickshot. V applies the
selected design; J cycles the three and persists its stable ID. T still inspects.
A temporary thumbnail and Spanish status describe selection/rejection/cooldown.
Only an alive player with captured mouse and no modal UI may invoke these actions.

GL Compatibility: lit alpha-textured grid mesh, not Godot Decal. 55 cm square,
3 m reach, 3 s cooldown, 120 s lifetime, 32 live marks per player. The complete
9×9 sample grid must hit the same static wall with nearly identical normals and
plane depth; unsupported edges/corners are rejected. This is conservative sampled
validation, not exact triangle clipping: very small holes between samples can
remain. No gameplay collision, weapon material or movement modifications.
World scene/player teardown clears marks. No downloads during gameplay.

Metadata: ByMykel/CSGO-API c52da3543f4cb57958d1e5c1847e6b692c02af4c.
Images: Rarmash/CS2-Simulator bc0d4305a10f06f601e5ba9e29b04835eee61986,
assets/graffiti/{1653,1654,1656}.webp, unchanged inventory images (not extracted
world spray materials). Stable IDs, original image URLs and hashes: data/graffiti.json.
The source code licences do not grant permission to Valve/community artwork.
All respective artwork rights remain with their owners; this prototype does not
assert redistribution permission. Review these rights before public distribution.

Not yet included: Arsenal selector, spray animation/audio, CS2 charge economy,
exact surface clipping, curved/dynamic surfaces, networking or the full catalogue.
