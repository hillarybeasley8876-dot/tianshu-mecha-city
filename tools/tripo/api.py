"""Tripo Studio web API, called from inside the logged-in Studio tab (cookies authenticate the requests).

The dedicated Chrome (tools/tripo/chrome.sh) must have a studio.tripo3d.ai tab open and logged in. Every call
runs `fetch(..., {credentials: 'include'})` in that tab via CDP, exactly like the web app does, and spends the
account's web credits. Endpoints were learned from the app's own traffic (tools/tripo/netlog.py).
"""
import asyncio
import json
import mimetypes
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp import Page  # noqa: E402

API = "https://api.tripo3d.ai/v2/studio"


class TripoError(RuntimeError):
    pass


RETRY_DELAYS = (3, 8, 20, 45)


async def call(page: Page, method: str, path: str, body: dict | None = None, retry: bool = False) -> dict:
    """One JSON request through the page; raises TripoError unless the reply is {code: 0}.

    retry=True retries transport failures ("Failed to fetch", timeouts) with backoff. Use it only for
    idempotent reads: retrying a task-creating POST could create (and pay for) the task twice."""
    init = {"method": method, "credentials": "include", "headers": {"Content-Type": "application/json"}}
    if body is not None:
        init["body"] = json.dumps(body)
    js = ("(async () => { const r = await fetch(%s, %s); return [r.status, await r.text()]; })()"
          % (json.dumps(API + path), json.dumps(init)))
    for delay in RETRY_DELAYS + (None,):
        try:
            status, text = await page.js(js, timeout=120)
            break
        except (RuntimeError, asyncio.TimeoutError) as exc:
            if not retry or delay is None:
                raise TripoError("%s %s transport error: %s" % (method, path, str(exc)[:200])) from exc
            print("tripo: %s %s failed (%s), retrying in %d s" % (method, path, str(exc)[:80], delay), file=sys.stderr)
            await asyncio.sleep(delay)
    try:
        reply = json.loads(text)
    except ValueError as exc:
        raise TripoError("%s %s -> HTTP %s, non-JSON: %s" % (method, path, status, text[:300])) from exc
    if status != 200 or reply.get("code") != 0:
        raise TripoError("%s %s -> HTTP %s code %s: %s" % (method, path, status, reply.get("code"), reply.get("message")))
    return reply.get("data") or {}


def _s3_put(token: dict, path: str) -> None:
    import boto3  # imported lazily: only uploads need it (run via `uv run --with boto3`)
    s3 = boto3.client("s3", region_name=token["host"].split(".")[1], aws_access_key_id=token["sts_ak"],
                      aws_secret_access_key=token["sts_sk"], aws_session_token=token["session_token"])
    ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        s3.put_object(Bucket=token["resource_bucket"], Key=token["resource_uri"], Body=f, ContentType=ctype)


async def upload_image(page: Page, path: str) -> dict:
    """Upload a local image the way the web app does (STS token -> S3 put -> audit). Returns the image ref."""
    ext = os.path.splitext(path)[1].lstrip(".").lower().replace("jpeg", "jpg")
    token = await call(page, "POST", "/storage/temporary_token", {"client": "aws", "format": ext})
    await asyncio.to_thread(_s3_put, token, path)
    ref = {"bucket": token["resource_bucket"], "key": token["resource_uri"]}
    audit = await call(page, "POST", "/audit/image", {"image": ref})
    if audit.get("result") != "pass":
        raise TripoError("image audit did not pass for %s: %s" % (path, audit))
    return dict(ref, image_audit_result="pass", image_source="upload")


async def progress(page: Page, op_ids: list[str]) -> list[dict]:
    return await call(page, "POST", "/progress", {"ids": op_ids}, retry=True)


async def project_detail(page: Page, project_id: str) -> dict:
    return await call(page, "GET", "/project/detail/v3/%s?locale=en" % project_id, retry=True)


async def wallet(page: Page) -> dict:
    return await call(page, "GET", "/user/profile/payment", retry=True)
