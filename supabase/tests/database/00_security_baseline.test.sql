-- Default-deny baseline (docs/13-data-model.md §4, docs/14 §1).
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select is(
  (
    select coalesce(
      array_agg(format('%I.%I', n.nspname, c.relname) order by n.nspname, c.relname),
      '{}'
    )
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private')
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  ),
  '{}'::text[],
  'every table in public and private has row level security enabled'
);

select is(
  (
    select count(*)::int
    from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
  ),
  0,
  'anon has no table privileges in public'
);

select ok(
  not has_schema_privilege('anon', 'private', 'usage'),
  'anon cannot use the private schema'
);

select ok(
  not has_table_privilege('authenticated', 'private.signup_allowlist', 'select'),
  'signed-in users cannot read the sign-up allowlist'
);

select ok(
  not has_function_privilege('authenticated', 'private.hook_before_user_created(jsonb)', 'execute'),
  'signed-in users cannot call the sign-up hook'
);

select * from finish();
rollback;
