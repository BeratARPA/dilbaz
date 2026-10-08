-- Phase 1 user tables, the sync RPCs and the private audio bucket
-- (docs/13-data-model.md §2–§6, docs/12 §6, ADR-0003).
--
-- Every table mirrors its local drift twin; the client writes locally and
-- queues the row in its outbox, then sync_push sends batches and sync_pull
-- brings back what changed since the client's cursor.
--
-- - Events (attempts, attempt_amendments, sessions, assessments,
--   content_reports) are inserted once and never changed by the learner:
--   no UPDATE or DELETE privilege.
-- - State rows (profiles, courses, cards, personal_items, gap_entries,
--   recordings) are last-writer-wins: cards by last_review, the others by
--   updated_at.
-- - Rows belong to the caller: profile_id is always auth.uid(), and a row
--   of a course the caller does not own is refused.
-- - Times come from the client (created_at, updated_at): a row written
--   offline keeps the moment it was made.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.devices (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  platform text not null,
  app_version text,
  last_sync_at timestamptz,
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.personal_items (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  kind text not null check (kind in ('sentence', 'chunk', 'word_sense')),
  text_l2 text not null,
  lemmas text[] not null default '{}',
  cefr text,
  source text not null check (
    source in ('gap', 'subtitle', 'task_correction', 'reading_lookup', 'openenglish', 'manual')
  ),
  gloss_l1 text,
  notes text,
  variants text[] not null default '{}',
  audio_path text,
  deprecated boolean not null default false,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.cards (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  item_ref text not null,
  mode text not null check (
    mode in ('speak', 'type', 'cloze', 'contrast', 'recognize_audio', 'dictation')
  ),
  fsrs_card_id bigint not null,
  state smallint not null,
  step int,
  stability double precision,
  difficulty double precision,
  due timestamptz not null,
  last_review timestamptz,
  reps int not null default 0,
  lapses int not null default 0,
  suspended boolean not null default false,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now(),
  unique (profile_id, item_ref, mode)
);

create table public.attempts (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  device_id uuid not null,
  activity text not null,
  item_ref text,
  card_id uuid,
  task_ref text,
  text_ref text,
  parent_attempt_id uuid,
  prompt jsonb not null,
  response jsonb not null,
  verdict text,
  target_ok boolean,
  error_tags text[] not null default '{}',
  hints_used smallint not null default 0,
  hint_max_level smallint not null default 0,
  rating smallint check (rating between 1 and 4),
  latency_ms int,
  duration_ms int,
  card_state_after jsonb,
  llm jsonb,
  experiment jsonb,
  created_at_client timestamptz not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.attempt_amendments (
  id uuid primary key,
  attempt_id uuid not null references public.attempts on delete cascade,
  profile_id uuid not null references public.profiles on delete cascade,
  kind text not null check (kind in ('llm_resolved', 'asr_override', 'user_dispute')),
  payload jsonb not null,
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.gap_entries (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  l1_text text not null,
  audio_path text,
  context text not null check (
    context in ('live_class', 'daily', 'pair', 'speaking_task', 'media')
  ),
  note text,
  suggestion jsonb,
  status text not null default 'new' check (status in ('new', 'carded', 'dismissed')),
  personal_item_ids uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.recordings (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  task_ref text,
  attempt_id uuid,
  audio_path text,
  duration_ms int not null,
  asr jsonb,
  annotation jsonb,
  metrics jsonb,
  outcome text check (outcome in ('done', 'partial', 'not_done')),
  is_assessment boolean not null default false,
  assessment_id uuid,
  keep boolean not null default false,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.assessments (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  kind text not null check (
    kind in ('placement', 'monthly_speaking', 'vocab_retest', 'writing_sample', 'listening_mini', 'external')
  ),
  results jsonb not null,
  level_estimates jsonb,
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.sessions (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  course_id uuid not null references public.courses on delete cascade,
  device_id uuid not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  planned jsonb,
  done jsonb,
  active_ms int not null default 0,
  strand_ms jsonb not null default '{}',
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

-- "Bu içerikte hata var" (docs/10 §8): the learner reports; the status is
-- the maintainers' to change, with the service role.
create table public.content_reports (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  item_ref text not null,
  reason text not null check (reason in ('meaning', 'sentence', 'audio', 'answer', 'other')),
  note text,
  context jsonb not null default '{}',
  status text not null default 'open' check (status in ('open', 'fixed', 'rejected')),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

-- State rows take a new sequence number on every change, so that a pull
-- sees them again.
create trigger personal_items_touch before update on public.personal_items
  for each row execute function private.touch_server_seq();
create trigger cards_touch before update on public.cards
  for each row execute function private.touch_server_seq();
create trigger gap_entries_touch before update on public.gap_entries
  for each row execute function private.touch_server_seq();
create trigger recordings_touch before update on public.recordings
  for each row execute function private.touch_server_seq();
create trigger devices_touch before update on public.devices
  for each row execute function private.touch_server_seq();
create trigger content_reports_touch before update on public.content_reports
  for each row execute function private.touch_server_seq();

-- What a pull reads (docs/13 §3).
create index personal_items_profile_seq on public.personal_items (profile_id, server_seq);
create index cards_profile_seq on public.cards (profile_id, server_seq);
create index cards_profile_due on public.cards (profile_id, due);
create index attempts_profile_seq on public.attempts (profile_id, server_seq);
create index attempts_card on public.attempts (card_id);
create index attempt_amendments_profile_seq on public.attempt_amendments (profile_id, server_seq);
create index attempt_amendments_attempt on public.attempt_amendments (attempt_id);
create index gap_entries_profile_seq on public.gap_entries (profile_id, server_seq);
create index recordings_profile_seq on public.recordings (profile_id, server_seq);
create index recordings_assessment on public.recordings (profile_id, is_assessment, created_at desc);
create index assessments_profile_seq on public.assessments (profile_id, server_seq);
create index sessions_profile_seq on public.sessions (profile_id, server_seq);
create index sessions_profile_started on public.sessions (profile_id, started_at desc);
create index content_reports_profile_seq on public.content_reports (profile_id, server_seq);
create index content_reports_open on public.content_reports (status, created_at);
create index devices_profile on public.devices (profile_id);

-- ---------------------------------------------------------------------------
-- Row level security: the owner only (docs/13 §4)
-- ---------------------------------------------------------------------------
alter table public.devices enable row level security;
alter table public.personal_items enable row level security;
alter table public.cards enable row level security;
alter table public.attempts enable row level security;
alter table public.attempt_amendments enable row level security;
alter table public.gap_entries enable row level security;
alter table public.recordings enable row level security;
alter table public.assessments enable row level security;
alter table public.sessions enable row level security;
alter table public.content_reports enable row level security;

create policy devices_select_own on public.devices
  for select to authenticated using (profile_id = (select auth.uid()));
create policy devices_insert_own on public.devices
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy devices_update_own on public.devices
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy personal_items_select_own on public.personal_items
  for select to authenticated using (profile_id = (select auth.uid()));
create policy personal_items_insert_own on public.personal_items
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy personal_items_update_own on public.personal_items
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy cards_select_own on public.cards
  for select to authenticated using (profile_id = (select auth.uid()));
create policy cards_insert_own on public.cards
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy cards_update_own on public.cards
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy gap_entries_select_own on public.gap_entries
  for select to authenticated using (profile_id = (select auth.uid()));
create policy gap_entries_insert_own on public.gap_entries
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy gap_entries_update_own on public.gap_entries
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy recordings_select_own on public.recordings
  for select to authenticated using (profile_id = (select auth.uid()));
create policy recordings_insert_own on public.recordings
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy recordings_update_own on public.recordings
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- Events: read and add, nothing else.
create policy attempts_select_own on public.attempts
  for select to authenticated using (profile_id = (select auth.uid()));
create policy attempts_insert_own on public.attempts
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy attempt_amendments_select_own on public.attempt_amendments
  for select to authenticated using (profile_id = (select auth.uid()));
create policy attempt_amendments_insert_own on public.attempt_amendments
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy assessments_select_own on public.assessments
  for select to authenticated using (profile_id = (select auth.uid()));
create policy assessments_insert_own on public.assessments
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy sessions_select_own on public.sessions
  for select to authenticated using (profile_id = (select auth.uid()));
create policy sessions_insert_own on public.sessions
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy content_reports_select_own on public.content_reports
  for select to authenticated using (profile_id = (select auth.uid()));
create policy content_reports_insert_own on public.content_reports
  for insert to authenticated
  with check (profile_id = (select auth.uid()) and status = 'open');

-- Data API privileges, explicitly (docs/13 §4).
grant select, insert, update
  on public.devices, public.personal_items, public.cards, public.gap_entries, public.recordings
  to authenticated;
grant select, insert
  on public.attempts, public.attempt_amendments, public.assessments, public.sessions,
     public.content_reports
  to authenticated;

-- ---------------------------------------------------------------------------
-- sync_push: a batch of rows from one device, in one transaction
-- ---------------------------------------------------------------------------
create function public.sync_push(p_device_id uuid, p_batch jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_size int;
  v_accepted int := 0;
  v_n int;
  v_conflicts jsonb := '[]'::jsonb;
  v_own uuid[];
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  select coalesce(sum(jsonb_array_length(value)), 0)::int into v_size
  from jsonb_each(p_batch)
  where jsonb_typeof(value) = 'array';
  if v_size > 500 then
    raise exception 'batch_too_large' using errcode = '54000';
  end if;
  -- One push of a learner at a time, and no pull while it runs (sync_pull).
  perform pg_advisory_xact_lock(hashtextextended('sync:' || v_uid::text, 0));

  -- The profile and its courses first: every other row refers to them.
  insert into public.profiles (
    id, display_name, l1, ui_locale, time_budget_min, weekly_days_goal,
    anchors, quiet_hours, goal_text, interests, scaffold_overrides, settings,
    updated_at, created_at)
  select id, display_name, coalesce(l1, 'tr'), coalesce(ui_locale, 'tr'),
    coalesce(time_budget_min, 30), coalesce(weekly_days_goal, 5),
    coalesce(anchors, '[]'), quiet_hours, goal_text, coalesce(interests, '{}'),
    coalesce(scaffold_overrides, '{}'), coalesce(settings, '{}'),
    coalesce(updated_at, now()), coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.profiles, coalesce(p_batch -> 'profiles', '[]'))
  where id = v_uid
  on conflict (id) do update
    set display_name = excluded.display_name, l1 = excluded.l1,
        ui_locale = excluded.ui_locale, time_budget_min = excluded.time_budget_min,
        weekly_days_goal = excluded.weekly_days_goal, anchors = excluded.anchors,
        quiet_hours = excluded.quiet_hours, goal_text = excluded.goal_text,
        interests = excluded.interests,
        scaffold_overrides = excluded.scaffold_overrides,
        settings = excluded.settings, updated_at = excluded.updated_at
    where excluded.updated_at >= public.profiles.updated_at;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  -- Every other row refers to the profile: without one nothing can go in,
  -- and the client tries again later.
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  insert into public.devices (id, profile_id, platform, app_version, last_sync_at)
  values (
    p_device_id,
    v_uid,
    coalesce(p_batch -> 'device' ->> 'platform', 'unknown'),
    p_batch -> 'device' ->> 'app_version',
    now()
  )
  on conflict (id) do update
    set last_sync_at = now(), app_version = excluded.app_version
    where public.devices.profile_id = v_uid;

  -- One course per language (unique (profile_id, l2)): another course of
  -- the same language is refused.
  select v_conflicts || coalesce(jsonb_agg(jsonb_build_object(
      'table', 'courses', 'id', i.id, 'reason', 'duplicate')), '[]')
  into v_conflicts
  from jsonb_populate_recordset(null::public.courses, coalesce(p_batch -> 'courses', '[]')) i
  where exists (
    select 1 from public.courses c
    where c.profile_id = v_uid and c.l2 = i.l2 and c.id <> i.id);
  insert into public.courses (
    id, profile_id, l2, pair_pack, level_estimates, vocab_estimate, fsrs_params,
    desired_retention, active, updated_at, created_at)
  select i.id, v_uid, i.l2, i.pair_pack, coalesce(i.level_estimates, '{}'),
    i.vocab_estimate, i.fsrs_params, coalesce(i.desired_retention, 0.90),
    coalesce(i.active, true), coalesce(i.updated_at, now()),
    coalesce(i.created_at, now())
  from jsonb_populate_recordset(null::public.courses, coalesce(p_batch -> 'courses', '[]')) i
  where not exists (
    select 1 from public.courses c
    where c.profile_id = v_uid and c.l2 = i.l2 and c.id <> i.id)
  on conflict (id) do update
    set pair_pack = excluded.pair_pack, level_estimates = excluded.level_estimates,
        vocab_estimate = excluded.vocab_estimate, fsrs_params = excluded.fsrs_params,
        desired_retention = excluded.desired_retention, active = excluded.active,
        updated_at = excluded.updated_at
    where public.courses.profile_id = v_uid
      and excluded.updated_at >= public.courses.updated_at;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  select coalesce(array_agg(id), '{}') into v_own
  from public.courses where profile_id = v_uid;

  -- Rows of a course the caller does not own are refused, by table.
  select v_conflicts || coalesce(jsonb_agg(jsonb_build_object(
      'table', t.name, 'id', r ->> 'id', 'reason', 'unknown_course')), '[]')
  into v_conflicts
  from (values ('attempts'), ('sessions'), ('assessments'), ('cards'),
               ('personal_items'), ('gap_entries'), ('recordings')) as t(name),
       jsonb_array_elements(coalesce(p_batch -> t.name, '[]')) as r
  where (r ->> 'course_id') is null
     or not ((r ->> 'course_id')::uuid = any (v_own));

  -- Events: inserted once.
  insert into public.attempts (
    id, profile_id, course_id, device_id, activity, item_ref, card_id, task_ref,
    text_ref, parent_attempt_id, prompt, response, verdict, target_ok,
    error_tags, hints_used, hint_max_level, rating, latency_ms, duration_ms,
    card_state_after, llm, experiment, created_at_client, created_at)
  select id, v_uid, course_id, device_id, activity, item_ref, card_id, task_ref,
    text_ref, parent_attempt_id, prompt, response, verdict, target_ok,
    coalesce(error_tags, '{}'), coalesce(hints_used, 0),
    coalesce(hint_max_level, 0), rating, latency_ms, duration_ms,
    card_state_after, llm, experiment, created_at_client,
    coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.attempts, coalesce(p_batch -> 'attempts', '[]'))
  where course_id = any (v_own)
  on conflict (id) do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  -- An amendment waits for its attempt.
  select v_conflicts || coalesce(jsonb_agg(jsonb_build_object(
      'table', 'attempt_amendments', 'id', a.id, 'reason', 'unknown_attempt')), '[]')
  into v_conflicts
  from jsonb_populate_recordset(null::public.attempt_amendments,
         coalesce(p_batch -> 'attempt_amendments', '[]')) a
  where not exists (
    select 1 from public.attempts x where x.id = a.attempt_id and x.profile_id = v_uid);
  insert into public.attempt_amendments (id, attempt_id, profile_id, kind, payload, created_at)
  select a.id, a.attempt_id, v_uid, a.kind, a.payload, coalesce(a.created_at, now())
  from jsonb_populate_recordset(null::public.attempt_amendments,
         coalesce(p_batch -> 'attempt_amendments', '[]')) a
  where exists (
    select 1 from public.attempts x where x.id = a.attempt_id and x.profile_id = v_uid)
  on conflict (id) do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  insert into public.sessions (
    id, profile_id, course_id, device_id, started_at, ended_at, planned, done,
    active_ms, strand_ms, created_at)
  select id, v_uid, course_id, device_id, started_at, ended_at, planned, done,
    coalesce(active_ms, 0), coalesce(strand_ms, '{}'), coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.sessions, coalesce(p_batch -> 'sessions', '[]'))
  where course_id = any (v_own)
  on conflict (id) do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  insert into public.assessments (
    id, profile_id, course_id, kind, results, level_estimates, created_at)
  select id, v_uid, course_id, kind, results, level_estimates, coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.assessments, coalesce(p_batch -> 'assessments', '[]'))
  where course_id = any (v_own)
  on conflict (id) do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  insert into public.content_reports (
    id, profile_id, item_ref, reason, note, context, status, created_at)
  select id, v_uid, item_ref, reason, note, coalesce(context, '{}'), 'open',
    coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.content_reports,
         coalesce(p_batch -> 'content_reports', '[]'))
  on conflict (id) do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  -- Cards: the later review wins (docs/12 §6).
  with incoming as (
    select * from jsonb_populate_recordset(null::public.cards, coalesce(p_batch -> 'cards', '[]'))
    where course_id = any (v_own)
  ), changed as (
    update public.cards c
    set fsrs_card_id = i.fsrs_card_id, state = i.state, step = i.step,
        stability = i.stability, difficulty = i.difficulty, due = i.due,
        last_review = i.last_review, reps = coalesce(i.reps, 0),
        lapses = coalesce(i.lapses, 0), suspended = coalesce(i.suspended, false),
        updated_at = coalesce(i.updated_at, now())
    from incoming i
    where c.id = i.id and c.profile_id = v_uid
      and (c.last_review is null
           or (i.last_review is not null and i.last_review >= c.last_review))
    returning c.id
  )
  select v_accepted + (select count(*) from changed) into v_accepted;
  select v_conflicts || coalesce(jsonb_agg(jsonb_build_object(
      'table', 'cards', 'id', c.id, 'reason', 'stale')), '[]')
  into v_conflicts
  from jsonb_populate_recordset(null::public.cards, coalesce(p_batch -> 'cards', '[]')) i
  join public.cards c on c.id = i.id
  where c.last_review is not null
    and (i.last_review is null or i.last_review < c.last_review);
  -- A card of the same item and mode made on another device: the first one
  -- pushed stays, and the client merges the two when it pulls.
  select v_conflicts || coalesce(jsonb_agg(jsonb_build_object(
      'table', 'cards', 'id', i.id, 'reason', 'duplicate')), '[]')
  into v_conflicts
  from jsonb_populate_recordset(null::public.cards, coalesce(p_batch -> 'cards', '[]')) i
  where i.course_id = any (v_own)
    and not exists (select 1 from public.cards c where c.id = i.id)
    and exists (
      select 1 from public.cards c
      where c.profile_id = v_uid and c.item_ref = i.item_ref and c.mode = i.mode);
  insert into public.cards (
    id, profile_id, course_id, item_ref, mode, fsrs_card_id, state, step,
    stability, difficulty, due, last_review, reps, lapses, suspended, updated_at,
    created_at)
  select id, v_uid, course_id, item_ref, mode, fsrs_card_id, state, step,
    stability, difficulty, due, last_review, coalesce(reps, 0),
    coalesce(lapses, 0), coalesce(suspended, false), coalesce(updated_at, now()),
    coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.cards, coalesce(p_batch -> 'cards', '[]')) i
  where course_id = any (v_own)
    and not exists (select 1 from public.cards c where c.id = i.id)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  -- Personal items, captures and recordings: the later change wins.
  insert into public.personal_items (
    id, profile_id, course_id, kind, text_l2, lemmas, cefr, source, gloss_l1,
    notes, variants, audio_path, deprecated, updated_at, created_at)
  select id, v_uid, course_id, kind, text_l2, coalesce(lemmas, '{}'), cefr,
    source, gloss_l1, notes, coalesce(variants, '{}'), audio_path,
    coalesce(deprecated, false), coalesce(updated_at, now()),
    coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.personal_items,
         coalesce(p_batch -> 'personal_items', '[]'))
  where course_id = any (v_own)
  on conflict (id) do update
    set kind = excluded.kind, text_l2 = excluded.text_l2, lemmas = excluded.lemmas,
        cefr = excluded.cefr, source = excluded.source, gloss_l1 = excluded.gloss_l1,
        notes = excluded.notes, variants = excluded.variants,
        audio_path = excluded.audio_path, deprecated = excluded.deprecated,
        updated_at = excluded.updated_at
    where public.personal_items.profile_id = v_uid
      and excluded.updated_at >= public.personal_items.updated_at;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  insert into public.gap_entries (
    id, profile_id, course_id, l1_text, audio_path, context, note, suggestion,
    status, personal_item_ids, updated_at, created_at)
  select id, v_uid, course_id, l1_text, audio_path, context, note, suggestion,
    coalesce(status, 'new'), coalesce(personal_item_ids, '{}'),
    coalesce(updated_at, now()), coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.gap_entries,
         coalesce(p_batch -> 'gap_entries', '[]'))
  where course_id = any (v_own)
  on conflict (id) do update
    set l1_text = excluded.l1_text, audio_path = excluded.audio_path,
        context = excluded.context, note = excluded.note,
        suggestion = excluded.suggestion, status = excluded.status,
        personal_item_ids = excluded.personal_item_ids,
        updated_at = excluded.updated_at
    where public.gap_entries.profile_id = v_uid
      and excluded.updated_at >= public.gap_entries.updated_at;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  insert into public.recordings (
    id, profile_id, course_id, task_ref, attempt_id, audio_path, duration_ms,
    asr, annotation, metrics, outcome, is_assessment, assessment_id, keep,
    updated_at, created_at)
  select id, v_uid, course_id, task_ref, attempt_id, audio_path, duration_ms,
    asr, annotation, metrics, outcome, coalesce(is_assessment, false),
    assessment_id, coalesce(keep, false), coalesce(updated_at, now()),
    coalesce(created_at, now())
  from jsonb_populate_recordset(null::public.recordings,
         coalesce(p_batch -> 'recordings', '[]'))
  where course_id = any (v_own)
  on conflict (id) do update
    set task_ref = excluded.task_ref, attempt_id = excluded.attempt_id,
        audio_path = excluded.audio_path, duration_ms = excluded.duration_ms,
        asr = excluded.asr, annotation = excluded.annotation,
        metrics = excluded.metrics, outcome = excluded.outcome,
        is_assessment = excluded.is_assessment,
        assessment_id = excluded.assessment_id, keep = excluded.keep,
        updated_at = excluded.updated_at
    where public.recordings.profile_id = v_uid
      and excluded.updated_at >= public.recordings.updated_at;
  get diagnostics v_n = row_count;
  v_accepted := v_accepted + v_n;

  return jsonb_build_object('accepted', v_accepted, 'conflicts', v_conflicts);
end;
$$;

-- ---------------------------------------------------------------------------
-- sync_pull: what changed since the client's cursor, a page at a time
-- ---------------------------------------------------------------------------
create function public.sync_pull(p_since bigint, p_limit int default 500)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_limit int := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  -- Rows are numbered as they are written. A pull in the middle of a push
  -- could see a later row before an earlier one commits and move its
  -- cursor past it, so it waits for the learner's push to finish.
  perform pg_advisory_xact_lock_shared(hashtextextended('sync:' || v_uid::text, 0));
  with changed as (
    select 'profiles' as name, x.server_seq as seq, to_jsonb(x) as row
      from public.profiles x where x.server_seq > p_since
    union all select 'courses', x.server_seq, to_jsonb(x)
      from public.courses x where x.server_seq > p_since
    union all select 'personal_items', x.server_seq, to_jsonb(x)
      from public.personal_items x where x.server_seq > p_since
    union all select 'cards', x.server_seq, to_jsonb(x)
      from public.cards x where x.server_seq > p_since
    union all select 'attempts', x.server_seq, to_jsonb(x)
      from public.attempts x where x.server_seq > p_since
    union all select 'attempt_amendments', x.server_seq, to_jsonb(x)
      from public.attempt_amendments x where x.server_seq > p_since
    union all select 'gap_entries', x.server_seq, to_jsonb(x)
      from public.gap_entries x where x.server_seq > p_since
    union all select 'recordings', x.server_seq, to_jsonb(x)
      from public.recordings x where x.server_seq > p_since
    union all select 'assessments', x.server_seq, to_jsonb(x)
      from public.assessments x where x.server_seq > p_since
    union all select 'sessions', x.server_seq, to_jsonb(x)
      from public.sessions x where x.server_seq > p_since
    union all select 'content_reports', x.server_seq, to_jsonb(x)
      from public.content_reports x where x.server_seq > p_since
  ),
  page as (
    select * from changed order by seq limit v_limit + 1
  ),
  kept as (
    select * from page order by seq limit v_limit
  )
  select jsonb_build_object(
    'rows', coalesce(
      (select jsonb_object_agg(name, rows)
       from (select name, jsonb_agg(row order by seq) as rows
             from kept group by name) grouped),
      '{}'::jsonb),
    'next', coalesce((select max(seq) from kept), p_since),
    'more', (select count(*) from page) > v_limit
  ) into v_result;
  return v_result;
end;
$$;

revoke execute on function public.sync_push(uuid, jsonb) from public, anon;
revoke execute on function public.sync_pull(bigint, int) from public, anon;
grant execute on function public.sync_push(uuid, jsonb) to authenticated;
grant execute on function public.sync_pull(bigint, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Task and test audio (docs/13 §6): the owner only (I-18); the first folder
-- of the path is the owner's id: {uid}/{yyyy}/{mm}/{uuid}.{ext}
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio-private', 'audio-private', false, 10485760,
        array['audio/mp4', 'audio/aac', 'audio/wav', 'audio/webm', 'audio/ogg'])
on conflict (id) do nothing;

create policy "owners read their audio"
  on storage.objects for select to authenticated
  using (bucket_id = 'audio-private'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "owners add their audio"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'audio-private'
              and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "owners replace their audio"
  on storage.objects for update to authenticated
  using (bucket_id = 'audio-private'
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'audio-private'
              and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "owners delete their audio"
  on storage.objects for delete to authenticated
  using (bucket_id = 'audio-private'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
