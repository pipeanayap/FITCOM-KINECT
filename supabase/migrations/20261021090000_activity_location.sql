-- Ubicación real de la actividad (SCRUM-35 / SCRUM-36).
-- zone sigue siendo el nombre legible del lugar; latitude/longitude permiten
-- calcular distancia. Son nullable para no romper actividades existentes.
alter table public.activities
  add column latitude double precision,
  add column longitude double precision,
  add constraint activities_latitude_range check (latitude is null or latitude between -90 and 90),
  add constraint activities_longitude_range check (longitude is null or longitude between -180 and 180),
  add constraint activities_coords_together check ((latitude is null) = (longitude is null));

-- Las columnas nuevas van al final para que create or replace view las acepte.
create or replace view public.activities_public
with (security_invoker = true)
as
select
  a.id, a.organizer_id, a.sport, a.title, a.description, a.scheduled_at,
  a.zone, a.level, a.capacity, a.estimated_cost, a.status, a.is_hidden,
  a.created_at, a.updated_at,
  coalesce(p.active_count, 0) as participant_count,
  a.capacity - coalesce(p.active_count, 0) as spots_left,
  case
    when a.status = 'cancelada' then 'cancelada'
    when a.scheduled_at <= now() then 'finalizada'
    when coalesce(p.active_count, 0) >= a.capacity then 'completa'
    else 'abierta'
  end as computed_status,
  a.latitude, a.longitude
from public.activities a
left join (
  select activity_id, count(*) as active_count
  from public.participations
  where status = 'activa'
  group by activity_id
) p on p.activity_id = a.id;

-- Una actividad cancelada tampoco puede cambiar de lugar.
create or replace function public.check_activity_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  active_count int;
begin
  if old.status = 'cancelada' and new.status = 'cancelada' then
    if new.sport is distinct from old.sport
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.scheduled_at is distinct from old.scheduled_at
      or new.zone is distinct from old.zone
      or new.latitude is distinct from old.latitude
      or new.longitude is distinct from old.longitude
      or new.level is distinct from old.level
      or new.capacity is distinct from old.capacity then
      raise exception 'No se puede editar una actividad cancelada';
    end if;
  end if;

  if new.scheduled_at <= now() and new.scheduled_at is distinct from old.scheduled_at then
    raise exception 'La fecha y hora de la actividad deben ser futuras';
  end if;

  if new.capacity is distinct from old.capacity then
    select count(*) into active_count
      from public.participations
      where activity_id = new.id and status = 'activa';
    if new.capacity < active_count then
      raise exception 'El cupo no puede ser menor al número de participantes actuales (%).', active_count;
    end if;
  end if;

  return new;
end;  
$$;
