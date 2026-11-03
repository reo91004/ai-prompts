"""External BTW package adapter for offline installer orchestration tests.

Compatibility and rendering are tested separately against the real package.
This fixture checks call arguments and materializes observable package state.
"""

import json
import os
from pathlib import Path
import shutil
import sys


def read(path):
    return json.loads(path.read_text())


def check(directory, version):
    assert version == "2.2.5"
    assert read(directory / "UPSTREAM.json") == {"test_fixture": True, "version": "0.1.3", "host": "2.2.5"}
    assert "btw-fixture" in (directory / "dist/tui.js").read_text()
    manifest = read(directory / "package.json")
    for name, expected in manifest["dependencies"].items():
        assert read(directory / "node_modules" / name / "package.json")["version"] == expected


action, *args = sys.argv[1:]
with open(os.environ["TOOLING_TEST_CALLS"], "a") as log:
    log.write("btw-fixture " + action + "\n")
if action == "patch":
    if args[0] == "--check":
        _, directory, version = args
        check(Path(directory), version)
    else:
        source, output, version = args
        source, output = Path(source), Path(output)
        assert version == "2.2.5"
        assert read(source / "package.json") == {"name": "opencode-btw-plus", "version": "0.1.3"}
        assert not list(output.iterdir())
        (output / "dist").mkdir()
        shutil.copyfile(source / "dist/tui.js", output / "dist/tui.js")
        shutil.copyfile(source / "LICENSE", output / "LICENSE")
        manifest = {
            "name": "research-agent-kit-btw-plus-compat", "version": "0.1.3-kit.1",
            "dependencies": {"@opencode/theme": "2.2.5", "string-width": "7.2.0"},
        }
        (output / "package.json").write_text(json.dumps(manifest))
        (output / "package-lock.json").write_text(json.dumps({"name": manifest["name"], "lockfileVersion": 3}))
        (output / "UPSTREAM.json").write_text(json.dumps({"test_fixture": True, "version": "0.1.3", "host": "2.2.5"}))
elif action == "dependencies":
    directory = Path(args[0])
    manifest = read(directory / "package.json")
    assert manifest["name"] == "research-agent-kit-btw-plus-compat"
    for name, version in manifest["dependencies"].items():
        package = directory / "node_modules" / name
        package.mkdir(parents=True)
        (package / "package.json").write_text(json.dumps({"name": name, "version": version}))
else:
    raise AssertionError(action)
