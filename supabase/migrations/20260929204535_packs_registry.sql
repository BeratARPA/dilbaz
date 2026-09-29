-- Content pack registry and pack storage (docs/13-data-model.md §2.2 and §6,
-- docs/11-language-packs.md §5).
--
-- `dilbaz-content upload` writes a built pack with the service role: the
-- SQLite file to the `packs` bucket, its clips to `pack-audio` and its row
-- here. Signed-in users read published rows and download the files; nobody
-- else reads or writes.

create table public.packs (
  id text primary key,                    -- 'en@1', 'tr-en@1'
  kind text not null check (kind in ('target', 'pair')),
  l2 text not null,
  l1 text,
  version numeric not null,
  status text not null check (status in ('draft', 'published', 'deprecated')),
  manifest jsonb not null,
  storage_path text not null,
  checksum text not null,
  created_at timestamptz default now()
);

alter table public.packs enable row level security;

create policy "signed-in users read published packs"
  on public.packs for select to authenticated
  using (status = 'published');

revoke all on public.packs from anon, authenticated;
grant select on public.packs to authenticated;
grant select, insert, update, delete on public.packs to service_role;

-- Private buckets: the files are read through signed-in requests only.
insert into storage.buckets (id, name, public)
values ('packs', 'packs', false), ('pack-audio', 'pack-audio', false)
on conflict (id) do nothing;

create policy "signed-in users read pack files"
  on storage.objects for select to authenticated
  using (bucket_id in ('packs', 'pack-audio'));
