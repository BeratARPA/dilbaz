-- Teams: partners see membership, never each other's raw data (I-18).
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test'),
  ('33333333-3333-4333-8333-333333333333', 'c@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B'),
  ('33333333-3333-4333-8333-333333333333', 'C');
insert into public.courses (id, profile_id, l2, pair_pack) values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'en', 'tr-en');

-- A creates a team and joins it.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select lives_ok(
  $$insert into public.teams (id, name, invite_code, created_by)
    values ('70000000-0000-4000-8000-000000000001', 'Biz', 'KAHVE7',
            '11111111-1111-4111-8111-111111111111')$$,
  'a user creates a team'
);
select lives_ok(
  $$insert into public.team_members (team_id, profile_id, role)
    values ('70000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'owner')$$,
  'the creator joins their own team'
);
select throws_ok(
  $$insert into public.teams (id, name, invite_code, created_by)
    values ('70000000-0000-4000-8000-000000000002', 'X', 'X1', '22222222-2222-4222-8222-222222222222')$$,
  '42501', null,
  'a team cannot be created in someone else''s name'
);

-- B cannot add themselves; joining goes through the invite-code function.
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);
select throws_ok(
  $$insert into public.team_members (team_id, profile_id)
    values ('70000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222')$$,
  '42501', null,
  'a user cannot join a team by inserting a member row'
);

-- The invite-code flow (F1-12) is simulated with full privileges.
reset role;
insert into public.team_members (team_id, profile_id)
values ('70000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);

select results_eq(
  'select name from public.teams',
  $$values ('Biz')$$,
  'a member sees their team'
);
select is(
  (select count(*)::int from public.team_members),
  2,
  'a member sees both member rows of their team'
);
select results_eq(
  'select display_name from public.profiles',
  $$values ('B')$$,
  'a partner cannot read the other partner''s profile'
);
select is(
  (select count(*)::int from public.courses),
  0,
  'a partner cannot read the other partner''s courses'
);

update public.team_members set share_levels = true
where profile_id = '22222222-2222-4222-8222-222222222222';
update public.team_members set share_monthly = true
where profile_id = '11111111-1111-4111-8111-111111111111';
select throws_ok(
  $$update public.team_members set role = 'owner'
    where profile_id = '22222222-2222-4222-8222-222222222222'$$,
  '42501', null,
  'a member cannot change their role'
);

-- C is not in the team.
select set_config('request.jwt.claims',
  '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
select is((select count(*)::int from public.teams), 0, 'outsiders do not see the team');
select is((select count(*)::int from public.team_members), 0, 'outsiders do not see members');

reset role;
select results_eq(
  $$select profile_id::text, share_levels, share_monthly from public.team_members
    order by profile_id$$,
  $$values ('11111111-1111-4111-8111-111111111111', false, false),
           ('22222222-2222-4222-8222-222222222222', true, false)$$,
  'members change only their own sharing switches'
);

select * from finish();
rollback;
