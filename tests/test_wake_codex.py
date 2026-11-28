"""Retry and confirmation logic of the Codex completion wake; no real Codex calls."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wake_codex", ROOT / "skills/resource-aware-orchestration/scripts/wake_codex.py")
wake_codex = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake_codex)
THREAD = "01a210dd-bb6f-7ff3-96d3-e353f196871f"


def event(kind, **fields):
    return json.dumps({"type": "event_msg", "payload": {"type": kind, **fields}}) + "\n"


class FakeCodex:
    """Plays the daemon: each queued message becomes one turn with the scripted outcome."""

    def __init__(self, home, outcomes):
        self.path = home / ".codex/sessions/2026/11/25" / f"rollout-2026-11-25T12-00-00-{THREAD}.jsonl"
        self.path.parent.mkdir(parents=True)
        self.path.write_text(event("task_complete", last_agent_message="READY", error=None))
        self.outcomes, self.calls = list(outcomes), []

    def __call__(self, *args):
        self.calls.append(args)
        if args[:3] == ("app-server", "daemon", "version"):
            return 0, "{}"
        if args[0] != "queue":
            return 0, ""
        outcome = self.outcomes.pop(0)
        if outcome == "no-resume":
            return 0, f"Warning: message was queued, but could not resume thread {THREAD}\nQueued message x"
        writer = outcome.startswith("writer")
        if writer:
            # An open TUI holds the thread; it delivers the message itself (or, while busy, not yet).
            outcome = "done" if outcome == "writer" else "never"
        with self.path.open("a") as handle:
            if outcome != "never":
                handle.write(event("task_started", turn_id="t"))
                handle.write(json.dumps({"type": "response_item", "payload": {"type": "message", "content": args[4]}}) + "\n")
            if outcome == "done":
                handle.write(event("task_complete", last_agent_message="recorded", error=None))
            elif outcome == "error":
                handle.write(event("task_complete", last_agent_message=None, error={"message": "refresh token has expired"}))
            elif outcome == "aborted":
                handle.write(event("turn_aborted", reason="interrupted"))
        if writer:
            return 0, (f"Queued message x for thread {THREAD}.\nWarning: message was queued, but could not resume "
                       f"thread {THREAD}: thread/resume failed: thread {THREAD} already has an active writer (code -32600)")
        return 0, "Queued message x"


class WakeTests(unittest.TestCase):
    def run_wake(self, outcomes, waited=False):
        with tempfile.TemporaryDirectory() as directory:
            home, run_dir = Path(directory) / "home", Path(directory) / "a1"
            run_dir.mkdir()
            (run_dir / "codex_thread").write_text(THREAD + "\n")
            (run_dir / "exit_code").write_text("3\n")
            fake, sleeps, now = FakeCodex(home, outcomes), [], [0.0]
            if waited:
                # The session's own turn polled wait_run.sh and read its report.
                report = json.dumps({"type": "response_item", "payload": {
                    "type": "function_call_output", "output": f"run ended: exit_code=3 dir={run_dir}"}})
                with fake.path.open("a") as handle:
                    handle.write(report + "\n")

            def sleep(seconds):
                sleeps.append(seconds)
                now[0] += seconds

            with mock.patch.dict(os.environ, {"HOME": str(home)}), mock.patch.object(wake_codex, "codex", fake), \
                    mock.patch.object(wake_codex, "log", lambda text: None):
                status = wake_codex.wake(run_dir, sleep=sleep, clock=lambda: now[0])
            queued = [call[4] for call in fake.calls if call[0] == "queue"]
            return status, sleeps, queued

    def test_first_wake_completes_without_retry(self):
        status, sleeps, queued = self.run_wake(["done"])
        self.assertEqual((status, sleeps, len(queued)), (0, [wake_codex.GRACE], 1))
        self.assertIn("exit_code=3", queued[0])
        self.assertIn("already handled", queued[0])

    def test_failed_resume_and_error_turn_are_retried_with_backoff(self):
        status, sleeps, queued = self.run_wake(["no-resume", "error", "done"])
        self.assertEqual(status, 0)
        self.assertEqual(sleeps, [wake_codex.GRACE, 60, 300])
        self.assertEqual(len(set(queued)), 3, "each attempt needs its own token")

    def test_unpicked_message_is_resent_after_the_pickup_limit(self):
        status, sleeps, _ = self.run_wake(["never", "done"])
        self.assertEqual(status, 0)
        self.assertEqual(sum(1 for s in sleeps if s == wake_codex.POLL), wake_codex.PICKUP_LIMIT // wake_codex.POLL + 1)

    def test_open_tui_delivers_the_single_message(self):
        status, sleeps, queued = self.run_wake(["writer"])
        self.assertEqual((status, sleeps, len(queued)), (0, [wake_codex.GRACE], 1))

    def test_busy_open_tui_is_waited_for_instead_of_resent(self):
        status, sleeps, queued = self.run_wake(["writer-busy", "done"])
        self.assertEqual((status, len(queued)), (0, 2))
        self.assertGreater(sum(1 for s in sleeps if s == wake_codex.POLL), wake_codex.WRITER_PICKUP_LIMIT // wake_codex.POLL)

    def test_no_wake_when_the_session_already_read_wait_run(self):
        status, sleeps, queued = self.run_wake([], waited=True)
        self.assertEqual((status, sleeps, queued), (0, [wake_codex.GRACE], []))

    def test_user_interruption_is_not_retried(self):
        status, _, queued = self.run_wake(["aborted"])
        self.assertEqual((status, len(queued)), (0, 1))

    def test_persistent_failure_gives_up_after_the_schedule(self):
        status, sleeps, queued = self.run_wake(["error"] * len(wake_codex.RETRY_DELAYS))
        self.assertEqual(status, 1)
        self.assertEqual(len(queued), len(wake_codex.RETRY_DELAYS))
        self.assertGreaterEqual(sum(sleeps), 20 * 3600)

    def test_daemon_is_started_when_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            home, run_dir = Path(directory) / "home", Path(directory) / "a1"
            run_dir.mkdir()
            (run_dir / "codex_thread").write_text(THREAD)
            (run_dir / "exit_code").write_text("0")
            fake = FakeCodex(home, ["done"])
            original = fake.__call__

            def no_daemon(*args):
                if args[:3] == ("app-server", "daemon", "version"):
                    fake.calls.append(args)
                    return 1, "failed to connect"
                return original(*args)

            with mock.patch.dict(os.environ, {"HOME": str(home)}), mock.patch.object(wake_codex, "codex", no_daemon), \
                    mock.patch.object(wake_codex, "log", lambda text: None):
                self.assertEqual(wake_codex.wake(run_dir, sleep=lambda s: None), 0)
            self.assertIn(("app-server", "daemon", "start"), fake.calls)


if __name__ == "__main__":
    unittest.main()
