-- LIMPIEZA TOTAL DE DATOS (todo menos los usuarios).
-- ⚠️ IRREVERSIBLE. Pegar en el editor SQL de Supabase sólo si de verdad quieres
-- empezar de cero. NO está en supabase/migrations a propósito: `supabase db push`
-- no debe ejecutarlo nunca.
--
-- Se conservan: auth.users y public.profiles (cuentas, nombres, zonas, intereses).
-- Se borran: actividades, participaciones, reportes, encuestas, moderación,
-- lugares, grupos y miembros, publicaciones, likes, comentarios, seguidores,
-- historias y notificaciones.
--
-- TRUNCATE no dispara los triggers por fila ni la RLS, así que no estorban las
-- reglas (p. ej. "el creador no puede salir de su grupo"). Las tablas que aún no
-- existen (si no has aplicado alguna migración) se saltan solas.

do $$
declare
  t text;
begin
  foreach t in array array[
    'notifications',
    'story_views', 'stories',
    'follows',
    'post_reports', 'post_comments', 'post_likes', 'posts',
    'community_group_members', 'community_groups',
    'moderation_actions', 'activity_feedback', 'activity_reports',
    'participations', 'activities',
    'places'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('truncate table public.%I restart identity cascade', t);
      raise notice 'vaciada: %', t;
    end if;
  end loop;
end $$;

-- Comprobación: todo en 0 menos los usuarios.
select
  (select count(*) from public.profiles)   as perfiles_conservados,
  (select count(*) from public.activities) as actividades,
  (select count(*) from public.posts)      as posts;

-- Los lugares curados de León se vuelven a cargar pegando supabase/places_leon.sql.
-- (Si quieres CONSERVAR los lugares, quita 'places' de la lista de arriba.)

-- FOTOS: este script NO borra los archivos de Storage. No los borres con SQL
-- (`delete from storage.objects`): quita la fila pero deja el archivo guardado.
-- Hazlo desde el dashboard: Storage → bucket post-images → seleccionar todo → Delete.
