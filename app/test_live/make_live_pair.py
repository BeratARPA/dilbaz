"""Two partners on the LOCAL Supabase stack for the Together live check.

Like make_live_user.py: reads the local stack's URL and keys from
`supabase status -o env` (local test keys only), puts the two test e-mails
on the local sign-up allowlist, creates two confirmed users with random
passwords, their profiles and a team of the two. Writes what the live test
needs to <out>; prints no key or password.

Usage: python -I make_live_pair.py <repo> <out-env-file>
"""

import json
import secrets
import subprocess
import sys
import urllib.request

repo, out = sys.argv[1], sys.argv[2]
USERS = [("canli-a@dilbaz.test", "Canli A"), ("canli-b@dilbaz.test", "Canli B")]
TEAM = "7e000000-0000-4000-8000-0000000000a1"


def npx(*args: str) -> str:
    return subprocess.run(
        ["npx.cmd", "supabase", *args],
        cwd=repo,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout


env = {}
for line in npx("status", "-o", "env").splitlines():
    if "=" in line:
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"')
url, service, anon = env["API_URL"], env["SERVICE_ROLE_KEY"], env["ANON_KEY"]
assert url.startswith("http://127.0.0.1:"), "local stack only"

headers = {
    "apikey": service,
    "Authorization": f"Bearer {service}",
    "Content-Type": "application/json",
}


def call(method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        url + path,
        method=method,
        headers=headers,
        data=None if body is None else json.dumps(body).encode(),
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read() or b"{}")


existing = {u.get("email"): u["id"] for u in call("GET", "/auth/v1/admin/users?per_page=200").get("users", [])}
made = []
for email, name in USERS:
    npx(
        "db", "query", "--local",
        f"insert into private.signup_allowlist (email, note) values ('{email}', 'local live check') on conflict do nothing",
    )
    password = secrets.token_urlsafe(18)
    if email in existing:
        user_id = existing[email]
        call("PUT", f"/auth/v1/admin/users/{user_id}", {"password": password})
    else:
        user_id = call(
            "POST", "/auth/v1/admin/users",
            {"email": email, "password": password, "email_confirm": True},
        )["id"]
    npx(
        "db", "query", "--local",
        f"insert into public.profiles (id, display_name) values ('{user_id}', '{name}') on conflict (id) do nothing",
    )
    made.append((email, password, user_id))

(a_id, b_id) = (made[0][2], made[1][2])
for sql in [
    "insert into public.teams (id, name, invite_code, created_by) "
    f"values ('{TEAM}', 'Canli', 'CANLI1', '{a_id}') on conflict do nothing",
    "insert into public.team_members (team_id, profile_id) values "
    f"('{TEAM}', '{a_id}'), ('{TEAM}', '{b_id}') on conflict do nothing",
    f"delete from public.pair_invites where team_id = '{TEAM}'",
    f"delete from public.pair_sessions where team_id = '{TEAM}'",
    f"delete from public.cheers where team_id = '{TEAM}'",
]:
    npx("db", "query", "--local", sql)

with open(out, "w", encoding="utf-8") as fh:
    fh.write(f"DILBAZ_LIVE_URL={url}\n")
    fh.write(f"DILBAZ_LIVE_ANON={anon}\n")
    for tag, (email, password, _) in zip("AB", made, strict=True):
        fh.write(f"DILBAZ_LIVE_{tag}_EMAIL={email}\n")
        fh.write(f"DILBAZ_LIVE_{tag}_PASSWORD={password}\n")
print("local partners ready:", ", ".join(email for email, _, _ in made))
