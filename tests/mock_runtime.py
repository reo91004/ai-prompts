"""External Python/runtime fixture for installer orchestration tests only.

The real runtime adapter has separate behavioral tests. This fixture keeps the
installer suites from reaching the user's launchd/systemd or listening ports.
"""
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
while args and args[0] in ("-I", "-B"):
    args.pop(0)
script, action, *rest = args
home = Path(os.environ["HOME"])
state = home / ".universal-research-agent-kit/headroom.json"
with open(os.environ["TOOLING_TEST_CALLS"], "a") as log:
    log.write("runtime " + " ".join([action, *rest]) + "\n")
if action in ("environment", "migrate-legacy", "adopt-default", "probe", "inspect", "stop-service", "resume"):
    pass
elif action == "pause":
    Path(rest[0]).write_text(json.dumps({"profile": "research-agent-kit", "resume_service": state.exists()}))
elif action == "profile":
    print("research-agent-kit")
elif action == "dependencies":
    if (home / ".broken-headroom").exists():
        sys.exit(1)
elif action == "install":
    state.write_text(json.dumps({"profile": "research-agent-kit", "previous_provider": {}}))
elif action == "check":
    if not state.is_file() or (home / ".broken-service").exists():
        sys.exit(1)
elif action == "remove":
    state.unlink(missing_ok=True)
elif action == "launch":
    import subprocess
    sys.exit(subprocess.call(rest))
elif action != "claude-direct-check":
    raise AssertionError(action)
