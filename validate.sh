#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for command_name in bash git gpgv head python3 sh; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command not found: ${command_name}" >&2
        exit 1
    fi
done

cd "${REPO_ROOT}"

python3 scripts/recipes.py validate
python3 -m unittest tests.test_recipes
./build.sh list

while IFS= read -r -d '' script; do
    case "$(head -n 1 "${script}")" in
        *bash*) bash -n "${script}" ;;
        *sh*) sh -n "${script}" ;;
    esac
done < <(git ls-files -z '*.sh')
