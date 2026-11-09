# Investigación aislada: SAS, Phoenix y animaciones

## Estado y límites

No se han sustituido personajes, añadido modelos al Arsenal, alterado GoldSrc ni conectado scripts nuevos al juego. No hay GLB descargados ni importación/render validado. Este directorio contiene herramientas originales de diagnóstico, no código copiado de cs2-web.

Referencia revisada: [apich/cs2-web e0e7e858](https://github.com/apich/cs2-web/tree/e0e7e858aec24c96c324113d7d91c9fce5085028).
El manifiesto de ese commit declara SAS 3.974.156 B, Phoenix 4.804.936 B y animaciones 4.802.692 B (13.581.784 B total). `manifest.json` conserva tamaños y SHA-256 para comprobar identidad. Ningún binario está incluido en ese checkout. Su origen declarado es `https://cs2.duskrain.cn/`, fuera de los hosts permitidos en este entorno: no se intentó eludir la restricción ni se verificó disponibilidad. El código original carece de licencia general; los derechos de los recursos Valve son independientes.

## Procedimiento reproducible

Obtener legalmente los tres archivos desde una instalación propia/exportación o facilitar los GLB existentes. Mantenerlos en una carpeta externa al proyecto para no activar importación ni empaquetarlos accidentalmente.

```sh
python research/cs2_agents/audit_glb.py /ruta/a/los/tres/glb
python -m unittest discover -s research/cs2_agents -p 'test_*.py' -v
```

El auditor no hace peticiones de red. Informa archivos ausentes, integridad contra manifiesto, articulaciones, clips, materiales, recursos externos y destinos de animación no presentes en cada skin. Devuelve código 1 si falta algo o difiere del manifiesto. Una exportación local diferente puede ser válida aunque no coincida con esos hashes; requiere revisión propia. Coincidir por nombre NO demuestra compatibilidad de bind poses, jerarquías ni escalas.

### Puerta de aceptación Godot (pendiente)

1. Importar en un proyecto de laboratorio Godot 4 GL Compatibility separado, nunca en las rutas clásicas.
2. Inspeccionar Skeleton3D, rest pose, escalas, normales, transparencia y texturas. La documentación fuente declara metros y frente +Z; comprobarlo visualmente antes de aplicar giro de PI para -Z.
3. Inventariar los clips reales. La documentación afirma 33, pero todavía no se ha corroborado en el binario.
4. Vincular la biblioteca de animaciones a cada esqueleto comprobando rutas y rest transforms. Evitar retarget automático por nombres sin examen de deformación.
5. Grabar ambos agentes caminando, corriendo, agachados, disparando/recargando y muriendo; comprobar pies, muñecas, dedos, giros y transiciones. No basta una pose inmóvil. No asumir que el paquete contiene todas esas acciones hasta inventariarlo.
6. Comprobar soporte de arma/attachments, root motion, alineación de disparo y presupuesto de GPU. No reutilizar hitboxes clásicas sobre otro rig sin validación.
7. Conservar los personajes clásicos y su flujo de selección incluso si el laboratorio pasa.

## Evaluación posterior: simulación previa de granadas

Se examinó `GrenadeProjectile.gd` de la revisión entregada `6e8f5ec287ff1c6b33f20713322f517269297160` mediante Git, sin restaurar ni modificar el checkout. La física real usa gravedad 21 m/s², subpasos/raycast, rebotes diferentes de suelo/pared, tratamiento de rejillas y condiciones de reposo/detonación. No conviene añadir un predictor parabólico independiente: divergiría de esos casos.

**Recomendación:** extraer en una futura implementación propia un paso de simulación compartido por proyectil y predictor, inyectando consulta de colisión y devolviendo estado/eventos sin reproducir efectos, sonidos, daños ni consumir RNG del mundo. Preservar exactamente los coeficientes actuales; no importar la física Three.js ni alterar GoldSrc. El predictor debe modelar mecha, retraso de humo en movimiento e impacto de molotov, no solo punto final.

Para bots: probar pocas velocidades/ángulos, limitar presupuesto por actualización y descartar riesgo para aliados, jugador humano, VIP y rehenes. Evaluar peligro durante el vuelo y radio/tiempo del efecto, no solo distancia al aterrizaje. Revalidar antes del lanzamiento si cambia el entorno. No introducir precarga o cachés globales.

**Pruebas necesarias antes de activar:** equivalencia predictor/proyectil con mismo delta y colisiones; suelo/pared/esquina/rejilla; humo/molotov/HE; mecha en vuelo; puertas móviles; seguridad de aliados; cero efectos colaterales y coste medido. Todavía no implementado ni probado en gameplay.

## Evaluación posterior: oclusión sonora

El `AudioManager.gd` entregado usa pool de 32 emisores 3D, distancia y eventos de percepción IA; no se observó comprobación de pared en `play_3d`. La referencia web aplica oclusión a pasos/aterrizajes mediante raycast y un filtro hasta 850 Hz con ganancia 0,72 (aprox. -2,85 dB). Son valores de referencia, no una acústica físicamente exacta ni parámetros ya validados aquí.

**Recomendación:** implementación propia inicialmente solo para pasos 3D, con rayo emisor→oyente contra geometría sólida, exclusión de actores y actualizaciones acotadas para voces activas. Suavizar apertura/cierre para evitar chasquidos. En Godot los efectos son por bus: no añadir un low-pass al Master, porque apagaría UI, armas propias y radio. Usar rutas seca/ocluida independientes y restaurar bus/ganancia al reutilizar cada voz del pool. Si se usa un filtro de atenuación del emisor, verificar antes su comportamiento real y no confundirlo con un filtro de oclusión.

Mantener la percepción IA sin cambios en el primer prototipo: los eventos actuales no representan automáticamente lo que oye cada bot tras una pared. Acoplarla exige evaluación individual y reglas explícitas; no reducir globalmente el radio de audición por el estado del oyente humano.

**Pruebas necesarias:** misma sala/pared/puerta que abre/cierra, dos fuentes simultáneas con oclusión distinta, reutilización del pool sin filtrado residual, radio/UI intactas, cambio de mapa y escucha A/B real. Todavía no implementado ni probado en gameplay.

## Particularidad del workspace

Durante esta investigación el árbol local estaba en `cd8452d` con numerosos archivos preexistentes sin seguimiento, mientras la rama remota conserva la entrega `6e8f5ec2`. Se respetó ese estado: no reset, checkout, mezcla ni sobrescritura de archivos del juego. Los diagnósticos anteriores se apoyan en la entrega remota consultada como objetos Git, no en una supuesta instalación local idéntica.
