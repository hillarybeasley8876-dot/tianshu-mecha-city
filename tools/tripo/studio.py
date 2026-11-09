"""Tripo Studio batch driver (web credits). Run through tools/tripo/studio.sh (adds deps).

  studio.sh balance                                  credits / membership
  studio.sh img2model NAME IMAGE [--faces N] [--quad] [--parts] [--smart-poly] [--dry-run]
                                                     upload IMAGE, start H3.1 image->model (8K PBR, ~65 credits)
  studio.sh wait NAME [NAME ...] [--timeout S]       poll until done, then download into art/tripo/NAME/
  studio.sh fetch NAME                               (re)download a finished job's model + covers
  studio.sh list                                     jobs in the registry
  studio.sh remesh NAME [--faces 20000]              retopology + texture bake (35 cr) — needed before rig
  studio.sh rig NAME                                 auto rig (20 cr; rig type detected: biped/...)
  studio.sh presets NAME run walk idle ...           retarget preset animations (names per rig type)
  studio.sh motion NAME LABEL "prompt" [--seconds 5] text-to-motion (20 cr) applied as animation LABEL
  studio.sh motions NAME FILE.json                   batch: presets + text motions from a list (skips done labels)
  studio.sh export NAME OUT.glb [--anims a,b|all] [--tex 4096]   rigged + animated GLB download
  studio.sh opwait OP_ID [OP_ID ...] [--timeout S]   poll raw operation ids until done (prints status)
  studio.sh detail PROJECT_ID [OUT.json]             project detail (operations, model urls)

Registry: art/tripo/jobs.json (name -> project/operation ids, params, status). Never re-create a job after a
network error without checking `list`/`balance` first: the task may already exist and have spent credits.
"""
import argparse
import asyncio
import fcntl
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import api  # noqa: E402
import pipeline  # noqa: E402
from cdp import Page, ensure_api_tab  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "tripo")
REGISTRY = os.path.join(OUT, "jobs.json")
MODEL_VERSION = "v3.1-20260211"


def load_registry() -> dict:
    if not os.path.exists(REGISTRY):
        return {}
    with open(REGISTRY) as f:
        return json.load(f)


def save_registry(jobs: dict) -> None:
    """Merge-save ONLY the given jobs ({name: job}) under an exclusive lock, so parallel studio.sh processes
    working on different jobs never overwrite each other's records with stale copies."""
    os.makedirs(OUT, exist_ok=True)
    with open(REGISTRY + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stored = load_registry()
        stored.update(jobs)
        tmp = REGISTRY + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(stored, f, indent=1, ensure_ascii=False)
        os.replace(tmp, REGISTRY)


def img2model_params(a: argparse.Namespace, image_ref: dict) -> dict:
    return {"face_limit": a.faces, "quad": a.quad, "visibility": "shareable", "model_version": MODEL_VERSION,
            "generate_parts": a.parts, "smart_poly": a.smart_poly, "texture": True, "delight": True, "pbr": True,
            "texture_alignment": "original_image", "texture_quality": "extreme", "enable_image_autofix": False,
            "geometry_quality": "detailed", "image": image_ref}


async def cmd_img2model(page: Page, a: argparse.Namespace) -> None:
    reg = load_registry()
    if a.name in reg and not a.force:
        raise SystemExit("job %s exists (%s); use --force to make another" % (a.name, reg[a.name]["status"]))
    if a.dry_run:
        print(json.dumps(img2model_params(a, {"key": "<upload>"}), indent=1))
        return
    ref = await api.upload_image(page, a.image)
    data = await api.call(page, "POST", "/operation/image_to_model", img2model_params(a, ref))
    reg[a.name] = {"kind": "image_to_model", "image": os.path.abspath(a.image), "project_id": data["project_id"],
                   "operation_id": data["operation_id"], "faces": a.faces, "quad": a.quad, "parts": a.parts,
                   "created": time.strftime("%Y-%m-%d %H:%M:%S"), "status": "running"}
    save_registry({a.name: reg[a.name]})
    print(json.dumps({"name": a.name, "project_id": data["project_id"], "operation_id": data["operation_id"]}))


def download(url: str, dest: str) -> None:
    subprocess.run(["curl", "-sS", "-L", "--retry", "3", "-m", "900", "-o", dest, url], check=True)


async def fetch(page: Page, name: str, job: dict) -> str:
    d = await api.project_detail(page, job["project_id"])
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    if not d.get("model_url"):
        raise api.TripoError("%s has no model_url yet" % name)
    download(d["model_url"], os.path.join(out, "model.glb"))
    for i, url in enumerate(d.get("cover_image") or []):
        download(url, os.path.join(out, "cover%d.webp" % i))
    with open(os.path.join(out, "detail.json"), "w") as f:
        json.dump({k: d.get(k) for k in ("id", "type", "operator")}, f, indent=1, ensure_ascii=False)
    return out


async def cmd_wait(page: Page, a: argparse.Namespace) -> None:
    reg = load_registry()
    todo = {n: reg[n] for n in a.names if reg.get(n, {}).get("status") == "running"}
    deadline = time.time() + a.timeout
    while todo and time.time() < deadline:
        rows = await api.progress(page, [j["operation_id"] for j in todo.values()])
        by_op = {r["id"]: r for r in rows}
        for name, job in list(todo.items()):
            r = by_op.get(job["operation_id"], {})
            if r.get("status") == "success":
                print("%s done -> %s" % (name, await fetch(page, name, job)), flush=True)
                job["status"] = "done"
            elif r.get("status") in ("failed", "banned", "cancelled", "expired"):
                print("%s %s: %s" % (name, r.get("status"), json.dumps(r)[:300]), flush=True)
                job["status"] = r["status"]
            else:
                continue
            save_registry({name: job})
            del todo[name]
        if todo:
            await asyncio.sleep(10)
    for name in todo:
        print("%s still running after %d s" % (name, a.timeout))


async def cmd_pipeline(page: Page, a: argparse.Namespace) -> None:
    reg = load_registry()
    job = reg.get(a.name)
    if job is None or job.get("status") != "done":
        raise SystemExit("job %s is not a finished generation" % a.name)
    if a.cmd == "remesh":
        await pipeline.remesh(page, job, a.faces)
    elif a.cmd == "rig":
        await pipeline.rig(page, job)
    elif a.cmd == "presets":
        await pipeline.presets(page, job, a.presets)
    elif a.cmd == "motion":
        await pipeline.text_motion(page, job, a.label, a.prompt, a.seconds)
    elif a.cmd == "export":
        labels = list(job.get("anims", {})) if a.anims == "all" else [x for x in a.anims.split(",") if x]
        print(await pipeline.export(page, job, os.path.abspath(a.out), labels, a.tex))
    save_registry({a.name: job})
    print(json.dumps({k: job.get(k) for k in ("rig_type", "remesh_op", "rig_op", "anims")}, ensure_ascii=False))


async def cmd_motions(page: Page, a: argparse.Namespace) -> None:
    """Run every preset and text motion of the list file that the job does not have yet; saves after each."""
    with open(a.file) as f:
        spec = json.load(f)
    reg = load_registry()
    job = reg[a.name]
    have = job.setdefault("anims", {})
    for label, preset in spec.get("presets", {}).items():
        if label not in have:
            try:
                await pipeline.preset(page, job, label, preset)
                print("preset", label, "->", preset, flush=True)
            except api.TripoError as exc:
                print("preset", label, "FAILED:", exc, flush=True)
            save_registry({a.name: job})
    for label, seconds, prompt in spec.get("motions", []):
        if label in have:
            continue
        try:
            await pipeline.text_motion(page, job, label, prompt, seconds)
            print("motion", label, "ok", flush=True)
        except api.TripoError as exc:
            print("motion", label, "FAILED:", exc, flush=True)
        save_registry({a.name: job})
    statuses = await pipeline.wait_ops(page, list(have.values()))
    print(json.dumps({k: statuses.get(v) for k, v in have.items()}, ensure_ascii=False))


async def cmd_opwait(page: Page, a: argparse.Namespace) -> None:
    todo = set(a.ops)
    deadline = time.time() + a.timeout
    while todo and time.time() < deadline:
        for r in await api.progress(page, sorted(todo)):
            if r.get("status") not in ("running", "queued", "waiting"):
                print(json.dumps({k: r.get(k) for k in ("id", "status", "progress")}), flush=True)
                todo.discard(r["id"])
        if todo:
            await asyncio.sleep(8)
    for op in todo:
        print("%s still running after %d s" % (op, a.timeout))


async def main(a: argparse.Namespace) -> None:
    if a.cmd == "list":
        for n, j in load_registry().items():
            print("%-24s %-10s %s %s" % (n, j["status"], j["kind"], j["created"]))
        return
    ensure_api_tab()
    await asyncio.sleep(0.5)
    page = await Page.open("mc_api=1")
    try:
        if a.cmd == "balance":
            w = await api.wallet(page)
            print(json.dumps({k: w.get(k) for k in ("member", "wallet", "credit", "balance") if k in w}, ensure_ascii=False)[:800])
        elif a.cmd == "img2model":
            await cmd_img2model(page, a)
        elif a.cmd == "wait":
            await cmd_wait(page, a)
        elif a.cmd == "fetch":
            print(await fetch(page, a.name, load_registry()[a.name]))
        elif a.cmd == "motions":
            await cmd_motions(page, a)
        elif a.cmd in ("remesh", "rig", "presets", "motion", "export"):
            await cmd_pipeline(page, a)
        elif a.cmd == "opwait":
            await cmd_opwait(page, a)
        elif a.cmd == "detail":
            d = await api.project_detail(page, a.project_id)
            text = json.dumps(d, indent=1, ensure_ascii=False)
            if a.out:
                with open(a.out, "w") as f:
                    f.write(text)
            print(text[:1500] if not a.out else a.out)
    finally:
        await page.close()


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")
    sub.add_parser("list")
    s = sub.add_parser("img2model")
    s.add_argument("name")
    s.add_argument("image")
    s.add_argument("--faces", type=int, default=2000000)
    s.add_argument("--quad", action="store_true")
    s.add_argument("--parts", action="store_true")
    s.add_argument("--smart-poly", action="store_true")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--force", action="store_true")
    s = sub.add_parser("wait")
    s.add_argument("names", nargs="+")
    s.add_argument("--timeout", type=int, default=1800)
    s = sub.add_parser("fetch")
    s.add_argument("name")
    s = sub.add_parser("remesh")
    s.add_argument("name")
    s.add_argument("--faces", type=int, default=20000)
    s = sub.add_parser("rig")
    s.add_argument("name")
    s = sub.add_parser("presets")
    s.add_argument("name")
    s.add_argument("presets", nargs="+")
    s = sub.add_parser("motion")
    s.add_argument("name")
    s.add_argument("label")
    s.add_argument("prompt")
    s.add_argument("--seconds", type=float, default=5.0)
    s = sub.add_parser("motions")
    s.add_argument("name")
    s.add_argument("file")
    s = sub.add_parser("export")
    s.add_argument("name")
    s.add_argument("out")
    s.add_argument("--anims", default="all")
    s.add_argument("--tex", type=int, default=4096)
    s = sub.add_parser("opwait")
    s.add_argument("ops", nargs="+")
    s.add_argument("--timeout", type=int, default=1800)
    s = sub.add_parser("detail")
    s.add_argument("project_id")
    s.add_argument("out", nargs="?")
    return p.parse_args()


if __name__ == "__main__":
    asyncio.run(main(parse()))
