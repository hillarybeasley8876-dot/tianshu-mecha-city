# Tripo Studio web API (learned from the app's own traffic, 2026-11-01)

All calls: `https://api.tripo3d.ai/v2/studio` + path, JSON, made from inside the logged-in Studio tab with
`fetch(..., {credentials: 'include'})` (tools/tripo/api.py). Replies are `{code: 0, message, data}`.
Every task-creating call spends web credits; never retry one blindly after a transport error.

| Step | Call | Body → data |
|---|---|---|
| Upload image | `POST /storage/temporary_token` | `{client: "aws", format: "png"}` → STS keys + `resource_bucket`, `resource_uri`; then S3 put (boto3) |
| Audit image | `POST /audit/image` | `{image: {bucket, key}}` → `{result: "pass"}` |
| Image → model (65 cr at 8K) | `POST /operation/image_to_model` | `{face_limit, quad, visibility: "shareable", model_version: "v3.1-20260211", generate_parts, smart_poly, texture: true, delight: true, pbr: true, texture_alignment: "original_image", texture_quality: "extreme", enable_image_autofix: false, geometry_quality: "detailed", image: {bucket, key, image_audit_result, image_source: "upload"}}` → `{project_id, operation_id}` |
| Progress | `POST /progress` | `{ids: [op...]}` → `[{id, status: running/success/failed, progress, left_time}]` |
| Project detail | `GET /project/detail/v3/<project_id>?locale=en` | `model_url` (meshopt GLB, signed ~minutes), `cover_image[]`, `operator{...}` |
| Retopology (35 cr) | `POST /operation/remesh` | `{bake: true, face_limit: ≤20000, model_version: "default", part_name_list: ["tripo_node_<image_to_model op id>"], project_id, quad: false, smart_poly: true}` |
| Rig check | `POST /operation/pre_rig_check` | `{model_version: "v3.0-20260909", project_id}` → `{riggable, rig_type: "biped" / ...}` (needs ≤ ~20k faces: remesh first) |
| Auto rig (20 cr) | `POST /operation/rigging_model` | `{model_version: "v3.0-20260909", project_id, rig_type}` |
| Preset animation | `POST /operation/retarget_model` | `{animations: ["preset:<rig_type>:<name>"], model_version: "default", project_id, rig_type}` |
| Text → motion (20 cr) | `POST /motion/generate` | `{segments: [{duration_seconds, prompt}]}` → `{task_id}`; poll `POST /motion/get_task {task_id}` → `asset_id` |
| Apply generated motion | `POST /operation/retarget_model` | `{motion_asset_id, model_version: "default", project_id, rig_type}` |
| Export | `POST /operation/export` | `{animate_in_place: false, animations: [retarget op ids], bake_animation_frame: 0, enable_bake_animation: false, export_orientation: "-y", export_vertex_colors: false, fbx_preset: "blender", format: "gltf", model_version: "default", name, pack_uv: false, project_id, texture_packaging: "zip", texture_size: 8192/4096/2048, with_animation: true}` |
| Download export | `POST /operation/download_with_name` | `{file_name, operator_id: <export op>}` → `{model_url}` (plain GLB with skin + animations) |

Biped preset names (humanoid rig): idle, walk, run, run_upstairs, jump, jump_down, fall, dive, flip, turn,
slash, chop, shoot, fire, front_kick_01/02, box_01..03, hit_to_body_01/02, hit_to_head, hit_to_side,
hit_to_stomach, defeat, defeat_02, look_around, lift_heavy, cast_a_spell, standing_relax, swagger, wait,
warm_up, ... (full list: Animate panel). Biped skeleton: 78 joints (BoneRoot, Hip, Pelvis, L/R Thigh/Calf/
Foot/ToeBase + twist bones, Waist, Spine01/02, Neck, Head, L/R Clavicle/Upperarm/Forearm/Hand + fingers).
