#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="${TMPDIR:-/tmp}/imageview-memory-fixtures"
RESULT_DIR="$ROOT_DIR/docs/assets/performance"
RESULT_FILE="$RESULT_DIR/memory-baseline-$(date +%Y-%m-%d-%H%M%S).md"
APP="$ROOT_DIR/.build/ImageView.app"
EXECUTABLE="$APP/Contents/MacOS/ImageView"

mkdir -p "$RESULT_DIR"
swift "$ROOT_DIR/scripts/generate-memory-fixtures.swift" "$FIXTURE_DIR" >/dev/null
"$ROOT_DIR/scripts/build-app.sh" >/dev/null

measure() {
    local name="$1"
    local target="$2"
    local limit_mib="$3"
    local mode="${4:-default}"
    local launch_arguments=(--benchmark-open "$target")
    if [[ "$mode" == "filmstrip" ]]; then
        launch_arguments+=(--benchmark-show-filmstrip)
    fi
    "$EXECUTABLE" "${launch_arguments[@]}" &
    local pid="$!"
    for _ in $(seq 1 80); do
        kill -0 "$pid" 2>/dev/null && break
        sleep 0.1
    done
    kill -0 "$pid" 2>/dev/null || { echo "Could not start ImageView process" >&2; return 1; }

    local peak=0
    local ending=0
    for _ in $(seq 1 60); do
        local rss
        rss="$(ps -o rss= -p "$pid" | tr -d ' ' || true)"
        if [[ "$rss" =~ ^[0-9]+$ ]]; then
            ending="$rss"
            (( rss > peak )) && peak="$rss"
        fi
        sleep 0.1
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    local peak_mib
    local ending_mib
    peak_mib="$(awk -v kib="$peak" 'BEGIN { printf "%.1f", kib / 1024 }')"
    ending_mib="$(awk -v kib="$ending" 'BEGIN { printf "%.1f", kib / 1024 }')"
    local status="PASS"
    if ! awk -v peak="$peak_mib" -v limit="$limit_mib" 'BEGIN { exit !(peak <= limit) }'; then
        status="FAIL"
        FAILED=1
    fi
    printf '| %s | %s | %s | %s | %s | %s |\n' "$name" "$(basename "$target")" "$peak_mib" "$ending_mib" "$limit_mib" "$status" >>"$RESULT_FILE"
}

{
    echo "# ImageView memory baseline"
    echo
    echo "- Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- macOS: $(sw_vers -productVersion)"
    echo "- Hardware: $(uname -m)"
    echo "- Sampling: peak resident memory sampled every 100 ms for 6 seconds after launch"
    echo
    echo '| Scenario | Fixture | Peak RSS (MiB) | Ending RSS (MiB) | Gate (MiB) | Status |'
    echo '| --- | --- | ---: | ---: | ---: | --- |'
} >"$RESULT_FILE"

FAILED=0
measure "Small image" "$FIXTURE_DIR/small/small-512.png" 180
measure "Large image" "$FIXTURE_DIR/large/large-8000.png" 1100
measure "Animated image" "$FIXTURE_DIR/animated/animated-24x1200.gif" 300
measure "1,000-image folder grid" "$FIXTURE_DIR/directory-1000" 220
measure "1,000-image viewer with filmstrip" "$FIXTURE_DIR/directory-1000/image-0500.png" 300 filmstrip

echo "$RESULT_FILE"
exit "$FAILED"
