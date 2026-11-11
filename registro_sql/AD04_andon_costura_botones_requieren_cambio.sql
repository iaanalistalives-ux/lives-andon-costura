-- Ad04 andon costura botones requieren cambio · 11/11/2026
-- Pedido de Christian: no se puede marcar Paro de máquina, Llamar supervisor, etc. si antes no está encendido
-- «Cambio de estilo». Al apagar «Cambio de estilo», lo que siga encendido se apaga solo a esa misma hora.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad05_andon_costura_requiere_cambio). Guardar sin Run.
-- Marcha atrás: update and_botones set requiere = null;   (los botones vuelven a ser independientes)

alter table and_botones add column requiere text references and_botones(codigo);   -- botón que debe estar encendido antes
update and_botones set requiere = 'CAMBIO' where codigo <> 'CAMBIO';
alter table and_registros add column padre_id bigint references and_registros(id); -- el cambio de estilo al que pertenece
alter table and_registros add column cierre_auto boolean not null default false;   -- se apagó solo al terminar el cambio
create index and_registros_padre on and_registros(padre_id);

-- and_panel_: cada botón devuelve además  'requiere' (nombre del botón requerido)  y
--   'bloqueado' = b.requiere is not null and not exists(registro en curso de ese botón en la línea)

-- and_api, cambios respecto de Ad03 (lo demás igual):
-- 1) declare: v_req text; v_padre bigint;
-- 2) 'pulsar', al APAGAR:
--      update and_registros set fin = now(), usuario_fin = v_usuario where id = r.id;
--      update and_registros set fin = now(), usuario_fin = v_usuario, cierre_auto = true where padre_id = r.id and fin is null and not anulado;
-- 3) 'pulsar', al ENCENDER:
--      select b.requiere into v_req from and_botones b where b.codigo = v_boton;
--      if v_req is not null then
--        select x.id into v_padre from and_registros x where x.linea_cod = v_linea and x.boton_cod = v_req and x.fin is null and not x.anulado;
--        if v_padre is null then return {ok:false, error:'Primero enciende «Cambio de estilo»'}; end if;
--      end if;
--      insert into and_registros(linea_cod,boton_cod,usuario_inicio,padre_id) values (v_linea,v_boton,v_usuario,v_padre) ...
-- 4) 'deshacer' de un INICIO: no se permite si ese registro ya tiene otros botones marcados dentro (padre_id).
-- 5) 'deshacer' de un FIN: no se permite si su cambio de estilo ya terminó; al deshacer el fin de un cambio,
--    vuelven a encenderse los que se apagaron solos con él (cierre_auto y la misma hora de fin).

create or replace view publico_and_registros as
  select r.id, r.linea_cod, l.nombre linea, r.boton_cod, b.nombre boton,
         (r.inicio at time zone 'America/Lima')::date fecha, r.inicio, r.fin,
         case when r.fin is not null then and_minutos_(r.inicio, r.fin) end minutos, r.usuario_inicio, r.usuario_fin,
         coalesce(r.estilo, p.estilo) estilo, r.padre_id, r.cierre_auto      -- cada paro o llamada hereda el estilo de su cambio
  from and_registros r join and_botones b on b.codigo = r.boton_cod join cat_lineas l on l.codigo = r.linea_cod
  left join and_registros p on p.id = r.padre_id
  where not r.anulado;
grant select on publico_and_registros to anon, authenticated;
