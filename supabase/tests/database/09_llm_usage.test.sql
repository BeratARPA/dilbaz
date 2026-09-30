-- LLM usage: written by the service role, read by its owner only; the usage
-- counts behind the fair share are for the tutor function alone
-- (docs/13-data-model.md §4, docs/07 §3).
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B');

select table_privs_are('public', 'llm_usage', 'authenticated', array['SELECT'],
  'signed-in users only read');
select table_privs_are('public', 'llm_usage', 'anon', '{}'::text[], 'anon: nothing');
select policies_are('public', 'llm_usage', array['llm_usage_select_own']);

-- The tutor function records each provider call.
set local role service_role;
insert into public.llm_usage
  (profile_id, route, provider, model, input_tokens, output_tokens,
   cache_read_tokens, cost_usd, stop_reason, latency_ms, created_at)
values
  ('11111111-1111-4111-8111-111111111111', 'answer_check', 'gemini', 'lite',
   4000, 300, 3500, 0, 'stop', 900, '2026-09-30 08:00Z'),
  ('11111111-1111-4111-8111-111111111111', 'answer_check', 'gemini', 'lite',
   4000, 200, 0, 0, 'stop', 800, '2026-09-30 09:00Z'),
  -- Before the quota day began: not counted.
  ('11111111-1111-4111-8111-111111111111', 'answer_check', 'gemini', 'lite',
   4000, 200, 0, 0, 'stop', 800, '2026-09-29 06:00Z'),
  ('11111111-1111-4111-8111-111111111111', 'answer_check', 'groq', 'oss',
   null, null, null, 0, 'network', 30, '2026-09-30 09:00Z'),
  ('22222222-2222-4222-8222-222222222222', 'answer_check', 'gemini', 'lite',
   4000, 250, 0, 0, 'stop', 700, '2026-09-30 09:30Z');
select is((select count(*)::int from public.llm_usage), 5, 'the service role writes');

select results_eq(
  $$select model, requests, tokens from public.llm_usage_counts(
      '11111111-1111-4111-8111-111111111111',
      array['lite', 'oss', 'other'],
      array['2026-09-30 07:00Z', '2026-09-30 00:00Z', '2026-09-30 00:00Z']::timestamptz[])
    order by model$$,
  $$values ('lite'::text, 2::bigint, 5000::bigint),
           ('oss', 1, 0),
           ('other', 0, 0)$$,
  'calls and uncached tokens per model since each quota day began, for one learner'
);
reset role;

select ok(
  not has_function_privilege('authenticated',
    'public.llm_usage_counts(uuid, text[], timestamptz[])', 'execute'),
  'signed-in users cannot read the usage counts of anyone'
);
select ok(
  not has_function_privilege('anon',
    'public.llm_usage_counts(uuid, text[], timestamptz[])', 'execute'),
  'nor can anon'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);

select results_eq(
  'select model, output_tokens from public.llm_usage',
  $$values ('lite'::text, 250)$$,
  'a learner sees only their own use'
);
select throws_ok(
  $$insert into public.llm_usage (profile_id, route, provider, model)
    values ('22222222-2222-4222-8222-222222222222', 'answer_check', 'gemini', 'lite')$$,
  '42501', null,
  'a learner cannot write usage'
);
select throws_ok(
  $$update public.llm_usage set output_tokens = 0$$,
  '42501', null,
  'nor change it'
);
select throws_ok(
  $$delete from public.llm_usage$$,
  '42501', null,
  'nor delete it'
);

select * from finish();
rollback;
