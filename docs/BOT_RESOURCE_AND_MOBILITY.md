# Segunda iteración: recursos, actividad y terreno

Base: `37b3a3e8`. Se recuperó la entrega remota en la misma rama, conservando respaldo del árbol previo en `/home/user/recovery/before-bot-mobility.tar.gz`. No se cambian los modelos clásicos, decorados retirados, esqueletos, armas ni la función GoldSrc de CSActor.

## Referencias examinadas

- [YaPB 6ed2ef55](https://github.com/yapb/yapb/blob/6ed2ef55eab321bdfe0cc995742903b952a95d15/src/navigate.cpp): `CanJumpUp` distingue espacio frontal, superior y lateral; `CanDuckUnder` estudia el espacio inferior; `IsDeadlyMove` sondea el suelo en el recorrido; la detección de atasco separa escalera, obstáculo rompible, intención y progreso. Es un bot comunitario para CS clásico, no el bot oficial CS2.
- [ReGameDLL_CS 70307312](https://github.com/rehlds/ReGameDLL_CS/blob/70307312cde05cec5d73a3d3a384b4bdac3d5fe2/regamedll/dlls/bot/cs_bot_pathfind.cpp): escalera con aproximación/ascenso/descenso/desmontaje, detección de caída y replanteo. Importante: `IsStraightLinePathWalkable` retorna `true` antes de su antiguo sondeo, con un comentario sobre bloqueos en conductos. No se presenta ese código inalcanzable como protección activa ni se traslada ciegamente: prohibir toda bajada bloquearía las rutas legítimas.
- Se mantiene la revisión anterior de perfiles públicos CS2 y el límite de CS:GO: no hay código oficial completo autorizado analizado ni una medición cuadro a cuadro de partidas oficiales. Esta iteración estudia código público de navegación clásica y aplica soluciones propias; no afirma calco ni igualdad de movimientos con Source 2. No se copiaron módulos externos, con especial cuidado por las cabeceras GPL de ReGameDLL.

## Por qué podían parecer inactivos

1. **Arma vacía retenida:** la selección anterior solo buscaba pistola cargada desde primaria a menos de 14 m. Sin reservas y sin pistola utilizable podía seguir intentando disparar la misma arma vacía.
2. **Cuchillo tratado como rifle:** parte de la selección lo sustituía por primaria sin mirar munición. El movimiento mezclaba avance con strafe y pausas de ráfaga de rifle en lugar de cerrar distancia directamente.
3. **Ruta fallida marcada como objetivo válido:** `_has_goal` se fijaba antes de saber si A* entregaba camino. Ahora refleja si el camino existe.
4. **Ruta vacía sin recuperación propia:** la navegación retornaba inmóvil. Ahora, para bots libres en DE/DM sin orden de mantener ni rol de bomba, hay un intento de replanteo cada 1,6 s. No se aplica a esperas deliberadas VIP/rehenes ni a guardias de bomba.
5. **Camping opcional largo:** se reduce para no francotiradores a 3–6 s. Contactos recientes y sonidos interrumpen el camping opcional; los roles de objetivo no se convierten en persecución ciega.

No toda inmovilidad es un fallo: recarga, apuntado, defuse, guardia de C4, espera del jugador y escolta pueden requerir detenerse. Se preservan esas diferencias y la excepción estable CT en mapas de rehenes.

## Munición y recogida

- Priorizar un arma ya cargada, incluida pistola sin el antiguo límite de 14 m.
- Si no hay cargador utilizable pero sí reservas, equipar y recargar en lugar de abandonar un arma recuperable.
- Sin munición en ambas armas: buscar un arma de fuego del suelo a menos de 9 m, dentro de percepción frontal o alcance inmediato, con munición, línea de visión, corredor y suelo continuos. Escaneo como máximo cada 0,4 s por bot; no hay precarga ni caché global.
- Respetar bloqueo del donante, cooldown, altura, alcance real y arma aún existente. No recoger C4/granadas como sustituto de fusil.
- Permitir sustituir una primaria/secundaria totalmente seca aunque su slot esté ocupado. El arma seca se deja como entidad física; el inventario recibe cargador y reservas reales de la recogida. El drop tomado se consume una vez; una entidad pendiente de borrado no puede recogerse otra vez.
- La búsqueda no conoce armas ocultas detrás de paredes y no teletransporta al bot. Al perder visibilidad o apoyo local abandona ese intento.

## Combate sin munición

Si no hay suministro visible utilizable, equipar cuchillo una sola vez, sin reiniciar el deploy en cada frame. Perseguir al enemigo visible cerrando distancia, sin pausas de ráfaga ni strafe de rifle, y ejecutar el ataque nativo al estar cerca y alineado. Si la aproximación directa no es transitable, intentar la ruta del grafo hacia la última posición visible. Nunca leer una posición oculta para mantener la persecución: siguen vigentes las correcciones de percepción de la primera iteración.

## Terreno y movimiento

- Antes de desplazamientos laterales de combate, comprobar suelo en dos distancias y tres posiciones de anchura. Probar alternativas laterales o detenerse si no hay apoyo.
- La salida improvisada de un atasco ya no elige una dirección sin suelo simplemente porque todas las opciones sean malas: devuelve dirección cero si ninguna es válida.
- Los saltos improvisados exigen obstáculo superable, espacio superior y un aterrizaje con normal caminable. Los saltos marcados en el grafo conservan sus velocidades y los descensos/escaleras conservan su lógica propia.
- Se conserva el agachado por conducto, salto-agachado y salida de escalera; no se cambian gravedad, aceleración, velocidad GoldSrc ni las máscaras de colisión.

Los rayos de terreno son heurísticas, no una prueba matemática del arco completo de la cápsula. Escaleras y rutas estrechas necesitan seguir pasando misiones reales; no se garantiza que todos los puntos de los 26 mapas estén resueltos por estas pruebas.

## QA

`BotResourceMobilityTest` usa física real para probar selección de pistola/cuchillo/recarga, deploy estable, suelo/borde/vacío, arma visible/oculta/vacía/bloqueada, sustitución de slot, conservación de munición, consumo único, salto con aterrizaje, techo, agachado y avance real con cuchillo. Se añade a la suite junto a percepción, misiones Estate/747/OilRig, combate, utilidades, audio y render animado.

La validación estática local pasa. La compilación y ejecución Godot se verifican en Actions; no confundir el AST local con prueba nativa ni afirmar éxito antes de finalizar esa ejecución.

## Compatibilidad de rescate

La primera ejecución de esta iteración compiló y aprobó el render de movilidad/daño de cuchillo, pero Estate no completó el tercer rescate; el control anterior sí lo completó. Por ello los CT en mapas `cs_*` conservan el criterio entregado de salto improvisado, elección de salida de atasco y validez de objetivo. Las nuevas restricciones de terreno no se presentan como activas en esa navegación especial. Las mejoras de munición/percepción/combate siguen disponibles; el VIP no persigue armas que no puede recoger. La persecución con cuchillo frena con input contrario antes de solapar la cápsula enemiga, sin modificar velocidades de física. La siguiente ejecución debe confirmar la compatibilidad.
