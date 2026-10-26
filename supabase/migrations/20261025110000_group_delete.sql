-- Sólo el creador puede eliminar su grupo. Las claves foráneas existentes
-- borran membresías y dejan group_id = NULL en actividades y publicaciones.
create policy "groups_delete_creator" on public.community_groups
  for delete to authenticated
  using (auth.uid() = created_by);
