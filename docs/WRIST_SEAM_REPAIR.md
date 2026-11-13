# Unión guante–antebrazo

## Causa técnica

Los guantes originales y el extremo de los antebrazos originales usan una mezcla de `ForeTwist` y `Hand`. Las mangas dedicadas importadas usaban principalmente `Forearm` en esa misma zona; algunas tenían también pequeñas influencias de dedos. En una pose neutra pueden solaparse, pero durante un giro de muñeca o una inspección no recorren la misma trayectoria.

Una primera corrección de pesos en el GLB canónico no bastó: al pasar a cada rig, las matrices de bind/roll del giro de antebrazo no son intercambiables. Las capturas y la prueba de envolvente detectaron deformaciones con el cuchillo, y esa corrección offline se descartó y revirtió.

## Corrección experimental por rig de destino (desactivada)

`WristSeamFit` trabaja después del retarget de las mangas y antes de retirar el antebrazo original. Toma la geometría y las matrices de bind reales de `ct_arms.bmp` del arma/cuchillo que se está instalando.

- Ajusta progresivamente los pesos en los últimos 12 cm para que el extremo siga la misma articulación que el guante. Conserva las posiciones y normales de la manga: proyectarlas sobre los vértices de un puño con otra topología generaba picos, y se descartó esa proyección.
- Combina una transferencia local suavizada de los ocho puntos originales distintos más cercanos con un perfil longitudinal interpolado de anillos de 1 cm. Copiar un único vértice creaba discontinuidades; un perfil sólo longitudinal ignoraba la articulación curva de la muñeca. Se separan las referencias izquierda/derecha aunque las manos estén muy juntas con la pistola. Usa las matrices de bind originales del destino incluso si un hueso con el mismo nombre ya tenía otro bind en la conversión. No confunde un índice de hueso coincidente con una matriz compatible.
- Conserva UVs, texturas y el resto de la manga dedicada. No escala ni gira la mano, no agrega un aro/cilindro y no cambia las pistas de animación.
- Regenera tangentes y cachea el ajuste por arma/agente/escena de destino; reconstruye los binds correspondientes también al reutilizar la caché.
- Los 19 guantes nativos retirados siguen eliminados y los guantes normales/anteriores conservan sus modelos.

## Validación

Verificación estática: 61 scripts, 53 referencias, 43 armas, 26 mapas, 391 GLB y 1021 WAV, sin errores.

`WristSeamTest` usa el controlador de juego, los ocho agentes, Glock/AK/Karambit y muestras de inspección/recarga/reposo. Compara el borde animado de las mangas con la envolvente del antebrazo original y captura animaciones reales. `AgentViewArmsTest` conserva la comprobación sobre armas/cuchillos y selección independiente de mangas y guantes. La última ejecución experimental, https://github.com/ShadowNigth/15/actions/runs/43356331830 (`55db7772`), **falló** la prueba estricta de envolvente en algunas poses (por ejemplo SAS/AK ~45–47 mm y SAS/Karambit ~47–48 mm frente al límite de 45 mm). Las capturas aún mostraban defectos en algunos bordes. No se modificó el umbral para obtener un resultado verde.

La variante anterior de transferencia por vértice pasó comprobaciones técnicas, pero visualmente generaba picos: tampoco se considera una corrección válida. Las mejoras de suavizado posteriores no cumplen todavía todos los criterios.

**Estado de entrega: problema no resuelto completamente.** `WristSeamFit.enabled` está en `false` por defecto, por lo que la partida conserva las mangas/guantes anteriores y no activa una modificación que aún falla. `WristSeamTest` activa explícitamente el experimento para continuar el diagnóstico. Los ocho GLB, su catálogo y el generador están restaurados a la revisión previa a esta tarea; las modificaciones offline fallidas no permanecen activas.

Pendiente: corregir y validar la continuidad del borde, especialmente en antebrazos descubiertos y en los cambios de rig del cuchillo, antes de habilitar la solución. No se afirma que el bug esté arreglado.
