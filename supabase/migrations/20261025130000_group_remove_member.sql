-- Quitar integrantes exige ser el creador y nunca permite quitar al creador.
create function public.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  g public.community_groups;
begin
  select * into g from public.community_groups where id = p_group_id for update;
  if not found or auth.uid() is null or auth.uid() <> g.created_by then
    raise exception 'Sólo el creador puede eliminar integrantes';
  end if;
  if p_user_id = g.created_by then
    raise exception 'No se puede eliminar al creador del grupo';
  end if;
  delete from public.community_group_members where group_id = p_group_id and user_id = p_user_id;
  if not found then raise exception 'Esta persona ya no pertenece al grupo'; end if;
end;
$$;
revoke all on function public.remove_group_member(uuid, uuid) from public, anon;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
