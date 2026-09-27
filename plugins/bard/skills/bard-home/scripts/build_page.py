#!/usr/bin/env python3
"""
Build the BARD home page from the bundled template.

The published page loads live data from BARD itself each time it is opened.
The snapshot baked in here is only a fallback, shown when live data can't load.

Usage:
    python build_page.py                                  # bundled snapshot
    python build_page.py --result /path/to/result.txt     # fresh snapshot from an execute_sql result
    python build_page.py --server "Bonhams-BARD" --yellow "#FFD100" --out /mnt/user-data/outputs/bard-home.html

--result accepts the raw text an execute_sql call returned (including the
<untrusted-data-...> wrapper), the JSON array inside it, or the bare model object.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "assets"
DEFAULT_PROJECT = "yxnechonpwuhhsatstgj"
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def extract_model(text: str) -> dict:
    """Pull the model object out of whatever form the query result arrived in."""
    text = text.strip()
    # Outer {"result": "..."} envelope some clients show
    if text.startswith("{") and '"result"' in text[:40]:
        try:
            outer = json.loads(text)
            if isinstance(outer.get("result"), str):
                text = outer["result"]
        except json.JSONDecodeError:
            pass
    m = re.search(r"<untrusted-data-[^>]*>\s*([\s\S]*?)\s*</untrusted-data-", text)
    body = json.loads(m.group(1) if m else text)
    if isinstance(body, list):
        body = body[0] if body else {}
    model = body.get("model", body) if isinstance(body, dict) else None
    if isinstance(model, str):  # some clients return the json column as a string
        model = json.loads(model)
    if not isinstance(model, dict) or model.get("v") != 1 or not isinstance(model.get("meta"), list):
        raise ValueError("Result doesn't look like the BARD page model (expected v=1 with a meta list).")
    return model


def js(value) -> str:
    """JSON for safe embedding inside a <script> block."""
    return json.dumps(value, ensure_ascii=False).replace("</", "<\\/")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--result", help="File holding an execute_sql result for assets/model.sql (optional)")
    ap.add_argument("--server", default="Supabase", help="Display name of the viewer's claude.ai Supabase connector (not a plugin connector)")
    ap.add_argument("--project", default=DEFAULT_PROJECT, help="Supabase project id for BARD")
    ap.add_argument("--yellow", default="#FFD100", help="Accent yellow for buttons and selected states")
    ap.add_argument("--out", default="/mnt/user-data/outputs/bard-home.html")
    args = ap.parse_args()

    if not HEX.match(args.yellow):
        print(f"--yellow must be a 6-digit hex colour like #FFD100 (got {args.yellow!r})", file=sys.stderr)
        return 2

    if args.result:
        model = extract_model(Path(args.result).read_text(encoding="utf-8"))
        source = f"fresh result ({args.result})"
    else:
        model = json.loads((ASSETS / "snapshot.json").read_text(encoding="utf-8"))
        source = "bundled snapshot"

    template = (ASSETS / "template.html").read_text(encoding="utf-8")
    sql = (ASSETS / "model.sql").read_text(encoding="utf-8").strip()

    replacements = {
        "__SNAPSHOT__": js(model),
        "__MODEL_SQL__": js(sql),
        "__PROJECT_ID__": js(args.project),
        "__SERVER__": js(args.server),
        "__YELLOW__": args.yellow.upper(),
    }
    for key, val in replacements.items():
        if key not in template:
            print(f"Template is missing placeholder {key}", file=sys.stderr)
            return 1
        template = template.replace(key, val)

    left = re.findall(r"__[A-Z_]+__", template)
    if left:
        print(f"Unfilled placeholders: {sorted(set(left))}", file=sys.stderr)
        return 1

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(template, encoding="utf-8")

    generated = str(model.get("generated_at", ""))[:10]
    age_days = None
    try:
        age_days = (datetime.now(timezone.utc).date() - datetime.fromisoformat(generated).date()).days
    except ValueError:
        pass
    print(json.dumps({
        "out": str(out),
        "bytes": out.stat().st_size,
        "snapshot_source": source,
        "snapshot_date": generated,
        "snapshot_age_days": age_days,
        "server": args.server,
        "project": args.project,
        "yellow": args.yellow.upper(),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
