-- Datos de prueba para desarrollo local (TECH-02).
-- Sólo pensado para un entorno de pruebas (supabase db reset / start):
-- crea usuarios de auth directamente, algo que no se hace así en producción.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data
) values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111',
   'authenticated', 'authenticated', 'ana@example.com', crypt('Passw0rd!', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Ana Torres"}'),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222',
   'authenticated', 'authenticated', 'beto@example.com', crypt('Passw0rd!', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Beto Ramírez"}'),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333',
   'authenticated', 'authenticated', 'carla@example.com', crypt('Passw0rd!', gen_salt('bf')),
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Carla Núñez"}');
-- el trigger on_auth_user_created crea el perfil de cada quien automáticamente

update public.profiles set zone = 'CDMX Sur', sports_interests = array['futbol', 'running']
  where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set zone = 'CDMX Norte', sports_interests = array['basquetbol']
  where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set zone = 'CDMX Sur', sports_interests = array['futbol']
  where id = '33333333-3333-3333-3333-333333333333';

insert into public.activities
  (id, organizer_id, sport, title, description, scheduled_at, zone, level, capacity, estimated_cost, latitude, longitude)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'futbol', 'Futbol 7 en Viveros', 'Cancha sintética, llevar balón extra.',
   now() + interval '3 days', 'Viveros de Coyoacán, CDMX', 'intermedio', 6, 50, 19.3547, -99.1707),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
   'basquetbol', 'Básquet casual', null,
   now() + interval '5 days', 'Deportivo Los Galeana, CDMX', 'cualquier_nivel', 4, null, 19.4936, -99.1297);

insert into public.participations (activity_id, user_id)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333');
