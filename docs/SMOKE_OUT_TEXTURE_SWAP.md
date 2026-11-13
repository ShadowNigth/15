# Smoke Out: intercambio derecha/izquierda y palma/dorso

Cambio solicitado por el usuario sobre **Moto Gloves | Smoke Out (5033_10078)**:

- La mano izquierda recibe el diseño de la textura derecha.
- La derecha recibe el diseño de la izquierda.
- La zona que antes correspondía a la palma pasa al dorso y viceversa.
- Se transfieren conjuntamente color, normal y ORM (oclusión/rugosidad/metal).

No se intercambian las manos físicas, no se espejan los modelos, ni se cambian huesos, pesos, UVs del modelo o animaciones. Los otros 26 acabados no se modifican. Los mapas originales se conservan en `assets/textures/moto_smoke_out/`; los nuevos están en `assets/textures/moto_smoke_out_swapped/`.

## Método

Los atlas tienen islas UV separadas, por lo que invertir un PNG entero no intercambiaría correctamente palma y dorso: colocaría dedos y costuras en regiones equivocadas. Se reconstruye la correspondencia de superficie con la mano opuesta, en un espacio anatómico neutralizado por falange para evitar confundir los dedos doblados con la palma. La orientación anatómica entre las dos manos invierte la normal palma/dorso. Se hornean las imágenes nuevas sobre las UVs existentes y se reorientan los detalles del normal map en el espacio tangente de destino. Las zonas exteriores a las islas reciben padding para los mipmaps.

La geometría neutralizada sólo se utiliza durante este proceso offline; nunca se guarda sobre el modelo de juego.

Reproducir, con numpy, pillow, scipy, trimesh y rtree:

```
python -m tools.source.swap_smoke_out_surfaces
python tests/check_smoke_out_texture_swap.py
```

Si se vuelve a importar el acabado original con `import_smoke_out`, ejecutar este postproceso después para conservar la personalización solicitada.

## Comprobaciones

- El SHA256 de la malla nativa sigue coincidiendo con su manifiesto original.
- Se mantienen los mismos 27 IDs de selección; los 26 Sport restantes no cambian.
- Ambos destinos declaran expresamente la textura de la mano contraria y la inversión palma/dorso en `mapping.json`.
- La región de referencia del antiguo panel dorsal claro recibe el diseño más oscuro de la palma en ambas manos.
- La correspondencia de superficie tiene distancia mediana de 3,58 mm y percentil 99 de 17,74 mm; no se presenta como una correspondencia geométrica exacta entre las dos manos asimétricas.
- El verificador estático del proyecto pasa sin errores.

Validación renderizada: [CI 43427693555](https://github.com/ShadowNigth/15/actions/runs/43427693555), código `7c8cabd5`: **14 285 comprobaciones de piloto y 4 205 947 de matriz, 0 fallos**. Se revisaron las capturas finales de Arsenal, recarga AK e inspección de karambit en `docs/evidence/smoke-out-texture-swap/`. El comparativo antes/después utiliza capturas reales de la misma pose de Arsenal, sin modificar las imágenes del guante.

Es una personalización solicitada, no la distribución original de fábrica del acabado. La transferencia entre superficies asimétricas puede estirar detalles y costuras; no se afirma que el atlas resultante sea un unwrap original de Valve. Los relieves físicos de la malla siguen donde estaban: sólo se cambia el aspecto de sus texturas.

