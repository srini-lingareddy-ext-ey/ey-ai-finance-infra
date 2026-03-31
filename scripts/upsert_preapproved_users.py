#!/usr/bin/env python3
"""
Upsert preapproved_users: default admin emails plus PREAPPROVED_EXTRA_EMAILS (comma-separated).
All rows use is_admin=true. Requires libpq env: PGHOST, PGDATABASE, PGPASSWORD; optional PGUSER (default citus), PGSSLMODE (default require).
"""
import os
import subprocess
import sys

DEFAULT_EMAILS = [
    "Amy.Feng.Chen@ey.com",
    "Kayl.Murdough@ey.com"
]


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> int:
    host = os.environ.get("PGHOST", "")
    db = os.environ.get("PGDATABASE", "")
    if not host or not db:
        print("PGHOST and PGDATABASE must be set", file=sys.stderr)
        return 1

    user = os.environ.get("PGUSER", "citus")
    sslmode = os.environ.get("PGSSLMODE", "require")
    password = os.environ.get("PGPASSWORD", "")
    if not password:
        print("PGPASSWORD must be set", file=sys.stderr)
        return 1

    extra_raw = os.environ.get("PREAPPROVED_EXTRA_EMAILS", "")
    extras = [p.strip() for p in extra_raw.split(",") if p.strip()]

    seen: set[str] = set()
    merged: list[str] = []
    for e in DEFAULT_EMAILS + extras:
        key = e.casefold()
        if key not in seen:
            seen.add(key)
            merged.append(e)

    values_sql = ",\n    ".join(f"({sql_literal(e)}, true)" for e in merged)
    sql = f"""INSERT INTO preapproved_users (email, is_admin)
VALUES
    {values_sql}
ON CONFLICT (email) DO UPDATE SET is_admin = EXCLUDED.is_admin;
"""

    conn = f"host={host} port=5432 dbname={db} user={user} sslmode={sslmode}"
    env = {**os.environ, "PGPASSWORD": password}
    subprocess.run(
        ["psql", conn, "-v", "ON_ERROR_STOP=1"],
        input=sql,
        text=True,
        check=True,
        env=env,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
