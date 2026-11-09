# Revisión de bots y rehenes: alcance real

## Base y preservación

Trabajo basado en la entrega `6e8f5ec287ff1c6b33f20713322f517269297160`, recuperada en la misma rama con autorización del usuario. Respaldo previo: `/home/user/recovery/before-bot-work.tar.gz`. Investigación de agentes preservada en `research/cs2_agents/`. Sin cambios a GoldSrc, personajes clásicos, armas, esqueletos ni mapas BSP.

## Fuentes y límites

- [ReGameDLL_CS 70307312](https://github.com/rehlds/ReGameDLL_CS/tree/70307312cde05cec5d73a3d3a384b4bdac3d5fe2): reconstrucción comunitaria de CS 1.6/Condition Zero; permite estudiar bots tipo CZ y rehenes. NO es el motor de CS2 ni prueba de que todos los servidores 1.6 usen esos bots. El LICENSE raíz dice MIT, pero archivos examinados de bots/rehenes conservan cabeceras GPL-2.0-or-later con excepción HL: no asumir licencia uniforme. No se copiaron implementaciones.
- [YaPB 7ba1da12](https://github.com/yapb/yapb/tree/7ba1da12fbc2e34a4a77e65c1c1f7cf51c55b029): bot comunitario para Counter-Strike, no bot oficial Valve. UNLICENSE. Se examinaron selección/retención de enemigo y separación de sospecha/contacto en `src/combat.cpp`; no se transplantó C++.
- [GameTracking-CS2 cce7bf1f](https://github.com/SteamDatabase/GameTracking-CS2/blob/cce7bf1f190144c1c08fb0fe75fd3c9514f2637f/game/csgo/pak01_dir/botprofile.db): perfiles distribuidos del juego, no algoritmo completo. Default declara Skill=50, Aggression=50, ReactionTime=0.3, Teamwork=75 y parámetros de enfoque/aceleración de mirada, con plantillas de preferencias de arma. No copiar esos valores aisladamente como si reprodujeran la IA.
- Para CS:GO se examinó el árbol histórico público [06f68b4b, anterior a septiembre de 2023](https://github.com/SteamDatabase/GameTracking-CSGO/tree/06f68b4b70d9bb3e6491dbac25d53a18835e95c4): no apareció `botprofile.db` ni la implementación completa de bots. El nombre GameTracking-CSGO actual redirige al seguimiento CS2: no contarlo como segunda fuente independiente de CSGO. No se usaron filtraciones ni se afirma revisión línea a línea de código oficial que no está disponible.

**Resultado de alcance:** revisión focal de módulos públicos concretos, no auditoría exhaustiva de todos los archivos ni calco certificado de CS2/CSGO/1.6. Un calco exacto exigiría código completo autorizado o mediciones de referencia por versión/dificultad/mapa, además de navegación y física equivalentes. Aquí se conserva GoldSrc por instrucción previa.

## Paso a paso: percepción y combate

1. `ReGameDLL_CS/regamedll/dlls/bot/cs_bot_vision.cpp`, `IsVisible`: distingue visibilidad de partes del cuerpo; la sección de cola de reacción conserva instantáneas retrasadas según perfil. La información sensorial y la reacción no son simplemente acceso permanente al actor enemigo.
2. `YaPB/src/combat.cpp`, `LookupEnemies`: separa SeeingEnemy de SuspectEnemy, conserva memoria temporal y contempla cegamiento/ignorar enemigos. Retener una sospecha no equivale a tener visión actual. Sus reglas de disparo a través de paredes son otro subsistema, no autorización para apuntado perfecto a coordenadas ocultas.
3. Nuestro `_physics_process` solo escaneaba enemigos cada 0,12–0,22 s, pero mientras retenía `target_enemy` actualizaba su posición viva cada frame. Al cruzar una esquina podía seguir leyendo coordenadas ocultas durante ese intervalo.
4. Cambio propio: `_validate_visual_contact()` comprueba vida/visibilidad antes de prioridades tácticas. Al perder visión, elimina el objetivo actual sin actualizar la última posición observada. Mantiene la investigación de memoria existente; no añade wallbang automático.
5. Nuestro `_on_taken_damage_from` usaba coordenadas exactas del atacante, orientaba la mirada hacia ellas y las enviaba a compañeros incluso sin visión. Cambio propio: solo el contacto visible actualiza memoria visual y comunica ubicación exacta. El impacto oculto queda como evidencia local para investigar, no como localizador a través de paredes. Se mantiene la reacción rápida al atacante visible.
6. No se cambiaron la física de movimiento, tasas de giro, recoil, compras, economía o selección de rutas para fingir igualdad con otro motor. El coste del raycast extra por objetivo activo requiere medición con muchos bots.

## Paso a paso: navegación y objetivos

1. `ReGameDLL_CS/regamedll/dlls/bot/cs_bot_listen.cpp`, `ShouldInvestigateNoise`: contempla disposición, tiempo seguro, diferencia de pisos y distancia de navegación; una distancia euclídea no basta para interpretar un ruido.
2. Nuestro bot ya dispone de rutas YaPB, personalidades, coberturas, tareas de bomba, escolta VIP y recuperación. No se sustituyó ese conjunto por un único comportamiento de persecución.
3. La negociación nueva CT en mapas de rehenes sigue desactivada como en la entrega estable: reactivarla sin comprobar Estate volvería a introducir una regresión conocida. Las pruebas de misiones existentes siguen siendo la puerta de aceptación.
4. Pendiente de una siguiente iteración: evaluación sistemática de investigación de sonidos entre pisos, reacción/enfoque medidos por dificultad, seguimiento de trayectorias y coordinación táctica contra partidas de referencia. No se presenta como trabajo implementado.

## Paso a paso: rehenes

1. `ReGameDLL_CS/regamedll/dlls/hostage/states/hostage_follow.cpp` separa pérdida/muerte del líder, espera, continuación, caminar/correr, bloqueo por amigos y actualización de ruta. Se examinó esa lógica de estados, no se copiaron umbrales ni código.
2. `hostage_improv.cpp` distingue amigos delante/en el espacio personal y contempla recuperación de obstáculos. Esto no demuestra que trasladar sus esperas de varios segundos a nuestro grafo sea correcto.
3. Nuestro seguidor tenía un único umbral de 2,15 m para empezar y detenerse, provocando cambios repetidos de estado al oscilar alrededor del límite.
4. Cambio propio: histéresis; arranca por encima de 2,15 m y, una vez en marcha, continúa hasta 1,65 m. La excepción de completar rescate sigue acercándolo hasta 0,35 m, para que cruce el volumen en vez de quedarse fuera.
5. Al perder/morir el líder ahora limpia referencia, ruta y evasión transitoria, cancela seguimiento y activa miedo acotado. No hay teletransporte, rescate forzado ni nuevo rig. Se conservan escaleras, puertas y recuperación de obstáculos.
6. El nuevo test `BotPerceptionHostageTest` verifica colisión real/visión/memoria/daño oculto y visible, histéresis y muerte del líder. Las misiones completas Estate/747 y VIP deben seguir pasando, además de evidencia animada en la suite de escuadrón. Las pruebas de umbrales no equivalen a prueba visual de rescate.

## Retirada de objetos de Aztec y Dust2

`AztecRenovation.apply` y `Dust2Renovation.apply` ya no cargan ni instancian el GLB decorativo. Se conservan cielo/atmósfera y perfiles de materiales/agua/relieve, además del BSP, puente, colisiones y navegación originales. Las pruebas nativas de renovación ahora exigen ausencia del nodo decorativo, no presencia.

Los GLB y generadores antiguos quedan como recursos inactivos para trazabilidad y compatibilidad de las pruebas de reproducibilidad; no se muestran en partidas. Los checks Python antiguos validan esos archivos archivados, NO prueban la ausencia de decorado en ejecución: eso corresponde a los tests Godot actualizados.

## Validación

- Verificador local: 47 scripts de producción, 49 referencias, 43 armas, 26 mapas, 308 GLB y 1021 WAV: PASS.
- Checks estáticos de recursos decorativos archivados: PASS para ambos mapas.
- Godot local no disponible: descarga bloqueada al redirigir a release-assets.githubusercontent.com. Compilación nativa, nuevas pruebas y regresiones se ejecutan en GitHub Actions; consultar el estado de la ejecución correspondiente antes de afirmar aprobación.

### Primera ejecución nativa (e9777c06)

Las cuatro suites de mapas (Aztec/Dust2, polish/renovación) aprobaron. La suite de escuadrón compiló y aprobó misiones (55), render animado y regresiones previas, pero el nuevo test falló 3/16 porque creaba actores sin activar `is_alive` (por defecto false antes de spawn). Se corrigió únicamente el montaje del test: ambos actores pasan a vivos explícitamente. No se relajaron las expectativas ni se cambió producción para hacer pasar la prueba. La ejecución posterior es la que debe confirmar la corrección.
