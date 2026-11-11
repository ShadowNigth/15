# Reference-style home menu

The home screen uses a slim translucent top navigation, an animated full-body
agent, a compact local profile card and a live 3D map background. It follows the
provided CS2 screenshot's hierarchy without inventing online friends, a store,
news feeds or Steam integration. Inventory/equipment open the existing editable
Arsenal and Play opens the existing local match configuration.

In **Ajustes → Fondo del menú de inicio**, select Dust II, Aztec or Italy.
The selection applies immediately behind the settings panel and persists in
`user://menu_presentation.cfg`. **Movimiento del fondo** disables the bounded
camera pan without disabling the agent's idle animation. No video download or
network connection is needed. These are existing classic map assets, not CS2's
higher-resolution map geometry or a video from the reference screenshot.

The backdrop owns a separate viewport and replaces its previous world on each
selection; it does not instantiate gameplay actors, colliders, mission triggers,
round managers or AI. The foreground agent also uses a cosmetic-only viewport,
native idle animation and existing hand/weapon calibration. Gameplay, first-person
models, cosmetics and movement profiles are unchanged.

QA includes rendered 16:9/4:3 menu and Arsenal captures, all three backgrounds,
bounded movement/reduced motion, persistence/reload and existing Arsenal routing.

## Design refinement

The latest layout adds a subtle cinematic vignette, larger top navigation,
a clear amber Play action at lower right and a lower-left information card
instead of obscuring the agent's legs. Existing background selection remains.
Rendered home/Arsenal routing tests: **200 passed**, run
[42951008173](https://github.com/ShadowNigth/15/actions/runs/42951008173).
