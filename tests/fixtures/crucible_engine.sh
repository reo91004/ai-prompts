make_crucible_fixture() {
  mkdir -p "$1/bin" "$1/crucible"
  printf '%s\n' 'name = "crucible-research-loop"' > "$1/pyproject.toml"
  printf '%s\n' '# Fixture package' > "$1/crucible/cli.py"
  printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'print("0.1.0" if "--version" in sys.argv else "\\n".join(sys.argv[1:]))' > "$1/bin/crucible"
  chmod +x "$1/bin/crucible"
}
