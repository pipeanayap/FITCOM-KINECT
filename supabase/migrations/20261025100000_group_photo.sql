-- Foto opcional de los grupos. Reutiliza el bucket post-images y sus políticas.
alter table public.community_groups add column photo_url text;

create or replace view public.community_groups_public
with (security_invoker = true)
as
select
  g.id, g.name, g.description, g.sport, g.zone, g.created_by, g.is_hidden, g.created_at,
  (select count(*) from public.community_group_members m where m.group_id = g.id) as member_count,
  g.photo_url
from public.community_groups g;
