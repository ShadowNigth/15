# Casquillos, HUD y revisión de personajes

Fuente fijada: `zh667/ScCsgoKnives`, commit
`1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`.
`data/native_world_manifest.json` registra rutas y SHA-256 de entradas/salidas.
No se modifican modelos, skins ni animaciones de armas existentes.

## Casquillos originales

- Ocho mallas originales: AK47, AWP, Desert Eagle, Glock, P90, MAG7, Nova y XM1014.
- Conversión OBJ → GLB conserva los triángulos, posiciones, normales y UV; cada
  GLB incorpora el PNG original sin redimensionarlo. El metal/roughness es una
  adaptación para Godot: no es el shader de partículas de Source 2.
- 33 rutas de armas, obtenidas de `cs2_casings.json`. Conservan el evento de cada
  clip y el retraso del emisor: el AWP expulsa a **0,74 s**, no al disparar.
- Los alias de último disparo, silenciador y las dos manos de Dual Elites se
  resuelven mediante `native_gun_animation_report.json`, no por calibre supuesto.
- El puerto del jugador se transforma desde su hueso animado en el instante de
  expulsión. La matriz de unión se calibra contra los dos rigs en idle; los
  offsets y velocidades de Source permanecen en pulgadas hasta convertirlos a m.
- Los bots conservan el esqueleto GoldSrc: usan la malla y el tiempo originales,
  pero una posición de puerto aproximada relativa a su orientación. No se afirma
  una unión anatómica exacta a un personaje CS2.
- No se inventa expulsión al disparar el R8 o el Zeus. El cambio de arma,
  recarga, nueva acción del jugador, muerte y reinicio cancelan eventos pendientes.
- Física cosmética existente: barrido contra el mundo, rebotes, sonidos de
  contacto ya importados, máximo 36 vainas vivas, desaparición a 3,4 s. Cola
  limitada a 64 eventos. No cambia balística, daños, economía ni tiempos de tiro.
- Desactivar la opción restaura los casquillos anteriores (tampoco genera vainas
  ficticias para R8/Zeus).

## HUD opcional

Ocho PNG originales de reserva: cargador normal/curvo, Bizon, caja, bala, P90,
revólver y cartucho de escopeta. Se colocan junto a los contadores existentes.
El número de reserva sigue siendo **balas**, no un número ficticio de cargadores.
Cuchillo, C4, granadas y Zeus no muestran iconos inapropiados.

Opciones independientes: iconos y colores de advertencia de poca munición.
No se reemplaza el HUD, el menú circular, radar, objetivos ni killfeed.
Las cinco preferencias cosméticas se guardan en `user://cosmetics.cfg` desde
Configuration & Controls. No se escribe configuración personal en el proyecto.

## CT/T: revisión, no sustitución ciega

> **Actualización:** los modelos de revisión `native/ct`, `native/t`, `native/hostage` y `native/chicken` ya no se distribuyen (el juego nunca los cargaba; ver [ASSET_PACKS.md](ASSET_PACKS.md)). El modo de rehenes y el VIP se retiraron del proyecto. El texto siguiente se conserva como registro histórico.

En el Arsenal aparecen `[Native review] ct`, `t` y `defuser_item`. El selector
permite reproducir sus clips.

- CT SAS y T Phoenix: los GLB upstream traen sólo un marcador
  `__sc_prebaked_*`, **no las animaciones ejecutables**. Se decodifican los
  archivos externos `ct.scanim`/`t.scanim`, verificando firma, nombres y estructura,
  y se reconstruyen los 170 clips de cada uno por nombre de nodo. Mallas, UV,
  pesos, inverse binds, materiales y bytes de imágenes permanecen intactos.
  Se omiten únicamente las traslaciones de `root_motion` para revisión en sitio.
- **Los personajes jugables, bots y clases clásicos no se reemplazan.**
  Su mezcla gait/upper-body, arma adjunta, crouch, muerte y navegación
  continúan usando los esqueletos y reglas probados. Los modelos candidatos aún
  requieren esa integración específica antes de sustituirlos en partidas.
- El kit sí se integra: `defuser_item.glb`, la bolsa de herramientas de cintura
  de CS2, junto a su textura externa original `defuser_item.png` (el GLB fuente
  no contiene materiales), sustituye opcionalmente la apariencia del kit caído. Conserva el
  sistema de física/AABB, compra y recogida por CT y 5/10 segundos de desactivación.
  Existe fallback al thighpack clásico si se desactiva o falta el candidato.

## Gallinas ambientales (retiradas)

Las gallinas decorativas de Italy, Inferno y Cobble se eliminaron por completo:
script, GLB, audio y spawns. No afectaban a equipos, economía ni condiciones de
victoria, y su retirada no cambia ninguna partida.

## Validación

`NativeWorldAssetsTest.tscn` utiliza la partida real de Italy, disparos de producción,
cola de eventos, mallas cargadas por Godot, iconos, kit recogible y
reproducción de candidatos. Comprueba AWP antes/después de 0,74 s, cancelación al
cambiar/morir y exclusión de R8/Zeus. CI captura imágenes
OpenGL reales de la partida y dos fases de los modelos en movimiento.
Ver los resultados del run correspondiente, no tomar la existencia del test como
prueba de que pasó. Las regresiones completas de armas, audio y cuchillos
se siguen ejecutando en el workflow nativo.

## Derechos

Valve conserva los derechos de los recursos de CS2. El código upstream usa GPL-3.0;
la presencia de archivos en GitHub no concede una licencia nueva de redistribución
entre juegos. Se mantienen las atribuciones y limitaciones de
`docs/KNIFE_ASSET_NOTICES.md` y los avisos originales. No se importan binarios ni
código C# de ejecución de Survivalcraft; el runtime de esta incorporación es GDScript.
