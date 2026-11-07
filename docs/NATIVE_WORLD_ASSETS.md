# Casquillos, HUD, revisión de personajes y gallinas

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

## CT/T y rehén: revisión, no sustitución ciega

En el Arsenal aparecen `[Native review] ct`, `t`, `hostage`, `defuser_item` y
`chicken`. El selector permite reproducir sus clips.

- CT SAS y T Phoenix: los GLB upstream traen sólo un marcador
  `__sc_prebaked_*`, **no las animaciones ejecutables**. Se decodifican los
  archivos externos `ct.scanim`/`t.scanim`, verificando firma, nombres y estructura,
  y se reconstruyen los 170 clips de cada uno por nombre de nodo. Mallas, UV,
  pesos, inverse binds, materiales y bytes de imágenes permanecen intactos.
  Se omiten únicamente las traslaciones de `root_motion` para revisión en sitio.
- El rehén conserva el GLB upstream byte a byte: siete clips. Upstream adapta
  poses rifle/knife de personajes por nombre de hueso; no son siete acciones
  originales específicas de rescate de rehenes de CS2.
- **Los personajes jugables, bots, clases, VIP y rehenes clásicos no se reemplazan.**
  Su mezcla gait/upper-body, arma adjunta, crouch, muerte, navegación y rescate
  continúan usando los esqueletos y reglas probados. Los modelos candidatos aún
  requieren esa integración específica antes de sustituirlos en partidas.
- El kit sí se integra: `defuser_item.glb`, la bolsa de herramientas de cintura
  de CS2, junto a su textura externa original `defuser_item.png` (el GLB fuente
  no contiene materiales), sustituye opcionalmente la apariencia del kit caído. Conserva el
  sistema de física/AABB, compra y recogida por CT y 5/10 segundos de desactivación.
  Existe fallback al thighpack clásico si se desactiva o falta el candidato.

## Gallinas ambientales

GLB upstream con idle/walk/run y textura embebida, byte a byte. El propio upstream
ya elimina el desplazamiento root_motion: nuestro CharacterBody3D mueve el cuerpo
sin sumar dos veces la distancia del clip.

- Italy: hasta cuatro; Inferno y Cobble: hasta tres cada uno. Sin gallinas en
  OilRig, Tundra, aviones, oficinas ni los demás mapas.
- Selección determinista y espaciada de puntos sobre el suelo BSP. Se validan
  pendiente, suelo, altura, separación y exclusión de agua/escaleras/objetivos/spawns.
  Si no hay suficientes sitios válidos se crean menos, nunca dentro de la pared.
- Alternan reposo y paseo, huyen al oír disparos, evitan paredes y desniveles y
  permanecen cerca de su zona. Voces espaciales originales a intervalos limitados.
- Reciben disparos/cuchillo, fuego y explosiones sin cobertura. Muerte con caída
  visual adaptada; no se afirma que haya un clip nativo de muerte o ragdoll.
- No forman parte de actores de equipos, blancos de los bots, economía,
  killfeed ni condiciones de victoria. No bloquean el paso. Se restauran por ronda.
- Opción para ocultarlas y desactivar su colisión y actividad.

## Reconstrucción (sólo desarrollo)

```
python tools/source/fetch_native_world_assets.py /RUTA/world-source
python tools/source/fetch_native_gun_animations.py /RUTA/gun-json
# numpy y scipy como dependencias de desarrollo, no de ejecución:
python -m tools.source.build_native_world_assets /RUTA/world-source /RUTA/gun-json
python tests/check_native_world_assets.py
```

Godot abre los recursos ya generados sin Python, gh, extracciones locales ni red.
Las entradas y el ejecutable Godot no se incluyen en el ZIP editable.

## Validación

`NativeWorldAssetsTest.tscn` utiliza la partida real de Italy, disparos de producción,
cola de eventos, mallas cargadas por Godot, iconos, kit recogible, gallinas y
reproducción de candidatos. Comprueba AWP antes/después de 0,74 s, cancelación al
cambiar/morir, exclusión de R8/Zeus y reinicio de los animales. CI captura imágenes
OpenGL reales de la partida y dos fases de los modelos en movimiento.
Ver los resultados del run correspondiente, no tomar la existencia del test como
prueba de que pasó. Las regresiones completas de armas, audio, cuchillos y misiones
se siguen ejecutando en el workflow nativo.

## Derechos

Valve conserva los derechos de los recursos de CS2. El código upstream usa GPL-3.0;
la presencia de archivos en GitHub no concede una licencia nueva de redistribución
entre juegos. Se mantienen las atribuciones y limitaciones de
`docs/KNIFE_ASSET_NOTICES.md` y los avisos originales. No se importan binarios ni
código C# de ejecución de Survivalcraft; el runtime de esta incorporación es GDScript.
