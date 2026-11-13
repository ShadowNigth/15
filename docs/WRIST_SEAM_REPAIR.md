# Unión guante–antebrazo: puño original por rig

## Problema y cambios descartados

La manga dedicada tenía un extremo de muñeca de otro modelo, con pesos principalmente de antebrazo. El guante original fue diseñado para otra topología de puño y mezclas `ForeTwist`/`Hand`. Copiar solamente los pesos —incluso promediados— no hacía coincidir ambas geometrías durante las poses. Las variantes de la tarea anterior fallaron comprobaciones o produjeron picos y se dejaron desactivadas.

## Corrección actual

`WristSeamFit` conserva el **puño original del arma/cuchillo de destino**, con su topología, coordenadas, pesos y matrices de bind auténticas. No intenta doblar la topología de una muñeca extranjera para hacerla encajar.

- El antebrazo/manga dedicado del agente se mantiene hasta 10,5 cm antes de la muñeca.
- Se conserva el tramo original desde 15 cm antes de la muñeca hasta el guante. Hay una zona de solape de 4,5 cm en el antebrazo, no en la articulación.
- Ambos cortes se realizan por intersección real de triángulos con un plano; se interpolan atributos y pesos y se conserva el orden de caras.
- El puño usa el material de la manga/piel dedicada del agente, con UVs transferidas del paquete dedicado; la mano y su textura original no cambian.
- Los binds se copian por hueso **y matriz**, no por nombre solamente. También se reconstruyen al usar la caché.
- No se agregan cilindros, aros ni esqueletos animados adicionales. No se tocan pistas, eventos, sonidos, manos o mangas de tercera persona.
- La reparación está habilitada por defecto. Los guantes Sport cs2go retirados siguen fuera del juego.

Esto conserva los paquetes de mangas dedicados, sin extraer brazos de los modelos de tercera persona. La geometría de transición de muñeca sí usa el puño ya compatible de cada viewmodel, en lugar de la muñeca extranjera que provocaba la rotura.

## Validación

`WristSeamTest` exige reparación activa en producción y mide las dos muñecas de ocho agentes con Glock, AK y Karambit en muestras de reposo, recarga e inspección. El umbral del borde se redujo de **45 mm a 1 mm** contra la geometría original animada, en vez de relajar la prueba anterior. `AgentViewArmsTest` mantiene la regresión de armas/cuchillos y selección independiente de guantes y mangas.

Verificación estática inicial: 61 scripts, 53 referencias, 43 armas, 26 mapas, 391 GLB y 1021 WAV, sin errores. Ejecución renderizada [43358588262](https://github.com/ShadowNigth/15/actions/runs/43358588262), código `3fdc6644`: **1520 comprobaciones de muñecas y 629 de compatibilidad sin fallos**. La reparación estaba habilitada por defecto, sin activación experimental del test. Se revisaron capturas reales de inspección de SAS y Phoenix; se entregan además Leet e inicio intermedio de recarga Glock en `docs/evidence/wrist-seam/`.

La prueba de muñeca cubre los dos bordes de los ocho agentes, tres armas y muestras de reposo/recarga/inspección; la regresión de instalación cubre las 43 armas y todos los cuchillos configurados. No se afirma haber inspeccionado visualmente cada fotograma de cada arma. El contorno exterior de la ropa puede variar entre agentes, pero el borde articulado ya sigue exactamente la geometría original compatible con la mano.

## Imágenes de los guantes del repositorio cs2go

[Galería de referencia](evidence/cs2go-gloves/README.md): 96 acabados en 10 modelos, usando las miniaturas originales incluidas en `3kh0/cs2go`, revisión `fb970df0ee8175d9b212d310f6a928f9f61014f2`. Son imágenes del catálogo original del repositorio, no imágenes generadas ni capturas de los guantes adaptados a este juego. Se entregan por separado y no los reinstalan. Hay una galería HTML autónoma con buscador y diez láminas por familia. Los derechos de Valve/autores permanecen separados; no se afirma permiso de redistribución general.
