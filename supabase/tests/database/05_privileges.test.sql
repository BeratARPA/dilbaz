-- Least privilege for the Data API roles (docs/13-data-model.md §4).
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

select table_privs_are('public', 'profiles', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'profiles: read, create and update own row');
select table_privs_are('public', 'courses', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'courses: read, create and update own rows');
select table_privs_are('public', 'teams', 'authenticated',
  array['SELECT', 'INSERT'], 'teams: read and create only');
select table_privs_are('public', 'team_members', 'authenticated',
  array['SELECT', 'INSERT'], 'team_members: no table-wide update');
select column_privs_are('public', 'team_members', 'share_levels', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'the sharing switch can be updated');
select column_privs_are('public', 'team_members', 'role', 'authenticated',
  array['SELECT', 'INSERT'], 'the role cannot be updated');

select table_privs_are('public', 'profiles', 'anon', '{}'::text[], 'anon: no profiles');
select table_privs_are('public', 'team_members', 'anon', '{}'::text[], 'anon: no members');

select ok(
  not has_sequence_privilege('anon', 'public.sync_seq', 'usage'),
  'anon cannot use the sync sequence'
);

-- New tables get nothing until a migration grants it explicitly.
create table public.privilege_probe (id int primary key);
select table_privs_are('public', 'privilege_probe', 'authenticated', '{}'::text[],
  'new tables are not exposed to signed-in users by default');
select table_privs_are('public', 'privilege_probe', 'anon', '{}'::text[],
  'new tables are not exposed to anon by default');
select ok(
  has_table_privilege('service_role', 'public.privilege_probe', 'select'),
  'the service role keeps access for server functions'
);

select * from finish();
rollback;
