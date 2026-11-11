-- Ad02 andon costura por estilo · 11/11/2026
-- El cambio de estilo empieza con el ESTILO (antes pedía la OP) y ya no exige máquinas para iniciar.
-- Motivo: el 24323 de la cronología es un estilo (Theory, grupos THY-1036/1056/1118/1145), no la OP 24323 (VIN-566).
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad02_andon_costura_por_estilo). Guardar sin Run.
-- La base estaba vacía (0 cambios): no se convirtió ningún dato.
-- Marcha atrás: alter table and_cambios alter column op set not null; alter column estilo drop not null;
--               y volver a crear and_api con el texto de Ad01.

alter table and_cambios alter column op drop not null;
alter table and_cambios alter column estilo set not null;

-- and_api se volvió a crear con estos cambios respecto de Ad01 (lo demás quedó igual):

-- 1) variable nueva en el declare:  v_estilo text;

-- 2) acción nueva, antes de 'buscar_op':
--   elsif p_accion = 'buscar_estilo' then
--     v_estilo := upper(btrim(coalesce(p->>'estilo','')));
--     if v_estilo = '' or not exists(select 1 from ops o where upper(btrim(o.estilo)) = v_estilo) then
--       return jsonb_build_object('ok',true,'existe',false); end if;
--     return jsonb_build_object('ok',true,'existe',true,'estilo',v_estilo,
--       'ops', (select jsonb_agg(s.x order by s.op desc)
--               from (select o.op, jsonb_build_object('op',o.op,'grupo',max(o.grupo)) x
--                     from ops o where upper(btrim(o.estilo)) = v_estilo group by o.op) s));

-- 3) 'iniciar_cambio':
--     v_linea := p->>'linea_cod'; v_op := nullif(btrim(coalesce(p->>'op','')),''); v_estilo := upper(btrim(coalesce(p->>'estilo','')));
--     ... if v_estilo = '' then return jsonb_build_object('ok',false,'error','Escribe el estilo que entra'); end if;
--     (se quitó la validación "Agrega al menos una máquina", al inicio y al final)
--     select o.grupo, o.e_cliente into r from ops o where o.op = v_op and upper(btrim(o.estilo)) = v_estilo limit 1;
--     insert into and_cambios(linea_cod, op, grupo, estilo, e_cliente, creado_por)
--       values (v_linea, v_op, r.grupo, v_estilo, r.e_cliente, v_usuario) returning * into c;
--     for x in select * from jsonb_array_elements(case when jsonb_typeof(p->'maquinas') = 'array' then p->'maquinas' else '[]'::jsonb end) loop

grant execute on function and_api(text, jsonb) to anon, authenticated;

-- Contrato que cambia para Sistemas:
--   buscar_estilo  recibe {estilo}                         devuelve {existe, estilo, ops:[{op, grupo}]}
--   iniciar_cambio recibe {linea_cod, estilo, op?, maquinas?[{maquina, operacion}]}   (estilo obligatorio; op y maquinas opcionales)
--   grupo y e_cliente solo se llenan si se eligió una OP de ese estilo (un estilo puede tener varios grupos).
