#!/usr/bin/env python3
import argparse
import os
import socket
import time
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
DEFAULT_HTTP_TIMEOUT_SECONDS = 120
DEFAULT_UPLOAD_CHUNK_SIZE_MB = 8
DEFAULT_API_RETRIES = 5
DEFAULT_UPLOAD_RETRY_LIMIT = 5
RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}
CHUNK_GRANULARITY_BYTES = 256 * 1024
VALID_TRACKS = {"internal", "alpha", "beta", "production"}


def parse_bool(s: str) -> bool:
    return str(s).strip().lower() in ("1", "true", "yes", "y", "on")


def get_env_int(name: str, default: int, *, min_value: int = 1) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default

    try:
        value = int(raw)
    except ValueError as exc:
        raise SystemExit(f"Environment variable {name} must be an integer, got: {raw!r}") from exc

    if value < min_value:
        raise SystemExit(f"Environment variable {name} must be >= {min_value}, got: {value}")

    return value


def normalize_chunk_size(chunk_size_bytes: int) -> int:
    if chunk_size_bytes < CHUNK_GRANULARITY_BYTES:
        return CHUNK_GRANULARITY_BYTES

    remainder = chunk_size_bytes % CHUNK_GRANULARITY_BYTES
    if remainder == 0:
        return chunk_size_bytes

    return chunk_size_bytes + (CHUNK_GRANULARITY_BYTES - remainder)


def is_retryable_upload_exception(exc: Exception) -> bool:
    if isinstance(exc, HttpError):
        status_code = getattr(exc.resp, "status", None)
        return status_code in RETRYABLE_STATUS_CODES

    if isinstance(exc, (TimeoutError, socket.timeout, ConnectionResetError, BrokenPipeError, ConnectionError)):
        return True

    if isinstance(exc, OSError):
        message = str(exc).lower()
        return any(token in message for token in (
            "timed out",
            "timeout",
            "connection reset",
            "broken pipe",
            "temporarily unavailable",
            "eof occurred in violation of protocol",
        ))

    return False


def execute_request(request, *, label: str, num_retries: int):
    try:
        return request.execute(num_retries=num_retries)
    except HttpError as exc:
        status_code = getattr(exc.resp, "status", "unknown")
        details = getattr(exc, "content", b"")
        details_text = details.decode("utf-8", errors="replace") if details else str(exc)
        raise SystemExit(f"[Play] {label} failed with HTTP {status_code}: {details_text}") from exc


def upload_bundle(
    service,
    *,
    package_name: str,
    edit_id: str,
    aab_path: Path,
    chunk_size_bytes: int,
    api_retries: int,
    upload_retry_limit: int,
):
    media = MediaFileUpload(
        str(aab_path),
        mimetype="application/octet-stream",
        chunksize=chunk_size_bytes,
        resumable=True,
    )

    request = service.edits().bundles().upload(
        packageName=package_name,
        editId=edit_id,
        media_body=media,
    )

    response = None
    consecutive_failures = 0
    last_reported_progress = -1

    while response is None:
        try:
            status, response = request.next_chunk(num_retries=api_retries)

            if status is not None:
                progress = int(status.progress() * 100)
                if progress != last_reported_progress:
                    print(f"[Play] Upload progress: {progress}%")
                    last_reported_progress = progress

            consecutive_failures = 0

        except Exception as exc:
            if not is_retryable_upload_exception(exc):
                raise

            consecutive_failures += 1
            if consecutive_failures > upload_retry_limit:
                raise SystemExit(
                    f"[Play] Upload failed after {upload_retry_limit} retry attempts: {exc}"
                ) from exc

            backoff_seconds = min(2 ** consecutive_failures, 30)
            print(
                f"[Play] Transient upload error ({exc.__class__.__name__}: {exc}). "
                f"Retrying current chunk in {backoff_seconds}s "
                f"({consecutive_failures}/{upload_retry_limit})..."
            )
            time.sleep(backoff_seconds)

    return response


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

    if track not in VALID_TRACKS:
        raise SystemExit(f"Invalid track '{track}'. Expected internal/alpha/beta/production.")

    aab_path = Path(args.aab_path)
    if not aab_path.is_absolute():
        workspace = Path(os.environ.get("GITHUB_WORKSPACE", "/github/workspace"))
        aab_path = workspace / aab_path

    if not aab_path.exists() or aab_path.suffix.lower() != ".aab":
        raise SystemExit(f"AAB not found or not an .aab: {aab_path}")

    creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not creds_path or not Path(creds_path).exists():
        raise SystemExit("GOOGLE_APPLICATION_CREDENTIALS missing or file not found")

    http_timeout_seconds = get_env_int(
        "PLAY_HTTP_TIMEOUT_SECONDS",
        DEFAULT_HTTP_TIMEOUT_SECONDS,
        min_value=1,
    )
    upload_chunk_size_mb = get_env_int(
        "PLAY_UPLOAD_CHUNK_SIZE_MB",
        DEFAULT_UPLOAD_CHUNK_SIZE_MB,
        min_value=1,
    )
    api_retries = get_env_int(
        "PLAY_API_RETRIES",
        DEFAULT_API_RETRIES,
        min_value=0,
    )
    upload_retry_limit = get_env_int(
        "PLAY_UPLOAD_RETRY_LIMIT",
        DEFAULT_UPLOAD_RETRY_LIMIT,
        min_value=0,
    )

    chunk_size_bytes = normalize_chunk_size(upload_chunk_size_mb * 1024 * 1024)

    # Important: google-api-python-client uses the socket default timeout when
    # it builds its underlying httplib2 transport.
    socket.setdefaulttimeout(http_timeout_seconds)

    print(
        "[Play] Upload settings: "
        f"timeout={http_timeout_seconds}s, "
        f"chunk_size={chunk_size_bytes // (1024 * 1024)}MB, "
        f"api_retries={api_retries}, "
        f"upload_retry_limit={upload_retry_limit}"
    )

    creds = service_account.Credentials.from_service_account_file(creds_path, scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    try:
        # 1) Create edit
        edit = execute_request(
            service.edits().insert(body={}, packageName=package_name),
            label="Create edit",
            num_retries=api_retries,
        )
        edit_id = edit["id"]
        print(f"[Play] Created edit: {edit_id}")

        # 2) Upload bundle using resumable chunked upload
        bundle = upload_bundle(
            service,
            package_name=package_name,
            edit_id=edit_id,
            aab_path=aab_path,
            chunk_size_bytes=chunk_size_bytes,
            api_retries=api_retries,
            upload_retry_limit=upload_retry_limit,
        )
        version_code = str(bundle["versionCode"])
        print(f"[Play] Uploaded bundle: {aab_path.name} (versionCode={version_code})")

        # 3) Assign to track
        release = {
            "status": status,
            "versionCodes": [version_code],
        }
        if release_name:
            release["name"] = release_name

        track_body = {"releases": [release]}

        execute_request(
            service.edits().tracks().update(
                packageName=package_name,
                editId=edit_id,
                track=track,
                body=track_body,
            ),
            label=f"Update track '{track}'",
            num_retries=api_retries,
        )
        print(f"[Play] Updated track '{track}' with versionCode={version_code}")

        # 4) Commit edit
        commit_kwargs = {
            "packageName": package_name,
            "editId": edit_id,
        }
        if changes_not_sent:
            commit_kwargs["changesNotSentForReview"] = True

        execute_request(
            service.edits().commit(**commit_kwargs),
            label="Commit edit",
            num_retries=api_retries,
        )
        print("[Play] Committed edit. Done.")
        return 0

    except HttpError as exc:
        status_code = getattr(exc.resp, "status", "unknown")
        details = getattr(exc, "content", b"")
        details_text = details.decode("utf-8", errors="replace") if details else str(exc)
        raise SystemExit(f"[Play] HTTP {status_code} error: {details_text}") from exc
    except Exception as exc:
        raise SystemExit(f"[Play] Upload failed: {exc}") from exc


if __name__ == "__main__":
    raise SystemExit(main())