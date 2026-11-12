# Hitboxes de objetos caídos y ragdolls articulados

## Objetos en el suelo

La caja anterior añadía mínimos de 22 × 13 × 18 cm incluso a objetos pequeños y márgenes adicionales al modelo. Esa zona de recogida se confundía con la superficie que recibe disparos.

- Las balas y el cuchillo ahora consultan los triángulos reales del modelo `w_` instalado, con colisión de ambas caras en la capa 4. No se usa la caja ampliada como superficie de impacto.
- Se acumulan las transformaciones de todos los nodos de malla. El centrado, escala y rotación se aplican igual al modelo y a su colisión, incluso durante el giro del objeto.
- Se conserva la transformación raíz de los archivos importados; no se sobreescribe su escala nativa al centrar el objeto. Importante para modelos con unidades distintas, como el kit de desactivación.
- Formas compartidas por modelo/escala, sin duplicar triángulos por cada instancia.
- Cobertura: todos los slots de armas, granadas, C4, variantes de cuchillo y kit de desactivación.

La recogida por proximidad conserva su radio independiente. La simulación de vuelo/contacto de los objetos conserva el barrido continuo y los apoyos de suelo anteriores: la nueva superficie triangular es la **hitbox de impactos**, no un reemplazo de esa simulación por cuerpos cóncavos dinámicos.

## Ragdolls

`ActorRagdoll` crea once cuerpos rígidos en unidades métricas: pelvis, tórax, cabeza, brazos/antebrazos y muslos/pantorrillas. Diez articulaciones ConeTwist limitan la apertura y torsión. Se toma la pose viva al morir, sin saltar al final de una animación de muerte; cada cuerpo conduce los huesos correspondientes del esqueleto real.

- Compatibilidad con los ocho agentes modernos y la nomenclatura clásica; no se reemplazan mallas ni materiales.
- Colisión con el escenario, fricción, amortiguación, CCD y reposo automático del motor. No bloquean el movimiento de jugadores y bots ni colisionan consigo mismos.
- La gravedad usa el perfil GoldSrc o CS2 seleccionado, compensando la gravedad base del motor; no adopta accidentalmente los 9,8 m/s² predeterminados.
- Velocidad heredada al morir, impulso direccional del disparo mortal y reacción posterior a disparos/cuchillo y explosiones. Las explosiones sobre cuerpos existentes comprueban cobertura del escenario.
- Sangre de contacto cuando la pelvis encuentra apoyo en el suelo.
- La simulación deja de usar el antiguo deslizamiento de raíz y los clips de muerte mientras el ragdoll está activo. Los clips y la ruta anterior siguen disponibles como fallback si no se puede construir el ragdoll.
- Reaparición/cambio de modelo: elimina cuerpos y articulaciones, limpia overrides del esqueleto. Al liberar el actor se libera todo su ragdoll.
- Se conservan la caída de armas/granadas, una sola bomba, puntuación, cámaras y notificaciones de muerte. No se modifica la física del personaje vivo ni sus hitboxes de daño.

El alcance de esta revisión son los actores jugables/bots basados en `CSActor`; no añade ragdolls a pollos ni sustituye modelos de rehenes.

## Validación

`DropRagdollTest` compara los triángulos de cada hitbox con la malla transformada y lanza rayos contra su superficie; recorre todos los slots, opciones de cuchillo y el kit. Comprueba los once cuerpos/diez articulaciones en los agentes y el fallback clásico, caída por gravedad sobre suelo/rampa/escalón, posiciones finitas, reacción a impactos y limpieza al reaparecer.

[Validación renderizada final](https://github.com/ShadowNigth/15/actions/runs/43253968919), commit `2d79ab02`: **609 comprobaciones, 0 fallos**, Godot 4.3, GL compatibility por software y paso fijo de 60 FPS. Se probaron los 43 slots, las 23 opciones de cuchillo (incluido el original), el kit, los ocho agentes modernos y un actor clásico. Los rayos se lanzan tras sincronizar las transformaciones del servidor físico y contra un triángulo de superficie de área suficiente; la igualdad geométrica se comprueba contra **todos** los triángulos, no sólo contra el triángulo elegido para el rayo.

La verificación estática pasó 60 scripts, 53 referencias, 43 armas, 26 mapas, 392 GLB y 1021 WAV. En el mismo commit también pasaron las suites de movimiento experimental, hitboxes/precisión, escuadras/interacciones y expansión cosmética. Las suites generales Native Godot y Modern agents seguían en ejecución al cerrar este informe: no se afirma que toda la CI del repositorio esté aprobada. Persisten avisos del importador y de VSync.

Capturas reales del renderer en una escena aislada de prueba, no imágenes generadas ni una grabación de partida completa:

- [Superficies de impacto superpuestas en verde al modelo](evidence/drop-ragdoll/drop_surface_collisions.jpg).
- [Pose inicial](evidence/drop-ragdoll/ragdoll_start.jpg).
- [Caída por gravedad](evidence/drop-ragdoll/ragdoll_falling.jpg).
- [Apoyo sobre rampa/escalón](evidence/drop-ragdoll/ragdoll_rest.jpg).
- [Tras reactivar los cuerpos con impactos](evidence/drop-ragdoll/ragdoll_impulse.jpg).

Los PNG originales y logs completos están en el artefacto `drop-collision-ragdoll-evidence` de la ejecución enlazada.
