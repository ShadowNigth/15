# Smoke Out: capturas multiángulo y multitoma

Compendio de capturas renderizadas reales del acabado **Moto Gloves Smoke Out
(5033_10078)**, tomadas desde distintas posiciones del Arsenal y en distintas
tomas de las animaciones de juego, para verificar que la mano mantiene su
forma original (palma ancha y dedos con longitud nativa) en todos los ángulos
y fases, sin aplastamiento.

## Qué muestran

- **Arsenal, 6 ángulos**: frente, perfil izquierdo, perfil derecho, reverso,
  superior y aproximación. Todas con la pose de previsualización nativa, sin
  el agarre cerrado del cuchillo y sin escalar vértices.
- **Arsenal, 3 tomas de inspección**: desde tres posiciones orbitales distintas
  durante la inspección del guante.
- **AK-47, 8 tomas**: inactivo, disparo, recarga (inicio / mitad / final) e
  inspección (inicio / mitad / final). Muestran la palma y los dedos adaptados
  a los contactos animados del arma sin perder el ancho de nudillos.
- **Karambit, 3 tomas**: inspección (inicio / mitad / final), con los dedos
  curvados alrededor del anillo del cuchillo.

## Archivos de evidencia

Todas las capturas viven en `docs/evidence/smoke-out-multi-angle/`:

- `native_arsenal_gloves.jpg`, `native_arsenal_gloves_{left,right,back,top,closeup}.jpg`
- `native_arsenal_inspect_{start,mid,end}.jpg`
- `native_ak47_{idle,shoot,reload,reload_start,reload_end,inspect,inspect_start,inspect_end}.jpg`
- `native_karambit_inspect_{start,mid,end}.jpg`

## Validación

- Verificación estática del proyecto: 62 scripts, 54 referencias, 43 armas,
  26 mapas, 402 GLB y 1021 WAV correctos.
- CI `43450853496` (commit `47f835ec`): éxito en las tres jobs
  (`local-body`, `arsenal-captures`, `karambit-captures`).
- Piloto nativo: **16.009 comprobaciones, 0 fallos**.
- Matriz completa de armas, cuchillos, agentes y animaciones: éxito.

No se modificaron la malla, los huesos, los pesos, las UV, las animaciones ni
las texturas intercambiadas de Smoke Out. Tampoco se tocaron los otros 26
acabados Sport.
