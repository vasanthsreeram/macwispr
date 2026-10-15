#!/usr/bin/env python3
"""Localhost polish sidecar for in-app testing of the Sotto LoRA adapter.

Loads base + adapter ONCE, serves POST /polish {"text": "..."} -> {"polished": "..."}.
MacWispr's `.localMLX` polish provider calls this at http://127.0.0.1:8848.

Run:
  cd bench && source .venv-polish/bin/activate
  python polish_finetune/polish_server.py            # default adapter sotto-lc-ft-clean
  python polish_finetune/polish_server.py --adapter polish_finetune/adapters/sotto-lc-ft-v2
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
MODEL = "juanquivilla/sotto-cleanup-lfm25-350m-mlx-5bit"

_MODEL = None
_TOK = None
_GEN = None
_SAMPLER = None


def load(adapter: Path):
    global _MODEL, _TOK, _GEN, _SAMPLER
    from mlx_lm import generate, load as mlx_load
    from mlx_lm.sample_utils import make_sampler
    print(f"[sidecar] loading {MODEL} + {adapter.name} ...", file=sys.stderr)
    _MODEL, _TOK = mlx_load(MODEL, adapter_path=str(adapter))
    _GEN = generate
    _SAMPLER = make_sampler(temp=0.0)
    # Warmup
    _GEN(_MODEL, _TOK, prompt="### Input:\nhello there\n\n### Output:\n",
         max_tokens=8, sampler=_SAMPLER, verbose=False)
    print("[sidecar] ready", file=sys.stderr)


def clean_out(s: str) -> str:
    s = s.strip()
    for stop in ("### Input:", "### Output:", "\n###"):
        i = s.find(stop)
        if i != -1:
            s = s[:i].strip()
    return s


def polish(text: str) -> tuple[str, float]:
    raw = text.strip()
    if len(raw.split()) < 3:
        return raw, 0.0
    prompt = f"### Input:\n{raw}\n\n### Output:\n"
    mt = min(200, max(32, len(raw.split()) * 4))
    t0 = time.perf_counter()
    out = _GEN(_MODEL, _TOK, prompt=prompt, max_tokens=mt, sampler=_SAMPLER, verbose=False)
    dt = time.perf_counter() - t0
    return clean_out(out if isinstance(out, str) else str(out)) or raw, dt


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quieter
        pass

    def _send(self, code: int, payload: dict):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/polish":
            self._send(404, {"error": "not found"})
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(n) or b"{}")
            text = data.get("text", "")
            out, dt = polish(text)
            print(f"[sidecar] {dt*1000:.0f}ms | {text[:50]!r} -> {out[:50]!r}",
                  file=sys.stderr)
            self._send(200, {"polished": out, "latency_ms": round(dt * 1000, 1)})
        except Exception as e:  # never crash the sidecar
            self._send(500, {"error": str(e)})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", type=Path, default=ROOT / "adapters" / "sotto-lc-ft-clean")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8848)
    args = ap.parse_args()
    load(args.adapter)
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"[sidecar] listening on http://{args.host}:{args.port}  (POST /polish)",
          file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
