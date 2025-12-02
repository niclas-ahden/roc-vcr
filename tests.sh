#!/usr/bin/env bash
# Run all tests for roc-vcr

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== roc-vcr Test Suite ==="
echo

# Track overall status
FAILED=0

# Mock tests (fast, no network)
echo "--- Mock Tests ---"
if roc run test/VcrMockTest.roc; then
    echo
else
    echo "Mock tests FAILED"
    FAILED=1
fi

# Integration tests (requires network)
echo "--- Integration Tests ---"
if roc run test/VcrIntegrationTest.roc; then
    echo
else
    echo "Integration tests FAILED"
    FAILED=1
fi

# Crash tests (bash-based)
echo "--- Crash Tests ---"
if ./test/crash/run_crash_tests.sh; then
    echo
else
    echo "Crash tests FAILED"
    FAILED=1
fi

# Summary
echo "=== Test Suite Complete ==="
if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
else
    echo "Some tests failed."
    exit 1
fi
