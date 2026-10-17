"""Digest-pinned Homebrew bottle source; network only during source fetch.

GHCR requires an anonymous scoped bearer token even for public bottle blobs.
Keep this separate from build commands and never persist tokens in artifacts.
"""

import hashlib
import json
from pathlib import Path
import re
import tarfile
import urllib.error
import urllib.parse
import urllib.request

from buildstream import Source, SourceError


class RegistryRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
        if redirected is not None:
            if urllib.parse.urlsplit(request.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
                redirected.remove_header("Authorization")
        return redirected


def download_blob(url, token_url, target, digest):
    opener = urllib.request.build_opener(RegistryRedirect())
    try:
        response = opener.open(url, timeout=120)
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise
        error.close()
        query = urllib.parse.urlencode({"service": "ghcr.io", "scope": "repository:homebrew/core/portable-ruby:pull"})
        with opener.open(token_url + "?" + query, timeout=120) as response:
            token = json.load(response)["token"]
        request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
        response = opener.open(request, timeout=120)
    checksum = hashlib.sha256()
    with response, open(target, "wb") as output:
        while chunk := response.read(1024 * 1024):
            checksum.update(chunk)
            output.write(chunk)
    if checksum.hexdigest() != digest:
        Path(target).unlink()
        raise ValueError("portable Ruby bottle checksum mismatch")


def extract_bottle(archive, directory):
    # bst2 is Python >=3.12, with traversal/link/device protection in data_filter.
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(directory, filter="data")


class GhcrTarSource(Source):
    BST_MIN_VERSION = "2.5"

    def configure(self, node):
        node.validate_keys(Source.COMMON_CONFIG_KEYS + ["url", "ref"])
        self.url = node.get_str("url")
        self.mark_download_url(self.url)
        self.load_ref(node)
        if not self.url.startswith("https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:"):
            raise SourceError("ghcr_tar is restricted to upstream Homebrew portable Ruby bottles")
        if self.ref and not self.url.endswith(self.ref):
            raise SourceError("bottle URL digest and ref must agree")

    def preflight(self):
        if not hasattr(tarfile, "data_filter"):
            raise SourceError("ghcr_tar requires Python >=3.12 safe tar extraction")

    def load_ref(self, node):
        self.ref = node.get_str("ref", None)
        if self.ref and not re.fullmatch("[0-9a-f]{64}", self.ref):
            raise SourceError("portable Ruby ref must be a SHA256 digest")

    def get_ref(self):
        return self.ref

    def set_ref(self, ref, node):
        self.ref = ref
        node["ref"] = ref

    def get_unique_key(self):
        return [self.url, self.ref, 1]

    def _archive(self):
        return Path(self.get_mirror_directory()) / self.ref

    def is_cached(self):
        if not self.ref:
            return False
        archive = self._archive()
        if not archive.is_file():
            return False
        with archive.open("rb") as source:
            return hashlib.file_digest(source, "sha256").hexdigest() == self.ref

    def fetch(self, alias_override=None):
        if self.is_cached():
            return
        url = self.translate_url(self.url, alias_override=alias_override)
        try:
            with self.tempdir() as temporary:
                archive = Path(temporary) / "bottle.tar.gz"
                download_blob(url, "https://ghcr.io/token", archive, self.ref)
                archive.replace(self._archive())
        except (OSError, ValueError, KeyError) as error:
            raise SourceError(f"Cannot fetch pinned portable Ruby: {error}") from error

    def stage(self, directory):
        try:
            extract_bottle(self._archive(), directory)
        except (tarfile.TarError, OSError) as error:
            raise SourceError(f"Cannot stage portable Ruby: {error}") from error


def setup():
    return GhcrTarSource
