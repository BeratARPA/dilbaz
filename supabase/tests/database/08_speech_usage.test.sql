-- Speech usage: written by the service role, read by its owner only
-- (docs/13-data-model.md §4).
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B');

select table_privs_are('public', 'speech_usage', 'authenticated', array['SELECT'],
  'signed-in users only read');
select table_privs_are('public', 'speech_usage', 'anon', '{}'::text[], 'anon: nothing');
select policies_are('public', 'speech_usage', array['speech_usage_select_own']);

-- The speech function records a transcription of each.
set local role service_role;
insert into public.speech_usage (profile_id, provider, kind, seconds, cost_usd) values
  ('11111111-1111-4111-8111-111111111111', 'deepgram', 'stt', 4.2, 0.000301),
  ('22222222-2222-4222-8222-222222222222', 'deepgram', 'stt', 2.0, 0.000143);
select is((select count(*)::int from public.speech_usage), 2, 'the service role writes');
reset role;

select throws_ok(
  $$insert into public.speech_usage (provider, kind) values ('deepgram', 'nap')$$,
  '23514', null,
  'the kind is one of stt, pron and tts'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select results_eq(
  'select provider, seconds from public.speech_usage',
  $$values ('deepgram'::text, 4.2::numeric)$$,
  'a learner sees only their own use'
);
select throws_ok(
  $$insert into public.speech_usage (profile_id, provider, kind)
    values ('11111111-1111-4111-8111-111111111111', 'deepgram', 'stt')$$,
  '42501', null,
  'a learner cannot write usage'
);
select throws_ok(
  $$update public.speech_usage set seconds = 0$$,
  '42501', null,
  'nor change it'
);

select * from finish();
rollback;
