#!/usr/bin/env bash
# Crash scenario tests for roc-vcr
# These tests verify that VCR crashes with the expected error messages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

PASSED=0
FAILED=0

# Test helper function
run_crash_test() {
    local test_name="$1"
    local test_file="$2"
    local expected_msg="$3"

    echo -n "Testing $test_name... "

    # Run the test with timeout and capture output (expect it to fail)
    output=$(timeout 120 roc run "$test_file" 2>&1) || true

    if [[ "$output" == *"$expected_msg"* ]]; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        echo "  Expected: $expected_msg"
        echo "  Got: $output"
        FAILED=$((FAILED + 1))
    fi
}

# Cleanup function - must make dirs writable before removing
cleanup() {
    chmod -R u+w test/crash/cassettes_readonly 2>/dev/null || true
    rm -rf test/crash/cassettes test/crash/cassettes_readonly
}

# Setup
trap cleanup EXIT
mkdir -p test/crash/cassettes

echo "=== VCR Crash Tests ==="
echo

# Test 1: Decode error (malformed JSON)
run_crash_test "decode_error" \
    "test/crash/test_decode_error.roc" \
    "VCR: Failed to decode cassette"

# Test 2: Replay not found (empty cassette)
run_crash_test "replay_not_found" \
    "test/crash/test_replay_not_found.roc" \
    "VCR Replay mode: No matching interaction found"

# Test 3: Save error (read-only directory)
# Setup: create read-only directory
mkdir -p test/crash/cassettes_readonly
chmod 555 test/crash/cassettes_readonly

run_crash_test "save_error" \
    "test/crash/test_save_error.roc" \
    "VCR: Failed to save cassette"

# Make writable again for next test setup
chmod 755 test/crash/cassettes_readonly

# Test 4: Delete error (cassette in read-only directory)
# Setup: create cassette then make directory read-only
echo '{"name":"cannot_delete","interactions":[]}' > test/crash/cassettes_readonly/cannot_delete.json
chmod 555 test/crash/cassettes_readonly

run_crash_test "delete_error" \
    "test/crash/test_delete_error.roc" \
    "VCR: Failed to delete cassette"

# Summary
echo
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
