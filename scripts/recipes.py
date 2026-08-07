#!/usr/bin/env python3
"""Validate the static binary recipe catalog and emit its CI matrix."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
FIELDS = (
    "name",
    "architecture",
    "version",
    "recipe_dir",
    "build_script",
    "output",
    "image",
    "tags",
    "cache_scope",
    "runner",
    "enabled",
)
ARCHITECTURES = {
    "aarch64": {
        "runner": "ubuntu-24.04-arm",
        "platform": "linux/arm64",
        "scripts_dir": "aarch64_alpine_build_scripts",
        "bins_dir": "aarch64_bins",
    },
    "x64": {
        "runner": "ubuntu-24.04",
        "platform": "linux/amd64",
        "scripts_dir": "x64_alpine_build_scripts",
        "bins_dir": "x64_bins",
    },
}
IDENTIFIER_RE = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*\Z")
IMAGE_RE = re.compile(
    r"ghcr[.]io/[a-z0-9](?:[a-z0-9-]*[a-z0-9])?/"
    r"static_bins-[a-z0-9][a-z0-9._-]*\Z"
)
TAG_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
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
    image: str
    tags: tuple[str, ...]
    cache_scope: str
    runner: str
    enabled: bool


def _error(line_number: int, message: str) -> CatalogError:
    return CatalogError(f"line {line_number}: {message}")


def _safe_relative_path(root: Path, value: str, field: str, line_number: int) -> Path:
    if "\\" in value:
        raise _error(line_number, f"{field} must use POSIX separators")
    path = PurePosixPath(value)
    if path.is_absolute() or value != path.as_posix():
        raise _error(line_number, f"{field} must be a normalized relative path")
    if not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise _error(line_number, f"{field} contains an unsafe path component")

    root_resolved = root.resolve()
    candidate = root.joinpath(*path.parts)
    candidate_resolved = candidate.resolve(strict=False)
    if os.path.commonpath((root_resolved, candidate_resolved)) != str(root_resolved):
        raise _error(line_number, f"{field} escapes the repository")
    return candidate


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
    path = root / relative_path
    if not os.access(path, os.X_OK):
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
    if not path.is_file():
        raise _error(line_number, f"missing {field}: {path}")


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

    version = row["version"]
    if VERSION_RE.fullmatch(version) is None:
        raise _error(line_number, f"invalid version: {version}")

    scripts_dir = architecture_config["scripts_dir"]
    bins_dir = architecture_config["bins_dir"]
    expected_recipe_dir = f"{scripts_dir}/{name}"
    expected_build_script = f"{expected_recipe_dir}/build.sh"
    expected_output = f"{bins_dir}/{name}"
    if row["recipe_dir"] != expected_recipe_dir:
        raise _error(line_number, f"recipe_dir must be {expected_recipe_dir}")
    if row["build_script"] != expected_build_script:
        raise _error(line_number, f"build_script must be {expected_build_script}")
    if row["output"] != expected_output:
        raise _error(line_number, f"output must be {expected_output}")

    recipe_dir = _safe_relative_path(root, row["recipe_dir"], "recipe_dir", line_number)
    build_script = _safe_relative_path(root, row["build_script"], "build_script", line_number)
    output = _safe_relative_path(root, row["output"], "output", line_number)
    if not recipe_dir.is_dir():
        raise _error(line_number, f"missing recipe directory: {row['recipe_dir']}")
    _require_file(build_script, "build script", line_number)
    _require_file(output, "committed output", line_number)
    _require_executable(root, row["build_script"], line_number)
    _require_executable(root, row["output"], line_number)

    dockerfile = recipe_dir / "Dockerfile"
    source_lock = recipe_dir / "source.lock"
    notice = recipe_dir / "licenses" / "NOTICE.md"
    inventory = recipe_dir / "licenses" / "archive-inventory.tsv"
    _require_file(dockerfile, "Dockerfile", line_number)
    _require_file(source_lock, "source lock", line_number)
    _require_file(notice, "distribution notice", line_number)
    _require_file(inventory, "linked-archive inventory", line_number)

    source_values = _read_lock(source_lock, line_number)
    required_source_fields = {
        "SOURCE_VERSION",
        "SOURCE_ARCHIVE",
        "SOURCE_SHA256",
        "SOURCE_UPSTREAM_URL",
        "SOURCE_MIRROR_URL",
        "SOURCE_LICENSE",
    }
    missing_source_fields = sorted(required_source_fields - source_values.keys())
    if missing_source_fields:
        raise _error(
            line_number,
            f"source.lock is missing: {', '.join(missing_source_fields)}",
        )
    if source_values["SOURCE_VERSION"] != version:
        raise _error(line_number, "catalog version does not match SOURCE_VERSION")
    if SHA256_RE.fullmatch(source_values["SOURCE_SHA256"]) is None:
        raise _error(line_number, "SOURCE_SHA256 must be 64 lowercase hexadecimal characters")
    for url_field in ("SOURCE_UPSTREAM_URL", "SOURCE_MIRROR_URL"):
        if not source_values[url_field].startswith("https://"):
            raise _error(line_number, f"{url_field} must use HTTPS")

    environment_relative = f"{scripts_dir}/environment.lock"
    environment_lock = _safe_relative_path(
        root, environment_relative, "environment lock", line_number
    )
    _require_file(environment_lock, "environment lock", line_number)
    environment_values = _read_lock(environment_lock, line_number)
    builder_image = environment_values.get("BUILDER_IMAGE", "")
    if DIGEST_IMAGE_RE.fullmatch(builder_image) is None:
        raise _error(line_number, "environment lock must pin BUILDER_IMAGE by SHA-256 digest")

    image = row["image"]
    if IMAGE_RE.fullmatch(image) is None:
        raise _error(line_number, f"invalid GHCR image: {image}")

    tags = tuple(row["tags"].split(";"))
    if any(TAG_RE.fullmatch(tag) is None for tag in tags) or len(set(tags)) != len(tags):
        raise _error(line_number, "tags must be unique valid container tags")
    required_tags = {f"{version}-{architecture}", f"{architecture}-latest"}
    if set(tags) != required_tags:
        raise _error(
            line_number,
            "tags must contain exactly the versioned and architecture-latest tags",
        )

    expected_cache_scope = f"{architecture}-{name}"
    if row["cache_scope"] != expected_cache_scope:
        raise _error(line_number, f"cache_scope must be {expected_cache_scope}")
    if row["runner"] != architecture_config["runner"]:
        raise _error(
            line_number,
            f"runner for {architecture} must be {architecture_config['runner']}",
        )
    if row["enabled"] not in {"true", "false"}:
        raise _error(line_number, "enabled must be true or false")

    return Recipe(
        name=name,
        architecture=architecture,
        version=version,
        recipe_dir=row["recipe_dir"],
        build_script=row["build_script"],
        output=row["output"],
        image=image,
        tags=tags,
        cache_scope=row["cache_scope"],
        runner=row["runner"],
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
    seen_paths: set[str] = set()
    seen_scopes: set[str] = set()
    seen_image_tags: set[str] = set()
    for recipe in recipes:
        if recipe.name in seen_names:
            raise CatalogError(f"duplicate recipe name: {recipe.name}")
        seen_names.add(recipe.name)
        for path in (recipe.recipe_dir, recipe.build_script, recipe.output):
            if path in seen_paths:
                raise CatalogError(f"duplicate recipe path: {path}")
            seen_paths.add(path)
        if recipe.cache_scope in seen_scopes:
            raise CatalogError(f"duplicate cache scope: {recipe.cache_scope}")
        seen_scopes.add(recipe.cache_scope)
        for tag in recipe.tags:
            image_tag = f"{recipe.image}:{tag}"
            if image_tag in seen_image_tags:
                raise CatalogError(f"duplicate image tag: {image_tag}")
            seen_image_tags.add(image_tag)
    return recipes


def matrix(recipes: Iterable[Recipe]) -> dict[str, list[dict[str, str]]]:
    include = []
    for recipe in sorted(
        (recipe for recipe in recipes if recipe.enabled), key=lambda item: item.name
    ):
        architecture_config = ARCHITECTURES[recipe.architecture]
        include.append(
            {
                "architecture": recipe.architecture,
                "cache_scope": recipe.cache_scope,
                "context": recipe.recipe_dir,
                "dockerfile": f"{recipe.recipe_dir}/Dockerfile",
                "environment_lock": (
                    f"{architecture_config['scripts_dir']}/environment.lock"
                ),
                "image": recipe.image,
                "name": recipe.name,
                "platform": architecture_config["platform"],
                "runner": recipe.runner,
                "tags": "\n".join(f"{recipe.image}:{tag}" for tag in recipe.tags),
                "version": recipe.version,
            }
        )
    return {"include": include}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "matrix"))
    parser.add_argument("--root", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--catalog", type=Path, default=Path("recipes.tsv"))
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
