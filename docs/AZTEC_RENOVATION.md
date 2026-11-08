# Aztec: renovación visual de ruinas tropicales

Capa visual independiente sobre Aztec pulido (`57034ba0`), activada exclusivamente
para `de_aztec`. Se puede desactivar con `visual_renovation = false` en los datos
pasados a MapLoader, sin cambiar el mapa original.

- Cornisas escalonadas y frisos con glifos en 197 paños rectangulares sólidos.
  Se apoyan en superficies existentes, por encima de la altura de los jugadores;
  no se rellenan puertas, ventanas ni huecos arquitectónicos.
- Helechos geométricos colgantes en una selección de muros altos.
- 19 árboles tropicales con frondas y 4 templos escalonados en el fondo, totalmente
  fuera de los límites jugables. No son nuevas coberturas ni lugares accesibles.
- Cielo tormentoso con capas de nubes direccionales que se desplazan lentamente,
  conservando el arte original `doom1` en el horizonte. Sin relámpagos ni destellos.
- Bruma verde-gris muy tenue compatible con OpenGL, no niebla volumétrica.

Las cinco texturas (`aztrim`, `-0azwll`, `azstata`, `azgrass`, `rope`) ya pertenecen
al mapa. No se reemplazan ni alteran sus PNG originales ni las UV del BSP.
La decoración usa color por vértice para sombras mates horneadas, no luces extra.
Agua, puente reparado, armas, personajes y objetivos conservan sus sistemas.

Presupuesto: 15.946 triángulos, 44 celdas, 5 materiales. Las celdas locales tienen
corte a 95 m y el fondo a 260 m. Sin colisiones, navegación, nuevas precargas,
sombras dinámicas ni geometría sobre las rutas. La decoración tiene un coste:
los recuentos de primitivas no deben presentarse como mejoras de FPS.

`tools/build_aztec_renovation.py` reproduce el GLB y el informe
`data/aztec_renovation.json`. `tests/check_aztec_renovation.py` verifica el
presupuesto, anclajes altos, límites del fondo, texturas originales y que el BSP,
los datos de juego y Dust2 permanezcan idénticos a la entrega anterior.

`AztecRenovationTest.tscn` hereda la batería nativa de Aztec: 752 rayos físicos,
32 apariciones, rutas de 514 nodos hacia ambos objetivos, bots en movimiento,
cruce real del puente en ambos sentidos, penetración de la red y C4/kit.
Compara las mismas cámaras con/sin decoración, incluido cielo y copas de árboles,
y comprueba que los nodos decorativos no introduzcan colisiones.
La integración de agua se ejecuta por separado. Las capturas PNG y los registros
quedan en el artefacto del workflow `Aztec visual renovation QA`.
