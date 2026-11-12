# Menú y Arsenal: revisión de presentación

## Cambios

- Navegación de inicio sin accesos duplicados al Arsenal; entrada suave de paneles y fondo persistente conservado.
- Desenfoque del fondo más fuerte en Ajustes que en los demás paneles.
- Armas y cuchillos usan sus modelos de mundo, aislados: no llevan brazos, secuencias de disparo/recarga ni sonidos del arma. Los materiales siguen leyendo el acabado equipado de `GameData`.
- Agentes de frente, sin arma adjunta; pose estática con los brazos hacia abajo. Sólo se modifica la instancia de presentación, no las animaciones del juego.
- Guantes sin arma ni mangas: gesto procedural de muñecas de 2,4 segundos. No se presenta como una animación oficial de Valve ni como una secuencia nueva de gameplay.
- Arrastre para girar, rueda para acercar/alejar y doble clic para restablecer. Encuadre según la relación de aspecto y los límites de la geometría evaluada con su esqueleto.
- Se retiran de la interfaz del Arsenal las pestañas de sonidos/secuencias y la categoría adicional de equipo; utilidad, armas, cuchillos, agentes y guantes siguen disponibles.

## Validación

La implementación `4b973a5f` pasó la ejecución [43139724142](https://github.com/ShadowNigth/15/actions/runs/43139724142):

- Menú y Arsenal: 279 comprobaciones; incluye carga aislada de las 43 armas, ocho agentes con ambos brazos hacia abajo, giro/zoom, filtros, restauración de selección y movimiento real de una muñeca durante la inspección.
- Armas nativas: 13.119 comprobaciones, 289 clips y 42 rigs.
- Cuchillos: 202 comprobaciones de selección, brazos/guantes y comportamiento de partida.
- Editor de interfaz: 69 comprobaciones.

Las pruebas headless aún emiten avisos del renderizador dummy (`Parameter "m" is null`) y algunos recursos al salir. No se afirma que los registros estén libres de advertencias.

La comprobación numérica no sustituye la revisión visual: se revisaron el AK con Redline, el Karambit con Gamma Doppler y el SAS de frente. No se certifica visualmente cada combinación de skin, ángulo y modelo.

La ejecución final [43140629489](https://github.com/ShadowNigth/15/actions/runs/43140629489), revisión `107aefdc`, también terminó **correctamente** con las mismas 279 + 13.119 + 202 + 69 comprobaciones. Esta revisión sólo cambia la espera de captura y su publicación: se espera a que finalice la transición del panel y se priorizan cinco capturas completas para no superar el límite de anotaciones de GitHub.

Se revisaron visualmente las capturas finales de guantes Sport Arid durante el gesto de muñecas y Ajustes con la transición terminada. Evidencia real del motor, no imágenes generadas:

- [Guantes en inspección](evidence/arsenal-gloves-inspection.jpg)
- [Agente SAS con brazos bajos](evidence/arsenal-agent-relaxed.jpg)
- [AK-47 Redline aislado](evidence/arsenal-ak-redline.jpg)
- [Karambit aislado](evidence/arsenal-karambit.jpg)
- [Ajustes y desenfoque](evidence/menu-settings-blur.jpg)
