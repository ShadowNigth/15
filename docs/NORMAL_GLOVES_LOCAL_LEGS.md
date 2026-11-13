# Guantes originales y piernas locales

## Solicitud

Retirar los guantes nuevos y regresar a las manos normales. Al mirar hacia abajo, mostrar muslos, rodillas y pies unidos al cuerpo, como en la referencia del usuario. La referencia guía la composición y continuidad del cuerpo; se conserva la ropa de cada agente, no se sustituye por el traje a rayas de la foto.

## Guantes

- Retirados los 19 Sport nativos de cs2go del catálogo del Arsenal, su GLB dedicado, sus 38 texturas nativas y las 190 texturas de la conversión cs2go anterior que ya no tenían referencias.
- Eliminado el código de intercambio L/R, corrección de quiralidad y giro dorso/palma, incluidos sus esqueletos cosméticos.
- Restaurada la exposición/inspección normal del Arsenal, sin el acomodo artificial de manos.
- `classic` vuelve a ser la selección predeterminada. Una selección anterior `cs2go_5030_*` se recupera como `classic` al cargar.
- Las mangas dedicadas de los agentes y los acabados Sport anteriores siguen independientes. No se modifican las animaciones de armas o cuchillos.
- Los generadores habituales ya no vuelven a agregar el lote retirado.

## Cuerpo local

`FirstPersonBody` sigue copiando exactamente la pose del agente, sin una segunda animación ni cambios en colisiones. La copia local se sitúa 58 cm detrás de la cámara, con el desplazamiento orientado por la mirada en vez de girar con el gait al hacer strafe. La separación se valida mirando a 70° y 89° para que el borde superior no aparezca como un aro hueco. La cadera no se desplaza lateralmente al cambiar la orientación de las piernas.

Se conserva la continuidad original de pelvis, abdomen y torso para no dejar un aro hueco a la altura de la cintura; no se agrega una tapa con UVs inventadas. Se excluyen cabeza y brazos. Se conservan las influencias de clavícula compartidas por el pecho: excluirlas recortaba demasiados triángulos del torso y abría la cintura. La posición mantiene la parte superior detrás del encuadre al mirar hacia abajo. El agente completo sigue proporcionando la sombra; la copia local permanece fuera de las cámaras de otros actores y se oculta al morir.

## Validación

Verificación estática: 60 scripts, 53 referencias, 43 armas, 26 mapas, 391 GLB y 1021 WAV, sin errores.

Pruebas renderizadas de `9a4fa8f0`: https://github.com/ShadowNigth/15/actions/runs/43332285703 — **180 comprobaciones de cuerpo local, 629 de mangas/guantes y 1852 de cosméticos, sin fallos**. Se cubrieron ocho agentes en reposo, mirando a 70°/89°, caminando, agachados, saltando y reapareciendo; compatibilidad de mangas/guantes originales en armas y cuchillos; regresión de skins y animaciones cosméticas.

Se revisaron las capturas reales de Phoenix mirando hacia abajo. Las iteraciones con 12–38 cm de separación dejaban visible una abertura del torso y fueron descartadas. La captura final a 89° muestra las piernas y los pies sin el aro hueco; la vista a 70° muestra menos pierna, como corresponde a una mirada menos vertical. No se afirma que la postura, encuadre, proporciones o vestimenta sean idénticos a la foto de CS2. Evidencia nueva en `docs/evidence/normal-gloves-local-legs/` (entorno de prueba renderizado con el controlador de juego).
