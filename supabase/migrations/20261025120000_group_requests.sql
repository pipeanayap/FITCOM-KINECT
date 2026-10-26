-- El ingreso ahora exige aprobación o aceptar una invitación.
-- Los miembros existentes se conservan.
drop policy "group_members_insert_own" on public.community_group_members;

create table public.community_group_requests (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('request', 'invitation')),
  created_at timestamptz not null default now(),
  unique (group_id, user_id)
);
alter table public.community_group_requests enable row level security;
create policy "group_requests_select_participants" on public.community_group_requests
  for select to authenticated using (
    user_id = auth.uid() or exists (
      select 1 from public.community_groups g where g.id = group_id and g.created_by = auth.uid()
    )
  );
-- No hay escritura directa desde el cliente: las RPC validan cada transición.

alter table public.notifications
  add column group_id uuid references public.community_groups(id) on delete cascade;
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('like', 'comment', 'follow', 'join', 'group_request', 'group_invitation', 'group_accepted', 'group_rejected'));
create or replace view public.notifications_public
with (security_invoker = true)
as
select
  n.id, n.user_id, n.actor_id, n.kind, n.post_id, n.activity_id, n.read_at, n.created_at,
  pr.full_name as actor_name, pr.avatar_url as actor_avatar, a.title as activity_title,
  n.group_id, g.name as group_name
from public.notifications n
join public.profiles pr on pr.id = n.actor_id
left join public.activities a on a.id = n.activity_id
left join public.community_groups g on g.id = n.group_id;

create function public.send_group_request(p_group_id uuid, p_user_id uuid, p_kind text)
returns void language plpgsql security definer set search_path = public
as $$
declare
  g public.community_groups;
  target uuid;
begin
  -- Serializa altas, invitaciones y respuestas dentro de cada grupo.
  select * into g from public.community_groups where id = p_group_id for update;
  if not found or g.is_hidden or auth.uid() is null then
    raise exception 'Grupo no disponible';
  end if;
  if p_kind = 'request' then
    if p_user_id <> auth.uid() then raise exception 'Sólo puedes solicitar tu propio ingreso'; end if;
    target := g.created_by;
  elsif p_kind = 'invitation' then
    if g.created_by <> auth.uid() then raise exception 'Sólo el creador puede invitar'; end if;
    target := p_user_id;
  else
    raise exception 'Tipo de solicitud inválido';
  end if;
  if exists (select 1 from public.community_group_members where group_id = p_group_id and user_id = p_user_id) then
    raise exception 'Esta persona ya es miembro';
  end if;
  if exists (select 1 from public.community_group_requests where group_id = p_group_id and user_id = p_user_id) then
    raise exception 'Ya existe una solicitud o invitación pendiente';
  end if;
  insert into public.community_group_requests (group_id, user_id, kind) values (p_group_id, p_user_id, p_kind);
  insert into public.notifications(user_id, actor_id, kind, group_id)
    values (target, auth.uid(), case p_kind when 'request' then 'group_request' else 'group_invitation' end, p_group_id);
end;
$$;

create function public.respond_group_request(p_group_id uuid, p_user_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare
  g public.community_groups;
  r public.community_group_requests;
  target uuid;
begin
  select * into g from public.community_groups where id = p_group_id for update;
  if not found or g.is_hidden or auth.uid() is null then raise exception 'Grupo no disponible'; end if;
  select * into r from public.community_group_requests where group_id = p_group_id and user_id = p_user_id for update;
  if not found then raise exception 'Esta solicitud ya fue atendida'; end if;
  if r.kind = 'request' then
    if auth.uid() <> g.created_by then raise exception 'Sólo el creador puede responder'; end if;
    target := r.user_id;
  else
    if auth.uid() <> r.user_id then raise exception 'Sólo la persona invitada puede responder'; end if;
    target := g.created_by;
  end if;
  if p_accept is null then raise exception 'Respuesta inválida'; end if;
  if p_accept then
    insert into public.community_group_members(group_id, user_id, role)
      values (r.group_id, r.user_id, 'miembro');
  end if;
  delete from public.community_group_requests where id = r.id;
  insert into public.notifications(user_id, actor_id, kind, group_id)
    values (target, auth.uid(), case when p_accept then 'group_accepted' else 'group_rejected' end, g.id);
end;
$$;
revoke all on function public.send_group_request(uuid, uuid, text) from public, anon;
revoke all on function public.respond_group_request(uuid, uuid, boolean) from public, anon;
grant execute on function public.send_group_request(uuid, uuid, text) to authenticated;
grant execute on function public.respond_group_request(uuid, uuid, boolean) to authenticated;
