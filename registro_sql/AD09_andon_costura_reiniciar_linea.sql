-- Ad09 andon costura reiniciar linea · 13/11/2026
-- Pedido de Christian: «falta un botón de reinicio abajo, donde sale lo registrado».
-- Acción nueva de la puerta: and_api('reiniciar', {usuario, linea_cod}) → devuelve el panel + hecho = 'REINICIO' + anulados (cuántos).
--   · Lo registrado HOY en esa línea queda anulado (anulado = true, anulado_por, anulado_en). No se borra ninguna fila.
--   · Lo de días anteriores que seguía encendido se cierra a esa hora (fin, cierre_auto) y el estilo sale de la línea (cerrado); no se anula.
--   · La línea queda «Sin iniciar» y la lista de hoy vacía. Exige permiso (and_puede), igual que pulsar y deshacer.
-- SOLO REGISTRO: ya fue ejecutado por Claude en Supabase (migración ad10_andon_costura_reiniciar). Guardar sin Run.
-- No cambia tablas, columnas, vistas ni las demás acciones.
-- PROBADO en una prueba que se deshizo sola (13/11/2026): línea con inicio, estilo, paro, cambio y almuerzo encendido → 4 anulados,
--   lista vacía, sin estilo, sin pausa; vuelve a iniciar bien; Rodrigo (supervisión) no guarda; línea inexistente da «Elige la línea»;
--   con registros de ayer encendidos: se cierran sin anularse; las demás líneas no se tocan (9 filas antes y después).
-- RECUPERAR un reinicio hecho por error (lo hace Claude): los registros de ese reinicio comparten anulado_en y anulado_por.
--   update and_registros set anulado = false, anulado_por = null, anulado_en = null where linea_cod = '<línea>' and anulado_en = '<hora del reinicio>';
--   (si había algo encendido de días anteriores, además se le quita fin/cerrado puestos a esa misma hora)
-- A Sistemas: en T-SQL es una acción más de and_api; «hoy» se calcula en hora de Lima.

-- La migración agregó dos cosas al texto de and_api (lo demás quedó igual; el texto completo está en la base):

-- 1) En la comprobación de permiso del inicio de la función:
--      if p_accion in ('pulsar','deshacer','poner_estilo','reiniciar') and not and_puede(v_usuario) then ...

-- 2) La acción, antes de 'deshacer':
/*
  elsif p_accion = 'reiniciar' then         -- la lista de hoy queda vacía y la línea vuelve a «Sin iniciar»
    if not exists(select 1 from cat_lineas where codigo = v_linea) then return jsonb_build_object('ok',false,'error','Elige la línea'); end if;
    -- lo registrado hoy en la línea se anula (no se borra: queda con quién y cuándo)
    update and_registros set anulado = true, anulado_por = v_usuario, anulado_en = now()
      where linea_cod = v_linea and not anulado
        and (inicio at time zone 'America/Lima')::date = (now() at time zone 'America/Lima')::date;
    get diagnostics v_id = row_count;
    -- lo de días anteriores que seguía encendido o con su estilo en la línea se cierra a esta hora, no se anula
    update and_registros set fin = now(), usuario_fin = v_usuario, cierre_auto = true
      where linea_cod = v_linea and fin is null and not anulado;
    update and_registros x set cerrado = now()
      where x.linea_cod = v_linea and x.cerrado is null and not x.anulado
        and exists(select 1 from and_botones h where h.requiere = x.boton_cod and not h.pausa);
    return and_panel_(v_linea) || jsonb_build_object('hecho','REINICIO','anulados',v_id);
*/

-- Marcha atrás (quita la acción y deja and_api como estaba en Ad08):
/*
do $rev$
declare d text; i int; f int;
begin
  select pg_get_functiondef('public.and_api(text,jsonb)'::regprocedure) into d;
  d := replace(d, $a$('pulsar','deshacer','poner_estilo','reiniciar')$a$, $a$('pulsar','deshacer','poner_estilo')$a$);
  i := position($a$  elsif p_accion = 'reiniciar' then$a$ in d);
  f := position($a$  elsif p_accion = 'deshacer' then$a$ in d);
  if i = 0 or f = 0 or f < i then raise exception 'No se encontró la acción reiniciar'; end if;
  d := substr(d, 1, i - 1) || substr(d, f);
  execute d;
end $rev$;
*/
