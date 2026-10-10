-- "Tüm verimi sil" (docs/14-security-privacy.md §4): the learner's rows
-- go, all of them; a partner's stay.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select ok(
  not has_function_privilege('anon', 'public.delete_my_data()', 'execute'),
  'anon cannot delete data'
);
select ok(
  has_function_privilege('authenticated', 'public.delete_my_data()', 'execute'),
  'a signed-in learner can delete their own data'
);

-- A and B, a couple: A made the team.
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B');
insert into public.courses (id, profile_id, l2, pair_pack) values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'en', 'tr-en'),
  ('b2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'en', 'tr-en');
insert into public.teams (id, name, invite_code, created_by) values
  ('7eae7eae-0000-4000-8000-000000000001', 'Biz', 'ABCDEFGHJK',
   '11111111-1111-4111-8111-111111111111');
insert into public.team_members (team_id, profile_id, role) values
  ('7eae7eae-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'owner'),
  ('7eae7eae-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'member');

-- Rows of every kind for A; one card for B.
insert into public.devices (id, profile_id, platform)
values ('d1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'android');
insert into public.cards (id, profile_id, course_id, item_ref, mode, fsrs_card_id, state, due) values
  ('0192f5a0-0000-7000-8000-000000000c01', '11111111-1111-4111-8111-111111111111',
   'a1111111-1111-4111-8111-111111111111', 'zz.word.bada', 'speak', 1, 1, now()),
  ('0192f5a0-0000-7000-8000-000000000c02', '22222222-2222-4222-8222-222222222222',
   'b2222222-2222-4222-8222-222222222222', 'zz.word.bada', 'speak', 1, 1, now());
insert into public.attempts (id, profile_id, course_id, device_id, activity, prompt, response,
  created_at_client)
values ('0192f5a0-0000-7000-8000-000000000a01', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 'd1111111-1111-4111-8111-111111111111',
  'card.produce_type', '{}', '{}', now());
insert into public.attempt_amendments (id, attempt_id, profile_id, kind, payload)
values ('0192f5a0-0000-7000-8000-000000000e01', '0192f5a0-0000-7000-8000-000000000a01',
  '11111111-1111-4111-8111-111111111111', 'user_dispute', '{}');
insert into public.personal_items (id, profile_id, course_id, kind, text_l2, source)
values ('0192f5a0-0000-7000-8000-000000000101', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 'sentence', 'Bada kolu.', 'gap');
insert into public.gap_entries (id, profile_id, course_id, l1_text, context)
values ('0192f5a0-0000-7000-8000-000000000201', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 'Sıkıldım', 'daily');
insert into public.recordings (id, profile_id, course_id, duration_ms)
values ('0192f5a0-0000-7000-8000-000000000301', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 60000);
insert into public.assessments (id, profile_id, course_id, kind, results)
values ('0192f5a0-0000-7000-8000-000000000b01', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 'placement', '{}');
insert into public.sessions (id, profile_id, course_id, device_id, started_at)
values ('0192f5a0-0000-7000-8000-000000000501', '11111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111', 'd1111111-1111-4111-8111-111111111111', now());
insert into public.content_reports (id, profile_id, item_ref, reason)
values ('0192f5a0-0000-7000-8000-000000000f01', '11111111-1111-4111-8111-111111111111',
  'zz.word.bada', 'meaning');
insert into public.llm_usage (profile_id, route, provider, model)
values ('11111111-1111-4111-8111-111111111111', 'answer_check', 'gemini', 'flash');

-- Signed in without a user.
set local role authenticated;
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok(
  'select public.delete_my_data()',
  '42501', 'not signed in',
  'it needs a signed-in learner'
);

-- Signed in as A.
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select lives_ok('select public.delete_my_data()', 'A deletes their data');

reset role;
select is(
  (
    select count(*)::int from (
      select profile_id from public.devices
      union all select profile_id from public.courses
      union all select profile_id from public.cards
      union all select profile_id from public.attempts
      union all select profile_id from public.attempt_amendments
      union all select profile_id from public.personal_items
      union all select profile_id from public.gap_entries
      union all select profile_id from public.recordings
      union all select profile_id from public.assessments
      union all select profile_id from public.sessions
      union all select profile_id from public.content_reports
      union all select profile_id from public.team_members
      union all select id from public.profiles
    ) rows
    where profile_id = '11111111-1111-4111-8111-111111111111'
  ),
  0,
  'none of A''s rows is left'
);
select is(
  (select count(*)::int from public.teams),
  0,
  'the team A made is gone, with its members'
);
select results_eq(
  $$select (select count(*) from public.profiles)::int,
           (select count(*) from public.cards
            where profile_id = '22222222-2222-4222-8222-222222222222')::int$$,
  $$values (1, 1)$$,
  'B keeps their own profile and data'
);
select results_eq(
  'select profile_id, route from public.llm_usage',
  $$values (null::uuid, 'answer_check'::text)$$,
  'usage counts stay, without a name'
);

select * from finish();
rollback;
