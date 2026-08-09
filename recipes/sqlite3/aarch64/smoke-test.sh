#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 SQLITE3 EXPECTED_VERSION" >&2
    exit 2
fi

sqlite_binary="$1"
expected_version="$2"
temporary_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

version_output="$(${sqlite_binary} --version)"
printf '%s\n' "${version_output}"
if [ "$(printf '%s\n' "${version_output}" | awk '{print $1}')" != \
    "${expected_version}" ]; then
    echo "error: unexpected SQLite version" >&2
    exit 1
fi

compile_options="$(${sqlite_binary} ':memory:' 'pragma compile_options;')"
for option in \
    DQS=0 ENABLE_DBPAGE_VTAB ENABLE_DBSTAT_VTAB ENABLE_EXPLAIN_COMMENTS \
    ENABLE_FTS5 \
    ENABLE_MATH_FUNCTIONS ENABLE_RTREE OMIT_LOAD_EXTENSION THREADSAFE=1; do
    if ! printf '%s\n' "${compile_options}" | grep -Fxq "${option}"; then
        echo "error: SQLite compile option is missing: ${option}" >&2
        exit 1
    fi
done
if printf '%s\n' "${compile_options}" | grep -Eq 'ENABLE_(ICU|LOAD_EXTENSION)|OMIT_JSON'; then
    echo "error: SQLite optional feature surface drifted" >&2
    exit 1
fi
if "${sqlite_binary}" ':memory:' '.help' | grep -Eq '^[.]load[[:space:]]'; then
    echo "error: SQLite shell unexpectedly exposes dynamic extension loading" >&2
    exit 1
fi
if ! "${sqlite_binary}" ':memory:' '.help recover' | grep -Eq '^[.]recover'; then
    echo "error: SQLite shell is missing the recovery command" >&2
    exit 1
fi
recovery_source="${temporary_dir}/recovery-source.db"
recovery_output="${temporary_dir}/recovery-output.db"
recovery_sql="${temporary_dir}/recovery.sql"
"${sqlite_binary}" "${recovery_source}" \
    "create table recovery_probe(value text); insert into recovery_probe values('preserved');"
"${sqlite_binary}" "${recovery_source}" '.recover' > "${recovery_sql}"
"${sqlite_binary}" "${recovery_output}" < "${recovery_sql}" > /dev/null
if [ "$("${sqlite_binary}" "${recovery_output}" \
    'select value from recovery_probe;')" != preserved ]; then
    echo "error: SQLite recovery command did not preserve controlled data" >&2
    exit 1
fi

database="${temporary_dir}/primary.db"
backup="${temporary_dir}/backup.db"
cat > "${temporary_dir}/commands.sql" <<SQL
.bail on
CREATE TABLE items(id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
INSERT INTO items(payload) VALUES('{"name":"alpha","value":7}'),('{"name":"beta","value":11}');
CREATE VIRTUAL TABLE docs USING fts5(body);
INSERT INTO docs(body) VALUES('static sqlite recovery'),('network diagnostics');
CREATE VIRTUAL TABLE boxes USING rtree(id,min_x,max_x,min_y,max_y);
INSERT INTO boxes VALUES(1,0,10,0,10),(2,20,30,20,30);
SELECT json_extract(payload,'$.name') || ':' || json_extract(payload,'$.value') FROM items ORDER BY id;
SELECT group_concat(rowid, ',') FROM docs WHERE docs MATCH 'sqlite';
SELECT count(*) FROM boxes WHERE min_x >= 20;
SELECT sqrt(81);
PRAGMA integrity_check;
.backup '${backup}'
SQL
"${sqlite_binary}" "${database}" < "${temporary_dir}/commands.sql" \
    > "${temporary_dir}/results.txt"
cat > "${temporary_dir}/expected.txt" <<'EOF'
alpha:7
beta:11
1
1
9.0
ok
EOF
cmp "${temporary_dir}/expected.txt" "${temporary_dir}/results.txt"

backup_result="$(printf '%s\n' \
    "select printf('%d:%d', count(*), sum(json_extract(payload, '$.value'))) from items;" |
    "${sqlite_binary}" "${backup}")"
if [ "${backup_result}" != '2:18' ]; then
    echo "error: SQLite backup did not preserve the controlled database" >&2
    exit 1
fi

echo "validated SQLite recovery, JSON, FTS5, RTree, math, integrity, and backup behavior"
