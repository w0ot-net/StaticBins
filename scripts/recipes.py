#!/usr/bin/env python3
"""Validate the static binary recipe catalog and emit its CI matrix."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("name", "architecture", "enabled")
ARCHITECTURES = {
    "aarch64": {
        "runner": "ubuntu-24.04-arm",
        "platform": "linux/arm64",
        "tag_suffix": "aarch64",
    },
    "x86_64": {
        "runner": "ubuntu-24.04",
        "platform": "linux/amd64",
        "tag_suffix": "x86_64",
    },
}
IDENTIFIER_RE = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*\Z")
DIGEST_IMAGE_RE = re.compile(r"[^@\s]+@sha256:[0-9a-f]{64}\Z")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
LOCK_ASSIGNMENT_RE = re.compile(r"([A-Z][A-Z0-9_]*)=([^\s#]+)\Z")


class CatalogError(ValueError):
    """Raised when catalog state is unsafe or incomplete."""


@dataclass(frozen=True)
class Recipe:
    name: str
    architecture: str
    version: str
    recipe_dir: str
    build_script: str
    output: str
    image_name: str
    tag_suffixes: tuple[str, str]
    cache_scope: str
    runner: str
    platform: str
    environment_lock: str
    enabled: bool


def _error(line_number: int, message: str) -> CatalogError:
    return CatalogError(f"line {line_number}: {message}")


def _git_index_mode(root: Path, relative_path: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--stage", "--", relative_path],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    lines = result.stdout.splitlines()
    if len(lines) != 1:
        raise CatalogError(f"conflicted Git index entry: {relative_path}")
    return lines[0].split(maxsplit=1)[0]


def _require_executable(root: Path, relative_path: str, line_number: int) -> None:
    mode = _git_index_mode(root, relative_path)
    if mode is not None:
        if mode != "100755":
            raise _error(line_number, f"tracked executable has Git mode {mode}: {relative_path}")
        return
    if not os.access(root / relative_path, os.X_OK):
        raise _error(line_number, f"untracked file is not executable: {relative_path}")


def _read_lock(path: Path, line_number: int) -> dict[str, str]:
    values: dict[str, str] = {}
    for lock_line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw_line or raw_line.startswith("#"):
            continue
        match = LOCK_ASSIGNMENT_RE.fullmatch(raw_line)
        if match is None:
            raise _error(
                line_number,
                f"unsafe assignment in {path.name} line {lock_line_number}",
            )
        key, value = match.groups()
        if key in values:
            raise _error(line_number, f"duplicate {key} in {path.name}")
        values[key] = value
    return values


def _require_file(path: Path, field: str, line_number: int) -> None:
    if path.is_symlink() or not path.is_file():
        raise _error(line_number, f"missing {field}: {path}")


def _require_inside(root: Path, path: Path, field: str, line_number: int) -> None:
    root_resolved = root.resolve()
    path_resolved = path.resolve(strict=False)
    if os.path.commonpath((root_resolved, path_resolved)) != str(root_resolved):
        raise _error(line_number, f"{field} escapes the repository: {path}")


def _require_source_archive(
    root: Path,
    recipe_path: Path,
    archive_name: str,
    expected_sha256: str,
    field: str,
    line_number: int,
) -> None:
    archive_path = recipe_path / "sources" / archive_name
    _require_inside(root, archive_path, field, line_number)
    if archive_path.is_symlink() or not archive_path.is_file():
        raise _error(line_number, f"missing regular {field}: {archive_path}")

    relative_path = archive_path.relative_to(root).as_posix()
    mode = _git_index_mode(root, relative_path)
    if mode is None:
        raise _error(line_number, f"untracked {field}: {relative_path}")
    if mode != "100644":
        raise _error(line_number, f"{field} has Git mode {mode}: {relative_path}")

    digest = hashlib.sha256()
    with archive_path.open("rb") as archive_file:
        for chunk in iter(lambda: archive_file.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha256:
        raise _error(line_number, f"{field} checksum does not match source.lock: {relative_path}")


def _validate_recipe(root: Path, row: dict[str, str], line_number: int) -> Recipe:
    for field in FIELDS:
        value = row[field]
        if not value or value != value.strip():
            raise _error(line_number, f"{field} must be non-empty without surrounding whitespace")
        if "\r" in value or "\n" in value:
            raise _error(line_number, f"{field} contains a line break")

    name = row["name"]
    if IDENTIFIER_RE.fullmatch(name) is None or name == "list":
        raise _error(line_number, f"invalid recipe name: {name}")

    architecture = row["architecture"]
    architecture_config = ARCHITECTURES.get(architecture)
    if architecture_config is None:
        raise _error(line_number, f"unsupported architecture: {architecture}")

    if row["enabled"] not in {"true", "false"}:
        raise _error(line_number, "enabled must be true or false")

    recipe_dir = f"recipes/{name}/{architecture}"
    build_script = f"{recipe_dir}/build.sh"
    output = f"artifacts/{architecture}/{name}"
    environment_lock = f"builders/{architecture}/environment.lock"
    recipe_path = root / recipe_dir

    if recipe_path.is_symlink() or not recipe_path.is_dir():
        raise _error(line_number, f"missing recipe directory: {recipe_dir}")
    required_paths = (
        (root / build_script, "build script"),
        (root / output, "committed output"),
        (recipe_path / "Dockerfile", "Dockerfile"),
        (recipe_path / "source.lock", "source lock"),
        (recipe_path / "licenses" / "NOTICE.md", "distribution notice"),
        (recipe_path / "licenses" / "archive-inventory.tsv", "linked-archive inventory"),
        (root / environment_lock, "environment lock"),
    )
    _require_inside(root, recipe_path, "recipe directory", line_number)
    for path, field in required_paths:
        _require_inside(root, path, field, line_number)
        _require_file(path, field, line_number)
    _require_executable(root, build_script, line_number)
    _require_executable(root, output, line_number)

    source_values = _read_lock(recipe_path / "source.lock", line_number)
    required_source_fields = {
        "SOURCE_VERSION",
        "SOURCE_ARCHIVE",
        "SOURCE_SHA256",
        "SOURCE_UPSTREAM_URL",
        "SOURCE_LICENSE",
    }
    missing_source_fields = sorted(required_source_fields - source_values.keys())
    if missing_source_fields:
        raise _error(
            line_number,
            f"source.lock is missing: {', '.join(missing_source_fields)}",
        )

    version = source_values["SOURCE_VERSION"]
    if VERSION_RE.fullmatch(version) is None:
        raise _error(line_number, f"invalid SOURCE_VERSION: {version}")
    if SHA256_RE.fullmatch(source_values["SOURCE_SHA256"]) is None:
        raise _error(line_number, "SOURCE_SHA256 must be 64 lowercase hexadecimal characters")
    source_archive = source_values["SOURCE_ARCHIVE"]
    if PurePosixPath(source_archive).name != source_archive or source_archive in {".", ".."}:
        raise _error(line_number, "SOURCE_ARCHIVE must be a safe filename")
    if not source_values["SOURCE_UPSTREAM_URL"].startswith("https://"):
        raise _error(line_number, "SOURCE_UPSTREAM_URL must use HTTPS")
    _require_source_archive(
        root,
        recipe_path,
        source_archive,
        source_values["SOURCE_SHA256"],
        "source archive",
        line_number,
    )

    if name == "tcpdump":
        required_libpcap_fields = {
            "LIBPCAP_VERSION",
            "LIBPCAP_ARCHIVE",
            "LIBPCAP_SHA256",
            "LIBPCAP_UPSTREAM_URL",
            "LIBPCAP_LICENSE",
        }
        expected_fields = required_source_fields | required_libpcap_fields
        missing_libpcap_fields = sorted(required_libpcap_fields - source_values.keys())
        if missing_libpcap_fields:
            raise _error(
                line_number,
                f"tcpdump source.lock is missing: {', '.join(missing_libpcap_fields)}",
            )
        unexpected_fields = sorted(source_values.keys() - expected_fields)
        if unexpected_fields:
            raise _error(
                line_number,
                f"tcpdump source.lock has unexpected fields: {', '.join(unexpected_fields)}",
            )

        libpcap_version = source_values["LIBPCAP_VERSION"]
        if VERSION_RE.fullmatch(libpcap_version) is None:
            raise _error(line_number, f"invalid LIBPCAP_VERSION: {libpcap_version}")
        if SHA256_RE.fullmatch(source_values["LIBPCAP_SHA256"]) is None:
            raise _error(
                line_number,
                "LIBPCAP_SHA256 must be 64 lowercase hexadecimal characters",
            )
        libpcap_archive = source_values["LIBPCAP_ARCHIVE"]
        if (
            PurePosixPath(libpcap_archive).name != libpcap_archive
            or libpcap_archive in {".", ".."}
        ):
            raise _error(line_number, "LIBPCAP_ARCHIVE must be a safe filename")
        if libpcap_archive == source_archive:
            raise _error(line_number, "tcpdump source archives must be distinct")
        if not source_values["LIBPCAP_UPSTREAM_URL"].startswith("https://"):
            raise _error(line_number, "LIBPCAP_UPSTREAM_URL must use HTTPS")
        _require_source_archive(
            root,
            recipe_path,
            libpcap_archive,
            source_values["LIBPCAP_SHA256"],
            "libpcap source archive",
            line_number,
        )
    else:
        unexpected_fields = sorted(source_values.keys() - required_source_fields)
        if unexpected_fields:
            raise _error(
                line_number,
                f"source.lock has unexpected fields: {', '.join(unexpected_fields)}",
            )

    environment_values = _read_lock(root / environment_lock, line_number)
    if DIGEST_IMAGE_RE.fullmatch(environment_values.get("BUILDER_IMAGE", "")) is None:
        raise _error(line_number, "environment lock must pin BUILDER_IMAGE by SHA-256 digest")

    tag_suffix = architecture_config["tag_suffix"]
    return Recipe(
        name=name,
        architecture=architecture,
        version=version,
        recipe_dir=recipe_dir,
        build_script=build_script,
        output=output,
        image_name=f"static_bins-{name}",
        tag_suffixes=(f"{version}-{tag_suffix}", f"{tag_suffix}-latest"),
        cache_scope=f"{architecture}-{name}",
        runner=architecture_config["runner"],
        platform=architecture_config["platform"],
        environment_lock=environment_lock,
        enabled=row["enabled"] == "true",
    )


def load_catalog(root: Path, catalog_path: Path) -> list[Recipe]:
    try:
        catalog_file = catalog_path.open(encoding="utf-8", newline="")
    except OSError as error:
        raise CatalogError(f"cannot read catalog {catalog_path}: {error}") from error

    with catalog_file:
        reader = csv.DictReader(catalog_file, delimiter="\t")
        if reader.fieldnames != list(FIELDS):
            raise CatalogError("catalog header does not match the required schema")
        recipes: list[Recipe] = []
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise _error(line_number, "wrong number of tab-delimited fields")
            recipes.append(_validate_recipe(root, row, line_number))

    if not recipes:
        raise CatalogError("catalog has no recipes")
    if not any(recipe.enabled for recipe in recipes):
        raise CatalogError("catalog has no enabled recipes")

    seen_names: set[str] = set()
    for recipe in recipes:
        if recipe.name in seen_names:
            raise CatalogError(f"duplicate recipe name: {recipe.name}")
        seen_names.add(recipe.name)
    return recipes


def matrix(recipes: Iterable[Recipe]) -> dict[str, list[dict[str, str]]]:
    include = []
    for recipe in sorted(
        (recipe for recipe in recipes if recipe.enabled), key=lambda item: item.name
    ):
        include.append(
            {
                "architecture": recipe.architecture,
                "cache_scope": recipe.cache_scope,
                "context": recipe.recipe_dir,
                "dockerfile": f"{recipe.recipe_dir}/Dockerfile",
                "environment_lock": recipe.environment_lock,
                "image_name": recipe.image_name,
                "name": recipe.name,
                "platform": recipe.platform,
                "runner": recipe.runner,
                "tag_suffixes": "\n".join(recipe.tag_suffixes),
                "version": recipe.version,
            }
        )
    return {"include": include}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "matrix"))
    parser.add_argument("--root", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--catalog", type=Path, default=Path("recipes/catalog.tsv"))
    args = parser.parse_args(argv)

    root = args.root.resolve()
    catalog_path = args.catalog
    if not catalog_path.is_absolute():
        catalog_path = root / catalog_path

    try:
        recipes = load_catalog(root, catalog_path)
    except (CatalogError, OSError, UnicodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if args.command == "validate":
        enabled_count = sum(recipe.enabled for recipe in recipes)
        print(f"validated {len(recipes)} recipes ({enabled_count} enabled)")
    else:
        print(json.dumps(matrix(recipes), separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
