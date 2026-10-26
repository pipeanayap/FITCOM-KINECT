-- image_path se conserva como ruta del archivo para no romper historias existentes.
alter table public.stories
  add column media_type text not null default 'image',
  add column video_duration double precision,
  add constraint stories_media_type_check check (media_type in ('image', 'video')),
  add constraint stories_video_duration_check check (
    (media_type = 'image' and video_duration is null)
    or (media_type = 'video' and video_duration is not null and video_duration > 0 and video_duration < 50)
  );

create or replace view public.stories_public
with (security_invoker = true)
as
select
  s.id, s.author_id, s.image_path, s.caption, s.created_at, s.expires_at,
  pr.full_name as author_name, pr.avatar_url as author_avatar,
  exists (
    select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid()
  ) as viewed_by_me,
  (select count(*)::int from public.story_views v where v.story_id = s.id) as view_count,
  s.media_type, s.video_duration
from public.stories s
join public.profiles pr on pr.id = s.author_id;

-- Bucket independiente: las reglas y límites de fotos y publicaciones no cambian.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('story-videos', 'story-videos', true, 52428800, array['video/mp4']);
create policy "story_videos_select_public" on storage.objects
  for select using (bucket_id = 'story-videos');
create policy "story_videos_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'story-videos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "story_videos_delete_own_folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'story-videos' and (storage.foldername(name))[1] = auth.uid()::text);
