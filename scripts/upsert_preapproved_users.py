#!/usr/bin/env python3
"""
Upsert preapproved_users from PREAPPROVED_EXTRA_EMAILS (comma-separated).
All rows use is_admin=true. If PREAPPROVED_EXTRA_EMAILS is empty or whitespace-only, prints a
GitHub Actions ::warning:: (stdout) and exits 0 without running SQL — admins must be added via
PostgreSQL manually.
Requires libpq env: PGHOST, PGDATABASE, PGPASSWORD; optional PGUSER (default citus), PGSSLMODE (default require).
"""
import os
import subprocess
import sys


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

    raw = os.environ.get("PREAPPROVED_EXTRA_EMAILS", "")
    parts = [p.strip() for p in raw.split(",") if p.strip()]

    seen: set[str] = set()
    emails: list[str] = []
    for e in parts:
        key = e.casefold()
        if key not in seen:
            seen.add(key)
            emails.append(e)

    if not emails:
        warn = (
            "PREAPPROVED_EXTRA_EMAILS is empty; preapproved_users was not updated. "
            "Add admin emails to the preapproved_users table via SQL in PostgreSQL before users can sign in."
        )
        print(f"::warning::{warn}")
        return 0

    values_sql = ",\n    ".join(f"({sql_literal(e)}, true)" for e in emails)
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
    print(f"Upserted {len(emails)} preapproved user(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
