-- Feed social (SCRUM-43 a SCRUM-46): publicaciones, likes, comentarios,
-- reportes y fotos en Supabase Storage.

-- =========================================================================
-- posts (SCRUM-43)
-- =========================================================================
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  -- 'post' lo escribe una persona; 'activity' lo crea solo el trigger al publicar una actividad.
  kind text not null default 'post' check (kind in ('post', 'activity')),
  body text check (body is null or char_length(body) <= 1000),
  image_paths text[] not null default '{}' check (cardinality(image_paths) <= 4),
  activity_id uuid references public.activities (id) on delete cascade,
  group_id uuid references public.community_groups (id) on delete set null,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  constraint posts_has_content check (
    (body is not null and char_length(btrim(body)) > 0)
    or cardinality(image_paths) > 0
    or activity_id is not null
  )
);

create index posts_created_at_idx on public.posts (created_at desc);
create index posts_activity_id_idx on public.posts (activity_id);

comment on table public.posts is 'Publicaciones del feed (SCRUM-43). Las de kind=activity las crea un trigger.';

-- Cada actividad nueva aparece sola en el feed, así el feed nunca nace vacío.
create function public.create_post_for_activity()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.posts (author_id, kind, activity_id, group_id, created_at)
  values (new.organizer_id, 'activity', new.id, new.group_id, new.created_at);
  return new;
end;
$$;

create trigger activities_create_post
  after insert on public.activities
  for each row execute function public.create_post_for_activity();

-- Las actividades que ya existían también entran al feed.
insert into public.posts (author_id, kind, activity_id, group_id, created_at)
select a.organizer_id, 'activity', a.id, a.group_id, a.created_at
from public.activities a;

-- =========================================================================
-- post_likes, post_comments (SCRUM-44)
-- =========================================================================
create table public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create index post_comments_post_id_idx on public.post_comments (post_id, created_at);

-- =========================================================================
-- post_reports (SCRUM-46) — mismo patrón que activity_reports
-- =========================================================================
create table public.post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null check (reason in ('contenido_inapropiado', 'spam', 'actividad_falsa', 'otro')),
  description text,
  status text not null default 'pendiente' check (status in ('pendiente', 'revisado')),
  created_at timestamptz not null default now(),
  unique (post_id, reporter_id)
);

-- =========================================================================
-- posts_public: post + autor + conteos + "me gusta" del usuario que mira
-- =========================================================================
create view public.posts_public
with (security_invoker = true)
as
select
  p.id, p.author_id, p.kind, p.body, p.image_paths, p.activity_id, p.group_id,
  p.is_hidden, p.created_at,
  pr.full_name as author_name,
  pr.avatar_url as author_avatar,
  (select count(*)::int from public.post_likes l where l.post_id = p.id) as like_count,
  (select count(*)::int from public.post_comments c where c.post_id = p.id and not c.is_hidden) as comment_count,
  exists (
    select 1 from public.post_likes l where l.post_id = p.id and l.user_id = auth.uid()
  ) as liked_by_me
from public.posts p
join public.profiles pr on pr.id = p.author_id;

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_reports enable row level security;

-- Un post de actividad desaparece solo si la actividad está oculta: la
-- subconsulta respeta el RLS de activities del usuario que mira.
create policy "posts_select_public" on public.posts
  for select using (
    (not is_hidden or public.is_admin())
    and (activity_id is null or exists (select 1 from public.activities a where a.id = activity_id))
  );
create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = author_id and kind = 'post');
create policy "posts_update_admin" on public.posts
  for update using (public.is_admin());
create policy "posts_delete_own_or_admin" on public.posts
  for delete using (auth.uid() = author_id or public.is_admin());

create policy "likes_select_public" on public.post_likes
  for select using (true);
create policy "likes_insert_own" on public.post_likes
  for insert with check (auth.uid() = user_id);
create policy "likes_delete_own" on public.post_likes
  for delete using (auth.uid() = user_id);

create policy "comments_select_public" on public.post_comments
  for select using (not is_hidden or public.is_admin());
create policy "comments_insert_own" on public.post_comments
  for insert with check (auth.uid() = author_id);
create policy "comments_delete_own_or_admin" on public.post_comments
  for delete using (auth.uid() = author_id or public.is_admin());

create policy "post_reports_insert_own" on public.post_reports
  for insert with check (auth.uid() = reporter_id);
create policy "post_reports_select_admin" on public.post_reports
  for select using (public.is_admin());
create policy "post_reports_update_admin" on public.post_reports
  for update using (public.is_admin());

-- Sólo en un grupo del que se es miembro (igual que las actividades).
create function public.check_post_group()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.group_id is not null and new.kind = 'post' and not exists (
    select 1 from public.community_group_members m
    where m.group_id = new.group_id and m.user_id = new.author_id
  ) then
    raise exception 'Sólo puedes publicar en grupos a los que perteneces';
  end if;
  return new;
end;
$$;

create trigger posts_check_group
  before insert on public.posts
  for each row execute function public.check_post_group();

-- =========================================================================
-- Storage: fotos de publicaciones (bucket público de lectura)
-- Escritura sólo dentro de la carpeta propia: <user_id>/<archivo>.jpg
-- =========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-images', 'post-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "post_images_select_public" on storage.objects
  for select using (bucket_id = 'post-images');
create policy "post_images_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "post_images_delete_own_folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);
