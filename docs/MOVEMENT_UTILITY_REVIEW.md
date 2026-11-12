# Revisión de movimiento, molotov y pantalla del C4

## Movimiento (presentación; física conservada)

`ModernAgentPose` sigue usando los clips nativos ya importados. No se reemplazan modelos, armas ni clips de recarga/disparo:

- Mezcla las dos direcciones cardinales nativas al desplazarse en diagonal, manteniendo la fase normalizada de la zancada.
- Conserva el reloj de locomoción al cambiar velocidad. Ajusta la transición a 0,20 s para cambios de postura, 0,10 s para entrada en salto/aire y 0,12 s para otros cambios.
- Usa el despegue hacia delante sólo cuando hay avance; los saltos laterales/hacia atrás mantienen el despegue genérico.
- Salto, salto agachado y caída son secuencias de una sola pasada: mantienen su última pose, en vez de repetir el despegue mientras se permanece en el aire.
- La absorción visual del aterrizaje depende de la velocidad vertical previa. No cambia el impulso del salto, gravedad, cápsula, precisión ni reglas GoldSrc/CS2.
- Primera persona: entrada/salida gradual del balanceo de caminar, menor amplitud agachado y transición suave del ladeo lateral. Se conserva la inercia aérea y los clips originales del arma.

## Molotov

Vidrio exterior: opacidad 0,48 → 0,72; superficie intermedia: 0,36 → 0,58. Tinte RGB 0,82/1,04/0,88 → 0,46/1,12/0,56, con mayor absorción verde de la transmisión. Ambas variantes de culling reciben el mismo cambio. Etiqueta, tela, líquido, sonidos y simulación del incendio no se reemplazan.

## C4: causa y restauración

El `v_c4.glb` importado tenía la carcasa y manos, pero no la primitiva independiente `weapon_c4_digits`, ni su atlas/actualización de filas. Por eso la pantalla quedaba vacía aunque se reprodujeran pulsaciones y sonidos.

Se restaura esa primitiva original: 12 vértices, 10 triángulos y UVs del atlas nativo. El ajuste ortogonal a la carcasa ya instalada usa correspondencias UV, con un error p95 de 0,0000030173 m. Se admite la reflexión que ya tiene ese espacio de coordenadas; no se remodela la bomba.

El LCD se vincula al hueso animado `weapon_hand_r`. Sus filas siguen el tiempo del clip `pressbutton`, convertido desde los 3 segundos de plantación del juego. Cancelar devuelve la fila inicial. Es una corrección de la pantalla de primera persona durante la plantación, no un nuevo contador de la bomba colocada.

Reproducción: `python -m tools.source.restore_c4_display <c4.cs2.skin> <c4_visuals.json>`.

Fuentes: [ScCsgoKnives, revisión fd1082b3](https://github.com/zh667/ScCsgoKnives/tree/fd1082b388c0274132181ab2621520819a48a12c), `src/ScCsgoKnives/AnimationData/c4.cs2.skin`, `c4_visuals.json` y `Assets/Textures/ScCsgoKnives/weapon_c4_digits.png` (blob `51acd2b5e79f5298083c2833adb85aa1e051d150`). Arte original de Valve/portadores: esta referencia no concede ni afirma permisos de redistribución adicionales. Se conservan los avisos existentes de archi/BDS y demás autores.

## Búsqueda de desactivación con cables

Se revisaron los paquetes fijados de ScCsgoKnives y cs2go (`fb970df0ee8175d9b212d310f6a928f9f61014f2`). No se encontró en ellos un clip nativo de primera persona que conecte cables al desactivar:

- [Fuente del C4 de cs2go](https://github.com/3kh0/cs2go/blob/fb970df0ee8175d9b212d310f6a928f9f61014f2/packages/assets/public/models/animations/c4/source.json) declara explícitamente: “First-person only; no defuse clip.”
- `models/agents/inspects/animations/weapon/defuser.glb` contiene `sh_buymenu_defuser`: una animación del agente para el menú de compra, sin malla ni secuencia de desactivación con cables.
- [bomb-defuse.ts](https://github.com/3kh0/cs2go/blob/fb970df0ee8175d9b212d310f6a928f9f61014f2/apps/game/src/bomb-defuse.ts) sí contiene una recreación procedural de herramientas y cables y dice “not presented as a Valve defuse clip”. No se importó ni se presenta como una animación nativa de CS2.

Esto documenta lo encontrado en esos recursos, no demuestra que el clip no exista en otras versiones del juego o en otros archivos. La desactivación jugable actual permanece funcional; no se sustituye por una animación falsa.

## Validación y evidencia renderizada

- Implementación: `cdb0398d`, refinamiento y pruebas ampliadas: `dbd8e015`.
- [Primera ejecución](https://github.com/ShadowNigth/15/actions/runs/43236552750): 71 comprobaciones, 0 fallos.
- [Ejecución ampliada](https://github.com/ShadowNigth/15/actions/runs/43238761703): **91 comprobaciones, 0 fallos**, Godot 4.3, GL compatibility, render por software y paso fijo de 60 FPS. Ocho alias de agente; caminar, diagonales, salto normal/agachado, caída sin reinicio de clip, pantalla animada y material del molotov.
- Capturas reales de la escena de pruebas: [LCD durante plantación a 1,7 s](evidence/motion-utility/c4_digits_17.jpg), [salto normal](evidence/motion-utility/motion_jump.jpg), [salto agachado intermedio](evidence/motion-utility/motion_crouch_jump_mid.jpg), [diagonal](evidence/motion-utility/motion_diagonal.jpg), [molotov](evidence/motion-utility/molotov_green.jpg). No son imágenes generadas ni pruebas limitadas a idle; tampoco son una grabación de una partida completa.
- Regresiones del mismo commit: Experimental movement, Squad and interaction y Hitbox and weapon accuracy terminaron correctamente. **No se afirma que toda la CI esté verde**: Modern agents gameplay falló dos expectativas `headshot radius follows larger body` (exigen radio fijo `0.115 * 1.08`, aunque `SkeletalHitboxes.fit_head` ajusta la cabeza a la malla). Su importación pasó 723 comprobaciones; gameplay informó 587 comprobaciones y 2 fallos. No se alteraron las hitboxes para satisfacer esa expectativa antigua. Otras suites seguían pendientes al preparar este informe.
- Persisten advertencias del importador/renderer; este resultado no significa ausencia total de advertencias.
