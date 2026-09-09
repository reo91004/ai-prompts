#!/usr/bin/env python3
"""Opt-in Headroom 0.34.0 loopback integration smoke with synthetic providers.

Run with the installed headroom-ai Python; optionally pass --codex /path/to/codex.
No user configuration or credentials are read. Logs remain in .agent_tmp.
This checks transport/project attribution, not inference or compression quality.
"""
import argparse
import asyncio
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def upstream(port, records):
    from fastapi import FastAPI, Request, WebSocket
    from fastapi.responses import StreamingResponse
    import uvicorn

    app = FastAPI()

    def record(path, headers, body):
        with open(records, "a") as stream:
            stream.write(json.dumps({"path": path, "headers": dict(headers), "body": body}) + "\n")

    def response(body):
        return {"id": "resp_smoke", "object": "response", "created_at": 1,
                "status": "completed", "model": body.get("model", "gpt-4.1"),
                "output": [{"id": "msg_smoke", "type": "message", "role": "assistant",
                            "status": "completed", "content": [{"type": "output_text",
                            "text": "SYNTHETIC_SMOKE_OK", "annotations": []}]}],
                "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}}

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.post("/{path:path}")
    async def post(request: Request, path: str):
        body = await request.json()
        record("/" + path, request.headers, body)
        if path.endswith("messages"):
            return {"id": "msg_smoke", "type": "message", "role": "assistant",
                    "model": body["model"], "content": [{"type": "text", "text": "SYNTHETIC_SMOKE_OK"}],
                    "stop_reason": "end_turn", "stop_sequence": None,
                    "usage": {"input_tokens": 10, "output_tokens": 5}}
        result = response(body)
        if body.get("stream"):
            events = [{"type": "response.created", "response": {**result, "status": "in_progress", "output": []}},
                      {"type": "response.output_item.added", "output_index": 0, "item": result["output"][0]},
                      {"type": "response.output_text.delta", "item_id": "msg_smoke", "output_index": 0,
                       "content_index": 0, "delta": "SYNTHETIC_SMOKE_OK"},
                      {"type": "response.output_item.done", "output_index": 0, "item": result["output"][0]},
                      {"type": "response.completed", "response": result}]
            return StreamingResponse(iter("event: " + e["type"] + "\ndata: " + json.dumps(e) + "\n\n" for e in events),
                                     media_type="text/event-stream")
        return result

    @app.websocket("/v1/responses")
    async def websocket(ws: WebSocket):
        await ws.accept()
        body = await ws.receive_json()
        record("WS /v1/responses", ws.headers, body)
        await ws.send_json({"type": "response.completed", "response": response(body)})
        await ws.close()

    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")


def request(url, body=None, headers=None):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    with opener.open(req, timeout=30) as result:
        return json.load(result)


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_ready(url, process):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Process exited {process.returncode} before {url}")
        try:
            return request(url)
        except (OSError, urllib.error.URLError):
            time.sleep(0.2)
    raise TimeoutError(url)


async def websocket_check(base):
    from websockets.asyncio.client import connect
    async with connect(base.replace("http:", "ws:") + "/v1/responses",
                       additional_headers={"Authorization": "Bearer synthetic-smoke-key",
                                           "X-Headroom-Project": "smoke-websocket"},
                       open_timeout=15, close_timeout=5) as ws:
        await ws.send(json.dumps({"type": "response.create", "model": "gpt-4.1",
                                  "input": "synthetic websocket smoke"}))
        result = json.loads(await asyncio.wait_for(ws.recv(), 30))
        assert result["type"] == "response.completed", result
        assert result["response"]["output"][0]["content"][0]["text"] == "SYNTHETIC_SMOKE_OK"
        return result


def smoke(codex):
    assert importlib.metadata.version("headroom-ai") == "0.34.0"
    root = Path(__file__).resolve().parents[1]
    (root / ".agent_tmp").mkdir(exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="headroom-upstream-", dir=root / ".agent_tmp"))
    print(f"Artifacts: {artifacts}", flush=True)
    home = artifacts / "home"
    home.mkdir()
    codex_home = home / ".codex"
    codex_home.mkdir()
    upstream_port, proxy_port = port(), port()
    base = f"http://127.0.0.1:{proxy_port}"
    target = f"http://127.0.0.1:{upstream_port}"
    env = {"HOME": str(home), "CODEX_HOME": str(codex_home), "PATH": "/usr/bin:/bin",
           "TMPDIR": str(artifacts), "LANG": "en_US.UTF-8", "PYTHONUNBUFFERED": "1",
           "PYTHONDONTWRITEBYTECODE": "1", "HEADROOM_TELEMETRY": "off",
           "HEADROOM_UPDATE_CHECK": "off", "HEADROOM_COMPRESSION_MAX_WORKERS": "2",
           "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
           "OPENAI_TARGET_API_URL": target, "ANTHROPIC_TARGET_API_URL": target,
           "OPENAI_API_KEY": "synthetic-smoke-key", "ANTHROPIC_API_KEY": "synthetic-smoke-key"}
    commands = [[sys.executable, "-B", str(Path(__file__).resolve()), "--serve", str(upstream_port),
                 "--records", str(artifacts / "upstream.jsonl")],
                [sys.executable, "-B", "-m", "headroom.cli", "proxy", "--host", "127.0.0.1",
                 "--port", str(proxy_port), "--mode", "cache", "--no-telemetry", "--no-learn",
                 "--no-embedding-server", "--no-rate-limit", "--compressor", "smart_crusher"]]
    metadata = {"scope": "real Headroom and optional Codex; synthetic loopback provider responses",
                "seed": None, "python": sys.version, "platform": platform.platform(),
                "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "versions": {name: importlib.metadata.version(name) for name in
                             ("headroom-ai", "fastapi", "uvicorn", "websockets")},
                "commands": commands, "environment": env, "memory": "disabled (no --memory)",
                "ports": {"upstream": upstream_port, "proxy": proxy_port}}
    (artifacts / "run.json").write_text(json.dumps(metadata, indent=2))
    processes, logs = [], []
    try:
        for name, command, url in zip(("upstream", "headroom"), commands,
                                      (target + "/health", base + "/readyz")):
            log = open(artifacts / (name + ".log"), "w")
            logs.append(log)
            process = subprocess.Popen(command, env=env, cwd=home, stdout=log, stderr=subprocess.STDOUT)
            processes.append(process)
            wait_ready(url, process)
        health = request(base + "/health")
        assert health["ready"] and health["version"] == "0.34.0", health
        assert not health["checks"]["memory"]["enabled"], health
        (artifacts / "health.json").write_text(json.dumps(health, indent=2))
        def send(provider):
            if provider == "openai":
                path, body = "/v1/responses", {"model": "gpt-4.1", "input": "synthetic HTTP smoke"}
            else:
                path, body = "/v1/messages", {"model": "claude-sonnet-4-20250514", "max_tokens": 16,
                                              "messages": [{"role": "user", "content": "synthetic HTTP smoke"}]}
            return request(base + path, body, {"Authorization": "Bearer synthetic-smoke-key",
                           "x-api-key": "synthetic-smoke-key", "anthropic-version": "2023-06-01",
                           "X-Headroom-Project": "smoke-" + provider})
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(send, ("openai", "anthropic")))
        assert responses[0]["output"][0]["content"][0]["text"] == "SYNTHETIC_SMOKE_OK", responses[0]
        assert responses[1]["content"][0]["text"] == "SYNTHETIC_SMOKE_OK", responses[1]
        responses.append(asyncio.run(websocket_check(base)))
        (artifacts / "responses.json").write_text(json.dumps(responses, indent=2))
        expected_projects = {"smoke-openai", "smoke-anthropic", "smoke-websocket"}
        if codex:
            config = codex_home / "config.toml"
            config.write_text('model = "gpt-4.1"\nmodel_provider = "headroom"\n'
                              '[model_providers.headroom]\nname = "Headroom smoke"\n'
                              f'base_url = "{base}/v1"\nwire_api = "responses"\n'
                              'env_key = "OPENAI_API_KEY"\nsupports_websockets = false\n')
            before = config.read_bytes()
            env["PATH"] = str(Path(codex).parent) + ":/usr/bin:/bin"
            command = [codex, "--config", 'model_providers.headroom.http_headers.X-Headroom-Project="smoke-codex"',
                       "exec", "--skip-git-repo-check", "--ephemeral", "--json", "Return SYNTHETIC_SMOKE_OK only."]
            metadata["codex_command"] = command
            metadata["codex_version"] = subprocess.check_output([codex, "--version"], env=env, text=True, stderr=subprocess.STDOUT).strip()
            (artifacts / "run.json").write_text(json.dumps(metadata, indent=2))
            with open(artifacts / "codex.log", "w") as log:
                result = subprocess.run(command, cwd=home, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=60)
            assert result.returncode == 0, f"Codex exit {result.returncode}; see codex.log"
            events = [json.loads(line) for line in (artifacts / "codex.log").read_text().splitlines()
                      if line.startswith("{")]
            assert any(e.get("item", {}).get("text") == "SYNTHETIC_SMOKE_OK" for e in events), events
            assert any(e["type"] == "turn.completed" for e in events), events
            assert config.read_bytes() == before, "Codex changed provider config"
            expected_projects.add("smoke-codex")
        stats = request(base + "/stats-lifetime")
        (artifacts / "stats-lifetime.json").write_text(json.dumps(stats, indent=2))
        assert expected_projects <= stats["projects"].keys(), stats
        records = [json.loads(line) for line in (artifacts / "upstream.jsonl").read_text().splitlines()]
        assert {"/v1/responses", "/v1/messages", "WS /v1/responses"} <= {r["path"] for r in records}
        assert all(not any(k.startswith("x-headroom-") for k in r["headers"]) for r in records), records
        summary = {"status": "passed", "projects": sorted(expected_projects),
                   "upstream_routes": [r["path"] for r in records], "internal_headers_stripped": True,
                   "codex": bool(codex), "scope": metadata["scope"]}
        (artifacts / "summary.json").write_text(json.dumps(summary, indent=2))
        print(json.dumps(summary, indent=2))
    finally:
        for process in reversed(processes):
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        for log in logs:
            log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex")
    parser.add_argument("--serve", type=int)
    parser.add_argument("--records")
    args = parser.parse_args()
    if args.serve:
        upstream(args.serve, args.records)
    else:
        smoke(args.codex)
