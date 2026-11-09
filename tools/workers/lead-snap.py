"""Lead monitor helper: one line `job:status:attempts` per M78 job that is done / failed / stopped."""
import json
import sys

rows = [json.loads(line) for line in sys.stdin if line.strip().startswith("{")]
finished = ["%s:%s:%s" % (d["job"], d["status"], d.get("attempts")) for d in rows
            if d.get("status") in ("done", "failed", "stopped")]
print("\n".join(sorted(finished)))
