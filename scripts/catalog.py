#!/usr/bin/env python3
"""Load and validate fsdk-containers image records.

A record in catalog/<name>.yaml is the single declarative description of one
published OCI image. This module is the only supported way to read one. It is
deliberately free of generation logic so the Justfile, the tests, and any
future tool can consume records without importing the generator.
"""
from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_DIR = REPO_ROOT / "catalog"
SCHEMA_PATH = CATALOG_DIR / "schema.json"

# The exclude set every distroless compose element uses. Measured 2026-08-21:
# 13 of 16 committed compose elements already match this exactly. Deviations
# must be declared via compose.exclude_omit with a reason.
CANONICAL_EXCLUDE = [
    "debug",
    "devel",
    "doc",
    "locale",
    "shells",
    "static-blocklist",
    "tests",
    "vm-only",
]


class CatalogError(Exception):
    """A record is missing, malformed, or contradicts its filename."""


def _validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    return Draft202012Validator(schema)


def validate(record: dict) -> dict:
    """Raise CatalogError if the record does not satisfy catalog/schema.json."""
    errors = sorted(_validator().iter_errors(record), key=lambda e: e.path)
    if errors:
        detail = "; ".join(
            f"{'/'.join(str(p) for p in e.absolute_path) or '<root>'}: {e.message}"
            for e in errors
        )
        raise CatalogError(f"invalid record: {detail}")
    if record.get("smoke", {}).get("shell_probe") and record["kind"] != "shell-enabled":
        raise CatalogError(
            f"{record['name']}: smoke.shell_probe requires kind: shell-enabled"
        )
    return record


def load_record(path: Path, expect_name: str | None = None) -> dict:
    """Load one record, validate it, and check it agrees with its filename."""
    path = Path(path)
    if not path.exists():
        raise CatalogError(f"no such record: {path}")
    record = yaml.safe_load(path.read_text())
    if not isinstance(record, dict):
        raise CatalogError(f"{path}: record must be a YAML mapping")
    validate(record)
    stem = path.stem
    if record["name"] != stem:
        raise CatalogError(
            f"{path}: name {record['name']!r} does not match filename stem {stem!r}"
        )
    if expect_name is not None and record["name"] != expect_name:
        raise CatalogError(
            f"{path}: expected record named {expect_name!r}, filename gives {stem!r}"
        )
    return record


def load_all() -> list[dict]:
    """Every record in catalog/, sorted by name."""
    records = [
        load_record(p) for p in sorted(CATALOG_DIR.glob("*.yaml"))
    ]
    return sorted(records, key=lambda r: r["name"])


def compose_exclude(record: dict) -> list[str]:
    """The exclude domains for this image, canonical minus declared omissions."""
    omitted = {
        entry["domain"]
        for entry in record.get("compose", {}).get("exclude_omit", [])
    }
    return [d for d in CANONICAL_EXCLUDE if d not in omitted]
