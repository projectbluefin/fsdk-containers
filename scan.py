import subprocess
import json
import base64
import re
import sys

dirs_to_scan = [
    "argo",
    "argocd",
    "manifests",
    "images",
    "flatcar",
    "exo-1",
    "scripts",
    ".github/workflows"
]

all_images = {}

# Regex patterns
# image: something
image_re = re.compile(r'(?:image:\s*|--image\s*|--image=)(["\']?)([\w\.\-\/:]+)\1', re.IGNORECASE)
# FROM something
from_re = re.compile(r'FROM\s+(?:--platform=[\w\/]+)?\s*(["\']?)([\w\.\-\/:]+)\1', re.IGNORECASE)
# general registry url references
registry_re = re.compile(r'(?:(?:ghcr\.io|docker\.io|quay\.io|cgr\.dev|registry\.k8s\.io|gcr\.io)\/[\w\.\-\/:]+:[a-zA-Z0-9\._\-]+)')

def run_gh_api(path):
    cmd = ["gh", "api", f"repos/projectbluefin/testing-lab/contents/{path}"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error calling API for {path}: {res.stderr}", file=sys.stderr)
        return None
    try:
        return json.loads(res.stdout)
    except Exception as e:
        print(f"Error parsing JSON for {path}: {e}", file=sys.stderr)
        return None

def scan_path(path):
    print(f"Scanning path: {path}", file=sys.stderr)
    data = run_gh_api(path)
    if not data:
        return
    
    if isinstance(data, list):
        # It's a directory
        for item in data:
            if item["type"] == "dir":
                scan_path(item["path"])
            elif item["type"] == "file":
                scan_file(item["path"])
    elif isinstance(data, dict):
        if data.get("type") == "file":
            scan_file_data(data)
        elif data.get("type") == "dir":
            pass

def scan_file(file_path):
    print(f"Fetching file: {file_path}", file=sys.stderr)
    data = run_gh_api(file_path)
    if data:
        scan_file_data(data)

def scan_file_data(data):
    file_path = data["path"]
    content_b64 = data.get("content", "")
    if not content_b64:
        return
    
    # decode content
    try:
        content_b64 = content_b64.replace("\n", "").replace("\r", "")
        content = base64.b64decode(content_b64).decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"Error decoding base64 for {file_path}: {e}", file=sys.stderr)
        return

    # Scan for images
    lines = content.splitlines()
    for line_num, line in enumerate(lines, 1):
        found_images = []
        for m in image_re.finditer(line):
            found_images.append(m.group(2))
        for m in from_re.finditer(line):
            found_images.append(m.group(2))
        for m in registry_re.finditer(line):
            found_images.append(m.group(0))
        
        for img in found_images:
            img = img.strip("\"'()[]{},;`")
            if not img:
                continue
            if img.startswith("projectbluefin/") or "ghcr.io/projectbluefin/" in img:
                continue
            if img.lower() in ["image", "true", "false", "null", "none"]:
                continue
            
            # Remove any trailing / or other chars from registry URL match
            if img not in all_images:
                all_images[img] = []
            all_images[img].append((file_path, line_num, line.strip()))

for d in dirs_to_scan:
    scan_path(d)

print(json.dumps(all_images, indent=2))
