-- Capa social: seguidores y perfil público (SCRUM-47, SCRUM-48), historias de
-- 24 horas (SCRUM-49) y notificaciones dentro de la app (SCRUM-50).

-- =========================================================================
-- follows (SCRUM-47)
-- =========================================================================
create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

create index follows_followee_idx on public.follows (followee_id);

alter table public.follows enable row level security;
create policy "follows_select_public" on public.follows for select using (true);
create policy "follows_insert_own" on public.follows
  for insert with check (auth.uid() = follower_id);
create policy "follows_delete_own" on public.follows
  for delete using (auth.uid() = follower_id);

-- Perfil público: datos + conteos + si yo lo sigo.
create view public.profile_stats
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
  ) as followed_by_me
from public.profiles p;

-- =========================================================================
-- stories / story_views (SCRUM-49)
-- Las fotos usan el mismo bucket post-images (carpeta propia del usuario).
-- =========================================================================
create table public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  image_path text not null,
  caption text check (caption is null or char_length(caption) <= 200),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);

create index stories_expires_idx on public.stories (expires_at);

create table public.story_views (
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

alter table public.stories enable row level security;
alter table public.story_views enable row level security;

-- Una historia deja de existir para todos a las 24 horas (el filtro vive en la RLS).
create policy "stories_select_active" on public.stories
  for select using (expires_at > now());
create policy "stories_insert_own" on public.stories
  for insert with check (auth.uid() = author_id and expires_at <= now() + interval '25 hours');
create policy "stories_delete_own_or_admin" on public.stories
  for delete using (auth.uid() = author_id or public.is_admin());

-- Cada quien ve sus vistas; el autor ve quién vio su historia.
create policy "story_views_select" on public.story_views
  for select using (
    auth.uid() = viewer_id
    or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
  );
create policy "story_views_insert_own" on public.story_views
  for insert with check (auth.uid() = viewer_id);

create view public.stories_public
with (security_invoker = true)
as
select
  s.id, s.author_id, s.image_path, s.caption, s.created_at, s.expires_at,
  pr.full_name as author_name,
  pr.avatar_url as author_avatar,
  exists (
    select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid()
  ) as viewed_by_me,
  (select count(*)::int from public.story_views v where v.story_id = s.id) as view_count
from public.stories s
join public.profiles pr on pr.id = s.author_id;

-- Limpieza opcional de filas vencidas (requiere activar la extensión pg_cron en
-- el dashboard). Los archivos en Storage no se borran solos.
-- select cron.schedule('limpiar-historias', '0 * * * *',
--   $$delete from public.stories where expires_at < now() - interval '1 day'$$);

-- =========================================================================
-- notifications (SCRUM-50): sólo las crean los triggers de abajo
-- =========================================================================
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('like', 'comment', 'follow', 'join')),
  post_id uuid references public.posts (id) on delete cascade,
  activity_id uuid references public.activities (id) on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
create policy "notifications_select_own" on public.notifications
  for select using (auth.uid() = user_id);
create policy "notifications_update_own" on public.notifications
  for update using (auth.uid() = user_id);
create policy "notifications_delete_own" on public.notifications
  for delete using (auth.uid() = user_id);
-- sin policy de insert: el cliente no puede fabricar notificaciones.

create view public.notifications_public
with (security_invoker = true)
as
select
  n.id, n.user_id, n.actor_id, n.kind, n.post_id, n.activity_id, n.read_at, n.created_at,
  pr.full_name as actor_name,
  pr.avatar_url as actor_avatar,
  a.title as activity_title
from public.notifications n
join public.profiles pr on pr.id = n.actor_id
left join public.activities a on a.id = n.activity_id;

create function public.notify_like()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  owner uuid;
begin
  select author_id into owner from public.posts where id = new.post_id;
  if owner is not null and owner <> new.user_id and not exists (
    select 1 from public.notifications
    where user_id = owner and actor_id = new.user_id and kind = 'like' and post_id = new.post_id
  ) then
    insert into public.notifications (user_id, actor_id, kind, post_id)
    values (owner, new.user_id, 'like', new.post_id);
  end if;
  return new;
end;
$$;

create trigger post_likes_notify
  after insert on public.post_likes
  for each row execute function public.notify_like();

create function public.notify_comment()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  owner uuid;
begin
  select author_id into owner from public.posts where id = new.post_id;
  if owner is not null and owner <> new.author_id then
    insert into public.notifications (user_id, actor_id, kind, post_id)
    values (owner, new.author_id, 'comment', new.post_id);
  end if;
  return new;
end;
$$;

create trigger post_comments_notify
  after insert on public.post_comments
  for each row execute function public.notify_comment();

create function public.notify_follow()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.notifications
    where user_id = new.followee_id and actor_id = new.follower_id and kind = 'follow'
  ) then
    insert into public.notifications (user_id, actor_id, kind)
    values (new.followee_id, new.follower_id, 'follow');
  end if;
  return new;
end;
$$;

create trigger follows_notify
  after insert on public.follows
  for each row execute function public.notify_follow();

-- Alguien se une a mi actividad (el organizador se auto-inscribe: no cuenta).
create function public.notify_join()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  organizer uuid;
begin
  select organizer_id into organizer from public.activities where id = new.activity_id;
  if organizer is not null and organizer <> new.user_id then
    insert into public.notifications (user_id, actor_id, kind, activity_id)
    values (organizer, new.user_id, 'join', new.activity_id);
  end if;
  return new;
end;
$$;

create trigger participations_notify
  after insert on public.participations
  for each row execute function public.notify_join();
