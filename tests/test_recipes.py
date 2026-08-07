from __future__ import annotations

import importlib.util
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
        image: str | None = None,
        enabled: str = "true",
        script_body: str = "#!/usr/bin/env bash\nexit 37\n",
    ) -> dict[str, str]:
        config = recipes.ARCHITECTURES[architecture]
        scripts_dir = config["scripts_dir"]
        bins_dir = config["bins_dir"]
        recipe_dir = self.root / scripts_dir / name
        license_dir = recipe_dir / "licenses"
        output = self.root / bins_dir / name
        license_dir.mkdir(parents=True, exist_ok=True)
        output.parent.mkdir(parents=True, exist_ok=True)

        (self.root / scripts_dir / "environment.lock").write_text(
            "BUILDER_IMAGE=ghcr.io/example/static_bins-builder@sha256:"
            + "1" * 64
            + "\n",
            encoding="utf-8",
        )
        (recipe_dir / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        (recipe_dir / "source.lock").write_text(
            f"SOURCE_VERSION={version}\n"
            f"SOURCE_ARCHIVE={name}-{version}.tar.xz\n"
            f"SOURCE_SHA256={'2' * 64}\n"
            f"SOURCE_UPSTREAM_URL=https://upstream.invalid/{name}.tar.xz\n"
            f"SOURCE_MIRROR_URL=https://mirror.invalid/{name}.tar.xz\n"
            "SOURCE_LICENSE=GPL-3.0-or-later\n",
            encoding="utf-8",
        )
        (recipe_dir / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
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
            "version": version,
            "recipe_dir": f"{scripts_dir}/{name}",
            "build_script": f"{scripts_dir}/{name}/build.sh",
            "output": f"{bins_dir}/{name}",
            "image": image or f"ghcr.io/example/static_bins-{name}",
            "tags": f"{version}-{architecture};{architecture}-latest",
            "cache_scope": f"{architecture}-{name}",
            "runner": config["runner"],
            "enabled": enabled,
        }
        self.rows.append(row)
        return row

    def write_catalog(self, header: tuple[str, ...] = recipes.FIELDS) -> Path:
        catalog = self.root / "recipes.tsv"
        lines = ["\t".join(header)]
        for row in self.rows:
            lines.append("\t".join(row[field] for field in recipes.FIELDS))
        catalog.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return catalog

    def track(self) -> None:
        subprocess.run(["git", "-C", str(self.root), "add", "--", "."], check=True)
        executable_paths = []
        for row in self.rows:
            executable_paths.extend((row["build_script"], row["output"]))
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
        catalog = fixture.write_catalog()
        fixture.track()

        loaded = recipes.load_catalog(fixture.root, catalog)
        first = recipes.matrix(loaded)
        second = recipes.matrix(recipes.load_catalog(fixture.root, catalog))
        self.assertEqual(first, second)
        self.assertEqual(["gdb"], [entry["name"] for entry in first["include"]])
        self.assertEqual("linux/arm64", first["include"][0]["platform"])
        self.assertEqual(
            "ghcr.io/example/static_bins-gdb:1.0-aarch64\n"
            "ghcr.io/example/static_bins-gdb:aarch64-latest",
            first["include"][0]["tags"],
        )

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

    def test_duplicate_full_image_tag_is_rejected(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        first = fixture.add_recipe("gdb", image="ghcr.io/example/static_bins-tools")
        second = fixture.add_recipe("tool", image="ghcr.io/example/static_bins-tools")
        second["tags"] = first["tags"]
        catalog = fixture.write_catalog()
        fixture.track()
        with self.assertRaisesRegex(recipes.CatalogError, "duplicate image tag"):
            recipes.load_catalog(fixture.root, catalog)

    def test_path_traversal_and_wrong_output_are_rejected(self) -> None:
        for field, value, expected_message in (
            ("recipe_dir", "../gdb", "recipe_dir must be"),
            ("output", "x64_bins/gdb", "output must be"),
        ):
            with self.subTest(field=field):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                row = fixture.add_recipe()
                fixture.write_catalog()
                fixture.track()
                row[field] = value
                catalog = fixture.write_catalog()
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

    def test_missing_required_recipe_files_are_rejected(self) -> None:
        for relative_path, expected_message in (
            ("aarch64_alpine_build_scripts/gdb/Dockerfile", "Dockerfile"),
            ("aarch64_alpine_build_scripts/gdb/build.sh", "build script"),
            ("aarch64_alpine_build_scripts/gdb/source.lock", "source lock"),
            ("aarch64_alpine_build_scripts/gdb/licenses/NOTICE.md", "notice"),
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
        row = fixture.add_recipe()
        catalog = fixture.write_catalog()
        fixture.track()
        os.chmod(fixture.root / row["build_script"], 0o755)
        subprocess.run(
            [
                "git",
                "-C",
                str(fixture.root),
                "update-index",
                "--chmod=-x",
                "--",
                row["build_script"],
            ],
            check=True,
        )
        with self.assertRaisesRegex(recipes.CatalogError, "Git mode 100644"):
            recipes.load_catalog(fixture.root, catalog)

    def test_invalid_runner_and_disabled_only_catalog_are_rejected(self) -> None:
        temporary_directory, fixture = self.make_fixture()
        self.addCleanup(temporary_directory.cleanup)
        row = fixture.add_recipe()
        row["runner"] = "self-hosted"
        catalog = fixture.write_catalog()
        fixture.track()
        with self.assertRaisesRegex(recipes.CatalogError, "runner"):
            recipes.load_catalog(fixture.root, catalog)

        temporary_directory2, fixture2 = self.make_fixture()
        self.addCleanup(temporary_directory2.cleanup)
        fixture2.add_recipe(enabled="false")
        catalog2 = fixture2.write_catalog()
        fixture2.track()
        with self.assertRaisesRegex(recipes.CatalogError, "no enabled recipes"):
            recipes.load_catalog(fixture2.root, catalog2)

    def test_malformed_boolean_and_tag_list_are_rejected(self) -> None:
        for field, value, expected_message in (
            ("enabled", "yes", "enabled must be"),
            ("tags", "1.0-aarch64;1.0-aarch64", "tags must be unique"),
        ):
            with self.subTest(field=field):
                temporary_directory, fixture = self.make_fixture()
                self.addCleanup(temporary_directory.cleanup)
                row = fixture.add_recipe()
                row[field] = value
                catalog = fixture.write_catalog()
                fixture.track()
                with self.assertRaisesRegex(recipes.CatalogError, expected_message):
                    recipes.load_catalog(fixture.root, catalog)

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


if __name__ == "__main__":
    unittest.main()
