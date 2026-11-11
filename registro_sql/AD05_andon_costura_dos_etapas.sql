-- Ad05 andon costura dos etapas · 11/11/2026
-- Pedido de Christian («las dos etapas, a ver para probar»): la línea siempre está dentro de un estilo.
--   Etapa CAMBIO:      «Cambio de estilo» encendido (graduando, probando, primera prenda).
--   Etapa PRODUCCION:  al apagarlo, el estilo queda puesto en la línea y los otros 5 botones siguen habilitados.
--   Al encender el siguiente «Cambio de estilo», el estilo anterior sale de la línea (cerrado) y empieza el nuevo.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad06_andon_costura_dos_etapas). Guardar sin Run.
-- Marcha atrás a «solo durante el cambio» (Ad04): volver a crear and_panel_ y and_api con la regla anterior
--   (bloqueado = no hay cambio ENCENDIDO); las columnas nuevas pueden quedarse sin uso.

alter table and_registros add column cerrado timestamptz;      -- solo en el cambio de estilo: cuándo salió ese estilo de la línea
alter table and_registros add column etapa text check (etapa in ('CAMBIO','PRODUCCION'));   -- en qué etapa se marcó el botón
update and_registros set etapa = 'CAMBIO' where padre_id is not null;

-- and_panel_ devuelve además:
--   'vigente' = el estilo que está en la línea: {id, estilo, etapa ('CAMBIO' si el cambio sigue encendido, 'PRODUCCION' si ya terminó), inicio, fin}
--               = el último «Cambio de estilo» de la línea con cerrado vacío y no anulado; null si la línea no tiene estilo.
--   'bloqueado' de cada botón = requiere otro botón y la línea no tiene estilo vigente (antes: no había cambio encendido).
--   'etapa' en cada fila de 'hoy'.

-- and_api, reglas (texto completo en la base):
--   pulsar · APAGAR cualquier botón: fin = ahora; si es el cambio de estilo, lo que siga encendido dentro se apaga solo (cierre_auto)
--            y el estilo pasa a PRODUCCION (sigue vigente).
--   pulsar · ENCENDER «Cambio de estilo»: al estilo vigente anterior se le pone cerrado = ahora y se apagan solos sus botones
--            encendidos; se crea el cambio nuevo (sin estilo hasta que lo elijan).
--   pulsar · ENCENDER otro botón: exige estilo vigente; guarda padre_id = ese cambio y etapa = CAMBIO o PRODUCCION.
--            Sin estilo vigente responde «Primero enciende «Cambio de estilo»».
--   poner_estilo: permitido mientras el estilo siga vigente (también ya en producción).
--   deshacer INICIO de un cambio: lo anula y el estilo anterior vuelve a quedar vigente, con lo que se le había apagado solo.
--   deshacer FIN: no se permite si ese estilo ya salió de la línea, ni si ya hay registros en producción de ese estilo.

create or replace view publico_and_registros as
  select r.id, r.linea_cod, l.nombre linea, r.boton_cod, b.nombre boton,
         (r.inicio at time zone 'America/Lima')::date fecha, r.inicio, r.fin,
         case when r.fin is not null then and_minutos_(r.inicio, r.fin) end minutos, r.usuario_inicio, r.usuario_fin,
         coalesce(r.estilo, p.estilo) estilo, r.padre_id, r.cierre_auto, r.etapa, r.cerrado
  from and_registros r join and_botones b on b.codigo = r.boton_cod join cat_lineas l on l.codigo = r.linea_cod
  left join and_registros p on p.id = r.padre_id
  where not r.anulado;
grant select on publico_and_registros to anon, authenticated;

-- Para el análisis:
--   duración del cambio de estilo      = minutos del registro CAMBIO (inicio → fin)
--   tiempo del estilo en la línea      = inicio del CAMBIO → cerrado
--   paros y esperas durante el cambio  = registros con padre_id = ese cambio y etapa = 'CAMBIO'
--   paros y esperas en producción      = registros con padre_id = ese cambio y etapa = 'PRODUCCION'
