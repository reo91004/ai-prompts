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
# Configuration editors and the SDK probe execute their real code against the
# isolated fixture paths; only external service operations below are simulated.
if not args or args[0] in ("-", "-c") or not args[0].endswith(("/headroom/runtime.py", "/headroom/maintenance.py")):
    os.execv(sys.executable, [sys.executable, "-I", "-B", *args])
script, action, *rest = args
home = Path(os.environ["HOME"])
state = home / ".universal-research-agent-kit/headroom.json"
plugin = home / ".universal-research-agent-kit/tooling/uv-tools/headroom-ai/opencode/_dist"
opencode_fragment = {
    "plugins": [{"package": str(plugin), "options": {"proxyUrl": "http://127.0.0.1:8787"}}],
    "mcp": {"servers": {"headroom": {
        "type": "local",
        "command": [str(home / ".universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python"), "-m", "headroom.cli", "mcp", "serve"],
        "environment": {"HEADROOM_PROXY_URL": "http://127.0.0.1:8787"},
    }}},
}
with open(os.environ["TOOLING_TEST_CALLS"], "a") as log:
    log.write("runtime " + " ".join([action, *rest]) + "\n")
if action in ("environment", "migrate-legacy", "adopt-default", "probe", "inspect", "stop-service", "resume", "opencode-idle"):
    pass
elif action == "pause":
    Path(rest[0]).write_text(json.dumps({"profile": "research-agent-kit", "resume_service": state.exists()}))
elif action == "profile":
    print("research-agent-kit")
elif action == "dependencies":
    if (home / ".broken-headroom").exists():
        sys.exit(1)
elif action == "install-mcp":
    import subprocess
    sys.exit(subprocess.call([str(home / ".universal-research-agent-kit/tooling/bin/headroom"), "mcp", "install", "--agent", rest[0]]))
elif action == "install":
    state.write_text(json.dumps({"profile": "research-agent-kit", "previous_provider": {}}))
    plugin.mkdir(parents=True, exist_ok=True)
    (plugin / "index.js").write_text("export default {id: 'headroom-fixture', setup() {}};\n")
elif action == "opencode-config":
    assert (plugin / "index.js").is_file()
    print(json.dumps(opencode_fragment))
elif action == "check-opencode-config":
    value = json.load(sys.stdin)
    assert opencode_fragment["plugins"][0] in value["plugins"]
    assert value["mcp"]["servers"]["headroom"] == opencode_fragment["mcp"]["servers"]["headroom"]
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
