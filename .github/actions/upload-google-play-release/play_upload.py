#!/usr/bin/env python3
import argparse
import os
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


def parse_bool(s: str) -> bool:
    return str(s).strip().lower() in ("1", "true", "yes", "y", "on")


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload AAB to Google Play track via Android Publisher API")
    ap.add_argument("--package_name", required=True)
    ap.add_argument("--aab_path", required=True)
    ap.add_argument("--track", default="internal")
    ap.add_argument("--release_name", default="")
    ap.add_argument("--status", default="completed")
    ap.add_argument("--changes_not_sent_for_review", default="false")
    args = ap.parse_args()

    package_name = args.package_name.strip()
    track = args.track.strip()
    release_name = (args.release_name or "").strip()
    status = args.status.strip()
    changes_not_sent = parse_bool(args.changes_not_sent_for_review)

    if track not in {"internal", "alpha", "beta", "production"}:
        raise SystemExit(f"Invalid track '{track}'. Expected internal/alpha/beta/production.")

    aab_path = Path(args.aab_path)
    if not aab_path.is_absolute():
        # In GitHub Actions, the workspace is mounted; relative paths are relative to /github/workspace
        workspace = Path(os.environ.get("GITHUB_WORKSPACE", "/github/workspace"))
        aab_path = workspace / aab_path

    if not aab_path.exists() or not aab_path.name.endswith(".aab"):
        raise SystemExit(f"AAB not found or not an .aab: {aab_path}")

    creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not creds_path or not Path(creds_path).exists():
        raise SystemExit("GOOGLE_APPLICATION_CREDENTIALS missing or file not found")

    scopes = ["https://www.googleapis.com/auth/androidpublisher"]
    creds = service_account.Credentials.from_service_account_file(creds_path, scopes=scopes)
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    # 1) Create edit
    edit = service.edits().insert(body={}, packageName=package_name).execute()
    edit_id = edit["id"]
    print(f"[Play] Created edit: {edit_id}")

    try:
        # 2) Upload bundle
        media = MediaFileUpload(str(aab_path), mimetype="application/octet-stream", resumable=True)
        bundle = service.edits().bundles().upload(
            packageName=package_name,
            editId=edit_id,
            media_body=media,
        ).execute()
        version_code = bundle["versionCode"]
        print(f"[Play] Uploaded bundle: {aab_path.name} (versionCode={version_code})")

        # 3) Assign to track
        track_body = {
            "releases": [
                {
                    "name": release_name,
                    "status": status,
                    "versionCodes": [str(version_code)],
                }
            ]
        }
        service.edits().tracks().update(
            packageName=package_name,
            editId=edit_id,
            track=track,
            body=track_body,
        ).execute()
        print(f"[Play] Updated track '{track}' with versionCode={version_code}")

        # 4) Commit edit
        commit_kwargs = {
            "packageName": package_name,
            "editId": edit_id,
        }
        # optional query param
        if changes_not_sent:
            commit_kwargs["changesNotSentForReview"] = True

        service.edits().commit(**commit_kwargs).execute()
        print("[Play] Committed edit. Done.")
        return 0

    except Exception:
        # Best-effort cleanup: delete edit if possible (not always necessary/available)
        # Some API clients don't expose a delete; safest is just re-raise.
        raise


if __name__ == "__main__":
    raise SystemExit(main())
