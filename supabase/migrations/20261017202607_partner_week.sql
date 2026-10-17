-- The partners' week (F2-09; docs/09 §7, docs/04 §9, docs/14 §3; I-18):
-- the shared weekly goal, each partner's summary, and cheers.
--
-- A partner never reads the other's sessions, attempts or recordings. The
-- summary function returns, for each member of the caller's team, only
-- counts: active days, minutes, minutes by strand and the tasks done
-- together; the level estimate only when that member shares it. The shared
-- goal is the members' weekly day goals added up.

create function public.partner_week_summary(
  p_team_id uuid,
  p_since timestamptz,
  p_offset_minutes int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_until timestamptz := p_since + interval '7 days';
  v_offset interval := make_interval(mins => coalesce(p_offset_minutes, 0));
begin
  if not private.is_team_member(p_team_id) then
    raise exception 'not_a_member';
  end if;
  return (
    select jsonb_build_object(
      'goal_days', coalesce(sum(p.weekly_days_goal), 0),
      'members', coalesce(jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'name', p.display_name,
          'days', w.days,
          'minutes', w.minutes,
          'strands', w.strands,
          'together', w.together,
          'levels', case when m.share_levels then (
            select c.level_estimates from public.courses c
            where c.profile_id = p.id and c.active
            order by c.created_at limit 1
          ) end
        )
        order by m.joined_at, p.id
      ), '[]'::jsonb)
    )
    from public.team_members m
    join public.profiles p on p.id = m.profile_id
    cross join lateral (
      select
        count(distinct ((s.started_at + v_offset) at time zone 'UTC')::date)::int as days,
        coalesce(sum((
          select coalesce(sum(value::bigint), 0)
          from jsonb_each_text(s.strand_ms)
        )), 0)::bigint / 60000 as minutes,
        coalesce((
          select jsonb_object_agg(k, v)
          from (
            select e.key as k, sum(e.value::bigint) / 60000 as v
            from public.sessions s2, jsonb_each_text(s2.strand_ms) e
            where s2.profile_id = p.id
              and s2.started_at >= p_since and s2.started_at < v_until
            group by e.key
          ) by_strand
        ), '{}'::jsonb) as strands,
        count(*) filter (
          where s.planned ->> 'activity' in ('pair_chat', 'pair_info_gap')
        )::int as together
      from public.sessions s
      where s.profile_id = p.id
        and s.started_at >= p_since and s.started_at < v_until
    ) w
    where m.team_id = p_team_id
  );
end;
$$;

revoke all on function public.partner_week_summary(uuid, timestamptz, int)
  from public, anon;
grant execute on function public.partner_week_summary(uuid, timestamptz, int)
  to authenticated;

-- "Tebrik gönder" (docs/09 §7): one tap, one of a few fixed kind messages;
-- the words are the app's (ARB), the row keeps their key.
create table public.cheers (
  id uuid primary key,
  team_id uuid not null references public.teams on delete cascade,
  from_profile uuid not null references public.profiles on delete cascade,
  to_profile uuid not null references public.profiles on delete cascade,
  message_key text not null
    check (message_key in ('steady', 'speaking', 'together')),
  created_at timestamptz not null default now(),
  check (from_profile <> to_profile)
);

create index cheers_to_profile_created_at_idx
  on public.cheers (to_profile, created_at desc);

alter table public.cheers enable row level security;

revoke all on public.cheers from anon, authenticated;
grant select, insert on public.cheers to authenticated;
grant select, insert, update, delete on public.cheers to service_role;

create policy cheers_select_own on public.cheers
  for select to authenticated
  using (
    from_profile = (select auth.uid()) or to_profile = (select auth.uid())
  );

create policy cheers_insert_own on public.cheers
  for insert to authenticated
  with check (
    from_profile = (select auth.uid())
    and private.is_team_member(team_id)
    and private.team_has_member(team_id, to_profile)
  );

alter publication supabase_realtime add table public.cheers;
