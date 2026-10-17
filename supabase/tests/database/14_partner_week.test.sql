-- The partners' week (F2-09, I-18): counts only, the level only when
-- shared, nothing for outsiders; cheers between partners only.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test'),
  ('33333333-3333-4333-8333-333333333333', 'c@dilbaz.test');
insert into public.profiles (id, display_name, weekly_days_goal) values
  ('11111111-1111-4111-8111-111111111111', 'A', 5),
  ('22222222-2222-4222-8222-222222222222', 'B', 4),
  ('33333333-3333-4333-8333-333333333333', 'C', 3);
insert into public.courses (id, profile_id, l2, pair_pack, level_estimates) values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111',
   'en', 'tr-en', '{"speaking": "A2"}'),
  ('a2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222',
   'en', 'tr-en', '{"speaking": "A1"}');
insert into public.teams (id, name, invite_code, created_by) values
  ('70000000-0000-4000-8000-000000000001', 'Biz', 'KAHVE7',
   '11111111-1111-4111-8111-111111111111');
insert into public.team_members (team_id, profile_id, share_levels) values
  ('70000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', false),
  ('70000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', true);
-- A: two sessions on Monday, one on Tuesday (one together); one the week before.
insert into public.sessions (id, profile_id, course_id, device_id, started_at, strand_ms, planned) values
  ('51000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111',
   'a1111111-1111-4111-8111-111111111111', gen_random_uuid(),
   '2026-10-12 08:00+00', '{"language": 600000}', null),
  ('51000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111',
   'a1111111-1111-4111-8111-111111111111', gen_random_uuid(),
   '2026-10-12 20:00+00', '{"output": 300000}', '{"activity": "pair_chat"}'),
  ('51000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111',
   'a1111111-1111-4111-8111-111111111111', gen_random_uuid(),
   '2026-10-13 02:00+00', '{"language": 120000, "fluency": 180000}', null),
  ('51000000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111',
   'a1111111-1111-4111-8111-111111111111', gen_random_uuid(),
   '2026-10-05 08:00+00', '{"language": 900000}', null);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);

select is(
  public.partner_week_summary('70000000-0000-4000-8000-000000000001',
    '2026-10-12 00:00+00') -> 'goal_days',
  '9'::jsonb,
  'the shared goal is both weekly goals added up'
);
select is(
  (select m - 'id' - 'levels' from jsonb_array_elements(
     public.partner_week_summary('70000000-0000-4000-8000-000000000001',
       '2026-10-12 00:00+00') -> 'members') m
   where m ->> 'name' = 'A'),
  '{"name": "A", "days": 2, "minutes": 20, "together": 1,
    "strands": {"language": 12, "output": 5, "fluency": 3}}'::jsonb,
  'the partner''s week in counts; last week''s session is not in it'
);
select is(
  (select m -> 'levels' from jsonb_array_elements(
     public.partner_week_summary('70000000-0000-4000-8000-000000000001',
       '2026-10-12 00:00+00') -> 'members') m
   where m ->> 'name' = 'A'),
  'null'::jsonb,
  'a level not shared stays hidden'
);
select is(
  (select m -> 'levels' from jsonb_array_elements(
     public.partner_week_summary('70000000-0000-4000-8000-000000000001',
       '2026-10-12 00:00+00') -> 'members') m
   where m ->> 'name' = 'B'),
  '{"speaking": "A1"}'::jsonb,
  'a shared level is in the summary'
);
select is(
  (select (m ->> 'days')::int from jsonb_array_elements(
     public.partner_week_summary('70000000-0000-4000-8000-000000000001',
       '2026-10-12 00:00+00', -300) -> 'members') m
   where m ->> 'name' = 'A'),
  1,
  'days are counted where the learner is (UTC-5: all three on Monday)'
);
select is((select count(*)::int from public.sessions), 0,
  'the partner still cannot read the sessions themselves');

-- Cheers.
select lives_ok(
  $$insert into public.cheers (id, team_id, from_profile, to_profile, message_key)
    values ('c1000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000001',
      '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'speaking')$$,
  'a partner cheers the other'
);
select throws_ok(
  $$insert into public.cheers (id, team_id, from_profile, to_profile, message_key)
    values ('c1000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000001',
      '22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333', 'speaking')$$,
  '42501', null,
  'nobody outside the team'
);
select throws_ok(
  $$insert into public.cheers (id, team_id, from_profile, to_profile, message_key)
    values ('c1000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000001',
      '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'free text')$$,
  '23514', null,
  'only the fixed messages'
);
select table_privs_are('public', 'cheers', 'authenticated',
  array['SELECT', 'INSERT'], 'cheers: read and send only');

-- C is in no team with them.
select set_config('request.jwt.claims',
  '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
select throws_ok(
  $$select public.partner_week_summary('70000000-0000-4000-8000-000000000001',
      '2026-10-12 00:00+00')$$,
  'P0001', 'not_a_member',
  'outsiders get no summary'
);
select is((select count(*)::int from public.cheers), 0, 'outsiders see no cheers');

reset role;
select ok(
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and tablename = 'cheers'),
  'cheers reach the partner over Realtime'
);

select * from finish();
rollback;
