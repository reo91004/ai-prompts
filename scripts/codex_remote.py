"""Enable native Remote Control, recovering one verified unmanaged listener."""

import ctypes
import json
import os
from pathlib import Path
import signal
import socket
import stat
import struct
import subprocess
import sys
import time
from dataclasses import dataclass


UNMANAGED = "Error: app server is running but is not managed by codex app-server daemon"
RETRY = "Disconnect this host's SSH connection in the Mac Codex app, then rerun sh install.sh --enable-codex-remote-control."


@dataclass(frozen=True)
class Process:
    pid: int
    uid: int
    ppid: int
    start: str
    executable: str
    argv: tuple


def process(pid):
    if sys.platform == "linux":
        root = Path(f"/proc/{pid}")
        fields = (root / "stat").read_text().rsplit(")", 1)[1].split()
        if fields[0] == "Z":
            raise ProcessLookupError(pid)
        return Process(pid, root.stat().st_uid, int(fields[1]), fields[19],
                       os.readlink(root / "exe"),
                       tuple(os.fsdecode(arg) for arg in (root / "cmdline").read_bytes().split(b"\0")[:-1]))
    if sys.platform != "darwin":
        raise RuntimeError("Automatic Codex recovery supports macOS and Linux only.")
    result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "uid=,ppid=,stat=,lstart="],
                            capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    if not result.stdout.strip():
        raise ProcessLookupError(pid)
    uid, ppid, state, start = result.stdout.strip().split(None, 3)
    if state.startswith("Z"):
        raise ProcessLookupError(pid)
    libc = ctypes.CDLL(None, use_errno=True)
    path = ctypes.create_string_buffer(4096)
    if libc.proc_pidpath(pid, path, len(path)) <= 0:
        raise OSError(ctypes.get_errno(), "Cannot inspect the Codex executable.")
    mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t()
    if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0:
        raise OSError(ctypes.get_errno(), "Cannot inspect Codex arguments.")
    args = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, args, ctypes.byref(size), None, 0) != 0:
        raise OSError(ctypes.get_errno(), "Cannot inspect Codex arguments.")
    argc = struct.unpack_from("i", args.raw)[0]
    # KERN_PROCARGS2: argc, executable path, NUL padding, argv, environment.
    argv = args.raw[4:].split(b"\0", 1)[1].lstrip(b"\0").split(b"\0")[:argc]
    return Process(pid, int(uid), int(ppid), start, os.fsdecode(path.value),
                   tuple(os.fsdecode(arg) for arg in argv))


def socket_owner(path):
    before = path.lstat()
    if not stat.S_ISSOCK(before.st_mode) or before.st_uid != os.getuid():
        raise RuntimeError("The Codex control socket is not owned by this user.")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
        peer.settimeout(2)
        peer.connect(str(path))
        if sys.platform == "linux":
            pid, uid, _ = struct.unpack("3i", peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        elif sys.platform == "darwin":
            pid = struct.unpack("i", peer.getsockopt(0, 2, 4))[0]  # LOCAL_PEERPID
            uid_value, gid_value = ctypes.c_uint(), ctypes.c_uint()
            if ctypes.CDLL(None).getpeereid(peer.fileno(), ctypes.byref(uid_value), ctypes.byref(gid_value)):
                raise OSError("Cannot inspect the Codex socket user.")
            uid = uid_value.value
        else:
            raise RuntimeError("Cannot inspect the Codex socket on this platform.")
    after = path.lstat()
    if (before.st_dev, before.st_ino, before.st_uid) != (after.st_dev, after.st_ino, after.st_uid):
        raise RuntimeError("The Codex control socket changed during inspection.")
    owner = process(pid)
    if uid != os.getuid() or owner.uid != uid:
        raise RuntimeError("The Codex socket process belongs to another user.")
    return owner


def known_listener(owner, home, binary):
    executable = Path(owner.executable)
    standalone = home / ".codex/packages/standalone"
    native = executable == binary.resolve() or (
        executable.is_relative_to(standalone) and executable.name == "codex"
        and executable.parent.name in ("bin", "codex"))
    # npm's launcher is node; only its native vendor payload may own this socket.
    npm = ((executable.is_relative_to(home) or executable.is_relative_to("/usr/local/lib/node_modules")
            or executable.is_relative_to("/usr/lib/node_modules"))
           and "/node_modules/@openai/codex/" in str(executable) and "/vendor/" in str(executable)
           and str(executable).endswith(("/codex/codex", "/bin/codex")))
    if not (native or npm) or not owner.argv:
        return False
    args = list(owner.argv[1:])
    while len(args) >= 2 and args[0] in ("-c", "--config"):
        args = args[2:]
    # Only the SSH Unix transport is eligible, never stdio or custom listeners.
    return args == ["app-server", "--listen", "unix://"]


def parent_pid(pid):
    # An SSH ancestor can belong to root: its executable/argv are unnecessary
    # for ancestry and may be unreadable by the current user.
    if sys.platform == "linux":
        return int(Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[1])
    return int(subprocess.check_output(["/bin/ps", "-p", str(pid), "-o", "ppid="], text=True))


def native(binary, *args):
    return subprocess.run([str(binary), *args], capture_output=True, text=True)


def document(result, action):
    if result.returncode:
        if result.stderr:
            print(result.stderr.rstrip(), file=sys.stderr)
        raise RuntimeError(f"Codex {action} failed; the verified kit remains installed.")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"Codex returned invalid JSON during {action}.") from None
    if not isinstance(data, dict):
        raise RuntimeError(f"Codex returned an invalid response during {action}.")
    return data


def version(binary):
    return document(native(binary, "app-server", "daemon", "version"), "daemon inspection")


def verify(binary, home):
    data = version(binary)
    if data.get("status") != "running" or data.get("backend") != "pid":
        raise RuntimeError("Codex managed daemon is not running; run codex remote-control start.")
    settings = home / ".codex/app-server-daemon/settings.json"
    preferences = json.loads(settings.read_text())
    if not isinstance(preferences, dict) or preferences.get("remoteControlEnabled") is not True:
        raise RuntimeError("Codex daemon remote-control preference is disabled.")


def recover(binary, home, wait_seconds=30):
    path = home / ".codex/app-server-control/app-server-control.sock"
    owner = socket_owner(path)
    if not known_listener(owner, home, binary):
        raise RuntimeError("The existing Codex listener has an unrecognized executable or launch command. " + RETRY)
    data = version(binary)
    # Only this running server version's SIGHUP contract has been source-verified.
    if data.get("status") != "running" or data.get("backend") is not None or data.get("appServerVersion") != "0.153.4":
        raise RuntimeError("The existing server's unmanaged status or graceful shutdown version is unverified. Finish its work and stop it from its original session.")
    ancestor = os.getpid()
    while ancestor > 1:
        if ancestor == owner.pid:
            raise RuntimeError("Run Remote Control activation from an external terminal after this Codex task finishes.")
        ancestor = parent_pid(ancestor)
    # pidfd prevents PID reuse between the final check and the signal on Linux.
    descriptor = None
    try:
        if sys.platform == "linux":
            descriptor = os.pidfd_open(owner.pid)
        if socket_owner(path) != owner:
            raise RuntimeError("The Codex listener changed during inspection. " + RETRY)
        print("Requesting graceful shutdown of the verified Codex listener; waiting up to 30 seconds for active work.", flush=True)
        if descriptor is not None:
            signal.pidfd_send_signal(descriptor, signal.SIGHUP)
        else:
            # macOS has no pidfd; identity is rechecked immediately before kill.
            os.kill(owner.pid, signal.SIGHUP)
    finally:
        if descriptor is not None:
            os.close(descriptor)
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        try:
            # Reparenting during SSH disconnect does not end this process.
            if process(owner.pid).start != owner.start:
                return
        except (ProcessLookupError, FileNotFoundError):
            return
        time.sleep(0.25)
    raise RuntimeError("The Codex server is still finishing work; no forced stop was sent. It may exit later. Wait for the task to finish, then retry activation.")


def enable(binary, home):
    result = native(binary, "remote-control", "start", "--json")
    if result.returncode and UNMANAGED in result.stderr.splitlines():
        recover(binary, home)
        result = native(binary, "remote-control", "start", "--json")
        if result.returncode and UNMANAGED in result.stderr.splitlines():
            raise RuntimeError("An unmanaged Codex server reappeared. No further process was signalled. " + RETRY)
    data = document(result, "Remote Control activation")
    status = data.get("status")
    if status not in ("connected", "connecting"):
        raise RuntimeError("Codex did not report connected/connecting Remote Control.")
    verify(binary, home)
    print("Codex Remote Control: " + status)
    if status == "connecting":
        print("Daemon started; relay connection is pending. Check authentication/network before pairing.")


if __name__ == "__main__":
    try:
        binary, home = Path(sys.argv[2]), Path.home()
        if os.environ.get("CODEX_HOME") not in (None, "", str(home / ".codex")):
            raise RuntimeError("Custom CODEX_HOME is not supported by this installer.")
        if sys.argv[1] == "enable":
            enable(binary, home)
        elif sys.argv[1] == "verify":
            verify(binary, home)
            print("Codex remote host: managed daemon running, Remote Control enabled (pairing/relay not verified).")
        else:
            raise RuntimeError("Expected enable or verify.")
    except (RuntimeError, OSError, ValueError) as error:
        sys.exit(str(error))
