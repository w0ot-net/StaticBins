from __future__ import annotations

import importlib.util
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


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
        source_bytes = f"{name}-{version} source fixture\n".encode()
        source_archive = f"{name}-{version}.tar.xz"
        (source_dir / source_archive).write_bytes(source_bytes)
        source_lock = (
            f"SOURCE_VERSION={version}\n"
            f"SOURCE_ARCHIVE={source_archive}\n"
            f"SOURCE_SHA256={hashlib.sha256(source_bytes).hexdigest()}\n"
            f"SOURCE_UPSTREAM_URL=https://upstream.invalid/{name}.tar.xz\n"
            "SOURCE_LICENSE=GPL-3.0-or-later\n"
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

    def track(self) -> None:
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

    def test_valid_catalog_and_matrix_are_deterministic(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe()
        fixture.add_recipe("tool", architecture="x86_64", version="2.5")
        catalog = fixture.write_catalog()
        fixture.track()

        loaded = recipes.load_catalog(fixture.root, catalog)
        first = recipes.matrix(loaded)
        second = recipes.matrix(recipes.load_catalog(fixture.root, catalog))
        self.assertEqual(first, second)
        self.assertEqual(["gdb", "tool"], [entry["name"] for entry in first["include"]])
        self.assertEqual("linux/arm64", first["include"][0]["platform"])
        self.assertEqual("linux/amd64", first["include"][1]["platform"])
        self.assertEqual("static_bins-gdb", first["include"][0]["image_name"])
        self.assertEqual(
            "1.0-aarch64\naarch64-latest",
            first["include"][0]["tag_suffixes"],
        )
        self.assertEqual(
            "2.5-x86_64\nx86_64-latest",
            first["include"][1]["tag_suffixes"],
        )

    def test_version_is_derived_from_source_lock(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe(version="7.4")
        catalog = fixture.write_catalog()
        fixture.track()
        loaded = recipes.load_catalog(fixture.root, catalog)
        self.assertEqual("7.4", loaded[0].version)
        self.assertEqual(
            ("7.4-aarch64", "aarch64-latest"), loaded[0].tag_suffixes
        )

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

    def test_disabled_recipe_is_excluded_from_matrix(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        fixture.add_recipe("gdb")
        fixture.add_recipe("tool", enabled="false")
        catalog = fixture.write_catalog()
        fixture.track()
        catalog_matrix = recipes.matrix(recipes.load_catalog(fixture.root, catalog))
        self.assertEqual(["gdb"], [entry["name"] for entry in catalog_matrix["include"]])

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
