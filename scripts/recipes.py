#!/usr/bin/env python3
"""Validate the static binary recipe catalog."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("name", "architecture", "enabled")
BUILDER_FIELDS = ("architecture", "platform", "tag_prefix")
IDENTIFIER_RE = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")
PLATFORM_RE = re.compile(r"linux/[a-z0-9][a-z0-9_-]*(?:/[a-z0-9][a-z0-9._-]*)?\Z")
TAG_PREFIX_RE = re.compile(r"[a-z0-9][a-z0-9._-]*-\Z")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]*\Z")
DIGEST_IMAGE_RE = re.compile(r"[^@\s]+@sha256:[0-9a-f]{64}\Z")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
ARTIFACT_MANIFEST_LINE_RE = re.compile(
    r"([0-9a-f]{64})  (artifacts/[^\r\n]+)\Z"
)
FINGERPRINT_RE = re.compile(r"[0-9A-F]{40}\Z")
LOCK_ASSIGNMENT_RE = re.compile(r"([A-Z][A-Z0-9_]*)=([^\s#]+)\Z")


class CatalogError(ValueError):
    """Raised when catalog state is unsafe or incomplete."""


@dataclass(frozen=True)
class SourceAuthentication:
    name: str
    mode: str
    fingerprint: str | None


@dataclass(frozen=True)
class BuilderArchitecture:
    architecture: str
    platform: str
    tag_prefix: str


@dataclass(frozen=True)
class Recipe:
    name: str
    architecture: str
    recipe_dir: str
    build_script: str
    output: str
    environment_lock: str
    enabled: bool
    source_authentications: tuple[SourceAuthentication, ...]


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


def _require_tracked_regular_file(
    root: Path, path: Path, field: str, line_number: int
) -> None:
    _require_inside(root, path, field, line_number)
    if path.is_symlink() or not path.is_file():
        raise _error(line_number, f"missing regular {field}: {path}")

    relative_path = path.relative_to(root).as_posix()
    mode = _git_index_mode(root, relative_path)
    if mode is None:
        raise _error(line_number, f"untracked {field}: {relative_path}")
    if mode != "100644":
        raise _error(line_number, f"{field} has Git mode {mode}: {relative_path}")


def _require_source_archive(
    root: Path,
    recipe_path: Path,
    archive_name: str,
    expected_sha256: str,
    field: str,
    line_number: int,
) -> None:
    archive_path = recipe_path / "sources" / archive_name
    _require_tracked_regular_file(root, archive_path, field, line_number)
    relative_path = archive_path.relative_to(root).as_posix()
    digest = hashlib.sha256()
    with archive_path.open("rb") as archive_file:
        for chunk in iter(lambda: archive_file.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha256:
        raise _error(line_number, f"{field} checksum does not match source.lock: {relative_path}")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_artifact_manifest(root: Path, recipe_outputs: set[str]) -> None:
    manifest_relative = "artifacts/SHA256SUMS"
    manifest_path = root / manifest_relative
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise CatalogError(f"missing regular artifact manifest: {manifest_relative}")
    manifest_mode = _git_index_mode(root, manifest_relative)
    if manifest_mode is None:
        raise CatalogError(f"untracked artifact manifest: {manifest_relative}")
    if manifest_mode != "100644":
        raise CatalogError(
            f"artifact manifest has Git mode {manifest_mode}: {manifest_relative}"
        )

    errors: list[str] = []
    records: dict[str, tuple[str, int]] = {}
    record_paths: list[str] = []
    for line_number, raw_line in enumerate(
        manifest_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        match = ARTIFACT_MANIFEST_LINE_RE.fullmatch(raw_line)
        if match is None:
            errors.append(f"SHA256SUMS line {line_number}: malformed record")
            continue
        expected_digest, relative_path = match.groups()
        posix_path = PurePosixPath(relative_path)
        if (
            "\\" in relative_path
            or posix_path.is_absolute()
            or posix_path.as_posix() != relative_path
            or any(part in {".", ".."} for part in posix_path.parts)
            or not posix_path.parts
            or posix_path.parts[0] != "artifacts"
            or relative_path == manifest_relative
        ):
            errors.append(
                f"SHA256SUMS line {line_number}: unsafe artifact path: {relative_path}"
            )
            continue
        if relative_path in records:
            errors.append(
                f"SHA256SUMS line {line_number}: duplicate artifact path: {relative_path}"
            )
            continue
        records[relative_path] = (expected_digest, line_number)
        record_paths.append(relative_path)

    if record_paths != sorted(record_paths):
        errors.append("SHA256SUMS artifact paths are not sorted")

    artifacts_root = root / "artifacts"
    actual_paths: set[str] = set()
    if artifacts_root.is_dir():
        for path in artifacts_root.rglob("*"):
            relative_path = path.relative_to(root).as_posix()
            if relative_path == manifest_relative:
                continue
            if path.is_symlink():
                errors.append(f"artifact is not a regular file: {relative_path}")
                continue
            if path.is_dir():
                continue
            if not path.is_file():
                errors.append(f"artifact is not a regular file: {relative_path}")
                continue
            actual_paths.add(relative_path)

    for relative_path in sorted(actual_paths - records.keys()):
        errors.append(f"artifact missing from SHA256SUMS: {relative_path}")
    for relative_path in sorted(records.keys() - actual_paths):
        errors.append(f"SHA256SUMS names missing artifact: {relative_path}")
    for relative_path in sorted(actual_paths - recipe_outputs):
        errors.append(f"artifact has no catalog recipe: {relative_path}")
    for relative_path in sorted(recipe_outputs - actual_paths):
        errors.append(f"catalog recipe has no artifact: {relative_path}")
    for relative_path in sorted(actual_paths & records.keys()):
        expected_digest, line_number = records[relative_path]
        mode = _git_index_mode(root, relative_path)
        if mode is None:
            errors.append(f"untracked artifact: {relative_path}")
            continue
        if mode != "100755":
            errors.append(f"artifact has Git mode {mode}: {relative_path}")
            continue
        actual_digest = _sha256_file(root / relative_path)
        if actual_digest != expected_digest:
            errors.append(
                f"SHA256SUMS line {line_number}: checksum mismatch: {relative_path}"
            )

    if errors:
        raise CatalogError("artifact manifest validation failed:\n- " + "\n- ".join(errors))


def _safe_filename(value: str, field: str, line_number: int) -> None:
    if PurePosixPath(value).name != value or value in {".", ".."}:
        raise _error(line_number, f"{field} must be a safe filename")


def _validate_source_authentication(
    root: Path,
    recipe_path: Path,
    values: dict[str, str],
    prefix: str,
    source_name: str,
    archive_name: str,
    line_number: int,
) -> tuple[SourceAuthentication, set[str]]:
    authentication_field = f"{prefix}AUTHENTICATION"
    signature_field = f"{prefix}SIGNATURE"
    key_field = f"{prefix}SIGNING_KEY"
    fingerprint_field = f"{prefix}SIGNER_FINGERPRINT"
    pgp_fields = {signature_field, key_field, fingerprint_field}
    mode = values[authentication_field]

    if mode == "checksum-only":
        mixed_fields = sorted(pgp_fields & values.keys())
        if mixed_fields:
            raise _error(
                line_number,
                f"{authentication_field}=checksum-only forbids: {', '.join(mixed_fields)}",
            )
        return SourceAuthentication(source_name, mode, None), set()

    if mode != "pgp":
        raise _error(
            line_number,
            f"{authentication_field} must be pgp or checksum-only",
        )

    missing_fields = sorted(pgp_fields - values.keys())
    if missing_fields:
        raise _error(
            line_number,
            f"{authentication_field}=pgp is missing: {', '.join(missing_fields)}",
        )

    signature_name = values[signature_field]
    key_name = values[key_field]
    fingerprint = values[fingerprint_field]
    _safe_filename(signature_name, signature_field, line_number)
    _safe_filename(key_name, key_field, line_number)
    if FINGERPRINT_RE.fullmatch(fingerprint) is None:
        raise _error(
            line_number,
            f"{fingerprint_field} must be 40 uppercase hexadecimal characters",
        )
    if len({archive_name, signature_name, key_name}) != 3:
        raise _error(line_number, f"{source_name} archive and PGP evidence must be distinct")

    source_directory = recipe_path / "sources"
    archive_path = source_directory / archive_name
    signature_path = source_directory / signature_name
    key_path = source_directory / key_name
    _require_tracked_regular_file(
        root, signature_path, f"{source_name} signature", line_number
    )
    _require_tracked_regular_file(
        root, key_path, f"{source_name} signing key", line_number
    )

    try:
        with tempfile.TemporaryDirectory(prefix="static_bins-gpgv-") as gpg_home:
            result = subprocess.run(
                [
                    "gpgv",
                    "--homedir",
                    gpg_home,
                    "--status-fd",
                    "1",
                    "--keyring",
                    str(key_path),
                    str(signature_path),
                    str(archive_path),
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
    except OSError as error:
        raise _error(line_number, f"cannot execute gpgv: {error}") from error

    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise _error(line_number, f"invalid {source_name} PGP signature{suffix}")

    valid_fingerprints = [
        fields[2]
        for line in result.stdout.splitlines()
        if (fields := line.split())[:2] == ["[GNUPG:]", "VALIDSIG"]
        and len(fields) > 2
    ]
    if valid_fingerprints != [fingerprint]:
        reported = ", ".join(valid_fingerprints) if valid_fingerprints else "none"
        raise _error(
            line_number,
            f"{source_name} PGP signer mismatch: expected {fingerprint}, got {reported}",
        )

    return SourceAuthentication(source_name, mode, fingerprint), pgp_fields


def _validate_source_record(
    root: Path,
    recipe_path: Path,
    values: dict[str, str],
    prefix: str,
    line_number: int,
) -> tuple[str, SourceAuthentication, set[str]]:
    required_fields = {
        f"{prefix}{suffix}"
        for suffix in (
            "VERSION",
            "ARCHIVE",
            "SHA256",
            "UPSTREAM_URL",
            "LICENSE",
            "AUTHENTICATION",
        )
    }
    missing_fields = sorted(required_fields - values.keys())
    if missing_fields:
        raise _error(
            line_number,
            f"source.lock is missing: {', '.join(missing_fields)}",
        )

    version_field = f"{prefix}VERSION"
    sha256_field = f"{prefix}SHA256"
    archive_field = f"{prefix}ARCHIVE"
    upstream_url_field = f"{prefix}UPSTREAM_URL"
    if VERSION_RE.fullmatch(values[version_field]) is None:
        raise _error(line_number, f"invalid {version_field}: {values[version_field]}")
    if SHA256_RE.fullmatch(values[sha256_field]) is None:
        raise _error(
            line_number,
            f"{sha256_field} must be 64 lowercase hexadecimal characters",
        )
    archive_name = values[archive_field]
    _safe_filename(archive_name, archive_field, line_number)
    if not values[upstream_url_field].startswith("https://"):
        raise _error(line_number, f"{upstream_url_field} must use HTTPS")

    source_name = "source" if prefix == "SOURCE_" else prefix[:-1].lower()
    archive_description = (
        "source archive" if prefix == "SOURCE_" else f"{source_name} source archive"
    )
    _require_source_archive(
        root,
        recipe_path,
        archive_name,
        values[sha256_field],
        archive_description,
        line_number,
    )
    authentication, authentication_fields = _validate_source_authentication(
        root,
        recipe_path,
        values,
        prefix,
        source_name,
        archive_name,
        line_number,
    )
    return archive_name, authentication, required_fields | authentication_fields


def load_builder_catalog(
    root: Path, catalog_path: Path | None = None
) -> dict[str, BuilderArchitecture]:
    if catalog_path is None:
        catalog_path = root / "builders/catalog.tsv"
    if catalog_path.is_symlink() or not catalog_path.is_file():
        raise CatalogError(f"missing regular builder catalog: {catalog_path}")

    try:
        catalog_text = catalog_path.read_bytes().decode("ascii")
    except (OSError, UnicodeError) as error:
        raise CatalogError(f"cannot read ASCII builder catalog {catalog_path}: {error}") from error

    lines = catalog_text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    expected_header = "\t".join(BUILDER_FIELDS)
    if not lines or lines[0] != expected_header:
        raise CatalogError("builder catalog header does not match the required schema")

    builders: dict[str, BuilderArchitecture] = {}
    seen_tag_prefixes: set[str] = set()
    previous_architecture: str | None = None
    for line_number, raw_line in enumerate(lines[1:], start=2):
        if not raw_line:
            raise _error(line_number, "blank builder catalog row")
        columns = raw_line.split("\t")
        if len(columns) != len(BUILDER_FIELDS):
            raise _error(line_number, "wrong number of tab-delimited builder fields")
        architecture, platform, tag_prefix = columns

        if IDENTIFIER_RE.fullmatch(architecture) is None:
            raise _error(line_number, f"invalid builder architecture: {architecture}")
        if PLATFORM_RE.fullmatch(platform) is None:
            raise _error(line_number, f"invalid builder platform: {platform}")
        if TAG_PREFIX_RE.fullmatch(tag_prefix) is None:
            raise _error(line_number, f"invalid builder tag prefix: {tag_prefix}")
        if architecture in builders:
            raise _error(line_number, f"duplicate builder architecture: {architecture}")
        if previous_architecture is not None and architecture <= previous_architecture:
            raise _error(line_number, "builder architectures are not sorted")
        if tag_prefix in seen_tag_prefixes:
            raise _error(line_number, f"duplicate builder tag prefix: {tag_prefix}")

        builder_relative = f"builders/{architecture}"
        builder_directory = root / builder_relative
        _require_inside(root, builder_directory, "builder directory", line_number)
        if builder_directory.is_symlink() or not builder_directory.is_dir():
            raise _error(line_number, f"missing builder directory: {builder_relative}")
        for filename, field in (
            ("Dockerfile", "builder Dockerfile"),
            ("packages.lock", "builder package lock"),
            ("environment.lock", "builder environment lock"),
        ):
            path = builder_directory / filename
            _require_inside(root, path, field, line_number)
            _require_file(path, field, line_number)
        _require_executable(root, f"{builder_relative}/build.sh", line_number)

        environment_values = _read_lock(
            builder_directory / "environment.lock", line_number
        )
        required_environment_fields = {
            "ALPINE_IMAGE",
            "BINFMT_IMAGE",
            "BUILDER_TAG",
            "BUILDER_IMAGE",
        }
        missing_environment_fields = sorted(
            required_environment_fields - environment_values.keys()
        )
        if missing_environment_fields:
            raise _error(
                line_number,
                "builder environment lock is missing: "
                + ", ".join(missing_environment_fields),
            )
        for field in ("ALPINE_IMAGE", "BINFMT_IMAGE", "BUILDER_IMAGE"):
            if DIGEST_IMAGE_RE.fullmatch(environment_values[field]) is None:
                raise _error(
                    line_number,
                    f"builder environment lock must pin {field} by SHA-256 digest",
                )
        builder_tag = environment_values["BUILDER_TAG"]
        if VERSION_RE.fullmatch(builder_tag) is None or not builder_tag.startswith(
            tag_prefix
        ):
            raise _error(
                line_number,
                f"builder environment lock BUILDER_TAG must begin with {tag_prefix}",
            )

        builders[architecture] = BuilderArchitecture(
            architecture=architecture,
            platform=platform,
            tag_prefix=tag_prefix,
        )
        seen_tag_prefixes.add(tag_prefix)
        previous_architecture = architecture

    if not builders:
        raise CatalogError("builder catalog has no architectures")
    return builders


def _validate_recipe(
    root: Path,
    row: dict[str, str],
    line_number: int,
    builder_architectures: dict[str, BuilderArchitecture],
) -> Recipe:
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
    if architecture not in builder_architectures:
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
    additional_prefixes = sorted(
        key[: -len("VERSION")]
        for key in source_values
        if key.endswith("_VERSION") and key != "SOURCE_VERSION"
    )
    source_authentications: list[SourceAuthentication] = []
    source_archives: set[str] = set()
    expected_fields: set[str] = set()
    for prefix in ("SOURCE_", *additional_prefixes):
        archive_name, authentication, record_fields = _validate_source_record(
            root, recipe_path, source_values, prefix, line_number
        )
        if archive_name in source_archives:
            raise _error(line_number, "source archives must be distinct")
        source_archives.add(archive_name)
        source_authentications.append(authentication)
        expected_fields.update(record_fields)

    unexpected_fields = sorted(source_values.keys() - expected_fields)
    if unexpected_fields:
        raise _error(
            line_number,
            f"source.lock has unexpected fields: {', '.join(unexpected_fields)}",
        )

    environment_values = _read_lock(root / environment_lock, line_number)
    if DIGEST_IMAGE_RE.fullmatch(environment_values.get("BUILDER_IMAGE", "")) is None:
        raise _error(line_number, "environment lock must pin BUILDER_IMAGE by SHA-256 digest")

    return Recipe(
        name=name,
        architecture=architecture,
        recipe_dir=recipe_dir,
        build_script=build_script,
        output=output,
        environment_lock=environment_lock,
        enabled=row["enabled"] == "true",
        source_authentications=tuple(source_authentications),
    )


def load_catalog(root: Path, catalog_path: Path) -> list[Recipe]:
    builder_architectures = load_builder_catalog(root)
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
            recipes.append(
                _validate_recipe(root, row, line_number, builder_architectures)
            )

    if not recipes:
        raise CatalogError("catalog has no recipes")
    if not any(recipe.enabled for recipe in recipes):
        raise CatalogError("catalog has no enabled recipes")

    seen_pairs: set[tuple[str, str]] = set()
    for recipe in recipes:
        pair = (recipe.name, recipe.architecture)
        if pair in seen_pairs:
            raise CatalogError(
                f"duplicate recipe pair: {recipe.name}/{recipe.architecture}"
            )
        seen_pairs.add(pair)
    _validate_artifact_manifest(root, {recipe.output for recipe in recipes})
    return recipes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate",))
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

    enabled_count = sum(recipe.enabled for recipe in recipes)
    for recipe in recipes:
        for authentication in recipe.source_authentications:
            source_id = (
                f"{recipe.name}/{recipe.architecture}:{authentication.name}"
            )
            if authentication.mode == "pgp":
                print(
                    f"authenticated source {source_id}: upstream PGP "
                    f"({authentication.fingerprint})"
                )
            else:
                print(
                    f"source authentication {source_id}: checksum-only "
                    "(upstream signature unavailable or not adopted)"
                )
    print(f"validated {len(recipes)} recipes ({enabled_count} enabled)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
