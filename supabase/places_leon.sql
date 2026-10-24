-- Lugares deportivos de León (SCRUM-40). Pegar en el editor SQL de Supabase.
-- Las coordenadas de abajo salen de MapKit (las mismas que guarda la app).
-- Para agregar más lugares: copia una fila y busca sus coordenadas con el
-- selector de ubicación de la app o en Apple/Google Maps.
insert into public.places (name, category, sports, address, description, latitude, longitude)
values
  ('Parque Metropolitano de León', 'parque', array['running', 'futbol', 'ciclismo'],
   'Prol. Blvd Adolfo López Mateos Nte. s/n, El Palote, León, Gto.',
   'Parque con pista para correr, canchas y áreas verdes junto a la presa El Palote.',
   21.1700019, -101.6860827),
  ('Universidad La Salle Bajío', 'club', array['hiking', 'futbol', 'basquetbol'],
   'Avenida Universidad 301, Lomas del Campestre, León, Gto.',
   'Instalaciones deportivas y áreas para entrenar.',
   21.1524718, -101.7122215);
-- Ejemplo para agregar más:
-- ('Nombre del lugar', 'cancha', array['padel'], 'Dirección', 'Descripción', 21.xxxx, -101.xxxx),
