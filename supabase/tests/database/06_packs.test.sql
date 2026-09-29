-- Pack registry and pack files: signed-in users read published packs only;
-- writing is the service role's (docs/13-data-model.md §4 and §6).
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select table_privs_are('public', 'packs', 'authenticated', array['SELECT'],
  'packs: signed-in users only read');
select table_privs_are('public', 'packs', 'anon', '{}'::text[], 'packs: nothing for anon');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.packs'::regclass),
  'packs has row level security'
);

insert into public.packs (id, kind, l2, l1, version, status, manifest, storage_path, checksum)
values
  ('en@1', 'target', 'en', null, 1, 'published', '{}', 'packs/en@1.sqlite', 'sha256:a'),
  ('tr-en@1', 'pair', 'en', 'tr', 1, 'draft', '{}', 'packs/tr-en@1.sqlite', 'sha256:b');
insert into storage.objects (bucket_id, name) values
  ('packs', 'en@1.sqlite'),
  ('pack-audio', 'en/1/v1/0123456789abcdef.mp3');

select results_eq(
  'select id, public from storage.buckets where id in (''packs'', ''pack-audio'') order by id',
  $$values ('pack-audio'::text, false), ('packs'::text, false)$$,
  'both pack buckets exist and are private'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select results_eq(
  'select id from public.packs',
  $$values ('en@1'::text)$$,
  'a signed-in user sees published packs only'
);
select throws_ok(
  $$insert into public.packs (id, kind, l2, version, status, manifest, storage_path, checksum)
    values ('xx@1', 'target', 'xx', 1, 'published', '{}', 'packs/xx@1.sqlite', 'sha256:c')$$,
  '42501', null,
  'a signed-in user cannot register a pack'
);
select is(
  (select count(*)::int from storage.objects where bucket_id in ('packs', 'pack-audio')),
  2,
  'a signed-in user can read the pack files'
);

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

select throws_ok(
  'select id from public.packs',
  '42501', null,
  'anon cannot read the registry'
);
select is(
  (select count(*)::int from storage.objects where bucket_id in ('packs', 'pack-audio')),
  0,
  'anon cannot see the pack files'
);

reset role;
select ok(
  has_table_privilege('service_role', 'public.packs', 'insert'),
  'the service role registers packs'
);

select * from finish();
rollback;
