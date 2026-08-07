from __future__ import annotations

import importlib.util
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_SPEC = importlib.util.spec_from_file_location(
    "recipes", REPOSITORY_ROOT / "scripts" / "recipes.py"
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
recipes = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = recipes
MODULE_SPEC.loader.exec_module(recipes)


class CatalogFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.rows: list[dict[str, str]] = []
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        subprocess.run(
            ["git", "-C", str(root), "config", "core.fileMode", "true"],
            check=True,
        )

    def add_recipe(
        self,
        name: str = "gdb",
        *,
        architecture: str = "aarch64",
        version: str = "1.0",
        enabled: str = "true",
        authentication: str = "checksum-only",
        script_body: str = "#!/usr/bin/env bash\nexit 37\n",
    ) -> dict[str, str]:
        recipe_dir = self.root / "recipes" / name / architecture
        license_dir = recipe_dir / "licenses"
        source_dir = recipe_dir / "sources"
        builder_dir = self.root / "builders" / architecture
        output = self.root / "artifacts" / architecture / name
        license_dir.mkdir(parents=True, exist_ok=True)
        source_dir.mkdir(parents=True, exist_ok=True)
        builder_dir.mkdir(parents=True, exist_ok=True)
        output.parent.mkdir(parents=True, exist_ok=True)

        (builder_dir / "environment.lock").write_text(
            "BUILDER_IMAGE=ghcr.io/example/static_bins-builder@sha256:"
            + "1" * 64
            + "\n",
            encoding="utf-8",
        )
        (recipe_dir / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        if authentication == "pgp":
            source_archive = "tcpdump-4.99.4.tar.gz"
            source_path = (
                REPOSITORY_ROOT
                / "recipes/tcpdump/x86_64/sources/tcpdump-4.99.4.tar.gz"
            )
            shutil.copyfile(source_path, source_dir / source_archive)
            source_bytes = source_path.read_bytes()
        else:
            source_bytes = f"{name}-{version} source fixture\n".encode()
            source_archive = f"{name}-{version}.tar.xz"
            (source_dir / source_archive).write_bytes(source_bytes)
        source_lock = (
            f"SOURCE_VERSION={version}\n"
            f"SOURCE_ARCHIVE={source_archive}\n"
            f"SOURCE_SHA256={hashlib.sha256(source_bytes).hexdigest()}\n"
            f"SOURCE_UPSTREAM_URL=https://upstream.invalid/{name}.tar.xz\n"
            "SOURCE_LICENSE=GPL-3.0-or-later\n"
            f"SOURCE_AUTHENTICATION={authentication}\n"
        )
        if authentication == "pgp":
            signature_name = "tcpdump-4.99.4.tar.gz.sig"
            key_name = (
                "tcpdump-group-1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D.gpg"
            )
            shutil.copyfile(
                REPOSITORY_ROOT
                / "recipes/tcpdump/x86_64/sources"
                / signature_name,
                source_dir / signature_name,
            )
            shutil.copyfile(
                REPOSITORY_ROOT / "recipes/tcpdump/x86_64/sources" / key_name,
                source_dir / key_name,
            )
            source_lock += (
                f"SOURCE_SIGNATURE={signature_name}\n"
                f"SOURCE_SIGNING_KEY={key_name}\n"
                "SOURCE_SIGNER_FINGERPRINT="
                "1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D\n"
            )
        if name == "tcpdump":
            libpcap_bytes = b"libpcap-1.10.4 source fixture\n"
            (source_dir / "libpcap-1.10.4.tar.gz").write_bytes(libpcap_bytes)
            source_lock += (
                "LIBPCAP_VERSION=1.10.4\n"
                "LIBPCAP_ARCHIVE=libpcap-1.10.4.tar.gz\n"
                f"LIBPCAP_SHA256={hashlib.sha256(libpcap_bytes).hexdigest()}\n"
                "LIBPCAP_UPSTREAM_URL=https://upstream.invalid/libpcap.tar.gz\n"
                "LIBPCAP_LICENSE=BSD-3-Clause\n"
                "LIBPCAP_AUTHENTICATION=checksum-only\n"
            )
        (recipe_dir / "source.lock").write_text(source_lock, encoding="utf-8")
        (recipe_dir / "build.sh").write_text(script_body, encoding="utf-8")
        (license_dir / "NOTICE.md").write_text("notice\n", encoding="utf-8")
        (license_dir / "archive-inventory.tsv").write_text(
            "# archive inventory\n", encoding="utf-8"
        )
        output.write_bytes(b"fixture")
        os.chmod(recipe_dir / "build.sh", 0o755)
        os.chmod(output, 0o755)

        row = {
            "name": name,
            "architecture": architecture,
            "enabled": enabled,
        }
        self.rows.append(row)
        return row

    def write_catalog(self, header: tuple[str, ...] = recipes.FIELDS) -> Path:
        catalog = self.root / "recipes" / "catalog.tsv"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        lines = ["\t".join(header)]
        for row in self.rows:
            lines.append("\t".join(row[field] for field in recipes.FIELDS))
        catalog.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return catalog

    def write_artifact_manifest(self) -> Path:
        manifest = self.root / "artifacts" / "SHA256SUMS"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        records = []
        for path in sorted((self.root / "artifacts").glob("*/*")):
            if path.is_file():
                relative_path = path.relative_to(self.root).as_posix()
                records.append(
                    f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {relative_path}"
                )
        manifest.write_text("\n".join(records) + "\n", encoding="utf-8")
        return manifest

    def track(self) -> None:
        self.write_artifact_manifest()
        subprocess.run(
            ["git", "-C", str(self.root), "add", "--", "artifacts", "builders", "recipes"],
            check=True,
        )
        executable_paths = []
        for row in self.rows:
            executable_paths.extend(
                (
                    f"recipes/{row['name']}/{row['architecture']}/build.sh",
                    f"artifacts/{row['architecture']}/{row['name']}",
                )
            )
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "update-index",
                "--chmod=+x",
                "--",
                *executable_paths,
            ],
            check=True,
        )


class RecipeCatalogTests(unittest.TestCase):
    def make_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], CatalogFixture]:
        temporary_directory = tempfile.TemporaryDirectory()
        return temporary_directory, CatalogFixture(Path(temporary_directory.name))

    def test_valid_catalog_is_deterministic(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        fixture.add_recipe("tool", architecture="x86_64", version="2.5")
        catalog = fixture.write_catalog()
        fixture.track()

        loaded = recipes.load_catalog(fixture.root, catalog)
        first = loaded
        second = recipes.load_catalog(fixture.root, catalog)
        self.assertEqual(first, second)
        self.assertEqual(["gdb", "tool"], [recipe.name for recipe in first])
        self.assertEqual(
            ["aarch64", "x86_64"], [recipe.architecture for recipe in first]
        )
        self.assertEqual(
            ["artifacts/aarch64/gdb", "artifacts/x86_64/tool"],
            [recipe.output for recipe in first],
        )

    def test_artifact_manifest_is_complete_and_exact(self) -> None:
        cases = (
            ("missing manifest", "missing regular artifact manifest"),
            ("omitted artifact", "artifact missing from SHA256SUMS"),
            ("extra record", "SHA256SUMS names missing artifact"),
            ("duplicate record", "duplicate artifact path"),
            ("unsorted records", "artifact paths are not sorted"),
            ("unsafe path", "unsafe artifact path"),
            ("malformed record", "malformed record"),
            ("corrupt artifact", "checksum mismatch"),
            ("untracked extra artifact", "artifact missing from SHA256SUMS"),
        )
        for mutation, expected_message in cases:
            with self.subTest(mutation=mutation):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe()
                catalog = fixture.write_catalog()
                fixture.track()
                manifest = fixture.root / "artifacts/SHA256SUMS"
                record = manifest.read_text(encoding="utf-8").strip()

                if mutation == "missing manifest":
                    manifest.unlink()
                elif mutation == "omitted artifact":
                    manifest.write_text("", encoding="utf-8")
                elif mutation == "extra record":
                    manifest.write_text(
                        record + "\n" + "0" * 64 + "  artifacts/x86_64/absent\n",
                        encoding="utf-8",
                    )
                elif mutation == "duplicate record":
                    manifest.write_text(record + "\n" + record + "\n", encoding="utf-8")
                elif mutation == "unsorted records":
                    extra = fixture.root / "artifacts/x86_64/extra"
                    extra.parent.mkdir(parents=True, exist_ok=True)
                    extra.write_bytes(b"extra")
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(fixture.root),
                            "add",
                            "--",
                            "artifacts/x86_64/extra",
                        ],
                        check=True,
                    )
                    extra_record = (
                        f"{hashlib.sha256(extra.read_bytes()).hexdigest()}  "
                        "artifacts/x86_64/extra"
                    )
                    manifest.write_text(extra_record + "\n" + record + "\n", encoding="utf-8")
                elif mutation == "unsafe path":
                    manifest.write_text(
                        "0" * 64 + "  artifacts/../outside\n", encoding="utf-8"
                    )
                elif mutation == "malformed record":
                    manifest.write_text(record.replace("  ", " ") + "\n", encoding="utf-8")
                elif mutation == "corrupt artifact":
                    (fixture.root / "artifacts/aarch64/gdb").write_bytes(b"changed")
                else:
                    (fixture.root / "artifacts/x86_64/extra").parent.mkdir(
                        parents=True, exist_ok=True
                    )
                    (fixture.root / "artifacts/x86_64/extra").write_bytes(b"extra")

                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_source_version_is_validated(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe(version="7.4")
        catalog = fixture.write_catalog()
        fixture.track()
        recipes.load_catalog(fixture.root, catalog)
        source_lock = fixture.root / "recipes/gdb/aarch64/source.lock"
        source_lock.write_text(
            source_lock.read_text(encoding="utf-8").replace(
                "SOURCE_VERSION=7.4", "SOURCE_VERSION=bad/version"
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(recipes.CatalogError, "invalid SOURCE_VERSION"):
            recipes.load_catalog(fixture.root, catalog)

    def test_checksum_only_mode_is_explicit_and_visible(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        catalog = fixture.write_catalog()
        fixture.track()

        loaded = recipes.load_catalog(fixture.root, catalog)
        self.assertEqual("checksum-only", loaded[0].source_authentications[0].mode)
        output = io.StringIO()
        with redirect_stdout(output):
            result = recipes.main(
                ["validate", "--root", str(fixture.root), "--catalog", str(catalog)]
            )
        self.assertEqual(0, result)
        self.assertIn(
            "checksum-only (upstream signature unavailable or not adopted)",
            output.getvalue(),
        )

        lock_path = fixture.root / "recipes/gdb/aarch64/source.lock"
        lock_path.write_text(
            lock_path.read_text(encoding="utf-8")
            + "SOURCE_SIGNATURE=leftover.sig\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(recipes.CatalogError, "checksum-only forbids"):
            recipes.load_catalog(fixture.root, catalog)

    def test_authentication_mode_and_fingerprint_are_bounded(self) -> None:
        for mutation, old, new, expected_message in (
            (
                "missing mode",
                "SOURCE_AUTHENTICATION=checksum-only\n",
                "",
                "source.lock is missing: SOURCE_AUTHENTICATION",
            ),
            (
                "unknown mode",
                "SOURCE_AUTHENTICATION=checksum-only",
                "SOURCE_AUTHENTICATION=automatic",
                "SOURCE_AUTHENTICATION must be pgp or checksum-only",
            ),
        ):
            with self.subTest(mutation=mutation):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe()
                catalog = fixture.write_catalog()
                fixture.track()
                lock_path = fixture.root / "recipes/gdb/aarch64/source.lock"
                lock_path.write_text(
                    lock_path.read_text(encoding="utf-8").replace(old, new),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe(authentication="pgp")
        catalog = fixture.write_catalog()
        fixture.track()
        lock_path = fixture.root / "recipes/gdb/aarch64/source.lock"
        lock_path.write_text(
            lock_path.read_text(encoding="utf-8").replace(
                "SOURCE_SIGNER_FINGERPRINT="
                "1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D",
                "SOURCE_SIGNER_FINGERPRINT="
                "1f166a5742abb9e0249a8d30e089def1d9c15d0d",
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(recipes.CatalogError, "40 uppercase hexadecimal"):
            recipes.load_catalog(fixture.root, catalog)

    def test_valid_pgp_source_is_authenticated(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe(authentication="pgp")
        catalog = fixture.write_catalog()
        fixture.track()

        loaded = recipes.load_catalog(fixture.root, catalog)
        authentication = loaded[0].source_authentications[0]
        self.assertEqual("pgp", authentication.mode)
        self.assertEqual(
            "1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D",
            authentication.fingerprint,
        )

        command_directory = fixture.root / "test-commands"
        command_directory.mkdir()
        git_command = shutil.which("git")
        assert git_command is not None
        (command_directory / "git").symlink_to(git_command)
        with mock.patch.dict(os.environ, {"PATH": str(command_directory)}):
            with self.assertRaisesRegex(recipes.CatalogError, "cannot execute gpgv"):
                recipes.load_catalog(fixture.root, catalog)

    def test_pgp_evidence_state_is_enforced(self) -> None:
        cases = (
            ("corrupt signature", "invalid source PGP signature"),
            ("substituted key", "invalid source PGP signature"),
            ("wrong fingerprint", "source PGP signer mismatch"),
            ("missing signature", "missing regular source signature"),
            ("unsafe signature", "SOURCE_SIGNATURE must be a safe filename"),
            ("signature symlink", "missing regular source signature"),
            ("untracked signature", "untracked source signature"),
            ("wrong signature mode", "source signature has Git mode 100755"),
        )
        signature_name = "tcpdump-4.99.4.tar.gz.sig"
        key_name = "tcpdump-group-1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D.gpg"
        for mutation, expected_message in cases:
            with self.subTest(mutation=mutation):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe(authentication="pgp")
                catalog = fixture.write_catalog()
                fixture.track()
                source_dir = fixture.root / "recipes/gdb/aarch64/sources"
                signature_path = source_dir / signature_name
                relative_signature = (
                    f"recipes/gdb/aarch64/sources/{signature_name}"
                )
                lock_path = fixture.root / "recipes/gdb/aarch64/source.lock"

                if mutation == "corrupt signature":
                    signature_path.write_bytes(b"corrupt signature fixture\n")
                elif mutation == "substituted key":
                    shutil.copyfile(
                        REPOSITORY_ROOT
                        / "recipes/gdb/aarch64/sources"
                        / "gnu-gdb-F40ADB902B24264AA42E50BF92EDB04BFF325CF3.gpg",
                        source_dir / key_name,
                    )
                elif mutation == "wrong fingerprint":
                    lock_path.write_text(
                        lock_path.read_text(encoding="utf-8").replace(
                            "SOURCE_SIGNER_FINGERPRINT="
                            "1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D",
                            "SOURCE_SIGNER_FINGERPRINT=" + "0" * 40,
                        ),
                        encoding="utf-8",
                    )
                elif mutation == "missing signature":
                    signature_path.unlink()
                elif mutation == "unsafe signature":
                    lock_path.write_text(
                        lock_path.read_text(encoding="utf-8").replace(
                            f"SOURCE_SIGNATURE={signature_name}",
                            "SOURCE_SIGNATURE=../source.sig",
                        ),
                        encoding="utf-8",
                    )
                elif mutation == "signature symlink":
                    signature_path.unlink()
                    signature_path.symlink_to("tcpdump-4.99.4.tar.gz")
                elif mutation == "untracked signature":
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(fixture.root),
                            "rm",
                            "--cached",
                            "--",
                            relative_signature,
                        ],
                        check=True,
                        stdout=subprocess.DEVNULL,
                    )
                else:
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(fixture.root),
                            "update-index",
                            "--chmod=+x",
                            "--",
                            relative_signature,
                        ],
                        check=True,
                    )

                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_tcpdump_two_source_lock_is_bounded_and_validated(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe("tcpdump", architecture="x86_64", version="4.99.4")
        catalog = fixture.write_catalog()
        fixture.track()
        loaded = recipes.load_catalog(fixture.root, catalog)
        self.assertEqual("tcpdump", loaded[0].name)

        mutations = (
            (
                "missing dependency field",
                "LIBPCAP_LICENSE=BSD-3-Clause\n",
                "",
                "tcpdump source.lock is missing: LIBPCAP_LICENSE",
            ),
            (
                "malformed dependency checksum",
                "LIBPCAP_SHA256="
                + hashlib.sha256(b"libpcap-1.10.4 source fixture\n").hexdigest(),
                "LIBPCAP_SHA256=not-a-checksum",
                "LIBPCAP_SHA256 must be",
            ),
            (
                "unsafe dependency archive",
                "LIBPCAP_ARCHIVE=libpcap-1.10.4.tar.gz",
                "LIBPCAP_ARCHIVE=../libpcap.tar.gz",
                "LIBPCAP_ARCHIVE must be a safe filename",
            ),
            (
                "duplicate source archive",
                "LIBPCAP_ARCHIVE=libpcap-1.10.4.tar.gz",
                "LIBPCAP_ARCHIVE=tcpdump-4.99.4.tar.xz",
                "source archives must be distinct",
            ),
            (
                "obsolete release field",
                "LIBPCAP_LICENSE=BSD-3-Clause\n",
                "LIBPCAP_LICENSE=BSD-3-Clause\n"
                + "SOURCE_"
                + "MIRROR_URL=https://mirror.invalid/source\n",
                "unexpected fields: " + "SOURCE_" + "MIRROR_URL",
            ),
            (
                "unexpected third source field",
                "LIBPCAP_LICENSE=BSD-3-Clause\n",
                "LIBPCAP_LICENSE=BSD-3-Clause\nTHIRD_SOURCE_VERSION=1.0\n",
                "unexpected fields: THIRD_SOURCE_VERSION",
            ),
        )
        original_lock = (
            fixture.root / "recipes/tcpdump/x86_64/source.lock"
        ).read_text(encoding="utf-8")
        for label, old, new, expected_message in mutations:
            with self.subTest(label=label):
                lock_path = fixture.root / "recipes/tcpdump/x86_64/source.lock"
                lock_path.write_text(original_lock.replace(old, new), encoding="utf-8")
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_source_archive_state_is_enforced(self) -> None:
        cases = (
            ("missing", "missing regular source archive"),
            ("symlink", "missing regular source archive"),
            ("untracked", "untracked source archive"),
            ("wrong mode", "source archive has Git mode 100755"),
            ("corrupt", "source archive checksum does not match"),
        )
        for mutation, expected_message in cases:
            with self.subTest(mutation=mutation):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe()
                catalog = fixture.write_catalog()
                fixture.track()
                relative_archive = "recipes/gdb/aarch64/sources/gdb-1.0.tar.xz"
                archive_path = fixture.root / relative_archive

                if mutation == "missing":
                    archive_path.unlink()
                elif mutation == "symlink":
                    archive_path.unlink()
                    archive_path.symlink_to("../source.lock")
                elif mutation == "untracked":
                    subprocess.run(
                        ["git", "-C", str(fixture.root), "rm", "--cached", "--", relative_archive],
                        check=True,
                        stdout=subprocess.DEVNULL,
                    )
                elif mutation == "wrong mode":
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(fixture.root),
                            "update-index",
                            "--chmod=+x",
                            "--",
                            relative_archive,
                        ],
                        check=True,
                    )
                else:
                    archive_path.write_bytes(b"corrupt source fixture\n")

                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_unknown_header_is_rejected(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        catalog = fixture.write_catalog(header=("wrong", *recipes.FIELDS[1:]))
        with self.assertRaisesRegex(recipes.CatalogError, "header"):
            recipes.load_catalog(fixture.root, catalog)

    def test_duplicate_name_is_rejected(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        fixture.rows.append(dict(fixture.rows[0]))
        catalog = fixture.write_catalog()
        fixture.track()
        with self.assertRaisesRegex(recipes.CatalogError, "duplicate recipe name"):
            recipes.load_catalog(fixture.root, catalog)

    def test_unsafe_name_and_unsupported_architecture_are_rejected(self) -> None:
        for field, value, expected_message in (
            ("name", "../gdb", "invalid recipe name"),
            ("architecture", "amd64", "unsupported architecture"),
        ):
            with self.subTest(field=field):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                row = fixture.add_recipe()
                catalog = fixture.write_catalog()
                fixture.track()
                row[field] = value
                catalog = fixture.write_catalog()
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_missing_required_recipe_files_are_rejected(self) -> None:
        for relative_path, expected_message in (
            ("recipes/gdb/aarch64/Dockerfile", "Dockerfile"),
            ("recipes/gdb/aarch64/build.sh", "build script"),
            ("recipes/gdb/aarch64/source.lock", "source lock"),
            ("recipes/gdb/aarch64/licenses/NOTICE.md", "notice"),
            ("artifacts/aarch64/gdb", "committed output"),
            ("builders/aarch64/environment.lock", "environment lock"),
        ):
            with self.subTest(relative_path=relative_path):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe()
                catalog = fixture.write_catalog()
                fixture.track()
                (fixture.root / relative_path).unlink()
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_tracked_executable_mode_comes_from_git_index(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        catalog = fixture.write_catalog()
        fixture.track()
        build_script = "recipes/gdb/aarch64/build.sh"
        os.chmod(fixture.root / build_script, 0o755)
        subprocess.run(
            [
                "git",
                "-C",
                str(fixture.root),
                "update-index",
                "--chmod=-x",
                "--",
                build_script,
            ],
            check=True,
        )
        with self.assertRaisesRegex(recipes.CatalogError, "Git mode 100644"):
            recipes.load_catalog(fixture.root, catalog)

    def test_malformed_boolean_and_disabled_only_catalog_are_rejected(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        row = fixture.add_recipe()
        row["enabled"] = "yes"
        catalog = fixture.write_catalog()
        fixture.track()
        with self.assertRaisesRegex(recipes.CatalogError, "enabled must be"):
            recipes.load_catalog(fixture.root, catalog)

        temporary_directory2, fixture2 = self.make_fixture()
        self.addCleanup(temporary_directory2.cleanup)
        fixture2.add_recipe(enabled="false")
        catalog2 = fixture2.write_catalog()
        fixture2.track()
        with self.assertRaisesRegex(recipes.CatalogError, "no enabled recipes"):
            recipes.load_catalog(fixture2.root, catalog2)

    def test_dispatcher_lists_rejects_and_propagates_exit_status(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe(
            script_body=(
                "#!/usr/bin/env bash\n"
                'test "${CATALOG_TEST_VALUE:-}" = preserved\n'
                "exit 37\n"
            )
        )
        fixture.write_catalog()
        dispatcher = fixture.root / "build.sh"
        shutil.copy2(REPOSITORY_ROOT / "build.sh", dispatcher)
        os.chmod(dispatcher, 0o755)

        listed = subprocess.run(
            [str(dispatcher), "list"], check=False, capture_output=True, text=True
        )
        self.assertEqual(0, listed.returncode)
        self.assertEqual("gdb\n", listed.stdout)

        for arguments in ((), ("unknown",), ("../gdb",), ("gdb", "extra")):
            with self.subTest(arguments=arguments):
                rejected = subprocess.run(
                    [str(dispatcher), *arguments],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(2, rejected.returncode)

        environment = dict(os.environ, CATALOG_TEST_VALUE="preserved")
        dispatched = subprocess.run(
            [str(dispatcher), "gdb"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        self.assertEqual(37, dispatched.returncode)

        fixture.rows[0]["enabled"] = "false"
        fixture.write_catalog()
        disabled = subprocess.run(
            [str(dispatcher), "gdb"], check=False, capture_output=True, text=True
        )
        self.assertEqual(2, disabled.returncode)

    def test_dispatcher_rejects_duplicate_malformed_and_missing_script(self) -> None:
        for mutation in ("duplicate", "malformed", "missing"):
            with self.subTest(mutation=mutation):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                fixture.add_recipe()
                fixture.write_catalog()
                dispatcher = fixture.root / "build.sh"
                shutil.copy2(REPOSITORY_ROOT / "build.sh", dispatcher)
                os.chmod(dispatcher, 0o755)

                if mutation == "duplicate":
                    fixture.rows.append(dict(fixture.rows[0]))
                    fixture.write_catalog()
                elif mutation == "malformed":
                    fixture.rows[0]["enabled"] = "yes"
                    fixture.write_catalog()
                else:
                    (fixture.root / "recipes/gdb/aarch64/build.sh").unlink()

                result = subprocess.run(
                    [str(dispatcher), "list"],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(1, result.returncode)


if __name__ == "__main__":
    unittest.main()
