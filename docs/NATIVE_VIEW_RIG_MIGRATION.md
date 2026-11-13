# Migración de brazos/manos a esqueletos originales cs2go

## Estado

El sistema nativo está **activo por defecto** después de validar el piloto AK + Smoke Out y la matriz de armas/agentes. `NativeViewRig.enabled = true`. La implementación antigua queda únicamente disponible para pruebas históricas aisladas; no es el camino normal de juego ni se utiliza como fallback automático. No confundir el éxito del verificador estático o de la igualdad de datos con aceptación visual.

## Diferencia con la implementación anterior

Antes se transformaban los vértices a un bind canónico de AK y se les asignaba un Skin del arma. Ahora cada paquete tiene su **Skeleton3D propio**, nombres/jerarquía de huesos originales y Skin original. El arma conserva su AnimationPlayer y esqueleto, utilizados sólo como fuente de movimiento para los esqueletos independientes. No se cambian eventos, tiempos, sonidos, accesorios ni las pistas de las armas.

Por cada hueso conducido se evalúa:

`pose_fuente = espacio_fuente_desde_arma × pose_animada_arma × corrección_de_reposo`

Las correcciones se calculan offline a partir de marcos anatómicos completos. Los metacarpianos y ayudantes sin equivalente conservan el desplazamiento respecto al ancestro que sobrevive. No se renombran huesos nativos ni se reasignan índices de joints a los huesos del arma.

Se conservan las posiciones, normales, tangentes, UV principal, JOINTS, WEIGHTS, índices de triángulos e inverse binds de los primitives seleccionados. El empaquetador elimina datos no usados (incluido un UV secundario sin uso) y meshgroups ajenos, no modifica la geometría seleccionada. El grupo Leet de torso/cuello se excluye; se utilizan los brazos/manos de primera persona, nunca el cuerpo de tercera persona.

## Selección de piezas

- Con guante predeterminado: brazos y manos/guantes del paquete nativo del agente.
- Con Moto Smoke Out: sleeves nativos del agente más el viewmodel Moto con **sus propios antebrazos y guantes coincidentes**. No se dibujan otras manos debajo. Se aplica el acabado real 5033_10078 ya importado, incluidos sus mapas PBR.
- Los **26 acabados Sport opcionales que ya existían** conservan exactamente sus IDs y nombres. Se migran al modelo cs2go `5030` con sus pesos/UVs/esqueleto originales y al paint correspondiente a cada familia, horneado con desgaste BS 0,8 / WW 0,4 / FT 0,25 / MW 0,12 y semilla 1. No se añaden nuevas opciones. Color a 1024 px WebP calidad 95; normal/ORM a 512 px WebP lossless. No se intenta aplicar los cinco atlas antiguos a las UVs nuevas.
- No se utilizan `WristSeamFit`, puños reconstruidos, proyección de extremos, cilindros ni superficies de brazos del arma dentro del reemplazo.
- La instalación es transaccional: sólo elimina las superficies anteriores de la instancia después de resolver todos los huesos con peso. Las pistas del esqueleto del arma permanecen como fuente de movimiento, sin brazos/manos antiguos visibles. Los importadores/activos anteriores se conservan para pruebas históricas, no para dibujar una segunda capa debajo.
- No se agregan otros acabados del catálogo de 96 guantes.

Los ocho paquetes de agente usan los mismos IDs/fuentes aprobados anteriormente; las sustituciones visuales FBI/Leet/Phoenix autorizadas no se convierten en nuevos agentes exactos por cambiar de esqueleto.

## Fuente y reproducción

`3kh0/cs2go`, commit `fb970df0ee8175d9b212d310f6a928f9f61014f2`.

```
npm ci --prefix tools/source/modern_agents
python -m tools.source.build_native_view_rigs
npm ci --prefix tools/source/cosmetics
python -m tools.source.migrate_existing_sport_finishes
python -m tools.source.verify_native_view_rigs
```

Dependencias Python: numpy, pillow, scipy, trimesh. La descarga/decodificación es de construcción; el juego funciona offline. Los derechos de los activos siguen perteneciendo a sus autores; la disponibilidad del repositorio no implica permiso general de redistribución.

El verificador compara los activos exportados directamente con la fuente decodificada fijada al commit: **248 arrays idénticos**, jerarquías y transformaciones locales originales de los huesos, y cobertura de todos los huesos con peso en las 43 bases de arma. Los 22 cuchillos se comprueban además en runtime con sus escenas y animaciones reales; comparten las bases de bind del cuchillo del proyecto.

## Puerta de aceptación

`NativeViewRigTest` activa la migración solamente en su proceso de prueba:

1. AK + Smoke Out: reposo, disparo, recarga e inspección, cinco fases por acción, capturas reales a mitad del clip.
2. Leet descubierto y karambit en inspección.
3. Matriz de las 43 bases más variantes de cuchillo, ocho agentes y los tres tipos de guante (predeterminado, Moto Smoke Out y Sport nativo), además de comprobar individualmente los 26 acabados Sport existentes con piel y manga, con las animaciones originales.

Workflow: `.github/workflows/native-view-rig-qa.yml`. La prueba piloto y la matriz son pasos separados; los renders se publican antes de la matriz. La activación general se realizó después de una ejecución válida y revisión de los renders. Arsenal sincroniza el nuevo rig antes de encuadrar y calcula los límites sólo con los vértices referenciados por los índices visibles; no incluye los antebrazos no dibujados del accessor compartido. La inspección sigue moviendo las muñecas reales.

## Evidencia

Primera integración activa validada: [CI 43381469817](https://github.com/ShadowNigth/15/actions/runs/43381469817), código `ddf1be39`: **4931 comprobaciones de piloto y 2 570 703 de matriz, 0 fallos**. Se revisaron renders de reposo, disparo, recarga, inspección AK, antebrazo Leet, karambit y Arsenal. Los contadores incluyen huesos × poses × configuraciones; no representan millones de secuencias independientes ni revisión visual de cada combinación.

Validación final ampliada: [CI 43384069630](https://github.com/ShadowNigth/15/actions/runs/43384069630), código `d07fb428`:

- **14 284 comprobaciones del piloto/acabados, 0 fallos**.
- **4 205 946 comprobaciones de la matriz, 0 fallos**.
- Los pasos de ejecución también rechazan errores `ERROR:`, no sólo fallos de aserción.
- Los 27 IDs/nombres/orden del catálogo (26 Sport anteriores + Smoke Out) coinciden exactamente con el catálogo anterior a esta migración; ninguna opción retirada se ha reintroducido.
- Verificador estático: 62 scripts, 54 referencias, 43 armas, 26 mapas, 402 GLB y 1021 WAV, sin errores.

Capturas finales en `docs/evidence/native-view-rig/`: AK reposo/disparo/recarga/inspección, Leet descubierto, karambit, Arsenal e inspección de guantes y Sport Amphibious. El resumen `native_ak47_animation_proof.jpg` reúne cuatro capturas reales, no imágenes generadas. Las capturas son del renderer de Godot sobre fondo de prueba, no del catálogo ni de una partida completa. La revisión visual se hizo sobre estas muestras; la matriz comprueba las poses restantes automáticamente.

El paso de importación con caché de Godot emite diagnósticos de UID de recursos y avisos GLTF/LOD ya registrados en CI; no se presentan como una importación sin diagnósticos. Los procesos de prueba posteriores completaron sus validaciones sin errores de ejecución. Los archivos `.godot` de CI no forman parte del ZIP ni del repositorio.

