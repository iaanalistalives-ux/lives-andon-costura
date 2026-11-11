-- Ad07 andon costura pausas almuerzo y fin de dia · 11/11/2026
-- Pedido de Christian: «falta un botón de finalizar, eso sería para finalizar el día, o también botón para su almuerzo».
-- Los dos botones son una PAUSA de la línea:
--   Almuerzo       → al tocarlo dice «Fin de almuerzo»; se toca otra vez al volver.
--   Finalizar día  → al tocarlo dice «Iniciar día»; se toca al día siguiente para seguir.
--   Con la línea en pausa los demás botones no responden y ningún reloj cuenta.
--   Al volver, la línea sigue donde estaba (mismo estilo, misma etapa) y lo que estaba encendido sigue encendido.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad08_andon_costura_pausas_almuerzo_y_fin_de_dia). Guardar sin Run.
-- El almuerzo fijo (11:00–11:45) deja de descontarse: ahora se descuenta la pausa real que marquen.
-- Marcha atrás: desactivar los dos botones (update and_botones set activo = false where pausa) y volver a la
--   versión anterior de and_minutos_ (2 parámetros, descuenta ALMUERZO_INICIO–ALMUERZO_FIN; está en Ad03).

alter table and_botones add column pausa boolean not null default false;   -- el botón pausa la línea
alter table and_botones add column nombre_encendido text;                  -- cómo se llama mientras está encendido
alter table and_botones drop constraint and_botones_color_check;
alter table and_botones add constraint and_botones_color_check check (color in ('azul','rojo','ambar','gris'));
insert into and_botones(codigo,nombre,icono,color,orden,activo,pide_estilo,requiere,pausa,nombre_encendido) values
  ('ALM','Almuerzo','🍽️','gris',7,true,false,'CAMBIO',true,'Fin de almuerzo'),
  ('FIN','Finalizar día','🏁','gris',8,true,false,'CAMBIO',true,'Iniciar día');
-- and_parametros: ALMUERZO_INICIO y ALMUERZO_FIN quedan sin uso (se conservan por si se pide el descuento fijo como seguro).

-- Minutos: tiempo transcurrido menos las pausas reales de esa línea que caen dentro.
-- p_linea vacío = sin descuento (se usa para medir la propia pausa).
create or replace function and_minutos_(p_ini timestamptz, p_fin timestamptz, p_linea text)
returns numeric language sql stable security definer set search_path to 'public' as $f$
  select case when p_ini is null then null else greatest(0, round((
    extract(epoch from (coalesce(p_fin, now()) - p_ini))
    - coalesce((
        select sum(greatest(0, extract(epoch from (
                 least(coalesce(p_fin, now()), coalesce(z.fin, now())) - greatest(p_ini, z.inicio)))))
        from and_registros z join and_botones zb on zb.codigo = z.boton_cod and zb.pausa
        where p_linea is not null and z.linea_cod = p_linea and not z.anulado
          and z.inicio < coalesce(p_fin, now()) and coalesce(z.fin, now()) > p_ini), 0)
  ) / 60.0)) end $f$;
grant execute on function and_minutos_(timestamptz,timestamptz,text) to anon, authenticated;
-- La versión anterior and_minutos_(timestamptz,timestamptz) se eliminó.

create or replace view publico_and_registros as
  select r.id, r.linea_cod, l.nombre linea, r.boton_cod, b.nombre boton,
         (r.inicio at time zone 'America/Lima')::date fecha, r.inicio, r.fin,
         case when r.fin is not null then and_minutos_(r.inicio, r.fin, case when b.pausa then null else r.linea_cod end) end minutos, r.usuario_inicio, r.usuario_fin,
         coalesce(r.estilo, p.estilo) estilo, r.padre_id, r.cierre_auto, r.etapa, r.cerrado, b.pausa
  from and_registros r join and_botones b on b.codigo = r.boton_cod join cat_lineas l on l.codigo = r.linea_cod
  left join and_registros p on p.id = r.padre_id
  where not r.anulado;
grant select on publico_and_registros to anon, authenticated;

-- and_panel_ devuelve además (texto completo en la base):
--   'pausa' = la pausa abierta de la línea {id, codigo, nombre, nombre_encendido, inicio}; null si no hay.
--   en cada botón: 'pausa', 'nombre_encendido'; 'bloqueado' también es verdadero si hay una pausa abierta que no es ese botón.
--   'pausa' en cada fila de 'hoy'. Los minutos ya descuentan las pausas.

-- and_api, cambios respecto de Ad06 (texto completo en la base):
--   pulsar · con una pausa abierta, cualquier otro botón responde «La línea está en pausa: toca «Fin de almuerzo»» (o «Iniciar día»).
--   pulsar · los botones de pausa exigen que la línea ya haya iniciado, como los otros 5; no cierran ni cambian el estilo.
--   deshacer FIN de una pausa: no se permite si después de esa pausa ya se marcó otro botón.

-- Para el análisis (vista publico_and_registros):
--   la columna 'minutos' de cada registro ya viene sin almuerzo ni tiempo fuera de jornada;
--   las filas con pausa = true son las pausas (ALM = almuerzo, FIN = de «Finalizar día» a «Iniciar día»); sus minutos son la duración de la pausa;
--   tiempo del estilo en la línea = and_minutos_(inicio del CAMBIO, cerrado, linea_cod).
-- Límite: si olvidan tocar Almuerzo o Finalizar día, ese tiempo cuenta como tiempo muerto.
