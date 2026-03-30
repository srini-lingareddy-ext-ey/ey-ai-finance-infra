#!/usr/bin/env python3
"""
After MongoDB (Cosmos DB for MongoDB vCore) is provisioned, ensure database eyaifin
and collection chats exist with an initial chat-shaped document when the collection is empty.

Idempotent: if chats already has documents, does nothing (safe on re-runs).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime, timezone

try:
    from pymongo import MongoClient
    from pymongo.errors import PyMongoError, ServerSelectionTimeoutError
except ImportError:
    print("Error: pymongo is required. Run: pip install pymongo", file=sys.stderr)
    sys.exit(1)

DEFAULT_DB = "eyaifin"
DEFAULT_COLLECTION = "chats"


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed eyaifin.chats for POC Mongo")
    parser.add_argument("--database", default=os.environ.get("MONGO_DATABASE", DEFAULT_DB))
    parser.add_argument("--collection", default=os.environ.get("MONGO_CHATS_COLLECTION", DEFAULT_COLLECTION))
    parser.add_argument("--poc-slug", default=os.environ.get("POC_SLUG", ""))
    parser.add_argument("--max-wait-seconds", type=int, default=300, help="Retry connecting until this budget elapses")
    args = parser.parse_args()

    uri = (os.environ.get("MONGO_URI") or "").strip()
    if not uri:
        print("Error: MONGO_URI environment variable is required", file=sys.stderr)
        return 1

    deadline = time.monotonic() + max(30, args.max_wait_seconds)
    last_err: Exception | None = None
    client: MongoClient | None = None
    while time.monotonic() < deadline:
        try:
            client = MongoClient(
                uri,
                serverSelectionTimeoutMS=20000,
                connectTimeoutMS=20000,
            )
            client.admin.command("ping")
            break
        except (ServerSelectionTimeoutError, PyMongoError) as e:
            last_err = e
            print(f"Mongo not ready yet ({e!s}); retrying in 15s...")
            time.sleep(15)
    else:
        print(f"Error: could not connect to Mongo within budget: {last_err}", file=sys.stderr)
        return 1

    assert client is not None
    try:
        db = client[args.database]
        col = db[args.collection]
        n = col.estimated_document_count()
        if n > 0:
            print(f"Skip seed: {args.database}.{args.collection} already has ~{n} document(s).")
            return 0

        now = datetime.now(timezone.utc)
        doc = {
            "chatId": "poc-bootstrap",
            "title": "POC bootstrap chat",
            "messages": [],
            "pocSlug": args.poc_slug or None,
            "createdAt": now,
            "updatedAt": now,
            "_seedSource": "ey-ai-finance-infra deploy-poc",
        }
        col.insert_one(doc)
        print(f"Seeded {args.database}.{args.collection} with bootstrap document (empty messages[]).")
        return 0
    except PyMongoError as e:
        print(f"Error: Mongo operation failed: {e}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
