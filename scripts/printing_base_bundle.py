#!/usr/bin/env python3
"""List the local-cache files that make up the printing-base-devel bundle.

Runs inside the bst2 container (it needs BuildStream's protos):

    printing_base_bundle.py CACHE CLOSURE > filelist

CLOSURE holds one `<element>@@<full-key>` line per element of
`bst show --deps all printing/base.bst`. An element is bundled when CACHE
holds a build log for that key. In the clean per-run cache that
`just printing-base-bundle` uses, the elements with a build log are exactly
the ones no configured remote could serve. Everything else `bst build`
pulled, and consumers pull it from the same remotes. For each bundled
element this prints its artifact refs (strong and weak key) and every CAS
object that BuildStream's `Artifact.query_cache()` needs to call it
cached: the `files` tree, the low/high-diversity metadata, the public data
and the logs. Paths are relative to CACHE, ready for `tar -T`.
"""

import glob
import os
import sys

from buildstream._protos.build.bazel.remote.execution.v2 import remote_execution_pb2
from buildstream._protos.buildstream.v2 import artifact_pb2


def normal_name(element):
    return element.rsplit(":", 1)[-1][: -len(".bst")].replace("/", "-")


def main(cache, closure):
    objects = set()

    def object_path(digest):
        return os.path.join("cas", "objects", digest.hash[:2], digest.hash[2:])

    def add(digest):
        if not digest.hash:
            return False
        path = object_path(digest)
        if path in objects:
            return False
        if not os.path.exists(os.path.join(cache, path)):
            sys.exit(f"ERROR: CAS object {digest.hash} is missing from {cache}")
        objects.add(path)
        return True

    def walk(digest):
        if not add(digest):
            return
        directory = remote_execution_pb2.Directory()
        with open(os.path.join(cache, object_path(digest)), "rb") as f:
            directory.ParseFromString(f.read())
        for node in directory.files:
            add(node.digest)
        for node in directory.directories:
            walk(node.digest)

    refs = []
    bundled = []
    for line in closure:
        element, key = line.strip().split("@@")
        name = normal_name(element)
        if not glob.glob(os.path.join(cache, "logs", "*", name, f"{key[:8]}-build.*.log")):
            continue
        found = glob.glob(os.path.join(cache, "artifacts", "refs", "*", name, key))
        if len(found) != 1:
            sys.exit(f"ERROR: {element} was built but has {len(found)} artifact refs for {key}")
        artifact = artifact_pb2.Artifact()
        with open(found[0], "rb") as f:
            artifact.ParseFromString(f.read())
        for ref_key in {artifact.strong_key, artifact.weak_key}:
            ref = os.path.join(os.path.dirname(found[0]), ref_key)
            if os.path.exists(ref):
                refs.append(os.path.relpath(ref, cache))
        if str(artifact.files):
            walk(artifact.files)
        for digest in (artifact.low_diversity_meta, artifact.high_diversity_meta, artifact.public_data):
            add(digest)
        for log in artifact.logs:
            add(log.digest)
        bundled.append(element)

    if not bundled:
        sys.exit("ERROR: no element in the closure was built in this cache")
    for element in bundled:
        print(f"bundled: {element}", file=sys.stderr)
    print(f"bundled {len(bundled)} elements, {len(refs)} refs, {len(objects)} objects", file=sys.stderr)
    for path in refs + sorted(objects):
        print(path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2]) as closure:
        main(sys.argv[1], closure)
