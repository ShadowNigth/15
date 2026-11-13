# Smoke Out: corrección de forma aplastada

## Problema

Los guantes Moto Smoke Out se veían aplastados en el Arsenal y con la palma
comprimida durante las animaciones. La malla, los pesos y las texturas no
estaban dañados: el problema estaba en la pose aplicada al esqueleto nativo.

Había dos causas:

1. El Arsenal reutilizaba la pose cerrada de la mano que agarra el cuchillo.
2. La adaptación copiaba las posiciones de las articulaciones del rig anterior,
   reduciendo el ancho entre nudillos y acortando visualmente los dedos de la
   palma acolchada de Moto.

## Corrección

- `scripts/actors/NativeViewRig.gd`
  - Conserva el desplazamiento original de cada articulación respecto a su
    padre, por lo que mantiene el ancho nativo de la palma y la longitud de
    las falanges.
  - Aplica una IK de dos huesos por dedo para seguir el contacto animado del
    arma sin estirar ni aplastar la mano.
  - Añade una vista independiente en el Arsenal que muestra ambas manos con
    un único transform rígido sobre su forma original, sin la compresión del
    agarre del cuchillo y sin escalar vértices.
- `scripts/ui/MainMenu.gd`
  - Activa esa vista al abrir los guantes y anima la rotación de las manos en
    la inspección.
- `tests/NativeViewRigTest.gd`
  - Verifica que la vista del Arsenal no usa el agarre del cuchillo.
  - Verifica en varias fases que la forma relativa de cada mano permanece
    idéntica a su forma nativa.
  - Verifica que, durante las animaciones, cada articulación conserva su
    desplazamiento original respecto a su padre.

No se modificaron la malla, los huesos, los pesos, las UV, las animaciones ni
las texturas intercambiadas de Smoke Out. Tampoco se tocaron los otros 26
acabados Sport.

## Evidencia renderizada

- `docs/evidence/smoke-out-shape-fix/before_after.jpg`: mismo Arsenal antes y
  después.
- `docs/evidence/smoke-out-shape-fix/arsenal.jpg`: manos abiertas con su
  volumen original.
- `docs/evidence/smoke-out-shape-fix/ak47_reload.jpg`: palma y dedos adaptados
  a la recarga del AK sin perder el ancho de los nudillos.
- `docs/evidence/smoke-out-shape-fix/karambit_inspect.jpg`: dedos curvados
  alrededor del anillo del Karambit.

## Validación

- Verificación estática del proyecto: 62 scripts, 54 referencias, 43 armas,
  26 mapas, 402 GLB y 1021 WAV correctos.
- CI `43434491651`, job `131915978620`: éxito.
- Piloto nativo: 15.468 comprobaciones, 0 fallos.
- Matriz completa de armas, cuchillos, agentes y animaciones: éxito.
