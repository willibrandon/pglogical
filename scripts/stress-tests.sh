#!/usr/bin/env bash
#
# stress-tests.sh - Run pglogical regression tests repeatedly to catch flaky tests
#
# Usage:
#   ./stress-tests.sh [OPTIONS]
#
# Options:
#   -n, --runs N         Number of times to run the test suite (default: 10)
#   -s, --stop-on-fail   Stop running after the first failure
#   -h, --help           Show this help message
#
# Examples:
#   ./stress-tests.sh -n 5
#   ./stress-tests.sh --runs 10 --stop-on-fail
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Default values
RUNS=10
STOP_ON_FAILURE=false

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_ROOT/test-results"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--runs)
            RUNS="$2"
            shift 2
            ;;
        -s|--stop-on-fail)
            STOP_ON_FAILURE=true
            shift
            ;;
        -h|--help)
            head -20 "$0" | tail -18
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create results directory
mkdir -p "$RESULTS_DIR"

# Track results
declare -A FAILED_TESTS
PASSED_RUNS=0
FAILED_RUNS=0
START_TIME=$(date +%s)

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}pglogical Stress Test Runner${NC}"
echo -e "${CYAN}========================================${NC}"
echo "Runs planned: $RUNS"
echo "Stop on failure: $STOP_ON_FAILURE"
echo "Results dir: $RESULTS_DIR"
echo "Started at: $(date)"
echo -e "${CYAN}========================================${NC}"
echo ""

for ((i=1; i<=RUNS; i++)); do
    RUN_START=$(date +%s)
    echo -e "${YELLOW}Run $i of $RUNS starting at $(date)...${NC}"

    # Clean previous results
    rm -f "$PROJECT_ROOT/regression.diffs" "$PROJECT_ROOT/regression.out"

    # Run tests and capture output
    cd "$PROJECT_ROOT"
    TEST_OUTPUT=$(make check 2>&1 || true)
    RUN_END=$(date +%s)
    DURATION=$((RUN_END - RUN_START))

    # Parse results
    PASSED=()
    FAILED=()

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*ok[[:space:]]+[0-9]+[[:space:]]+-[[:space:]]+([^[:space:]]+) ]]; then
            PASSED+=("${BASH_REMATCH[1]}")
        elif [[ $line =~ ^[[:space:]]*not[[:space:]]+ok[[:space:]]+[0-9]+[[:space:]]+-[[:space:]]+([^[:space:]]+) ]]; then
            TEST_NAME="${BASH_REMATCH[1]}"
            FAILED+=("$TEST_NAME")
            # Track which runs each test failed in
            if [[ -z "${FAILED_TESTS[$TEST_NAME]}" ]]; then
                FAILED_TESTS[$TEST_NAME]="$i"
            else
                FAILED_TESTS[$TEST_NAME]="${FAILED_TESTS[$TEST_NAME]}, $i"
            fi
        fi
    done <<< "$TEST_OUTPUT"

    # Save artifacts for failed runs
    if [[ ${#FAILED[@]} -gt 0 ]]; then
        RUN_DIR="$RESULTS_DIR/run-$i"
        mkdir -p "$RUN_DIR"

        [[ -f "$PROJECT_ROOT/regression.diffs" ]] && cp "$PROJECT_ROOT/regression.diffs" "$RUN_DIR/"
        [[ -f "$PROJECT_ROOT/regression.out" ]] && cp "$PROJECT_ROOT/regression.out" "$RUN_DIR/"
        [[ -d "$PROJECT_ROOT/results" ]] && cp -r "$PROJECT_ROOT/results" "$RUN_DIR/"
        [[ -d "$PROJECT_ROOT/log" ]] && cp -r "$PROJECT_ROOT/log" "$RUN_DIR/"

        echo "$TEST_OUTPUT" > "$RUN_DIR/output.txt"

        FAILED_RUNS=$((FAILED_RUNS + 1))
        echo -e "  ${RED}Run $i FAILED (${#FAILED[@]} failures: ${FAILED[*]})${NC}"
        echo -e "  ${GRAY}Artifacts saved to: $RUN_DIR${NC}"

        if [[ "$STOP_ON_FAILURE" == true ]]; then
            echo ""
            echo -e "${YELLOW}Stopping due to --stop-on-fail flag.${NC}"
            break
        fi
    else
        PASSED_RUNS=$((PASSED_RUNS + 1))
        echo -e "  ${GREEN}Run $i PASSED (${#PASSED[@]} tests in ${DURATION}s)${NC}"
    fi
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_MINUTES=$((TOTAL_DURATION / 60))

# Summary
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}========================================${NC}"
echo "Total runs: $((PASSED_RUNS + FAILED_RUNS))"
echo "Total time: ${TOTAL_MINUTES} minutes"
echo ""

echo -e "${GREEN}Passed runs: $PASSED_RUNS${NC}"
if [[ $FAILED_RUNS -gt 0 ]]; then
    echo -e "${RED}Failed runs: $FAILED_RUNS${NC}"
else
    echo -e "${GREEN}Failed runs: $FAILED_RUNS${NC}"
fi
echo ""

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Flaky tests detected:${NC}"
    for test in "${!FAILED_TESTS[@]}"; do
        RUNS_FAILED="${FAILED_TESTS[$test]}"
        # Count failures
        FAIL_COUNT=$(echo "$RUNS_FAILED" | tr ',' '\n' | wc -l)
        TOTAL_RUNS=$((PASSED_RUNS + FAILED_RUNS))
        FAIL_RATE=$(echo "scale=1; $FAIL_COUNT * 100 / $TOTAL_RUNS" | bc)
        echo -e "  ${RED}$test - failed in runs: $RUNS_FAILED ($FAIL_RATE% failure rate)${NC}"
    done | sort
else
    echo -e "${GREEN}No flaky tests detected across $((PASSED_RUNS + FAILED_RUNS)) runs!${NC}"
fi

echo ""
echo -e "${GRAY}Results saved to: $RESULTS_DIR${NC}"

# Return exit code based on whether any tests failed
if [[ $FAILED_RUNS -gt 0 ]]; then
    exit 1
else
    exit 0
fi
