import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'skills/crucible/scripts/engine.py'
spec = importlib.util.spec_from_file_location('engine_locator', SCRIPT)
locator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(locator)


class CrucibleEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='crucible-install-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'home'
        self.home.mkdir()
        self.env = {key: value for key, value in os.environ.items() if key != 'CRUCIBLE_ROOT'}
        self.env['HOME'] = str(self.home)

    def fixture(self, target):
        subprocess.run(['bash', '-c', 'source "$1"; make_crucible_fixture "$2"', 'fixture', str(ROOT / 'tests/fixtures/crucible_engine.sh'), str(target)], check=True)
        return target

    def test_home_search_handles_arbitrary_names_and_spaces(self):
        target = self.fixture(self.home / 'my projects/research tool')
        with patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(locator.locate(self.home), target.resolve())

    def test_multiple_checkouts_require_explicit_choice(self):
        self.fixture(self.home / 'one')
        self.fixture(self.home / 'two')
        with patch.dict(os.environ, self.env, clear=True):
            with self.assertRaisesRegex(ValueError, 'Multiple'):
                locator.locate(self.home)

    def test_cached_connection_is_fast_and_stale_path_is_rediscovered(self):
        target = self.fixture(self.home / 'custom')
        state = self.home / '.universal-research-agent-kit/crucible.json'
        state.parent.mkdir()
        state.write_text(json.dumps({'engine_root': str(target), 'python': sys.executable}))
        with patch.dict(os.environ, self.env, clear=True), patch.object(locator.os, 'walk', side_effect=AssertionError('cache should avoid scan')):
            self.assertEqual(locator.locate(self.home), target)
        moved = self.home / 'renamed'
        target.rename(moved)
        with patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(locator.locate(self.home), moved)

    def test_environment_and_cache_backups_are_not_engine_candidates(self):
        self.fixture(self.home / '.cache/core')
        self.fixture(self.home / '.universal-research-agent-kit/backups/core')
        environment = self.home / 'env'
        self.fixture(environment / 'source')
        (environment / 'pyvenv.cfg').write_text('fixture')
        with patch.dict(os.environ, self.env, clear=True):
            self.assertIsNone(locator.locate(self.home))

    def test_installer_downloads_once_and_reuses_existing_checkout(self):
        repository = self.fixture(Path(self.temp.name) / 'source')
        real_git = shutil.which('git')
        subprocess.run([real_git, 'init', str(repository)], check=True, capture_output=True)
        subprocess.run([real_git, '-C', str(repository), 'add', '.'], check=True)
        subprocess.run([real_git, '-C', str(repository), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'Installer fixture'], check=True, capture_output=True)
        mock_bin = Path(self.temp.name) / 'bin'
        mock_bin.mkdir()
        script = mock_bin / 'git'
        script.write_text('#!/bin/bash\nif [ "$1" = clone ]; then\n for arg in "$@"; do target="$arg"; done\n exec "$REAL_GIT" clone --depth 1 "$TEST_REPOSITORY" "$target"\nfi\nexec "$REAL_GIT" "$@"\n')
        script.chmod(0o755)
        env = {**self.env, 'PATH': str(mock_bin) + os.pathsep + self.env['PATH'], 'REAL_GIT': real_git, 'TEST_REPOSITORY': str(repository)}
        command = ['bash', '-c', 'source "$1/install.sh"; kit_init_state; KIT_HEADROOM_PYTHON="$2"; prepare_crucible; kit_release_lock', 'install-test', str(ROOT), sys.executable]
        first = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        engine = self.home / 'Crucible'
        self.assertTrue(locator.valid(engine))
        (engine / 'user-note').write_text('preserve')
        second = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('Reusing Crucible', second.stdout)
        self.assertEqual((engine / 'user-note').read_text(), 'preserve')
        connection = json.loads((self.home / '.universal-research-agent-kit/crucible.json').read_text())
        self.assertEqual(connection['engine_root'], str(engine))
        check = subprocess.run([sys.executable, str(SCRIPT), 'check'], env=env, capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        shutil.rmtree(engine)
        script.write_text('#!/bin/bash\nif [ "$1" = clone ]; then\n for arg in "$@"; do target="$arg"; done\n "$REAL_GIT" clone --depth 1 "$TEST_REPOSITORY" "$target" || exit $?\n mkdir -p "$HOME/Crucible"\n printf preserve-user-data > "$HOME/Crucible/user-file"\n exit 0\nfi\nexec "$REAL_GIT" "$@"\n')
        race_command = list(command)
        race_command[2] = race_command[2].replace('kit_init_state;', 'kit_init_state; kit_enable_rollback;')
        raced = subprocess.run(race_command, env=env, capture_output=True, text=True)
        self.assertNotEqual(raced.returncode, 0)
        self.assertEqual((engine / 'user-file').read_text(), 'preserve-user-data')


if __name__ == '__main__':
    unittest.main()
