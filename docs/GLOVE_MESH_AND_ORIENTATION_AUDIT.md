# Guantes intercambiados: malla y orientación

## Criterio visual

Se conserva el intercambio que aprobó el usuario. La palma y el dorso no se
han vuelto a intercambiar ni se ha reflejado el modelo en esta revisión. No se
puede determinar por el signo de un determinante qué aspecto visual debe
considerarse «correcto» para el usuario.

## Diagnóstico y ajuste parcial

Después del intercambio, una transformación rígida sitúa la muñeca del guante
sobre la de la otra mano, pero deja varias articulaciones de los dedos del
modelo trasladado lejos de las que lo animan. En el modelo Moto, comparando
posiciones de reposo, algunas diferencias entre articulaciones correspondientes
llegan a 133 mm. Esto no es una medición de huecos o de contacto con el arma.

La transferencia ahora aproxima cada vértice a sus nuevas articulaciones
según sus pesos existentes, aplicando la mitad del desplazamiento calculado.
Se mantienen los UV, los pesos, los triángulos, los materiales y el intercambio
entre manos. El ajuste completo se descartó porque deformaba más la forma de
reposo. Este ajuste **no es una solución completa**: reduce estiramientos pero
modifica parcialmente la forma en reposo y todavía pueden verse dedos y pulgares
deformados. Las normales y tangentes se rotan, pero no se recalculan después
del desplazamiento; el sombreado también necesita revisión visual.

La prueba `GloveDeformationAudit` compara, con skinning en CPU, longitudes de
aristas de malla en relación con el modelo original, ignorando aristas menores
a 1 mm. En una medición adicional de la malla de reposo con ese umbral, el
percentil 99 de la relación de longitudes pasó de 1,00× a 1,48× (Sport) y 1,54×
(Moto); la mayor elongación de arista fue de aproximadamente 10 mm. Es un
compromiso real: el ajuste mejora las poses probadas, pero altera la mano abierta. Cubre Sport y Moto, AK, Glock, AWP y cuchillo, ambas manos y tres fases
de las animaciones idle, inspect y reload cuando existen: **132 casos**. En
todos, bajaron tanto el percentil 99 de la relación de longitudes como la
máxima elongación absoluta respecto al intercambio rígido anterior.

Ejemplo Moto/Glock/inspect al 50 %, superficie original izquierda: percentil
99 de la relación de longitud 9,82× → 7,01×; elongación máxima de una arista
128,3 → 83,9 mm. Sigue siendo una deformación grande. Estas cifras no prueban
que el guante se vea bien ni que agarre el arma. `GloveHandExchangeTest` también
comprueba las copias de vértices en costuras en la malla de reposo; no es una
prueba visual de todas las costuras animadas.

## Auditoría de brazos, manos y mangas

- `check_native_rig_orientation.py` examinó 18.928 mapeos de agentes y 4.558
  mapeos de guantes: sin correspondencias izquierda/derecha cruzadas ni
  correcciones singulares o de determinante negativo. El intercambio de las
  superficies de guante es deliberado y se prueba aparte.
- `NativeArmOrientationAudit` probó el rig de producción con ocho agentes,
  dos tipos de guante, AK, Glock, AWP y cuchillo, y muestras de idle/inspect:
  6.784 comprobaciones de transformaciones finitas y conservación de signo,
  sin fallos. La separación máxima entre anclas de muñeca de guante y manga en
  estas muestras fue 0 mm; esto no mide la separación entre superficies.
- `GloveHandExchangeIntegrationTest` probó los 27 acabados, además de muestras
  de animación de varias armas; 551.516 comprobaciones sin fallos.

Estas auditorías **no demuestran** que mangas, manos o brazos se vean
anatómicamente correctos en todas las armas, modelos, cámaras o poses. No se
han verificado visualmente ni el contacto con el arma ni intersecciones entre
malla, manga y brazo en esta revisión. Es necesario revisar el render real de
Godot en el modo gráfico del juego y corregir cualquier problema que se vea.

## Pruebas

```
python3 tests/check_native_rig_orientation.py
tools/godot/godot --headless --path . tests/GloveHandExchangeTest.tscn
tools/godot/godot --headless --path . tests/GloveHandExchangeIntegrationTest.tscn
tools/godot/godot --headless --path . tests/GloveDeformationAudit.tscn
tools/godot/godot --headless --path . tests/NativeArmOrientationAudit.tscn
```
