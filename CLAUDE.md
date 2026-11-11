# CLAUDE.md — Líneas de costura · Cambio de estilo (lives-andon-costura)

Las reglas generales de trabajo están en el repo privado `lives-instrucciones` (CLAUDE.md). Este archivo solo describe esta herramienta.

## Qué hace
Registro con botones, en celular o tablet, de lo que pasa en cada máquina de una línea de costura durante un cambio de estilo (no hay botones físicos). Nació de la cronología del cambio de estilo de la OP 24323 en la Línea 4 (toma de tiempos de Ingeniería, oct-2026): un cambio son unos 40 registros por máquina, varios a la vez.
- `index.html` — **pantalla de la línea** (única pantalla por ahora; link directo, se usa en planta).
  - Elige la línea una vez (queda en el equipo; `?linea=4` o `?linea=LIN-0003` la fija).
  - Sin cambio abierto: formulario «Iniciar cambio de estilo» (OP que entra + lista de máquinas, una por renglón «máquina, operación»; se puede pegar desde Excel).
  - Con cambio abierto: una tarjeta por máquina, siempre en el mismo lugar, con color por estado y minutos en curso. Al tocarla sale UNA ventana con 9 botones fijos: Graduando, Probando; esperando a Mecánico / Operaria / Calidad / Ficha / Plantillas; Aprobada, Rechazada. Dos toques por registro, sin teclado.
  - La hora la pone la base; el toque siguiente en la misma máquina cierra el anterior (no hay botón de fin). «Deshacer» 8 segundos tras cada toque.
  - No se pide motivo de rechazo ni nombre de quien atiende: el motivo de una espera es a quién se espera.
  - «Primera prenda» es una tarjeta más (Enviada a Calidad, Aprobada, Rechazada). «Agregar máquina» a media marcha; «Cerrar cambio de estilo» con confirmación.
  - Se pone al día sola cada 20 segundos (varios equipos en la misma línea).
- Pendiente (segunda entrega): dashboard de análisis con Excel LIVES (duración de cada cambio, minutos por tipo y por a quién se esperó, rechazos por máquina). Las vistas `publico_and_*` ya existen para eso.

## Base de datos (Supabase lives-datos) — prefijo `and_`
Registro: `registro_sql/AD01_andon_costura_base.sql` (migración `ad01_andon_costura_base`, 11/11/2026).
- Catálogos con código: `and_estados` (GRAD, PROB, ENV, ESP, LISTA, RECH), `and_areas` (a quién se espera: MEC, OPE, CAL, FIC, PLA), `and_maquinas` (código = el de la máquina sin espacios, ej. `BRA06`; se llena solo al cargar un cambio; falta el inventario oficial), `and_parametros` (`REGISTRO_LIBRE`, `ALMUERZO_INICIO`, `ALMUERZO_FIN`).
- Registro: `and_cambios` (uno abierto por línea; línea por código de `cat_lineas`, OP con grupo y estilo tomados de `ops`), `and_cambio_maquinas` (máquinas y operación de cada cambio), `and_eventos` (cada toque: estado, a quién se espera, inicio, fin, usuario; `cm_id` vacío = primera prenda; deshacer = `anulado`).
- Puerta única: `and_api(p_accion, p)` → `inicio`, `tablero`, `buscar_op`, `iniciar_cambio`, `agregar_maquina`, `quitar_maquina`, `tocar`, `deshacer`, `cerrar_cambio`. Las escrituras devuelven el tablero completo.
- Apoyo: `and_puede` (permiso), `and_supervision_`, `and_par`, `and_minutos_` (minutos sin contar el almuerzo, hora de Lima), `and_tablero_` (interna).
- Vistas: `publico_and_eventos`, `publico_and_cambios`.
- Lee de otras herramientas: `cat_lineas` (ojo: LINEA 4 = `LIN-0003`) y `ops`. No usa Storage.
- Las tablas se leen libres; escribir solo por `and_api`.

## Quién puede registrar
Libre durante las pruebas (`and_parametros.REGISTRO_LIBRE` = SI). Rodrigo (rcamogliano): supervisión, ve todo y no guarda. Lo registrado se firma con `?usuario=` o con «Identificarme» (opcional fuera del portal). A Sistemas: `and_puede` es la pieza que reemplazan con su seguridad.

## Límites conocidos
- Depende de que alguien toque; con una tablet compartida no se sabe qué persona tocó si no se identifica.
- Los nombres de operación son texto libre (la cronología no trae códigos); `potenciales` (COSTURA) tiene códigos de operación para cruzar más adelante.
- No hay catálogo de mecánicos ni supervisores: se guarda el área, no la persona.
