# Coordinación e interacción: integración original

Esta integración es código propio. CSGODOT se estudió como referencia conceptual;
no se copiaron sus implementaciones. No incorpora movimiento CS2, GDExtension,
Forward+ ni recursos externos. Continúan los personajes clásicos, animaciones,
audio, materiales y renderer `gl_compatibility` existentes.

## Cambios

- `TeammateTraffic`: negociación virtual de encuentros, prioridad humana/VIP/
  defusor/portador, seguimiento, espera, desplazamiento lateral y retroceso.
  Comprueba cápsula y apoyo antes de escapar lateralmente. Mantiene dirección
  durante el encuentro. Prioriza también al rescatador que ya lleva un rehén.
  Si varios bots quedan sin progreso, un reintento acotado devuelve el control
  a su navegación original sin teletransportes ni saltos forzados.
  La espera no consume los temporizadores que saltan o
  descartan nodos de navegación. No modifica las máscaras 2/1 ni la función
  GoldSrc de `CSActor`.
- `BombSquad`: elección compartida con kit, tiempo disponible, recorrido y nodos
  bloqueados. Conserva al defusor activo, incluido el humano. Una elección tiene
  una concesión corta para evitar alternancia y cálculos de ruta por cada frame;
  se invalida al morir el elegido. Los restantes compañeros ocupan posiciones
  reales de cobertura. Dos T cercanos pueden apoyar al portador; el resto conserva
  sus rutas. La recogida de C4 empatada se resuelve por identidad estable.
- `GameplayInputGate`: propietarios débiles para menús anidados; cerrar uno no
  devuelve el ratón al juego mientras otro siga abierto. Liberación al salir del
  árbol, reapertura idempotente y cierre no capturante para QA. Conserva la señal
  booleana antigua para compatibilidad. Se cancelan ráfagas, preparación R8,
  intención de lanzamiento y plantado, no la recarga ni los temporizadores de
  animaciones ya ejecutadas. Tras cerrar se exige soltar ataque/uso/salto.
- `UseSelection`: búsqueda dirigida por E con obstáculos, pequeña tolerancia de
  puntería para armas en el suelo y cambio explícito de ranura ocupada. Se conserva
  munición, silenciador y bloqueo de recogida. La recogida automática no reemplaza
  armas. La desactivación tiene prioridad sobre otros usos en ese tick.
- Auditoría opcional `shot_audited`/`tracer_audited`: identidad, frame físico,
  cartuchos, sonido escogido, origen ocular, dirección y boca animada. No mantiene
  historial ni agrega recursos precargados. No sustituye los eventos nativos,
  casquillos ni el sonido. La auditoría ocurre antes del incremento de recoil.
- `ClassicPoseFit`: correcciones limitadas y reversibles sobre los huesos nativos.
  Ajuste de pies quietos sobre apoyo cercano y apoyo de mano izquierda para armas
  largas, calibrado con la pose original relativa a la mano derecha. Omite acciones
  nativas, pistolas, duales, cuchillos, utilidades, agua, escalera y muerte donde
  corresponde. No escala huesos, mallas ni armas. Restaura la pose antes del siguiente
  muestreo; actúa después de capas/columna y antes de sincronizar hitboxes.

## Pruebas

`SquadInteractionTest`: propietarios anidados/liberados/reabiertos, elección de
kit, conservación del desactivador, sustitución tras muerte y cancelación de
acciones diferidas.

`SquadGameplayTest`: encuentro real en pasillo con ensanchamientos, modelos
clásicos, ausencia de acumulación en poses, transform de arma, disparos reales de
Glock/M4/AWP/FAMAS/Elite/M3 y cambio explícito con conservación del arma saliente.
Con `SQUAD_CAPTURE_DIR` y renderer OpenGL guarda fotogramas del encuentro y poses.

`UtilityPropagationTest`: fuego sembrado reproducible, apoyo y conectividad,
rechazo sin suelo, pared sólida, flood fill del humo, extinción, explosión/wake y
rebote mediante el barrido real de `GrenadeProjectile`. No reemplaza el algoritmo
de fuego/humo/rebote.

El workflow `squad-systems-qa.yml` importa con Godot 4.3 y ejecuta estas pruebas
además de `NativeGunAnimationTest`, `NativeAudioTest`, `KillFirePolishTest`,
`IncendiaryProceduralTest`, `TacticalAIRegressionTest` y `MissionObjectiveRegressionTest`.
La caché de recursos importados del workflow es exclusivamente de compilación en
CI: no agrega precarga, pantallas de progreso ni cachés nuevas al juego.
El test de apuntado compara la dirección con la cámara visible (incluido recoil),
no con el ángulo lógico sin recoil.
La validación AST no equivale a una prueba de juego ni a validación visual.
