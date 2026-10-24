-- Lugares deportivos curados (SCRUM-40) y grupos / comunidades (SCRUM-41).

-- =========================================================================
-- places — lugares de León cargados por el equipo (sin panel de negocios)
-- =========================================================================
create table public.places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null check (category in ('cancha', 'gimnasio', 'parque', 'club', 'estudio', 'otro')),
  sports text[] not null default '{}',
  address text,
  description text,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.places is 'Lugares deportivos curados por el equipo (SCRUM-40). Sólo admins los crean.';

-- =========================================================================
-- community_groups / community_group_members (SCRUM-41)
-- ("community_" para no chocar con la palabra clave GROUPS de SQL)
-- =========================================================================
create table public.community_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 60),
  description text,
  sport text,
  zone text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.community_groups is 'Grupos / comunidades deportivas (SCRUM-41).';

create table public.community_group_members (
  group_id uuid not null references public.community_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'miembro' check (role in ('admin', 'miembro')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- El creador entra solo como admin del grupo (igual que el organizador en una actividad).
create function public.add_creator_as_group_admin()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.community_group_members (group_id, user_id, role)
  values (new.id, new.created_by, 'admin');
  return new;
end;
$$;

create trigger community_groups_add_creator
  after insert on public.community_groups
  for each row execute function public.add_creator_as_group_admin();

-- El creador no puede salir de su propio grupo (salvo que el grupo se borre en cascada).
create function public.check_group_member_leave()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if exists (select 1 from public.community_groups g where g.id = old.group_id and g.created_by = old.user_id) then
    raise exception 'El creador no puede salir de su propio grupo';
  end if;
  return old;
end;
$$;

create trigger community_group_members_before_delete
  before delete on public.community_group_members
  for each row execute function public.check_group_member_leave();

-- =========================================================================
-- activities: lugar y grupo opcionales
-- =========================================================================
alter table public.activities
  add column place_id uuid references public.places (id) on delete set null,
  add column group_id uuid references public.community_groups (id) on delete set null;

-- Sólo se puede publicar en un grupo del que se es miembro (regla en la base de datos).
create function public.check_activity_group()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.group_id is not null
     and (tg_op = 'INSERT' or new.group_id is distinct from old.group_id)
     and not exists (
       select 1 from public.community_group_members m
       where m.group_id = new.group_id and m.user_id = new.organizer_id
     ) then
    raise exception 'Sólo puedes publicar en grupos a los que perteneces';
  end if;
  return new;
end;
$$;

create trigger activities_check_group
  before insert or update on public.activities
  for each row execute function public.check_activity_group();

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
  a.latitude, a.longitude,
  a.place_id, a.group_id
from public.activities a
left join (
  select activity_id, count(*) as active_count
  from public.participations
  where status = 'activa'
  group by activity_id
) p on p.activity_id = a.id;

create view public.community_groups_public
with (security_invoker = true)
as
select
  g.id, g.name, g.description, g.sport, g.zone, g.created_by, g.is_hidden, g.created_at,
  (select count(*) from public.community_group_members m where m.group_id = g.id) as member_count
from public.community_groups g;

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.places enable row level security;
alter table public.community_groups enable row level security;
alter table public.community_group_members enable row level security;

create policy "places_select_public" on public.places
  for select using (not is_hidden or public.is_admin());
create policy "places_write_admin" on public.places
  for all using (public.is_admin()) with check (public.is_admin());

create policy "groups_select_public" on public.community_groups
  for select using (not is_hidden or public.is_admin());
create policy "groups_insert_own" on public.community_groups
  for insert with check (auth.uid() = created_by);
create policy "groups_update_creator_or_admin" on public.community_groups
  for update using (auth.uid() = created_by or public.is_admin());

create policy "group_members_select_public" on public.community_group_members
  for select using (true);
create policy "group_members_insert_own" on public.community_group_members
  for insert with check (auth.uid() = user_id and role = 'miembro');
create policy "group_members_delete_own" on public.community_group_members
  for delete using (auth.uid() = user_id);
