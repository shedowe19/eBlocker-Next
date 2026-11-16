#!/usr/bin/env bash
# Central-only mirror with normal TLS validation and strict artifact checksums.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
attempt_log=$(mktemp)
trap 'rm -f -- "$attempt_log"' EXIT

for attempt in 1 2 3; do
    : > "$attempt_log"
    set +e
    mvn -B -ntp --strict-checksums --update-snapshots \
        --settings "$script_dir/maven-settings.xml" \
        -Dstyle.color=never -Dmaven.wagon.rto=120000 \
        -Dmaven.wagon.httpconnectionManager.maxBackoffSeconds=30 \
        "$@" 2>&1 | tee "$attempt_log"
    statuses=("${PIPESTATUS[@]}")
    set -e
    result=${statuses[0]}
    if (( statuses[1] != 0 )); then
        exit "${statuses[1]}"
    fi
    if (( result == 0 )); then
        exit 0
    fi

    # Repeat only failed artifact transfers, never compiler, test or integrity failures.
    if (( attempt == 3 )) ||
       grep -Eiq '\[ERROR\].*(COMPILATION ERROR|There are test failures|There was an error in the forked process|Failed tests:|Checksum validation failed|ChecksumFailureException)' "$attempt_log"; then
        exit "$result"
    fi
    transport_errors=$(grep -Ei '\[ERROR\].*(Could not transfer artifact|Could not transfer metadata)' "$attempt_log" || true)
    if ! grep -Eiq '(status( code)?:?[[:space:]]*(408|429|500|502|503|504)|Too Many Requests|Read timed out|Connection reset|connect timed out|Connection timed out|Temporary failure in name resolution|UnknownHostException)' <<< "$transport_errors"; then
        exit "$result"
    fi
    delay=$((attempt * 10))
    printf 'Maven artifact transfer failed; retry %s/3 after %ss.\n' "$((attempt + 1))" "$delay" >&2
    sleep "$delay"
done
