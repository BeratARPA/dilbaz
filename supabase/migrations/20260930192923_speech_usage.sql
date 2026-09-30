-- Use of the speech providers (docs/13-data-model.md §2, docs/08 §10): each
-- transcription records who asked, the provider and the seconds of audio,
-- so that the Deepgram credit and the free quotas can be watched
-- (ADR-0009). Rows are written by the speech function with the service
-- role; a learner reads only their own.

create table public.speech_usage (
  id bigserial primary key,
  profile_id uuid references public.profiles on delete set null,
  provider text not null,
  kind text not null check (kind in ('stt', 'pron', 'tts')),
  seconds numeric,
  characters int,
  -- What the call takes from a credit; 0 on a free tier.
  cost_usd numeric(10, 6),
  created_at timestamptz not null default now()
);

create index speech_usage_profile_created on public.speech_usage (profile_id, created_at);

alter table public.speech_usage enable row level security;

create policy speech_usage_select_own on public.speech_usage
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- Signed-in users read; only the service role writes (docs/13 §4).
grant select on public.speech_usage to authenticated;
grant select, insert, update, delete on public.speech_usage to service_role;
grant usage, select on sequence public.speech_usage_id_seq to service_role;
