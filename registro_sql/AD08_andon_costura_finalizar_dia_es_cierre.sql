-- Ad08 andon costura finalizar dia es cierre · 11/11/2026
-- Pedido de Christian: «al finalizar día debe ser como un cierre, o sea empezar de cero, porque sale iniciar día
--   pero abajo confundiría en la tabla».
-- «Finalizar día» deja de ser una pausa (Ad07) y pasa a ser un CIERRE:
--   al tocarlo, todo lo encendido se apaga a esa hora (cierre_auto), el estilo sale de la línea (cerrado)
--   y la línea vuelve a «Sin iniciar»: «Inicio de operación» activo y los demás botones grises.
--   Ya no existe «Iniciar día»: el día siguiente se empieza con «Inicio de operación», que pregunta el estilo.
--   En la tabla queda una sola fila «Finalizar día» con su hora (fin = inicio), sin reloj.
--   «Almuerzo» sigue siendo pausa, sin cambios.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad09_andon_costura_finalizar_dia_es_cierre). Guardar sin Run.
-- LÍMITE aceptado por Christian: un cambio de estilo a medias al finalizar el día se corta ahí; al día siguiente la línea
--   entra directo a producción y el tiempo de cambio del segundo día no se registra como cambio.
--   (Opción ofrecida y no elegida: que el cambio a medias continúe al día siguiente.)
-- Marcha atrás a la pausa: update and_botones set pausa = true, nombre_encendido = 'Iniciar día', cierre = false where codigo = 'FIN';

alter table and_botones add column cierre boolean not null default false;   -- el botón cierra el día de la línea
update and_botones set pausa = false, nombre_encendido = null, cierre = true where codigo = 'FIN';

-- Vista: se agrega la columna cierre al final (lo demás igual que en Ad07).
create or replace view publico_and_registros as
  select r.id, r.linea_cod, l.nombre linea, r.boton_cod, b.nombre boton,
         (r.inicio at time zone 'America/Lima')::date fecha, r.inicio, r.fin,
         case when r.fin is not null then and_minutos_(r.inicio, r.fin, case when b.pausa then null else r.linea_cod end) end minutos, r.usuario_inicio, r.usuario_fin,
         coalesce(r.estilo, p.estilo) estilo, r.padre_id, r.cierre_auto, r.etapa, r.cerrado, b.pausa, b.cierre
  from and_registros r join and_botones b on b.codigo = r.boton_cod join cat_lineas l on l.codigo = r.linea_cod
  left join and_registros p on p.id = r.padre_id
  where not r.anulado;
grant select on publico_and_registros to anon, authenticated;

-- and_panel_: cada botón y cada fila de 'hoy' traen además 'cierre' (texto completo en la base).

-- and_api, cambios respecto de Ad07 (texto completo en la base):
--   pulsar · botón con cierre = true (exige que la línea haya iniciado, como los demás):
--        insert into and_registros(linea_cod,boton_cod,usuario_inicio,padre_id,etapa,fin,usuario_fin)
--          values (v_linea,v_boton,v_usuario,v_padre,v_etapa,now(),v_usuario);          -- registro instantáneo
--        update and_registros set fin = now(), usuario_fin = v_usuario, cierre_auto = true
--          where linea_cod = v_linea and fin is null and not anulado;                   -- apaga todo lo encendido
--        update and_registros set cerrado = now() where id = v_padre;                   -- el estilo sale de la línea
--   deshacer INICIO de ese registro: lo anula, el estilo vuelve a la línea y se vuelve a encender lo que el cierre apagó.
--        No se permite si la línea ya volvió a iniciar.

-- Para el análisis (vista publico_and_registros):
--   fila con cierre = true = fin del día de esa línea (su hora está en inicio);
--   registros con cierre_auto = true y fin = esa hora quedaron encendidos al cerrar el día.
