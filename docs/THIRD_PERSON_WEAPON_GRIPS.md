# Armas equipadas de los bots: agarre, orientación y tamaño

## Alcance

Corrección de la presentación de armas, granadas y cuchillos en manos de los **ocho agentes modernos**. Se mantiene el modo clásico como fallback con sus modelos previos. No se modifican modelos/animaciones de primera persona, física, daños, inventario, objetos caídos, proyectiles ni cadáveres.

## Causa y solución

Los `p_` anteriores se ajustaban al volumen de otro modelo mediante ICP. Un encaje de silueta no identifica el puño, puede invertir la dirección de un modelo de forma parecida, y no garantiza que dos armas tengan escala coherente. El socket compensaba los ejes de los personajes clásicos y las pulgadas de los nuevos, pero no esos errores internos de los props.

Ahora los props equipados se extraen de los **modelos y poses idle ya instalados**: se evalúa el skin completo con sus matrices inversas de bind y se conservan únicamente superficies de arma, UVs y materiales. No se incluyen brazos ni guantes. La geometría se centra en la muñeca real de agarre, no en el centro del AABB.

Se recupera un marco anatómico con las bases de los dedos índice, medio y meñique para alinear cada agarre al de cada agente. Las transformaciones compensan las unidades del esqueleto, usan escala uniforme y mantienen el aumento visual del 8% del bot. El soporte de la mano izquierda de los rifles se calcula desde ese mismo modelo, no desde la silueta antigua.

- 43 slots jugables y las 23 opciones de cuchillo instaladas (original incluido).
- 67 props: los modelos de dos pistolas y Shadow Daggers se separan y acoplan a **cada mano**, sin una segunda pieza flotando en el espacio de la derecha.
- El mechero de primera persona del molotov no se pega a la mano derecha en tercera persona.
- Corrección de winding al hornear transformaciones reflejadas; no se usa escala negativa para dar vuelta armas.
- Escalas de presentación independientes: se limitan armas sobredimensionadas con referencias de longitud, sin normalizar todos los cuchillos a una única longitud ni alterar `world_scale` del suelo. Son objetivos de presentación aproximados, no mediciones de precisión de armas reales.
- Destellos/luces de disparo siguen el extremo delantero del nuevo prop, en vez de un desplazamiento fijo para todos los tamaños.
- Se limpia la pieza izquierda al cambiar de arma o morir.

## Reproducción

`python -m tools.source.build_held_weapon_grips` con numpy y pillow. El proceso es offline y sólo usa recursos que ya estaban en el proyecto. Produce `assets/models/held/` y `data/held_weapon_grips.json`; no modifica los GLB de origen. La tabla conserva SHA-256 del viewmodel usado. Continúan vigentes los créditos y limitaciones de los recursos archi/BDS/ScCsgoKnives/Valve existentes; no se afirman permisos nuevos.

## Validación

Suite `HeldWeaponGripTest`: todos los slots en SAS/Phoenix, muestras en los otros seis agentes, todas las opciones de cuchillo, anclaje de muñeca, escalas métricas uniformes, dirección de geometría real y separación de la pieza izquierda; capturas del renderer de Godot, incluyendo cambio de postura y giro. Las hojas de contacto se generan exclusivamente a partir de esos framebuffers.

Resultado renderizado pendiente. Verificación estática inicial: 59 scripts, 53 referencias, 43 armas, 26 mapas, 392 GLB y 1021 WAV, sin errores.
