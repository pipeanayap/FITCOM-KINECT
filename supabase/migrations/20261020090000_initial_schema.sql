-- FITCOM — esquema inicial (TECH-02)
-- Entidades: profiles, activities, participations, activity_reports,
-- moderation_actions, activity_feedback. Incluye los estados de actividad,
-- las restricciones contra duplicados/sobrecupo y las políticas de permisos
-- (RLS) que exige TECH-03 para que la lógica crítica no dependa del cliente.

-- =========================================================================
-- profiles — perfil básico (US-02), extiende auth.users
-- =========================================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  zone text,
  sports_interests text[] not null default '{}',
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil público de cada usuario (US-02).';

-- Crea el perfil automáticamente cuando alguien se registra (US-01).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- =========================================================================
-- activities — publicar actividad (US-03)
-- =========================================================================
create table public.activities (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.profiles (id) on delete cascade,
  sport text not null,
  title text not null,
  description text,
  scheduled_at timestamptz not null,
  zone text not null,
  level text not null check (level in ('principiante', 'intermedio', 'avanzado', 'cualquier_nivel')),
  capacity int not null check (capacity >= 1),
  estimated_cost numeric(10, 2) check (estimated_cost is null or estimated_cost >= 0),
  coordination_link text,
  status text not null default 'abierta' check (status in ('abierta', 'cancelada')),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_in_future_on_create check (scheduled_at > created_at - interval '1 minute')
);

comment on table public.activities is 'Actividades publicadas por organizadores (US-03, US-11, US-12).';
comment on column public.activities.status is
  'abierta/cancelada son explícitos; completa y finalizada se calculan en la vista activities_public.';

create trigger activities_set_updated_at
  before update on public.activities
  for each row execute function public.set_updated_at();

-- No se puede mover la fecha al pasado ni bajar el cupo por debajo de los
-- participantes activos (US-11), y no se edita una actividad cancelada/pasada.
create function public.check_activity_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  active_count int;
begin
  if old.status = 'cancelada' and new.status = 'cancelada' then
    -- sólo se permite tocar campos administrativos (is_hidden) en una cancelada
    if new.sport is distinct from old.sport
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.scheduled_at is distinct from old.scheduled_at
      or new.zone is distinct from old.zone
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

create trigger activities_before_update
  before update on public.activities
  for each row execute function public.check_activity_update();

-- =========================================================================
-- participations — unirse / salir de una actividad (US-07, US-10)
-- =========================================================================
create table public.participations (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'activa' check (status in ('activa', 'cancelada')),
  joined_at timestamptz not null default now(),
  left_at timestamptz
);

comment on table public.participations is
  'Inscripciones a actividades. Se conservan las canceladas para el historial y las métricas (US-17).';

-- Un usuario sólo puede tener una inscripción activa por actividad a la vez,
-- pero puede volver a unirse después de haber salido (US-07, US-10).
create unique index participations_one_active_per_user
  on public.participations (activity_id, user_id)
  where (status = 'activa');

-- Cupo y reglas de negocio al unirse/salir (US-07, US-08, US-10).
-- El bloqueo de la fila de la actividad serializa a los participantes que
-- compiten por el último lugar, para que nunca se exceda el cupo.
create function public.check_participation_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  act record;
  active_count int;
begin
  if tg_op = 'INSERT' then
    select * into act from public.activities where id = new.activity_id for update;

    if act is null then
      raise exception 'La actividad no existe';
    end if;
    if act.status = 'cancelada' then
      raise exception 'No puedes unirte a una actividad cancelada';
    end if;
    if act.scheduled_at <= now() then
      raise exception 'No puedes unirte a una actividad que ya ocurrió';
    end if;

    select count(*) into active_count
      from public.participations
      where activity_id = new.activity_id and status = 'activa';
    if active_count >= act.capacity then
      raise exception 'La actividad ya alcanzó su cupo máximo';
    end if;

    new.joined_at = now();
    new.left_at = null;
  elsif tg_op = 'UPDATE' and new.status = 'cancelada' and old.status = 'activa' then
    select * into act from public.activities where id = new.activity_id for update;
    if act.organizer_id = new.user_id then
      raise exception 'El organizador no puede abandonar su propia actividad; debe editarla o cancelarla';
    end if;
    if act.status = 'cancelada' or act.scheduled_at <= now() then
      raise exception 'No puedes salir de una actividad ya cancelada o finalizada';
    end if;
    new.left_at = now();
  end if;

  return new;
end;
$$;

create trigger participations_before_change
  before insert or update on public.participations
  for each row execute function public.check_participation_change();

-- El organizador queda inscrito automáticamente al crear la actividad (US-03).
create function public.add_organizer_as_participant()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.participations (activity_id, user_id, status)
  values (new.id, new.organizer_id, 'activa');
  return new;
end;
$$;

create trigger activities_after_insert_add_organizer
  after insert on public.activities
  for each row execute function public.add_organizer_as_participant();

-- =========================================================================
-- activities_public — vista con contadores y estado calculado (US-04 a US-09)
-- =========================================================================
-- Nota: deliberadamente NO incluye coordination_link. Ese campo sólo se
-- expone a través de la función get_coordination_link() (US-13: "el enlace
-- sólo se muestra a los participantes registrados"); así la restricción vive
-- en la base de datos y no sólo en lo que decida mostrar el cliente.
create view public.activities_public
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
  end as computed_status
from public.activities a
left join (
  select activity_id, count(*) as active_count
  from public.participations
  where status = 'activa'
  group by activity_id
) p on p.activity_id = a.id;

comment on view public.activities_public is
  'Lectura pública de actividades con disponibilidad y estado ya calculados. No incluye coordination_link.';

-- (US-13) Sólo el organizador, un participante activo o un admin recibe el
-- enlace; cualquier otra persona recibe null, sin importar qué pida el cliente.
create function public.get_coordination_link(p_activity_id uuid)
returns text
language plpgsql
stable
security definer set search_path = public
as $$
declare
  link text;
  allowed boolean;
begin
  select
    (a.organizer_id = auth.uid() or public.is_admin()
      or exists (
        select 1 from public.participations pt
        where pt.activity_id = a.id and pt.user_id = auth.uid() and pt.status = 'activa'
      )),
    a.coordination_link
  into allowed, link
  from public.activities a
  where a.id = p_activity_id;

  return case when allowed then link else null end;
end;
$$;

-- =========================================================================
-- activity_reports — reportar una actividad (US-14)
-- =========================================================================
create table public.activity_reports (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null check (reason in ('contenido_inapropiado', 'spam', 'actividad_falsa', 'otro')),
  description text,
  status text not null default 'pendiente' check (status in ('pendiente', 'revisado')),
  created_at timestamptz not null default now(),
  unique (activity_id, reporter_id)
);

comment on table public.activity_reports is
  'Un reporte por usuario y actividad (US-14); evita reportes repetidos sin control.';

-- =========================================================================
-- moderation_actions — bitácora de moderación (US-15)
-- =========================================================================
create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  admin_id uuid not null references public.profiles (id),
  action text not null check (action in ('ocultar', 'restablecer')),
  created_at timestamptz not null default now()
);

comment on table public.moderation_actions is 'Historial de acciones de moderación (US-15).';

-- =========================================================================
-- activity_feedback — encuesta posterior a la actividad (US-16)
-- =========================================================================
create table public.activity_feedback (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  activity_happened boolean not null,
  met_people boolean,
  ease_rating int check (ease_rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (activity_id, user_id)
);

comment on table public.activity_feedback is 'Encuesta opcional después de la actividad (US-16).';

-- =========================================================================
-- Row Level Security
-- =========================================================================
alter table public.profiles enable row level security;
alter table public.activities enable row level security;
alter table public.participations enable row level security;
alter table public.activity_reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.activity_feedback enable row level security;

-- Atajo: ¿el usuario autenticado es administrador?
create function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- profiles: nombres e intereses son públicos (US-08); cada quien edita lo suyo.
create policy "profiles_select_public" on public.profiles
  for select using (true);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- activities: exploración pública sin sesión (US-04), ocultas sólo para admins.
create policy "activities_select_public" on public.activities
  for select using (not is_hidden or public.is_admin());
create policy "activities_insert_own" on public.activities
  for insert with check (auth.uid() = organizer_id);
create policy "activities_update_organizer_or_admin" on public.activities
  for update using (auth.uid() = organizer_id or public.is_admin());
-- sin policy de delete: se cancela, no se borra (conserva el historial, US-12).

-- participations: lista de participantes es pública (US-08); cada quien
-- se inscribe o se da de baja a sí mismo.
create policy "participations_select_public" on public.participations
  for select using (true);
create policy "participations_insert_own" on public.participations
  for insert with check (auth.uid() = user_id);
create policy "participations_update_own" on public.participations
  for update using (auth.uid() = user_id);

-- activity_reports: cualquier autenticado reporta lo suyo; sólo admins revisan.
create policy "reports_insert_own" on public.activity_reports
  for insert with check (auth.uid() = reporter_id);
create policy "reports_select_admin" on public.activity_reports
  for select using (public.is_admin());
create policy "reports_update_admin" on public.activity_reports
  for update using (public.is_admin());

-- moderation_actions: sólo administradores.
create policy "moderation_all_admin" on public.moderation_actions
  for all using (public.is_admin()) with check (public.is_admin());

-- activity_feedback: cada quien registra y consulta la suya; admins ven todo.
create policy "feedback_insert_own" on public.activity_feedback
  for insert with check (auth.uid() = user_id);
create policy "feedback_select_own_or_admin" on public.activity_feedback
  for select using (auth.uid() = user_id or public.is_admin());
