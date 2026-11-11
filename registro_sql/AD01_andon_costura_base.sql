-- Ad01 andon costura base · 11/11/2026
-- Botones de la línea de costura (cambio de estilo). Prefijo and_ · puerta and_api.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad01_andon_costura_base). Guardar sin Run.
-- Propio de Postgres (anotar para SQL Server): jsonb en la puerta, security definer, políticas de lectura por fila,
-- generate_series y "at time zone" en and_minutos_, índice único parcial (un cambio abierto por línea).

-- ===== Catálogos =====
create table and_parametros(clave text primary key, valor text not null, nota text);
insert into and_parametros(clave,valor,nota) values
 ('REGISTRO_LIBRE','SI','SI = cualquiera puede registrar (pruebas). NO = solo ctalepcio, hasta que Sistemas ponga su seguridad'),
 ('ALMUERZO_INICIO','11:00','Hora de inicio del almuerzo; se descuenta de los minutos'),
 ('ALMUERZO_FIN','11:45','Hora de fin del almuerzo');

create table and_estados(codigo text primary key, nombre text not null,
  tipo text not null check (tipo in ('TRABAJO','ESPERA','RESULTADO')), orden int not null, activo boolean not null default true);
insert into and_estados(codigo,nombre,tipo,orden) values
 ('GRAD','Graduando','TRABAJO',1),('PROB','Probando','TRABAJO',2),('ENV','En Calidad','TRABAJO',3),
 ('ESP','Esperando','ESPERA',4),('LISTA','Aprobada','RESULTADO',5),('RECH','Rechazada','RESULTADO',6);

create table and_areas(codigo text primary key, nombre text not null, orden int not null, activo boolean not null default true);
insert into and_areas(codigo,nombre,orden) values
 ('MEC','Mecánico',1),('OPE','Operaria',2),('CAL','Calidad',3),('FIC','Ficha',4),('PLA','Plantillas',5);

create table and_maquinas(codigo text primary key, nombre text not null, activo boolean not null default true,
  creado_en timestamptz not null default now(), creado_por text);

-- ===== Registro =====
create table and_cambios(
  id bigint generated always as identity primary key,
  codigo text unique,
  linea_cod text not null references cat_lineas(codigo),
  op text not null, grupo text, estilo text, e_cliente text,
  inicio timestamptz not null default now(), fin timestamptz,
  estado text not null default 'ABIERTO' check (estado in ('ABIERTO','CERRADO','ANULADO')),
  creado_por text, cerrado_por text);
create unique index and_cambios_uno_abierto on and_cambios(linea_cod) where estado='ABIERTO';

create table and_cambio_maquinas(
  id bigint generated always as identity primary key,
  cambio_id bigint not null references and_cambios(id),
  maquina_cod text not null references and_maquinas(codigo),
  operacion text not null default '',
  orden int not null default 0, activo boolean not null default true,
  creado_en timestamptz not null default now(), creado_por text,
  unique(cambio_id, maquina_cod));

create table and_eventos(
  id bigint generated always as identity primary key,
  cambio_id bigint not null references and_cambios(id),
  cm_id bigint references and_cambio_maquinas(id),          -- vacío = primera prenda
  estado_cod text not null references and_estados(codigo),
  area_cod text references and_areas(codigo),               -- a quién se espera (solo ESP)
  inicio timestamptz not null default now(), fin timestamptz,
  usuario text,
  anulado boolean not null default false, anulado_por text, anulado_en timestamptz,
  check (estado_cod <> 'ESP' or area_cod is not null));
create index and_eventos_cambio on and_eventos(cambio_id, cm_id, inicio desc);

-- Ver es libre (banco de pruebas); escribir solo por and_api
do $$ declare t text; begin
  foreach t in array array['and_parametros','and_estados','and_areas','and_maquinas','and_cambios','and_cambio_maquinas','and_eventos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (true)', t||'_leer', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to anon, authenticated', t);
  end loop; end $$;

-- ===== Funciones de apoyo =====
create or replace function and_par(p_clave text) returns text language sql stable security definer set search_path=public as
$$ select valor from and_parametros where clave = p_clave $$;

create or replace function and_supervision_(p_usuario text) returns boolean language sql stable security definer set search_path=public as
$$ select lower(btrim(coalesce(p_usuario,''))) = 'rcamogliano'
      or exists(select 1 from perfiles where user_id::text = auth.uid()::text and lower(btrim(usuario)) = 'rcamogliano') $$;

-- Permiso: es la pieza que Sistemas reemplaza con su seguridad
create or replace function and_puede(p_usuario text default null) returns boolean language plpgsql stable security definer set search_path=public as $$
begin
  if and_supervision_(p_usuario) then return false; end if;
  if lower(btrim(coalesce(p_usuario,''))) = 'ctalepcio' then return true; end if;
  return upper(coalesce(and_par('REGISTRO_LIBRE'),'NO')) = 'SI';
end $$;

-- Minutos entre dos horas, sin contar el almuerzo (hora de Lima). Sin fin = hasta ahora.
create or replace function and_minutos_(p_ini timestamptz, p_fin timestamptz) returns numeric language sql stable security definer set search_path=public as $$
  select case when p_ini is null then null else greatest(0, round((
    extract(epoch from (coalesce(p_fin, now()) - p_ini))
    - coalesce((
        select sum(greatest(0, extract(epoch from (
                 least(coalesce(p_fin, now()), (g.d::date + t.ff) at time zone 'America/Lima')
               - greatest(p_ini,             (g.d::date + t.ii) at time zone 'America/Lima')))))
        from generate_series((p_ini at time zone 'America/Lima')::date::timestamp,
                             (coalesce(p_fin, now()) at time zone 'America/Lima')::date::timestamp, interval '1 day') g(d),
             (select and_par('ALMUERZO_INICIO')::time ii, and_par('ALMUERZO_FIN')::time ff) t), 0)
  ) / 60.0)) end $$;

-- Estado de la línea: cambio abierto, máquinas con su último estado, primera prenda y últimos registros
create or replace function and_tablero_(p_linea text) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c and_cambios%rowtype;
begin
  select * into c from and_cambios where linea_cod = p_linea and estado = 'ABIERTO';
  if not found then return jsonb_build_object('ok',true,'ahora',now(),'cambio',null); end if;
  return jsonb_build_object('ok',true,'ahora',now(),
    'cambio', jsonb_build_object('id',c.id,'codigo',c.codigo,'linea_cod',c.linea_cod,'op',c.op,'grupo',c.grupo,'estilo',c.estilo,
                                 'inicio',c.inicio,'min',and_minutos_(c.inicio,null)),
    'maquinas', coalesce((
       select jsonb_agg(jsonb_build_object('cm_id',m.id,'maquina',q.nombre,'operacion',m.operacion,
                'estado',u.estado_cod,'area',u.area_cod,'evento_id',u.id,
                'min', case when u.id is not null and u.fin is null then and_minutos_(u.inicio,null) end,
                'rechazos',(select count(*) from and_eventos e where e.cm_id = m.id and not e.anulado and e.estado_cod = 'RECH'))
              order by m.orden, m.id)
       from and_cambio_maquinas m join and_maquinas q on q.codigo = m.maquina_cod
       left join lateral (select * from and_eventos e where e.cm_id = m.id and not e.anulado order by e.inicio desc, e.id desc limit 1) u on true
       where m.cambio_id = c.id and m.activo), '[]'::jsonb),
    'pp', (select jsonb_build_object('estado',u.estado_cod,'evento_id',u.id,
                'min', case when u.id is not null and u.fin is null then and_minutos_(u.inicio,null) end,
                'rechazos',(select count(*) from and_eventos e where e.cambio_id = c.id and e.cm_id is null and not e.anulado and e.estado_cod = 'RECH'))
           from (select 1) z
           left join lateral (select * from and_eventos e where e.cambio_id = c.id and e.cm_id is null and not e.anulado order by e.inicio desc, e.id desc limit 1) u on true),
    'log', coalesce((
       select jsonb_agg(s.x order by s.inicio desc, s.id desc) from (
         select e.inicio, e.id, jsonb_build_object('id',e.id,'cm_id',e.cm_id,'maquina',q.nombre,'operacion',m.operacion,
                  'estado',e.estado_cod,'area',e.area_cod,'inicio',e.inicio,'fin',e.fin,
                  'min', case when s2.tipo <> 'RESULTADO' then and_minutos_(e.inicio,e.fin) end) x
         from and_eventos e join and_estados s2 on s2.codigo = e.estado_cod
         left join and_cambio_maquinas m on m.id = e.cm_id left join and_maquinas q on q.codigo = m.maquina_cod
         where e.cambio_id = c.id and not e.anulado order by e.inicio desc, e.id desc limit 30) s), '[]'::jsonb));
end $$;

-- ===== Puerta única =====
create or replace function and_api(p_accion text, p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_usuario text := nullif(lower(btrim(coalesce(p->>'usuario',''))),'');
  c and_cambios%rowtype; e and_eventos%rowtype; u and_eventos%rowtype; v_est and_estados%rowtype;
  v_linea text; v_op text; v_cm bigint; v_id bigint; v_area text; v_cod text; v_nom text; v_n int := 0; x jsonb; r record;
  f_escritura boolean := p_accion in ('iniciar_cambio','agregar_maquina','quitar_maquina','tocar','deshacer','cerrar_cambio');
begin
  if f_escritura and not and_puede(v_usuario) then
    return jsonb_build_object('ok',false,'error', case when and_supervision_(v_usuario)
      then 'Modo supervisión: puedes ver todo, pero no se guarda nada' else 'No tienes permiso para registrar en las líneas de costura' end);
  end if;

  if p_accion = 'inicio' then
    return jsonb_build_object('ok',true,'puede',and_puede(v_usuario),'supervision',and_supervision_(v_usuario),
      'lineas', coalesce((select jsonb_agg(jsonb_build_object('codigo',codigo,'nombre',nombre) order by nombre) from cat_lineas where upper(coalesce(activo::text,'SI')) in ('SI','TRUE','T')),'[]'::jsonb),
      'estados', (select jsonb_agg(jsonb_build_object('codigo',codigo,'nombre',nombre,'tipo',tipo) order by orden) from and_estados where activo),
      'areas', (select jsonb_agg(jsonb_build_object('codigo',codigo,'nombre',nombre) order by orden) from and_areas where activo));

  elsif p_accion = 'tablero' then
    return and_tablero_(p->>'linea_cod');

  elsif p_accion = 'buscar_op' then
    v_op := btrim(coalesce(p->>'op',''));
    select o.grupo, o.estilo, o.e_cliente into r from ops o where o.op = v_op limit 1;
    if not found then return jsonb_build_object('ok',true,'existe',false); end if;
    return jsonb_build_object('ok',true,'existe',true,'op',v_op,'grupo',r.grupo,'estilo',r.estilo,'e_cliente',r.e_cliente);

  elsif p_accion = 'iniciar_cambio' then
    v_linea := p->>'linea_cod'; v_op := btrim(coalesce(p->>'op',''));
    if not exists(select 1 from cat_lineas where codigo = v_linea) then return jsonb_build_object('ok',false,'error','Elige la línea'); end if;
    if v_op = '' then return jsonb_build_object('ok',false,'error','Escribe la OP que entra'); end if;
    if exists(select 1 from and_cambios where linea_cod = v_linea and estado = 'ABIERTO') then
      return jsonb_build_object('ok',false,'error','Esta línea ya tiene un cambio de estilo abierto'); end if;
    if jsonb_typeof(p->'maquinas') is distinct from 'array' or jsonb_array_length(p->'maquinas') = 0 then
      return jsonb_build_object('ok',false,'error','Agrega al menos una máquina'); end if;
    select o.grupo, o.estilo, o.e_cliente into r from ops o where o.op = v_op limit 1;
    insert into and_cambios(linea_cod, op, grupo, estilo, e_cliente, creado_por)
      values (v_linea, v_op, r.grupo, r.estilo, r.e_cliente, v_usuario) returning * into c;
    update and_cambios set codigo = 'CE-'||to_char(now() at time zone 'America/Lima','YYMMDD')||'-'||c.id where id = c.id;
    for x in select * from jsonb_array_elements(p->'maquinas') loop
      v_nom := upper(btrim(regexp_replace(coalesce(x->>'maquina',''),'\s+',' ','g')));
      v_cod := replace(v_nom,' ','');
      continue when v_cod = '';
      v_n := v_n + 1;
      insert into and_maquinas(codigo,nombre,creado_por) values (v_cod,v_nom,v_usuario) on conflict (codigo) do nothing;
      insert into and_cambio_maquinas(cambio_id,maquina_cod,operacion,orden,creado_por)
        values (c.id, v_cod, btrim(coalesce(x->>'operacion','')), v_n, v_usuario) on conflict (cambio_id,maquina_cod) do nothing;
    end loop;
    if v_n = 0 then raise exception 'Agrega al menos una máquina'; end if;
    return and_tablero_(v_linea);

  elsif p_accion in ('agregar_maquina','quitar_maquina','tocar','cerrar_cambio') then
    select * into c from and_cambios where id = (p->>'cambio_id')::bigint;
    if not found or c.estado <> 'ABIERTO' then return jsonb_build_object('ok',false,'error','El cambio de estilo ya no está abierto. Vuelve a cargar la pantalla'); end if;

    if p_accion = 'agregar_maquina' then
      v_nom := upper(btrim(regexp_replace(coalesce(p->>'maquina',''),'\s+',' ','g'))); v_cod := replace(v_nom,' ','');
      if v_cod = '' then return jsonb_build_object('ok',false,'error','Escribe el código de la máquina'); end if;
      insert into and_maquinas(codigo,nombre,creado_por) values (v_cod,v_nom,v_usuario) on conflict (codigo) do nothing;
      if exists(select 1 from and_cambio_maquinas where cambio_id = c.id and maquina_cod = v_cod and activo) then
        return jsonb_build_object('ok',false,'error','Esa máquina ya está en este cambio'); end if;
      insert into and_cambio_maquinas(cambio_id,maquina_cod,operacion,orden,creado_por)
        values (c.id, v_cod, btrim(coalesce(p->>'operacion','')), (select coalesce(max(orden),0)+1 from and_cambio_maquinas where cambio_id = c.id), v_usuario)
        on conflict (cambio_id,maquina_cod) do update set activo = true, operacion = excluded.operacion;

    elsif p_accion = 'quitar_maquina' then
      v_cm := (p->>'cm_id')::bigint;
      if exists(select 1 from and_eventos where cm_id = v_cm and not anulado) then
        return jsonb_build_object('ok',false,'error','Esa máquina ya tiene registros; no se puede quitar'); end if;
      update and_cambio_maquinas set activo = false where id = v_cm and cambio_id = c.id;

    elsif p_accion = 'tocar' then
      v_cm := nullif(p->>'cm_id','')::bigint; v_area := nullif(p->>'area','');
      select * into v_est from and_estados where codigo = p->>'estado' and activo;
      if not found then return jsonb_build_object('ok',false,'error','Estado no válido'); end if;
      if v_cm is not null and not exists(select 1 from and_cambio_maquinas where id = v_cm and cambio_id = c.id and activo) then
        return jsonb_build_object('ok',false,'error','Esa máquina no es de este cambio'); end if;
      if v_cm is null and v_est.codigo not in ('ENV','LISTA','RECH') then return jsonb_build_object('ok',false,'error','Estado no válido para la primera prenda'); end if;
      if v_cm is not null and v_est.codigo = 'ENV' then return jsonb_build_object('ok',false,'error','Estado no válido para una máquina'); end if;
      if v_est.codigo = 'ESP' then
        if not exists(select 1 from and_areas where codigo = v_area and activo) then return jsonb_build_object('ok',false,'error','Falta a quién se espera'); end if;
      else v_area := null; end if;
      select * into u from and_eventos where cambio_id = c.id and cm_id is not distinct from v_cm and not anulado order by inicio desc, id desc limit 1;
      if found and u.estado_cod = v_est.codigo and u.area_cod is not distinct from v_area then
        return and_tablero_(c.linea_cod) || jsonb_build_object('sin_cambio',true);   -- tocar lo mismo no duplica
      end if;
      update and_eventos set fin = now() where cambio_id = c.id and cm_id is not distinct from v_cm and not anulado and fin is null;
      insert into and_eventos(cambio_id,cm_id,estado_cod,area_cod,fin,usuario)
        values (c.id, v_cm, v_est.codigo, v_area, case when v_est.tipo = 'RESULTADO' then now() end, v_usuario) returning id into v_id;
      return and_tablero_(c.linea_cod) || jsonb_build_object('evento_id',v_id);

    elsif p_accion = 'cerrar_cambio' then
      update and_eventos set fin = now() where cambio_id = c.id and not anulado and fin is null;
      update and_cambios set estado = 'CERRADO', fin = now(), cerrado_por = v_usuario where id = c.id;
    end if;
    return and_tablero_(c.linea_cod);

  elsif p_accion = 'deshacer' then
    select * into e from and_eventos where id = (p->>'evento_id')::bigint and not anulado;
    if not found then return jsonb_build_object('ok',false,'error','Ese registro ya no existe'); end if;
    select * into c from and_cambios where id = e.cambio_id;
    if c.estado <> 'ABIERTO' then return jsonb_build_object('ok',false,'error','El cambio de estilo ya está cerrado'); end if;
    if exists(select 1 from and_eventos where cambio_id = e.cambio_id and cm_id is not distinct from e.cm_id and not anulado
              and (inicio, id) > (e.inicio, e.id)) then
      return jsonb_build_object('ok',false,'error','Solo se puede deshacer el último registro de la máquina'); end if;
    update and_eventos set anulado = true, anulado_por = v_usuario, anulado_en = now() where id = e.id;
    -- lo anterior vuelve a quedar en curso si este registro lo había cerrado
    select * into u from and_eventos where cambio_id = e.cambio_id and cm_id is not distinct from e.cm_id and not anulado order by inicio desc, id desc limit 1;
    if found and u.fin = e.inicio and exists(select 1 from and_estados where codigo = u.estado_cod and tipo <> 'RESULTADO') then
      update and_eventos set fin = null where id = u.id;
    end if;
    return and_tablero_(c.linea_cod);
  end if;
  return jsonb_build_object('ok',false,'error','Acción desconocida: '||coalesce(p_accion,''));
end $$;

-- ===== Vistas para el dashboard =====
create or replace view publico_and_eventos as
  select e.id, c.codigo cambio, c.linea_cod, l.nombre linea, c.op, c.grupo, c.estilo,
         m.maquina_cod, q.nombre maquina, m.operacion, (e.cm_id is null) primera_prenda,
         e.estado_cod, s.nombre estado, s.tipo, e.area_cod, a.nombre espera_a,
         e.inicio, e.fin, case when s.tipo <> 'RESULTADO' and e.fin is not null then and_minutos_(e.inicio, e.fin) end minutos, e.usuario
  from and_eventos e join and_cambios c on c.id = e.cambio_id join cat_lineas l on l.codigo = c.linea_cod
  join and_estados s on s.codigo = e.estado_cod left join and_areas a on a.codigo = e.area_cod
  left join and_cambio_maquinas m on m.id = e.cm_id left join and_maquinas q on q.codigo = m.maquina_cod
  where not e.anulado and c.estado <> 'ANULADO';

create or replace view publico_and_cambios as
  select c.id, c.codigo, c.linea_cod, l.nombre linea, c.op, c.grupo, c.estilo, c.estado, c.inicio, c.fin,
         case when c.fin is not null then and_minutos_(c.inicio, c.fin) end minutos_total,
         (select count(*) from and_cambio_maquinas m where m.cambio_id = c.id and m.activo) maquinas,
         (select count(*) from and_eventos e where e.cambio_id = c.id and not e.anulado and e.estado_cod = 'RECH') rechazos,
         (select coalesce(sum(and_minutos_(e.inicio, e.fin)),0) from and_eventos e where e.cambio_id = c.id and not e.anulado and e.estado_cod = 'ESP' and e.fin is not null) minutos_espera,
         (select min(e.inicio) from and_eventos e where e.cambio_id = c.id and e.cm_id is null and not e.anulado and e.estado_cod = 'LISTA') primera_prenda_aprobada
  from and_cambios c join cat_lineas l on l.codigo = c.linea_cod where c.estado <> 'ANULADO';

-- Permisos (regla: toda función de permiso y la puerta, para anon y authenticated)
grant select on publico_and_eventos, publico_and_cambios to anon, authenticated;
grant execute on function and_api(text, jsonb), and_puede(text), and_par(text), and_supervision_(text), and_minutos_(timestamptz, timestamptz) to anon, authenticated;
revoke execute on function and_tablero_(text) from public, anon, authenticated;
