-- Use of the LLM providers (docs/13-data-model.md §2.6, docs/07 §3): every
-- provider call of the tutor function records the route, provider, model,
-- tokens and latency. On the free tiers the cost is 0; the table tracks
-- quota use and the fair share of the two learners (ADR-0009). Rows are
-- written by the tutor function with the service role; a learner reads only
-- their own.

create table public.llm_usage (
  id bigserial primary key,
  profile_id uuid references public.profiles on delete set null,
  route text not null,
  provider text not null,
  model text not null,
  input_tokens int,
  output_tokens int,
  cache_read_tokens int,
  cache_write_tokens int,
  -- 0 on a free tier (ADR-0009).
  cost_usd numeric(10, 6),
  -- The provider's finish reason, or the failure code of the call.
  stop_reason text,
  latency_ms int,
  created_at timestamptz not null default now()
);

create index llm_usage_profile_created on public.llm_usage (profile_id, created_at);

alter table public.llm_usage enable row level security;

create policy llm_usage_select_own on public.llm_usage
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- Signed-in users read; only the service role writes (docs/13 §4).
grant select on public.llm_usage to authenticated;
grant select, insert, update, delete on public.llm_usage to service_role;
grant usage, select on sequence public.llm_usage_id_seq to service_role;

-- A learner's calls and tokens per model since each model's quota day began
-- (docs/07 §3, fair share). Tokens read from a provider cache do not count
-- against its limits, so they are left out.
create function public.llm_usage_counts(
  p_profile_id uuid,
  p_models text[],
  p_since timestamptz[]
)
returns table (model text, requests bigint, tokens bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    m.model,
    count(u.id),
    coalesce(sum(
      coalesce(u.input_tokens, 0) - coalesce(u.cache_read_tokens, 0)
        + coalesce(u.output_tokens, 0)
    ), 0)::bigint
  from unnest(p_models, p_since) as m (model, since)
  left join public.llm_usage u
    on u.model = m.model
    and u.profile_id = p_profile_id
    and u.created_at >= m.since
  group by m.model
$$;

revoke execute on function public.llm_usage_counts(uuid, text[], timestamptz[])
  from public, anon, authenticated;
grant execute on function public.llm_usage_counts(uuid, text[], timestamptz[])
  to service_role;
