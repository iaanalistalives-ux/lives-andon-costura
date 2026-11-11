-- Ad03 andon costura botones fijos · 11/11/2026
-- Rediseño pedido por Christian: panel de BOTONES FIJOS por línea (un toque enciende, otro apaga), sin formulario.
-- Reemplaza el diseño por máquina de Ad01/Ad02. El estilo que entra se elige de la base de OPs (tabla ops).
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migraciones ad03_andon_costura_botones_fijos y
-- ad04_andon_costura_estilo_de_ops; aquí va el resultado final de las dos). Guardar sin Run.
-- Borrado con la confirmación de Christian: 6 tablas, 2 vistas y 2 funciones del diseño anterior, más 1 fila de prueba suya
-- (cambio CE-261111-4, Línea 1, estilo 25225, sin máquinas ni toques). Para rehacer lo borrado: Ad01 + Ad02.
-- Propio de Postgres (anotar para SQL Server): jsonb en la puerta, security definer, políticas de lectura por fila,
-- índice único parcial (un registro en curso por línea y botón), "at time zone".

drop view publico_and_eventos;
drop view publico_and_cambios;
drop function and_api(text, jsonb);
drop function and_tablero_(text);
drop table and_eventos;
drop table and_cambio_maquinas;
drop table and_cambios;
drop table and_maquinas;
drop table and_estados;
drop table and_areas;
-- Se conservan de Ad01: and_parametros, and_par, and_puede, and_supervision_, and_minutos_.

-- ===== Catálogo de botones (se agregan o quitan aquí, sin tocar la pantalla) =====
create table and_botones(codigo text primary key, nombre text not null, icono text not null default '', color text not null default 'ambar'
  check (color in ('azul','rojo','ambar')), orden int not null, activo boolean not null default true,
  pide_estilo boolean not null default false);
insert into and_botones(codigo,nombre,icono,color,orden,pide_estilo) values
 ('CAMBIO','Cambio de estilo','🔄','azul',1,true),
 ('PARO','Paro de máquina','🔧','rojo',2,false),
 ('SUP','Llamar supervisor','🙋','ambar',3,false),
 ('CAL','Llamar Calidad','📏','ambar',4,false),
 ('MAT','Falta material','📦','ambar',5,false),
 ('FICHA','Duda de ficha','📄','ambar',6,false);

-- ===== Registro: cada vez que se enciende un botón =====
create table and_registros(
  id bigint generated always as identity primary key,
  linea_cod text not null references cat_lineas(codigo),
  boton_cod text not null references and_botones(codigo),
  inicio timestamptz not null default now(), fin timestamptz,
  usuario_inicio text, usuario_fin text,
  anulado boolean not null default false, anulado_por text, anulado_en timestamptz,
  estilo text);                                             -- estilo que entra (solo botones con pide_estilo)
create unique index and_registros_uno_abierto on and_registros(linea_cod, boton_cod) where fin is null and not anulado;
create index and_registros_linea on and_registros(linea_cod, inicio desc);

do $$ declare t text; begin
  foreach t in array array['and_botones','and_registros'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (true)', t||'_leer', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to anon, authenticated', t);
  end loop; end $$;

-- Estado de la línea: cada botón (encendido o no) y los registros de hoy
create or replace function and_panel_(p_linea text) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('ok',true,'ahora',now(),'linea_cod',p_linea,
    'botones', coalesce((select jsonb_agg(jsonb_build_object('codigo',b.codigo,'nombre',b.nombre,'icono',b.icono,'color',b.color,'pide_estilo',b.pide_estilo,
                 'abierto', case when r.id is not null then jsonb_build_object('id',r.id,'inicio',r.inicio,'min',and_minutos_(r.inicio,null),'estilo',r.estilo) end) order by b.orden)
               from and_botones b
               left join and_registros r on r.boton_cod = b.codigo and r.linea_cod = p_linea and r.fin is null and not r.anulado
               where b.activo), '[]'::jsonb),
    'hoy', coalesce((select jsonb_agg(s.x order by s.inicio desc, s.id desc) from (
               select r.inicio, r.id, jsonb_build_object('id',r.id,'boton',b.nombre,'estilo',r.estilo,'inicio',r.inicio,'fin',r.fin,'min',and_minutos_(r.inicio,r.fin)) x
               from and_registros r join and_botones b on b.codigo = r.boton_cod
               where r.linea_cod = p_linea and not r.anulado
                 and (r.inicio at time zone 'America/Lima')::date = (now() at time zone 'America/Lima')::date
               order by r.inicio desc, r.id desc limit 40) s), '[]'::jsonb))
$$;

-- ===== Puerta única =====
create or replace function and_api(p_accion text, p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_usuario text := nullif(lower(btrim(coalesce(p->>'usuario',''))),'');
  v_linea text := p->>'linea_cod'; v_boton text := p->>'boton';
  r and_registros%rowtype; v_id bigint;
begin
  if p_accion in ('pulsar','deshacer','poner_estilo') and not and_puede(v_usuario) then
    return jsonb_build_object('ok',false,'error', case when and_supervision_(v_usuario)
      then 'Modo supervisión: puedes ver todo, pero no se guarda nada' else 'No tienes permiso para registrar en las líneas de costura' end);
  end if;

  if p_accion = 'inicio' then
    return jsonb_build_object('ok',true,'puede',and_puede(v_usuario),'supervision',and_supervision_(v_usuario),
      'lineas', coalesce((select jsonb_agg(jsonb_build_object('codigo',codigo,'nombre',nombre) order by nombre) from cat_lineas where upper(coalesce(activo::text,'SI')) in ('SI','TRUE','T')),'[]'::jsonb));

  elsif p_accion = 'estilos' then          -- estilos de la base de OPs, el más reciente primero
    return jsonb_build_object('ok',true,'estilos', coalesce((select jsonb_agg(jsonb_build_object('estilo',s.estilo,'cliente',s.cli) order by s.f desc, s.estilo desc)
      from (select upper(btrim(o.estilo)) estilo, max(o.fecha_creacion) f,
                   string_agg(distinct split_part(o.grupo,'-',1), ' ') filter (where split_part(o.grupo,'-',1) not in ('RES','')) cli
            from ops o where coalesce(btrim(o.estilo),'') <> '' group by 1) s), '[]'::jsonb));

  elsif p_accion = 'poner_estilo' then     -- qué estilo entra (solo en un registro en curso)
    select * into r from and_registros where id = (p->>'registro_id')::bigint and not anulado and fin is null;
    if not found then return jsonb_build_object('ok',false,'error','Ese registro ya no está en curso'); end if;
    if not exists(select 1 from ops o where upper(btrim(o.estilo)) = upper(btrim(coalesce(p->>'estilo','')))) then
      return jsonb_build_object('ok',false,'error','Ese estilo no está en la base de OPs'); end if;
    update and_registros set estilo = upper(btrim(p->>'estilo')) where id = r.id;
    return and_panel_(r.linea_cod);

  elsif p_accion = 'panel' then
    return and_panel_(v_linea);

  elsif p_accion = 'pulsar' then            -- un toque enciende; otro toque apaga
    if not exists(select 1 from cat_lineas where codigo = v_linea) then return jsonb_build_object('ok',false,'error','Elige la línea'); end if;
    if not exists(select 1 from and_botones where codigo = v_boton and activo) then return jsonb_build_object('ok',false,'error','Ese botón no existe'); end if;
    select * into r from and_registros where linea_cod = v_linea and boton_cod = v_boton and fin is null and not anulado for update;
    if found then
      update and_registros set fin = now(), usuario_fin = v_usuario where id = r.id;
      return and_panel_(v_linea) || jsonb_build_object('hecho','FIN','registro_id',r.id);
    end if;
    insert into and_registros(linea_cod,boton_cod,usuario_inicio) values (v_linea,v_boton,v_usuario) returning id into v_id;
    return and_panel_(v_linea) || jsonb_build_object('hecho','INICIO','registro_id',v_id);

  elsif p_accion = 'deshacer' then          -- deshace el último toque: quita el inicio o vuelve a encender
    select * into r from and_registros where id = (p->>'registro_id')::bigint and not anulado;
    if not found then return jsonb_build_object('ok',false,'error','Ese registro ya no existe'); end if;
    if p->>'hecho' = 'INICIO' then
      if r.fin is not null then return jsonb_build_object('ok',false,'error','Ese registro ya fue terminado'); end if;
      update and_registros set anulado = true, anulado_por = v_usuario, anulado_en = now() where id = r.id;
    elsif p->>'hecho' = 'FIN' then
      if exists(select 1 from and_registros where linea_cod = r.linea_cod and boton_cod = r.boton_cod and fin is null and not anulado) then
        return jsonb_build_object('ok',false,'error','Ese botón ya se volvió a encender'); end if;
      update and_registros set fin = null, usuario_fin = null where id = r.id;
    else return jsonb_build_object('ok',false,'error','Falta qué deshacer'); end if;
    return and_panel_(r.linea_cod);
  end if;
  return jsonb_build_object('ok',false,'error','Acción desconocida: '||coalesce(p_accion,''));
end $$;

-- ===== Vista para el dashboard =====
create or replace view publico_and_registros as
  select r.id, r.linea_cod, l.nombre linea, r.boton_cod, b.nombre boton,
         (r.inicio at time zone 'America/Lima')::date fecha, r.inicio, r.fin,
         case when r.fin is not null then and_minutos_(r.inicio, r.fin) end minutos, r.usuario_inicio, r.usuario_fin, r.estilo
  from and_registros r join and_botones b on b.codigo = r.boton_cod join cat_lineas l on l.codigo = r.linea_cod
  where not r.anulado;

grant select on publico_and_registros to anon, authenticated;
grant execute on function and_api(text, jsonb) to anon, authenticated;
revoke execute on function and_panel_(text) from public, anon, authenticated;

-- Contrato para Sistemas (and_api recibe acción + datos y responde JSON):
--   inicio        {usuario}                         -> {puede, supervision, lineas:[{codigo,nombre}]}
--   panel         {linea_cod}                       -> {ahora, botones:[{codigo,nombre,icono,color,pide_estilo,abierto:{id,inicio,min,estilo}|null}], hoy:[{id,boton,estilo,inicio,fin,min}]}
--   pulsar        {usuario, linea_cod, boton}       -> panel + {hecho:'INICIO'|'FIN', registro_id}
--   deshacer      {usuario, registro_id, hecho}     -> panel
--   estilos       {}                                -> {estilos:[{estilo,cliente}]}   (de la base de OPs)
--   poner_estilo  {usuario, registro_id, estilo}    -> panel
