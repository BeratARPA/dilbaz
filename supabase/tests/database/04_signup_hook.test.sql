-- Sign-up allowlist hook (docs/14-security-privacy.md §2).
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into private.signup_allowlist (email) values ('allowed@dilbaz.test');

select is(
  private.hook_before_user_created('{"user": {"email": "allowed@dilbaz.test"}}'),
  '{}'::jsonb,
  'an allowlisted email may sign up'
);
select is(
  private.hook_before_user_created('{"user": {"email": "Allowed@Dilbaz.TEST"}}'),
  '{}'::jsonb,
  'email matching ignores case'
);
select is(
  private.hook_before_user_created('{"user": {"email": "stranger@example.com"}}')
    -> 'error' ->> 'http_code',
  '403',
  'any other email is rejected'
);
select is(
  private.hook_before_user_created('{"user": {}}') -> 'error' ->> 'message',
  'signup_not_allowed',
  'a request without an email is rejected'
);
select ok(
  has_function_privilege('supabase_auth_admin', 'private.hook_before_user_created(jsonb)', 'execute'),
  'the auth server may call the hook'
);
select ok(
  has_table_privilege('supabase_auth_admin', 'private.signup_allowlist', 'select'),
  'the auth server may read the allowlist'
);
select throws_ok(
  $$insert into private.signup_allowlist (email) values ('Upper@Dilbaz.test')$$,
  '23514', null,
  'allowlist entries are stored in lowercase'
);

select * from finish();
rollback;
