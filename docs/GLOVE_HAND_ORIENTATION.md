# Reconstrucción de los guantes Sport

La conversión anterior fue rechazada visualmente por el usuario. Se elimina el intercambio de huesos y la reflexión de la palma introducidos en esa revisión; sus resultados técnicos no se consideran aprobación visual.

## Implementación nueva

`python -m tools.source.rebuild_native_sport` reconstruye `assets/models/agent_arms/sport.glb` desde el mesh **viewmodel** original de `models/gloves/5030.glb` de cs2go, revisión fijada en el importador. No mezcla el mesh worldmodel ni reutiliza los vértices del Sport convertido anteriormente.

La calibración usa muñeca, índice, meñique y segmentos reales de los dedos para crear bases anatómicas completas en origen y destino. Evita inferir la rotación únicamente a partir de ejes longitudinales casi paralelos de los dedos, que dejan ambiguo el giro de palma/dorso. La base completa de la palma se expresa en coordenadas locales de la muñeca para calibrar las convenciones de los huesos, sin orientar cada falange por separado. Conserva correspondencia del mismo lado, UVs, pesos, matrices de bind y materiales nativos. El factor de unidades sigue siendo el del paquete dedicado.

En ejecución se retira toda la lógica de intercambio/reflexión anterior. La geometría nueva usa el retarget compartido hacia cada rig de arma/cuchillo, sin modificar sus animaciones ni las mangas independientes. Los 19 acabados nativos usan la nueva geometría.

## Evidencia

Validación estática de la reconstrucción: 60 scripts, 53 referencias, 43 armas, 26 mapas, 392 GLB y 1021 WAV, sin errores. Ejecución renderizada [43302805116](https://github.com/ShadowNigth/15/actions/runs/43302805116), revisión `655a277e`: 14912 comprobaciones del flujo de guantes y 855 de compatibilidad, sin fallos. La captura completa de esta revisión está en `docs/evidence/glove-orientation/arsenal-rebuilt.jpg`; se actualizaron también las capturas de detalle y Glock. Se entregan para revisión visual del usuario, no como aprobación visual implícita.

## Ajuste de presentación solicitado: intercambio y palmas abajo

A continuación el usuario pidió intercambiar de lugar los dos guantes y girarlos con las palmas hacia abajo. El Arsenal ahora hornea exclusivamente su pose de exposición, separa cada mano completa, intercambia sus posiciones horizontales y orienta rígidamente las bases anatómicas para mostrar ambos dorsos con las palmas hacia el suelo. La inclinación de exposición permite apreciar el acabado. No refleja texturas ni cambia vínculos de dedos o animaciones del juego. La inspección de exposición anima cada mano completa y regresa a su pose inicial; la rotación y el zoom manual siguen independientes.

Validación renderizada: https://github.com/ShadowNigth/15/actions/runs/43307142396 — 14917 comprobaciones del flujo de guantes y 855 de compatibilidad, sin fallos. Captura completa nueva: `docs/evidence/glove-orientation/arsenal-swapped-palm-down.jpg`; detalle: `gloves-swapped-palm-down.jpg`.
