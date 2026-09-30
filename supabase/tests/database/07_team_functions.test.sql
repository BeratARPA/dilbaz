-- Teams by invite code: a partner joins with the code and in no other way
-- (docs/13-data-model.md §4).
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test'),
  ('33333333-3333-4333-8333-333333333333', 'c@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B');

select ok(
  not has_function_privilege('anon', 'public.create_team(text)', 'execute'),
  'anon cannot create a team'
);
select ok(
  not has_function_privilege('anon', 'public.join_team(text)', 'execute'),
  'anon cannot join a team'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.create_team(text)'::regprocedure),
  false,
  'creating runs with the caller''s own rights'
);

-- A creates a team.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

create temp table made on commit drop as
  select public.create_team('  Biz  ') as team;
grant select on made to authenticated;

select is((select team ->> 'name' from made), 'Biz', 'the name is trimmed');
select matches(
  (select team ->> 'invite_code' from made), '^[0-9A-F]{10}$',
  'the invite code is ten characters, made on the server'
);
select results_eq(
  'select profile_id, role from public.team_members',
  $$values ('11111111-1111-4111-8111-111111111111'::uuid, 'owner'::text)$$,
  'the creator is the owner of the new team'
);
select throws_ok(
  $$select public.create_team('   ')$$,
  'P0001', 'team_name_required',
  'a team needs a name'
);

-- B cannot see the team before joining, and a wrong code opens nothing.
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);

select is((select count(*)::int from public.teams), 0, 'a stranger does not see the team');
select throws_ok(
  $$select public.join_team('0000000000')$$,
  'P0001', 'invite_not_found',
  'a wrong code joins nothing'
);
select throws_ok(
  $$select public.join_team(null)$$,
  'P0001', 'invite_not_found',
  'no code joins nothing'
);

-- With the code, in any case and with spaces around it, B is in.
select is(
  (select public.join_team('  ' || lower(team ->> 'invite_code') || ' ') ->> 'name' from made),
  'Biz',
  'the invite code joins the team'
);
select is(
  (select count(*)::int from public.team_members),
  2,
  'the new member sees both members'
);
select lives_ok(
  $$select public.join_team((select team ->> 'invite_code' from made))$$,
  'joining twice is harmless'
);
select is(
  (select count(*)::int from public.team_members),
  2,
  'and adds no second row'
);

-- C has no profile yet: the membership cannot be written.
select set_config('request.jwt.claims',
  '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
select throws_ok(
  $$select public.join_team((select team ->> 'invite_code' from made))$$,
  '23503', null,
  'joining needs a profile'
);

-- Without a session the function refuses.
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok(
  $$select public.join_team('0000000000')$$,
  'P0001', 'not_signed_in',
  'joining needs a signed-in user'
);

select * from finish();
rollback;
