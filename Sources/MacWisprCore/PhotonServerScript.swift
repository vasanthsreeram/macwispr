import Foundation

/// The Python source for the Photon sidecar server.
///
/// Photon (kestrel) reports hostname and usage counts to api.moondream.ai with
/// no opt-out, so the telemetry guard runs before anything imports moondream.
public enum PhotonServerScript {
    /// Disables Photon vendor telemetry. Each patch is isolated so the DNS
    /// block still applies if kestrel internals change.
    public static let telemetryGuard = #"""
    # --- MacWispr telemetry guard: no egress to moondream.ai ---
    import socket as _mw_socket
    _mw_real_getaddrinfo = _mw_socket.getaddrinfo
    def _mw_getaddrinfo(host, *args, **kwargs):
        h = host.decode("ascii", "ignore") if isinstance(host, bytes) else host
        if isinstance(h, str):
            h = h.lower().rstrip(".")
            if h == "moondream.ai" or h.endswith(".moondream.ai"):
                raise _mw_socket.gaierror(_mw_socket.EAI_NONAME, "blocked by MacWispr")
        return _mw_real_getaddrinfo(host, *args, **kwargs)
    _mw_socket.getaddrinfo = _mw_getaddrinfo
    try:
        import kestrel.photon as _mw_photon
        async def _mw_false(self, *a, **k): return False
        async def _mw_none(self, *a, **k): return None
        def _mw_noop(self, *a, **k): return None
        _mw_cls = _mw_photon.PhotonReporter
        _mw_cls.validate_api_key = _mw_false
        _mw_cls.shutdown = _mw_none
        _mw_cls._flush_window = _mw_none
        _mw_cls.start = _mw_noop
        _mw_cls.record_success = _mw_noop
        _mw_cls.record_error = _mw_noop
        try:
            import sys as _mw_sys
            _mw_core = _mw_sys.modules.get("kestrel.engine.core")
            if _mw_core is not None and hasattr(_mw_core, "PhotonReporter"):
                _mw_core.PhotonReporter = _mw_cls
        except Exception:
            pass
    except Exception:
        pass
    # --- end telemetry guard ---
    """#

    /// Full server source. Reports download progress while fetching the
    /// weights, then `{"ready": true}`. Each request `{"wav": path}` -> `{"text": ...}`.
    public static func source(modelId: String) -> String {
        let body = #"""
        import sys, json, os, warnings
        warnings.filterwarnings("ignore")
        def emit(obj):
            sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()
        MODEL = "__MODEL__"
        try:
            from huggingface_hub import snapshot_download
            if os.environ.get("HF_HUB_OFFLINE") != "1":
                emit({"status": "Downloading Parakeet Redux (about 180 MB)…", "progress": 0.45})
                snapshot_download(MODEL)
            emit({"status": "Loading Parakeet Redux…", "progress": 0.85})
            import moondream as md
            speech = md.photon(MODEL, device="mps")
        except Exception as e:
            emit({"error": "load: " + str(e)}); sys.exit(1)
        emit({"ready": True})
        for line in sys.stdin:
            try:
                req = json.loads(line)
                res = speech.transcribe(audio=req["wav"])
                out = {"text": res.get("text", "")}
            except Exception as e:
                out = {"error": str(e)}
            emit(out)
        """#
        // Guard goes first, before any moondream/kestrel import.
        return telemetryGuard + "\n" + body.replacingOccurrences(of: "__MODEL__", with: modelId)
    }
}
