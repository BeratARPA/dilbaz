-- Information gap sessions (F2-08): only the two partners read a session,
-- nobody writes it directly, each answers only for themself (I-18).
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test'),
  ('33333333-3333-4333-8333-333333333333', 'c@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B'),
  ('33333333-3333-4333-8333-333333333333', 'C');
insert into public.teams (id, name, invite_code, created_by) values
  ('70000000-0000-4000-8000-000000000001', 'Biz', 'KAHVE7',
   '11111111-1111-4111-8111-111111111111');
insert into public.team_members (team_id, profile_id) values
  ('70000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111'),
  ('70000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222');

select table_privs_are('public', 'pair_sessions', 'authenticated',
  array['SELECT'], 'pair_sessions: read only; the functions write');
select table_privs_are('public', 'pair_sessions', 'anon', '{}'::text[], 'anon: nothing');
select ok(
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and tablename = 'pair_sessions'),
  'sessions reach the partners over Realtime'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select is(
  public.pair_start('90000000-0000-4000-8000-000000000001', 'en.gap.gap_friend',
    '22222222-2222-4222-8222-222222222222', 'a') -> 'roles',
  '{"11111111-1111-4111-8111-111111111111": "a", "22222222-2222-4222-8222-222222222222": "b"}'::jsonb,
  'A starts with B: A has role a, B role b'
);
select is(
  public.pair_start('90000000-0000-4000-8000-000000000001', 'en.gap.gap_friend',
    '22222222-2222-4222-8222-222222222222', 'a') ->> 'state',
  'invited',
  'asking again answers with the same session'
);
select throws_ok(
  $$select public.pair_start('90000000-0000-4000-8000-000000000002', 'en.gap.gap_friend',
      '33333333-3333-4333-8333-333333333333', 'a')$$,
  'P0001', 'not_partners',
  'nobody outside the team'
);
select throws_ok(
  $$insert into public.pair_sessions (id, team_id, task_ref, created_by, participants, roles)
    values ('90000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000001',
      'x', '11111111-1111-4111-8111-111111111111',
      array['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222']::uuid[],
      '{}')$$,
  '42501', null,
  'the table is not written directly'
);
select throws_ok(
  $$select public.pair_answer('90000000-0000-4000-8000-000000000001', '"c"')$$,
  'P0001', 'session_not_active',
  'no answer before the partner joined'
);
select is(
  public.pair_join('90000000-0000-4000-8000-000000000001') ->> 'state',
  'invited',
  'the one who started cannot join for the partner'
);

-- B joins and answers.
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);
select is((select count(*)::int from public.pair_sessions), 1, 'the partner sees the session');
select is(
  public.pair_join('90000000-0000-4000-8000-000000000001') ->> 'state',
  'active',
  'the invited partner joins'
);
select is(
  public.pair_answer('90000000-0000-4000-8000-000000000001', '"c"') -> 'answers',
  '{"22222222-2222-4222-8222-222222222222": "c"}'::jsonb,
  'an answer is the caller''s own'
);

select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select is(
  public.pair_answer('90000000-0000-4000-8000-000000000001', '"done"') ->> 'state',
  'done',
  'both answered: the session is done'
);
select is(
  (select ended_at is not null from public.pair_sessions),
  true,
  'and it has ended'
);
select throws_ok(
  $$select public.pair_answer('90000000-0000-4000-8000-000000000001', '"x"')$$,
  'P0001', 'session_not_active',
  'a done session takes no answer'
);
select is(
  public.pair_cancel('90000000-0000-4000-8000-000000000001') ->> 'state',
  'done',
  'a done session stays done'
);

-- C sees nothing and cannot touch it.
select set_config('request.jwt.claims',
  '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
select is((select count(*)::int from public.pair_sessions), 0, 'outsiders do not see sessions');
select throws_ok(
  $$select public.pair_cancel('90000000-0000-4000-8000-000000000001')$$,
  'P0001', 'session_not_found',
  'nor cancel them'
);

select * from finish();
rollback;
