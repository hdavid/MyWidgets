"""Inject/restore Grafana tokens in properties.xml at build time.

Tokens live in garmin/local-tokens.json (gitignored, chmod 600):
    {"moutiers": "...", "bernerie": "..."}

Usage (build.sh drives this):
    bake_tokens.py inject    # backs up properties.xml, fills token defaults
    bake_tokens.py restore   # puts the clean file back
The baked values become the app's property defaults, so the widget works
out of the box; the settings screen still allows overriding per watch.
"""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.join(HERE, "..", "resources", "settings", "properties.xml")
BACKUP = PROPS + ".orig"
TOKENS = os.path.join(HERE, "..", "..", "local-tokens.json")

MARKERS = {
    "moutiers": '<property id="tokenMoutiers" type="string">',
    "bernerie": '<property id="tokenBernerie" type="string">',
}

if sys.argv[1] == "inject":
    if not os.path.exists(TOKENS):
        print("no garmin/local-tokens.json — building with empty tokens "
              "(enter them in Garmin Connect)")
        sys.exit(0)
    tokens = json.load(open(TOKENS))
    src = open(PROPS).read()
    for key, marker in MARKERS.items():
        if marker + "</property>" not in src:
            print(f"properties.xml: expected empty default for {key} — aborting")
            sys.exit(1)
        src = src.replace(marker + "</property>",
                          marker + tokens[key] + "</property>")
    shutil.copy(PROPS, BACKUP)
    with open(PROPS, "w") as f:
        f.write(src)
    print("tokens baked into property defaults")
elif sys.argv[1] == "restore":
    if os.path.exists(BACKUP):
        shutil.move(BACKUP, PROPS)
        print("properties.xml restored")
