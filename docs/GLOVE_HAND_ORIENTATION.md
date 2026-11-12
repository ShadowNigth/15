# Intercambio anatómico de los guantes Sport nuevos

## Problema señalado

La captura del usuario corresponde a la inspección de Bronze Morph en el Arsenal. La revisión anterior cambiaba L/R en los binds y trasladaba los vértices a la mano contraria, pero conservaba su orientación local de origen. Cambiar los índices y posiciones de los huesos no cambia la quiralidad de una mano: puede conservar el pulgar/palma del lado incorrecto.

## Cambio

`AgentViewArms` mantiene el intercambio completo de las manos de los Sport nuevos, pero ahora calcula un marco anatómico en cada muñeca y falange:

- Eje longitudinal siguiendo la cadena del dedo.
- Eje lateral a partir del índice y meñique.
- Eje perpendicular de palma/dorso, que se refleja para cambiar la quiralidad al pasar a la mano opuesta.
- Anclaje en el hueso de destino; se mantienen los pesos de cada vértice vinculados al dedo correspondiente de la mano contraria.

La corrección incluye normales por inversa transpuesta, inversión del orden de los triángulos y regeneración de tangentes. No se limita a desactivar el culling para ocultar una malla del revés. La versión de la caché de geometría también cambia para no reutilizar la conversión anterior.

No se espeja la cámara/Arsenal para disimular el problema. Las preferencias de mano derecha/izquierda del jugador conservan su comportamiento independiente. No se alteran texturas, UVs, pinturas, poses ni pistas de animación de armas/cuchillos, y no se intercambian las mangas de los agentes. Se aplica a la geometría compartida por los 19 acabados Sport nuevos con `native_uv`; los guantes clásicos y la conversión Sport anterior conservan su ruta existente.

## Validación

`GloveHandOrientationTest` comprueba anclajes, dirección de las falanges, cambio de quiralidad y reversibilidad del intercambio. Captura el **Bronze Morph `cs2go_5030_10046` de la incidencia** en el Arsenal, incluidos momentos distintos de su inspección. También comprueba primera persona con Glock, inspección de cuchillo original, Karambit y Shadow Daggers, Amphibious y la preferencia de mano izquierda.

`AgentViewArmsTest` conserva la comprobación de cada arma y cuchillo y de las mangas independientes. Estas comprobaciones son regresiones técnicas, no sustituyen la revisión visual de las capturas.

Ejecución renderizada [43296464936](https://github.com/ShadowNigth/15/actions/runs/43296464936): **234 comprobaciones de orientación y 855 de compatibilidad, sin fallos**. Se revisaron las capturas reales de Bronze Morph en Arsenal, inspección/palma y Glock; se incluyen en `docs/evidence/glove-orientation/`. Verificación estática inicial: 60 scripts, 53 referencias, 43 armas, 26 mapas, 392 GLB y 1021 WAV, sin errores. La revisión técnica no implica aprobación visual del usuario.
