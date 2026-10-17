"""Exercise the GHCR transport with a real local token/redirect/blob server."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import threading
import types
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

ROOT = Path(__file__).parents[1]


def load_plugin():
    # BuildStream is only present in bst2; transport itself uses real HTTP and tar.
    stub = types.ModuleType("buildstream")
    stub.Source = object
    stub.SourceError = RuntimeError
    with patch.dict(sys.modules, {"buildstream": stub}):
        spec = importlib.util.spec_from_file_location("ghcr_tar", ROOT / "plugins/sources/ghcr_tar.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


class RegistryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plugin = load_plugin()

    def test_anonymous_token_exchange_and_blob_checksum(self):
        blob = b"real pinned bottle bytes"
        seen = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append((self.path, self.headers.get("Authorization")))
                if self.path.startswith("/token?"):
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps({"token": "anonymous-pull"}).encode())
                elif self.path.startswith("/blob"):
                    if self.headers.get("Authorization") == "Bearer anonymous-pull":
                        self.send_response(302)
                        self.send_header("Location", f"http://localhost:{self.server.server_port}/storage")
                    else:
                        self.send_response(401)
                    self.end_headers()
                elif self.path == "/storage":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(blob)
                else:
                    self.send_response(404)
                    self.end_headers()

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "blob"
                base = f"http://127.0.0.1:{server.server_port}"
                digest = hashlib.sha256(blob).hexdigest()
                self.plugin.download_blob(base + "/blob", base + "/token", target, digest)
                self.assertEqual(target.read_bytes(), blob)
                self.assertIn(("/storage", None), seen, "registry credentials must not leak to storage host")
                with self.assertRaisesRegex(ValueError, "checksum"):
                    self.plugin.download_blob(base + "/blob", base + "/token", target, "0" * 64)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_archive_cannot_escape_staging_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "bottle.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                member = tarfile.TarInfo("../escape")
                member.size = 4
                tar.addfile(member, io.BytesIO(b"evil"))
            with self.assertRaises((tarfile.TarError, ValueError)):
                self.plugin.extract_bottle(archive, root / "stage")
            self.assertFalse((root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
