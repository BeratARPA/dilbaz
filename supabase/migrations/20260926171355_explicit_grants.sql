-- Explicit Data API privileges (docs/13-data-model.md §4).
--
-- Supabase grants every new table in public to anon and authenticated by
-- default (including TRUNCATE, which bypasses RLS). The hosted project runs
-- with "Automatically expose new tables" turned off; this migration makes
-- every environment behave the same: new tables get no privileges, and each
-- table grants exactly what its policies need.

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;

revoke all on public.profiles, public.courses, public.teams, public.team_members
  from anon, authenticated;

grant select, insert, update on public.profiles, public.courses to authenticated;
grant select, insert on public.teams, public.team_members to authenticated;
-- A member may change only their own sharing switches (policy + columns).
grant update (share_levels, share_monthly) on public.team_members to authenticated;

revoke all on sequence public.sync_seq from anon, authenticated;
grant usage on sequence public.sync_seq to authenticated;
