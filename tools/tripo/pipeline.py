"""Tripo Studio asset pipeline steps after generation: remesh -> rig -> animations -> export (see API.md).

Each function takes the open API page + a registry job dict, performs one step, waits for it, records the
operation ids in the job and returns it. Credits: remesh 35, rig 20, text motion 20, presets/export free.
"""
import asyncio
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import api  # noqa: E402
from cdp import Page  # noqa: E402

RIG_MODEL = "v3.0-20260909"


async def wait_ops(page: Page, ops: list[str], timeout: float = 1200.0) -> dict:
    """Poll until every op leaves the running states; returns {op: status}."""
    todo, done = set(ops), {}
    deadline = time.time() + timeout
    while todo and time.time() < deadline:
        for r in await api.progress(page, sorted(todo)):
            if r.get("status") not in ("running", "queued", "waiting"):
                done[r["id"]] = r.get("status")
                todo.discard(r["id"])
        if todo:
            await asyncio.sleep(6)
    for op in todo:
        done[op] = "timeout"
    return done


async def project_call(page: Page, path: str, body: dict) -> dict:
    """POST an operation on a project; Tripo allows one running operation per project (code 12003 'Failed
    to acquire lock'), so wait and retry while the lock is held."""
    for attempt in range(40):
        try:
            return await api.call(page, "POST", path, body)
        except api.TripoError as exc:
            if "12003" not in str(exc) or attempt == 39:
                raise
            await asyncio.sleep(6)
    raise api.TripoError("unreachable")


def _check(statuses: dict, step: str) -> None:
    bad = {k: v for k, v in statuses.items() if v != "success"}
    if bad:
        raise api.TripoError("%s failed: %s" % (step, bad))


async def remesh(page: Page, job: dict, faces: int = 20000) -> dict:
    body = {"bake": True, "face_limit": faces, "model_version": "default", "project_id": job["project_id"],
            "part_name_list": ["tripo_node_%s" % job["operation_id"]], "quad": False, "smart_poly": True}
    op = (await project_call(page, "/operation/remesh", body))["operation_id"]
    _check(await wait_ops(page, [op]), "remesh")
    job["remesh_op"] = op
    return job


async def rig(page: Page, job: dict) -> dict:
    check = await api.call(page, "POST", "/operation/pre_rig_check",
                           {"model_version": RIG_MODEL, "project_id": job["project_id"]})
    if not check.get("riggable"):
        raise api.TripoError("model is not riggable: %s" % check)
    body = {"model_version": RIG_MODEL, "project_id": job["project_id"], "rig_type": check["rig_type"]}
    op = (await project_call(page, "/operation/rigging_model", body))["operation_id"]
    _check(await wait_ops(page, [op]), "rig")
    job.update(rig_type=check["rig_type"], rig_op=op, anims=job.get("anims") or {})
    return job


async def presets(page: Page, job: dict, names: list[str]) -> dict:
    for name in names:
        await preset(page, job, name, name)
    return job


async def preset(page: Page, job: dict, label: str, name: str) -> dict:
    body = {"animations": ["preset:%s:%s" % (job["rig_type"], name)], "model_version": "default",
            "project_id": job["project_id"], "rig_type": job["rig_type"]}
    op = (await project_call(page, "/operation/retarget_model", body))["operation_id"]
    _check(await wait_ops(page, [op]), "retarget preset " + name)
    job.setdefault("anims", {})[label] = op
    return job


async def text_motion(page: Page, job: dict, label: str, prompt: str, seconds: float = 5.0) -> dict:
    task = (await api.call(page, "POST", "/motion/generate",
                           {"segments": [{"duration_seconds": seconds, "prompt": prompt}]}))["task_id"]
    asset = None
    for _ in range(90):
        t = await api.call(page, "POST", "/motion/get_task", {"task_id": task}, retry=True)
        if t.get("status") == "success":
            asset = t["asset_id"]
            break
        if t.get("status") in ("failed", "expired", "cancelled"):
            raise api.TripoError("motion %s: %s" % (label, t))
        await asyncio.sleep(4)
    if asset is None:
        raise api.TripoError("motion %s timed out" % label)
    body = {"motion_asset_id": asset, "model_version": "default", "project_id": job["project_id"],
            "rig_type": job["rig_type"]}
    op = (await project_call(page, "/operation/retarget_model", body))["operation_id"]
    _check(await wait_ops(page, [op]), "retarget motion " + label)
    job["anims"][label] = op
    job.setdefault("motion_prompts", {})[label] = prompt
    return job


async def export(page: Page, job: dict, out_path: str, anim_labels: list[str], tex: int = 4096) -> str:
    ops = [job["anims"][a] for a in anim_labels]
    body = {"animate_in_place": False, "animations": ops, "bake_animation_frame": 0, "enable_bake_animation": False,
            "export_orientation": "-y", "export_vertex_colors": False, "fbx_preset": "blender", "format": "gltf",
            "model_version": "default", "name": os.path.splitext(os.path.basename(out_path))[0], "pack_uv": False,
            "project_id": job["project_id"], "texture_packaging": "zip", "texture_size": tex, "with_animation": bool(ops)}
    op = (await project_call(page, "/operation/export", body))["operation_id"]
    _check(await wait_ops(page, [op]), "export")
    url = (await api.call(page, "POST", "/operation/download_with_name",
                          {"file_name": body["name"], "operator_id": op}, retry=True))["model_url"]
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    subprocess.run(["curl", "-sS", "-L", "--retry", "3", "-m", "900", "-o", out_path, url], check=True)
    job.setdefault("exports", {})[out_path] = {"op": op, "anims": anim_labels, "tex": tex}
    return out_path
