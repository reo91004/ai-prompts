"""Find a source checkout under HOME and run it with the kit's Python."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def valid(root):
    root = Path(root)
    try:
        return ((root / 'bin/crucible').is_file() and (root / 'crucible/cli.py').is_file()
                and bool(re.search(r'''(?m)^name\s*=\s*['"]crucible-research-loop['"]''', (root / 'pyproject.toml').read_text())))
    except (OSError, UnicodeError):
        return False


def connection(home):
    path = Path(home) / '.universal-research-agent-kit/crucible.json'
    return json.loads(path.read_text()) if path.is_file() else {}


def locate(home):
    explicit = os.environ.get('CRUCIBLE_ROOT')
    if explicit:
        if not valid(explicit):
            raise ValueError('CRUCIBLE_ROOT does not identify a Crucible checkout')
        return Path(explicit).resolve()
    saved = connection(home).get('engine_root')
    if saved and valid(saved):
        return Path(saved).resolve()
    matches = set()
    skipped = {'.git', '.cache', '.Trash', '__pycache__', 'node_modules', '.venv', 'venv', '.crucible', '.plans', '.universal-research-agent-kit'}
    for directory, dirs, files in os.walk(home, followlinks=False):
        if 'conda-meta' in dirs or 'pyvenv.cfg' in files:
            dirs[:] = []
            continue
        if 'pyproject.toml' in files and 'bin' in dirs and 'crucible' in dirs and valid(directory):
            matches.add(Path(directory).resolve())
            dirs[:] = []
        else:
            dirs[:] = [name for name in dirs if name not in skipped]
    if len(matches) > 1:
        raise ValueError('Multiple Crucible checkouts found; set CRUCIBLE_ROOT:\n' + '\n'.join(map(str, sorted(matches))))
    return next(iter(matches)) if matches else None


def main():
    home = Path.home()
    action = sys.argv[1]
    if action == 'check':
        saved = connection(home)
        if not saved or not valid(saved['engine_root']):
            raise ValueError('Crucible connection is missing or stale; rerun install.sh')
        subprocess.run([saved['python'], '-I', '-B', str(Path(saved['engine_root']) / 'bin/crucible'), '--version'], check=True, timeout=15)
        return 0
    if action == 'connect':
        root = Path(sys.argv[2]).resolve()
        if not valid(root):
            raise ValueError('Invalid Crucible checkout: ' + str(root))
        subprocess.run([sys.executable, '-I', '-B', str(root / 'bin/crucible'), '--version'], check=True, timeout=15)
        Path(sys.argv[3]).write_text(json.dumps({'engine_root': str(root), 'python': sys.executable}, indent=2) + '\n')
        return 0
    root = locate(home)
    if action == 'find':
        if root is None:
            return 1
        print(root)
        return 0
    if action != 'run':
        raise ValueError('Unknown engine locator action')
    if root is None:
        raise ValueError('Crucible was not found under HOME; run ai-prompts/install.sh')
    saved = connection(home)
    python = saved.get('python', sys.executable) if saved.get('engine_root') == str(root) else sys.executable
    os.execv(python, [python, str(root / 'bin/crucible'), *sys.argv[2:]])


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
