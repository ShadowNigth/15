# Puños por fuera / piel por dentro y Moto Gloves | Smoke Out

## Solicitud

Se distinguen los dos casos indicados por el usuario:

- **Antebrazo descubierto:** la piel entra en la abertura del guante; no forma una manga por encima del borde.
- **Manga:** el extremo de la ropa se superpone al borde exterior del guante.

Se añade solamente **Moto Gloves | Smoke Out — 5033_10078**. Los 19 Sport nativos retirados siguen fuera del catálogo. La selección predeterminada sigue siendo `classic`.

## Ajuste de unión

`WristSeamFit` conserva el puño articulado compatible con cada arma/cuchillo y sus binds originales. Mide la abertura del guante que está realmente instalado, incluyendo el Moto nuevo y los guantes anteriores. El ajuste se cachea por arma, agente, escena y guante, para que al cambiar de guante no se reutilice el radio de otro modelo.

El antebrazo importado termina a 10,5 cm de la muñeca; se conserva una transición original desde 15 cm atrás. En la zona distal:

- Leet, Phoenix y Phoenix A: el radio de piel se reduce suavemente hasta quedar dentro de la abertura, con 7 mm de holgura nominal y 28 mm de inserción longitudinal.
- SAS, ST6, SAS Officer, FBI y Dragomir: la tela se ajusta suavemente fuera del contorno exterior, con 6 mm de holgura nominal y 18 mm de superposición sobre el borde.

Se ignoran los vértices interiores próximos al eje de la palma al medir la abertura; no se confunden con el borde exterior del puño. Los cortes se realizan por intersección de triángulos con planos, interpolando pesos/UVs/normales. No se añaden cilindros ni aros decorativos, ni se espejan las manos, ni se cambian animaciones de armas.

## Smoke Out nativo

Fuente: `3kh0/cs2go`, commit `fb970df0ee8175d9b212d310f6a928f9f61014f2`.

- Modelo: `packages/assets/public/models/gloves/5033.glb`, sólo su mesh **viewmodel** y los dos materiales `glove_motorcycle_left/right`. No se mezclan el worldmodel ni el antebrazo descubierto incluido en el paquete fuente.
- Acabado: `packages/assets/public/skins/gloves/paints/5033_10078.json`, horneado con el baker/shaders originales, desgaste 0,07 y semilla 1.
- Se conservan las UVs del modelo nativo. La importación adapta muñeca y cada falange con marcos anatómicos completos; no usa un giro ambiguo común inferido de segmentos paralelos ni intercambia los lados.
- Se incluyen mapas de color, normal, rugosidad, metal y oclusión. Se reconstruye el componente Z del normal a partir de XY y se extrae la rugosidad de `normal.b` según los metadatos fuente. Las texturas de ejecución están a 1024 px; el juego no requiere red, navegador ni WebGPU.
- El material nativo evita la sustitución de sus mapas por las constantes antiguas de los guantes clásicos.

Reproducir: `python -m tools.source.import_smoke_out`, con las dependencias Python de los importadores y `npm ci` en `tools/source/modern_agents` y `tools/source/cosmetics`. Derechos de Valve/autores por separado; la fuente pública no se interpreta como permiso general de redistribución.

## Validación

Verificación estática inicial: 61 scripts, 53 referencias, 43 armas, 26 mapas, 392 GLB y 1021 WAV, sin errores.

`WristSeamTest` compara la trayectoria del puño ya ajustado por capas con la referencia articulada equivalente, conservando tolerancia de 1 mm. `SmokeOutTest` comprueba ambos lados, medidas de abertura y holgura, identidad de modelo/acabado, materiales PBR, Arsenal, todas las armas y muestras de reposo/inspección/recarga con agentes de piel y manga. Las medidas de holgura se realizan en espacio de bind; las poses se verifican mediante capturas reales.

Validación final en Godot (CI [43363510789](https://github.com/ShadowNigth/15/actions/runs/43363510789), código `4ea77ff3`):

- Smoke Out: **31 163 comprobaciones, 0 fallos**.
- Agentes/brazos: **629 comprobaciones, 0 fallos**.
- Muñecas animadas: **1736 comprobaciones, 0 fallos**.

Capturas renderizadas revisadas en `docs/evidence/smoke-out/`: Arsenal, detalle de ambos guantes, SAS con manga sobre el borde, Leet con piel dentro del puño e inspección del karambit. Son capturas del renderer de prueba sobre fondo neutro, no fotografías del catálogo ni una partida completa. La primera calibración de los dedos y la primera medición de abertura fallaron y no se aceptaron como evidencia final; estas capturas corresponden al resultado posterior corregido.

