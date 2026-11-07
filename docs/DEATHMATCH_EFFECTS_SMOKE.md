# Deathmatch adicional, efectos e iconos

## Uso

En **Play CS 1.5 (LAN / Bots) → Game mode**, elegir:

- **Classic — DE / CS / AS**: rondas, compra, economía, una C4, rehenes y VIP según el mapa, como antes.
- **Team Deathmatch (bots)**: CT contra T, primera escuadra a 40 bajas o mayor puntuación tras 10 minutos. Empate si ambas terminan igualadas. Reaparición tras 3 s, protección durante 2 s que se cancela al disparar, atacar con cuchillo o lanzar una granada. Pantalla final 8 s y nueva partida automática.

La primaria se elige en **DM primary (free)**. Cada aparición entrega esa arma al jugador, una primaria variada a los bots, Deagle, chaleco y casco. No hay compra, C4, rehenes ni VIP en DM, incluso sobre mapas CS/AS. Los puntos de aparición provienen del mapa: se penalizan los ocupados y se favorecen la distancia y la cobertura respecto de enemigos vivos. No se generan armas descartadas en DM; el modo clásico conserva sus descartes.

Es una adaptación local en GDScript, **no** una importación del módulo C# de Survivalcraft, ni networking, ni Deathmatch todos-contra-todos.

## Recursos visuales reales

`data/polish_assets.json` fija el repositorio, árbol, blob Git y SHA-256 de **49 PNG** copiados sin alterar desde `zh667/ScCsgoKnives`:

- 35 siluetas de armas, seis iconos de granadas y dos de armadura/casco.
- Fogonazo y humo de cañón, tres atlas de explosión y un resplandor.

El fetcher `tools/source/fetch_polish_assets.py` reproduce los archivos desde el árbol fijado, sin descargar nada durante el juego. Los nombres antiguos de armas se resuelven con alias explícitos pequeños; no se carga el informe completo de animaciones para dibujar el HUD. Cuchillos, C4 y otros elementos sin PNG correspondiente conservan su icono anterior. **No se vuelve a introducir el icono de cargador:** la munición sigue siendo numérica.

Se usan las hojas presentes en el árbol original, no los archivos `cs2fx_*` citados por un documento de tareas pero ausentes del repositorio. Disparo: cuadrícula 8×4, tramo inicial breve del atlas; humo de cañón: 8×4 y 26 celdas pobladas; explosiones: 4×4 / 16 fotogramas. El reproductor avanza por tiempo transcurrido y respeta la opacidad de origen. Se mantienen sockets, capas de primera/tercera persona, silenciadores, armas dobles, luces y los eventos de casquillos existentes. La explosión utiliza un núcleo corto, polvo y humo; conserva escombros, daño e impulso sin duplicar el impulso físico.

El límite de 96 emisores de atlas es únicamente de efectos transitorios activos; **no** limita cachés ni añade precarga, carga en segundo plano o pantalla de progreso.

## Comparación del humo y correcciones

El proyecto ya tenía expansión volumétrica, túneles por disparos, dispersión por HE y turbulencia al atravesarlo. No se presentan como prestaciones nuevas. Frente al comportamiento descrito por ScCsgoKnives, se refuerzan estas interacciones en la simulación existente:

| Interacción | Problema identificado aquí | Cambio |
|---|---|---|
| HE | Una explosión podía despejar vóxeles detrás de una pared | Línea de visión por vóxel antes de aplicar fuerza y vaciado |
| Bala | Un segmento externo sin recortar podía abrir humo tras una pared | Recorte de la estela en la primera colisión del mundo |
| Cuerpo en movimiento | El tope 0,55 podía rellenar de golpe un hueco de HE más fuerte | La estela nunca reduce un vaciado previo; además respeta paredes |
| Deriva | El centro de una celda desplazada podía cruzar una pared | Barrido del desplazamiento y detención en la superficie |
| Percepción | Radio y umbrales distintos para vista, bots y fundido | Opacidad, expansión y caducidad compartidas; soporte espacial uniforme |
| Fuego | No había extinción de las parcelas por humo denso | Extinción local del combustible alcanzado, sin daño ni propagación desde él; fundido visual corto y bloqueo por paredes |
| Granada de humo sobre fuego | Esperaba siempre al temporizador | Despliegue temprano al alcanzar fuego activo visible |

El shader sigue teniendo detalle y erosión procedurales: la prueba física es una aproximación volumétrica, no lectura de cada píxel. No se afirma identidad visual o física exacta con CS2 ni con el motor de Survivalcraft. Se conservan el fuego irregular, materiales y normales originales, personajes clásicos CT/T y rehenes, y la ausencia de gallinas y de la pantalla de precarga.

## Validación reproducible

- `python tools/verify_godot_project.py` (con `gdtoolkit==4.3.4`).
- Godot 4.3: importación nativa y las suites previas de armas, mundo, combate, rescate y misiones.
- Nueva escena `tests/DeathmatchPolishTest.tscn`: reglas, bots reales en movimiento, protección, bajas/puntuación, respawn, límites, limpieza y retorno a DE/CS clásicos; oclusión/vaciado/deriva/extinción del humo; iconos y reproducción de atlas.
- Con OpenGL y `POLISH_CAPTURE_DIR`, guarda fotogramas reales de disparo en DM, baja, HE animada y volumen de humo. La CI conserva imágenes y registros en `native-world-rendered-evidence`.

## Atribución

Fuente: <https://github.com/zh667/ScCsgoKnives>, árbol fijado en el manifiesto. La adaptación de lógica es propia para Godot; las texturas mantienen su procedencia original. El código GPL del proyecto fuente y los recursos derivados de Counter-Strike/Valve no deben confundirse: no se afirma que la licencia GPL otorgue permiso sobre todos los recursos de Valve ni autorización general de redistribución. Se conservan los créditos anteriores de mapas y texturas, incluidos BDS / CS:GO Ports donde correspondan.
