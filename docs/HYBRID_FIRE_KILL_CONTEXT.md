# Llamas originales, indicadores de baja y multikills

## Molotov e incendiaria: combinación, no sustitución

El shader `incendiary_flame.gdshader` mezcla un **42 % del atlas original de 16 fotogramas** `grenade_fire_atlas.png` con el fuego procedural existente. Ambos comparten **las mismas cintas cruzadas y parcelas**: no se añaden discos, alfombras planas ni billboards gigantes que ignoren la geometría.

- Fases y velocidades independientes por parcela; interpolación entre fotogramas, incluido el retorno del último al primero.
- Se conservan la forma irregular, centros calientes, bordes naranja/rojo, humo, brasas, calor, encendido escalonado y extinción.
- Propagación, selección de suelo, límites de desnivel y rayos contra paredes siguen siendo los originales del sistema procedural. El atlas es visual: no amplía el radio de daño ni crea otro simulador de fuego.
- El fundido de la textura comparte los uniformes de ignición y extinción de cada parcela. Una parcela extinguida no conserva una llama animada independiente.

## Cinco indicadores confirmados

El killfeed y las cartas usan los PNG originales de ScCsgoDeathmatch:

| Campo | Cuándo se confirma |
|---|---|
| `headshot` | La región esquelética alcanzada por el impacto letal es la cabeza |
| `through_smoke` | El tramo realmente recorrido hasta la víctima atraviesa suficiente humo no vaciado, con el mismo soporte/opacidad que la percepción volumétrica |
| `no_scope` | El arma es un rifle con mira de francotirador y no estaba usando zoom al disparar |
| `attacker_blind` | El atacante tenía un flash significativo (`flash_alpha > 0.2`) al iniciar el ataque, no la víctima |
| `penetration` | La bala completó una salida del mundo/material, rompió y atravesó una barrera o cruzó un impacto de rejilla antes de alcanzar a la víctima |

Los flags pueden coexistir. La penetración **no** se concede por rozar una pared sin atravesarla, ni por el mero hecho de portar un arma capaz de penetrar. Un rifle normal no recibe no-scope. No se han añadido indicadores de salto ni de víctima cegada, porque no forman parte de esta implementación solicitada.

### Conservación del contexto

`KillContext.capture()` congela la ceguera, zoom y una copia de la opacidad/posición de las celdas de humo **antes** de abrir estelas. Cada rayo/pellet acumula su propio recorrido y penetración. Así, el vaciado de la primera bala no borra la evidencia de un disparo que ya estaba en curso, y el humo situado detrás de la víctima no se cuenta.

El contexto se pasa como argumento del daño letal, nunca como una variable global de la última bala. La muerte por una granada o por fuego no hereda flags de un disparo anterior. La ceguera de una granada se fija al lanzarla y se transmite a su explosión o fuego persistente; el cuchillo también conserva la ceguera de su propio ataque.

La señal antigua `kill_logged` de seis argumentos se conserva para compatibilidad. El HUD usa `kill_detailed`, que sólo publica los cinco booleanos confirmados, sin incluir copias del volumen de humo.

## Cartas y bajas consecutivas

- **DOUBLE KILL**, **TRIPLE KILL**, **QUADRA KILL** y contador **5X MULTI KILL** en adelante.
- Ventana móvil de **4 segundos** entre bajas válidas. Una baja tardía empieza otra cadena; el total de la ronda no se borra.
- Titular grande con impulso inicial, retención legible y fundido; carta nueva ampliada durante el destello, con el abanico y los iconos del último ataque.
- Muerte propia: termina la cadena, sin borrar las cartas ganadas. Inicio de ronda/partida: reinicia todo.
- Sólo bajas reales de enemigos del jugador local; no suicidios ni teamkills.
- En Deathmatch se muestran las **cinco cartas más recientes**, con numeración acumulada; cinco bajas en una partida larga no se etiquetan falsamente como ACE.

## Recursos y atribución

`data/kill_polish_assets.json` registra árbol fijado, blob Git, ruta y SHA-256 de seis PNG copiados sin alterar desde `zh667/ScCsgoKnives`: un atlas y cinco indicadores. Fetcher reproducible: `tools/source/fetch_kill_polish_assets.py`.

La adaptación de shaders, eventos y HUD es para Godot. Se mantiene la procedencia original de las texturas: la licencia del código fuente no debe confundirse con una autorización general sobre los recursos derivados de Valve. No se cambian armas, skins, normales, guantes, personajes clásicos ni mapas.

## Pruebas

`tests/KillFirePolishTest.tscn` dispara rayos reales contra hitboxes esqueléticas y una pared penetrable; comprueba contexto inmutable, muerte letal/no letal, humo vaciado, ausencia de flags heredados, ceguera al lanzar, combo/fin de cadena/Deathmatch e integración del atlas en ambas granadas. Guarda capturas OpenGL de doble/triple baja y dos instantes de las llamas en una escena con paredes reales. Se ejecutan también las regresiones previas de fuego, Deathmatch, combate, armas, mapas y rescate.
