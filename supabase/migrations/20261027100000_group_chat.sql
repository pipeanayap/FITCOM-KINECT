-- Chat de grupo: sólo los miembros leen y escriben, y sólo en grupos visibles.
-- El autor borra sus mensajes; el creador del grupo puede borrar cualquiera.
create table public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index group_messages_group_created_idx on public.group_messages (group_id, created_at desc);

alter table public.group_messages enable row level security;

create policy "group_messages_select_members" on public.group_messages
  for select to authenticated using (
    exists (
      select 1 from public.community_group_members m
      where m.group_id = group_messages.group_id and m.user_id = auth.uid()
    )
  );

create policy "group_messages_insert_members" on public.group_messages
  for insert to authenticated with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.community_group_members m
      where m.group_id = group_messages.group_id and m.user_id = auth.uid()
    )
    and exists (
      select 1 from public.community_groups g
      where g.id = group_messages.group_id and not g.is_hidden
    )
  );

create policy "group_messages_delete_author_or_creator" on public.group_messages
  for delete to authenticated using (
    author_id = auth.uid()
    or exists (
      select 1 from public.community_groups g
      where g.id = group_messages.group_id and g.created_by = auth.uid()
    )
  );

-- Mensajes nuevos en vivo (Realtime respeta la política de lectura de arriba).
alter publication supabase_realtime add table public.group_messages;
