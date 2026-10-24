-- Perfil completo: @usuario único y bio (SCRUM-51), y conteo de planes en el
-- perfil público (SCRUM-53).

alter table public.profiles
  add column username text,
  add column bio text check (bio is null or char_length(bio) <= 160);

-- Convierte un nombre en un usuario base: sin acentos, minúsculas, sólo a-z 0-9.
create function public.username_base(p_name text)
returns text
language sql
immutable
as $$
  select left(
    case when length(b) < 3 then b || 'usr' else b end,
    16
  )
  from (
    select regexp_replace(
      lower(translate(coalesce(p_name, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')),
      '[^a-z0-9]', '', 'g'
    ) as b
  ) t;
$$;

-- Usuarios para las cuentas que ya existen: el primero se queda con el nombre
-- base y los repetidos reciben un número (luisfelipe, luisfelipe2, ...).
with base as (
  select id, public.username_base(full_name) as b, created_at from public.profiles
),
ranked as (
  select id, b, row_number() over (partition by b order by created_at, id) as rn from base
)
update public.profiles p
set username = r.b || case when r.rn > 1 then r.rn::text else '' end
from ranked r
where p.id = r.id;

alter table public.profiles
  alter column username set not null,
  add constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$');

create unique index profiles_username_key on public.profiles (lower(username));

-- Cuentas nuevas: el usuario se genera solo (handle_new_user no lo manda).
create function public.generate_username()
returns trigger
language plpgsql
as $$
declare
  base text := public.username_base(new.full_name);
  candidate text := base;
  n int := 1;
begin
  if new.username is not null then
    return new;
  end if;
  while exists (select 1 from public.profiles where lower(username) = candidate) loop
    n := n + 1;
    candidate := left(base, 18 - length(n::text)) || n::text;
  end loop;
  new.username := candidate;
  return new;
end;
$$;

create trigger profiles_generate_username
  before insert on public.profiles
  for each row execute function public.generate_username();

-- profile_stats: + usuario, bio y planes (inscripciones activas). Las columnas
-- nuevas van al final para que create or replace view las acepte.
create or replace view public.profile_stats
with (security_invoker = true)
as
select
  p.id, p.full_name, p.zone, p.sports_interests, p.avatar_url,
  (select count(*)::int from public.follows f where f.followee_id = p.id) as followers_count,
  (select count(*)::int from public.follows f where f.follower_id = p.id) as following_count,
  (select count(*)::int from public.posts x
     where x.author_id = p.id and x.kind = 'post' and not x.is_hidden) as posts_count,
  exists (
    select 1 from public.follows f where f.followee_id = p.id and f.follower_id = auth.uid()
  ) as followed_by_me,
  p.username,
  p.bio,
  (select count(*)::int from public.participations pa
     where pa.user_id = p.id and pa.status = 'activa') as plans_count
from public.profiles p;
