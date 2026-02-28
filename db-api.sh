#!/bin/bash
###############################################################################
#  Databricks API Keep-Alive  —  Runs from your LOCAL machine
#
#  This uses the Databricks Execution Context API to submit commands,
#  which is the same pathway as notebook cells — guaranteed to be
#  recognized as cluster activity.
#
#  Usage:
#    export DATABRICKS_HOST="https://your-workspace.cloud.databricks.com"
#    export DATABRICKS_TOKEN="dapi_xxxxxxxxxxxxx"
#    export DATABRICKS_CLUSTER_ID="xxxx-xxxxxx-xxxxxxxx"
#    bash databricks_keepalive_api.sh
#
#  Or pass as arguments:
#    bash databricks_keepalive_api.sh \
#      --host "https://your-workspace.cloud.databricks.com" \
#      --token "dapi_xxxxxxxxxxxxx" \
#      --cluster "xxxx-xxxxxx-xxxxxxxx" \
#      --interval 300
###############################################################################

set -uo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
HOST="${DATABRICKS_HOST:-}"
TOKEN="${DATABRICKS_TOKEN:-}"
CLUSTER="${DATABRICKS_CLUSTER_ID:-}"
INTERVAL=300    # 5 minutes

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)     HOST="$2";     shift 2 ;;
        --token)    TOKEN="$2";    shift 2 ;;
        --cluster)  CLUSTER="$2";  shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--host URL] [--token TOKEN] [--cluster ID] [--interval SECONDS]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Validate ────────────────────────────────────────────────────────────────
if [ -z "$HOST" ] || [ -z "$TOKEN" ] || [ -z "$CLUSTER" ]; then
    echo "ERROR: Missing required configuration."
    echo ""
    echo "Set environment variables:"
    echo "  export DATABRICKS_HOST=\"https://your-workspace.cloud.databricks.com\""
    echo "  export DATABRICKS_TOKEN=\"dapi_xxxxxxxxxxxxx\""
    echo "  export DATABRICKS_CLUSTER_ID=\"xxxx-xxxxxx-xxxxxxxx\""
    echo ""
    echo "Or pass as arguments: $0 --host URL --token TOKEN --cluster ID"
    exit 1
fi

# Remove trailing slash from host
HOST="${HOST%/}"

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*"; }

# ─── Check cluster status ───────────────────────────────────────────────────
check_cluster_status() {
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X GET "${HOST}/api/2.0/clusters/get" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"cluster_id\": \"${CLUSTER}\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        error "Failed to get cluster status (HTTP ${HTTP_CODE})"
        return 1
    fi

    STATE=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','UNKNOWN'))" 2>/dev/null)
    echo "$STATE"
}

# ─── Create execution context ───────────────────────────────────────────────
create_context() {
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "${HOST}/api/1.2/contexts/create" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"clusterId\": \"${CLUSTER}\", \"language\": \"python\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        error "Failed to create context (HTTP ${HTTP_CODE}): ${BODY}"
        return 1
    fi

    CONTEXT_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    echo "$CONTEXT_ID"
}

# ─── Execute command ─────────────────────────────────────────────────────────
execute_command() {
    local context_id="$1"

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "${HOST}/api/1.2/commands/execute" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"clusterId\": \"${CLUSTER}\",
            \"contextId\": \"${context_id}\",
            \"language\": \"python\",
            \"command\": \"result = spark.sql('SELECT 1 as keep_alive').collect(); print(f'keep-alive OK: {result}')\"
        }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        error "Failed to execute command (HTTP ${HTTP_CODE})"
        return 1
    fi

    CMD_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','unknown'))" 2>/dev/null)
    echo "$CMD_ID"
}

# ─── Destroy context (cleanup) ──────────────────────────────────────────────
destroy_context() {
    local context_id="$1"
    curl -s -X POST "${HOST}/api/1.2/contexts/destroy" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"clusterId\": \"${CLUSTER}\", \"contextId\": \"${context_id}\"}" > /dev/null 2>&1
}

###############################################################################
#  Main Loop
###############################################################################
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  💓 Databricks API Keep-Alive                               ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Host:     ${HOST}"
echo -e "  Cluster:  ${CLUSTER}"
echo -e "  Interval: ${INTERVAL}s"
echo ""

# Verify cluster is running
info "Checking cluster status..."
STATE=$(check_cluster_status)
if [ "$STATE" != "RUNNING" ]; then
    error "Cluster is not running (state: ${STATE}). Start it first."
    exit 1
fi
info "Cluster is ${GREEN}RUNNING${NC}. Starting keep-alive loop..."
echo ""

PING_COUNT=0
FAIL_COUNT=0

# Trap Ctrl+C for clean exit
cleanup() {
    echo ""
    info "Stopping keep-alive..."
    if [ -n "${CURRENT_CONTEXT:-}" ]; then
        destroy_context "$CURRENT_CONTEXT"
    fi
    info "Total pings: ${PING_COUNT}, Failures: ${FAIL_COUNT}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Main loop
while true; do
    PING_COUNT=$((PING_COUNT + 1))

    # Check cluster state before pinging
    STATE=$(check_cluster_status 2>/dev/null)
    if [ "$STATE" != "RUNNING" ]; then
        warn "Cluster state: ${STATE}. Waiting for RUNNING..."
        sleep 30
        continue
    fi

    # Create context, execute, cleanup
    CONTEXT_ID=$(create_context 2>/dev/null)
    if [ -z "$CONTEXT_ID" ] || [ "$CONTEXT_ID" = "" ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        warn "Ping #${PING_COUNT} FAILED (context creation). Failures: ${FAIL_COUNT}"
    else
        CURRENT_CONTEXT="$CONTEXT_ID"
        CMD_ID=$(execute_command "$CONTEXT_ID" 2>/dev/null)
        if [ -z "$CMD_ID" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            warn "Ping #${PING_COUNT} FAILED (command execution). Failures: ${FAIL_COUNT}"
        else
            info "Ping #${PING_COUNT} ✓  (context: ${CONTEXT_ID:0:8}..., cmd: ${CMD_ID:0:8}...)"
        fi
        # Clean up context to avoid leaking
        destroy_context "$CONTEXT_ID"
        CURRENT_CONTEXT=""
    fi

    sleep "${INTERVAL}"
done