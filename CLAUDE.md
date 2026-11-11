# CLAUDE.md — Botones de la línea de costura (lives-andon-costura)

Las reglas generales de trabajo están en el repo privado `lives-instrucciones` (CLAUDE.md). Este archivo solo describe esta herramienta.

## Qué hace
Panel de BOTONES FIJOS por línea de costura, en celular o tablet (no hay botones físicos). Un toque enciende el botón (queda de color, con su reloj) y otro toque lo apaga; cada vez queda un registro con línea, botón, hora de inicio y de fin. No es un formulario: nadie escribe nada para registrar (pedido expreso de Christian, 11/11/2026, tras descartar un primer diseño por máquina con formulario).
- `index.html` — **panel de la línea** (única pantalla por ahora; link directo, se usa en planta).
  - Elige la línea una sola vez (queda en el equipo; `?linea=4` o `?linea=LIN-0003` la fija y ya no pregunta).
  - 6 botones, siempre en el mismo lugar: Cambio de estilo, Paro de máquina, Llamar supervisor, Llamar Calidad, Falta material, Duda de ficha. Salen de la tabla `and_botones`: se agregan, quitan o renombran ahí, sin tocar la pantalla.
  - Varios botones pueden estar encendidos a la vez. «Deshacer» 8 segundos tras cada toque (quita el inicio o vuelve a encender).
  - Al encender «Cambio de estilo» sale la ventana «¿Qué estilo entra?» con los estilos de la base de OPs (`ops`), los 24 más recientes como botones y un buscador «Buscar estilo…» (teclado numérico). Se puede tocar «Después» y elegirlo luego con «Elegir estilo» en la lista de hoy.
  - Abajo, los registros de hoy de esa línea (inicio, fin, qué pasó, minutos).
  - Se pone al día sola cada 15 segundos (varios equipos en la misma línea).
  - Los contenedores propios llevan la clase `lsand-menu` para que lives-franja no meta los botones en una barra.
- Pendiente (segunda entrega): dashboard de análisis con Excel LIVES (minutos por botón, por línea y por día; duración de cada cambio de estilo). La vista `publico_and_registros` ya existe para eso.

## Base de datos (Supabase lives-datos) — prefijo `and_`
Registros en `registro_sql/`: `AD03_andon_costura_botones_fijos.sql` es el vigente (resultado final). `AD01` y `AD02` son el diseño anterior por máquina, ya borrado de la base; se guardan solo como historia.
- `and_botones` (catálogo con código: CAMBIO, PARO, SUP, CAL, MAT, FICHA; color azul/rojo/ambar; `pide_estilo`).
- `and_registros` (línea por código de `cat_lineas`, botón, inicio, fin, usuario de inicio y de fin, `estilo` si el botón lo pide; deshacer un inicio = `anulado`). Solo un registro en curso por línea y botón.
- `and_parametros` (`REGISTRO_LIBRE`, `ALMUERZO_INICIO`, `ALMUERZO_FIN`).
- Puerta única: `and_api(p_accion, p)` → `inicio`, `panel`, `pulsar`, `deshacer`, `estilos`, `poner_estilo`. Las escrituras devuelven el panel completo.
- Apoyo: `and_puede` (permiso), `and_supervision_`, `and_par`, `and_minutos_` (minutos sin contar el almuerzo, hora de Lima), `and_panel_` (interna).
- Vista: `publico_and_registros`.
- Lee de otras herramientas: `cat_lineas` (ojo: LINEA 4 = `LIN-0003`) y `ops` (lista de estilos). No usa Storage.
- Las tablas se leen libres; escribir solo por `and_api`.

## Quién puede registrar
Libre durante las pruebas (`and_parametros.REGISTRO_LIBRE` = SI). Rodrigo (rcamogliano): supervisión, ve todo y no guarda. Lo registrado se firma con `?usuario=` o con «Identificarme» (opcional fuera del portal). A Sistemas: `and_puede` es la pieza que reemplazan con su seguridad.

## Límites conocidos
- Depende de que alguien toque, y de que vuelva a tocar para terminar: un botón olvidado encendido infla los minutos (el reloj a la vista ayuda a notarlo).
- No se sabe qué máquina paró ni el motivo fino: se decidió no pedirlo para no cansar a quien toca.
- Con una tablet compartida no se sabe qué persona tocó si no se identifica.
- La cronología que originó la herramienta (cambio al estilo 24323 de Theory en la Línea 4, oct-2026; 24323 es un estilo, no una OP) tiene más detalle por máquina del que este panel recoge.
