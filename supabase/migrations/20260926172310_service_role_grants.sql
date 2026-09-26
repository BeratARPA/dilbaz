-- Server functions (usage logs, pair tasks, retention, backups) act as the
-- service role, which bypasses RLS but still needs table privileges. With
-- "Automatically expose new tables" off, the hosted project grants the
-- service role no data access on new tables; make it explicit so every
-- environment behaves the same (docs/13-data-model.md §4).

alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables to service_role;
alter default privileges for role postgres in schema public
  grant usage, select on sequences to service_role;

grant select, insert, update, delete
  on public.profiles, public.courses, public.teams, public.team_members
  to service_role;
