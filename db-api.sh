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
#    bash db-api.sh
#
#  Or pass as arguments:
#    bash db-api.sh --host "https://..." --token "dapi_..." --interval 300
#
#  Optionally skip interactive selection:
#    bash db-api.sh --cluster "xxxx-xxxxxx-xxxxxxxx"
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
            echo ""
            echo "If --cluster is omitted, running clusters will be listed for interactive selection."
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Validate ────────────────────────────────────────────────────────────────
if [ -z "$HOST" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: Missing required configuration."
    echo ""
    echo "Set environment variables:"
    echo "  export DATABRICKS_HOST=\"https://your-workspace.cloud.databricks.com\""
    echo "  export DATABRICKS_TOKEN=\"dapi_xxxxxxxxxxxxx\""
    echo ""
    echo "Or pass as arguments: $0 --host URL --token TOKEN"
    exit 1
fi

# Remove trailing slash from host
HOST="${HOST%/}"

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*"; }

# ─── List running clusters ───────────────────────────────────────────────────
list_running_clusters() {
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X GET "${HOST}/api/2.0/clusters/list" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        error "Failed to list clusters (HTTP ${HTTP_CODE})"
        return 1
    fi

    # Output: tab-separated lines of "cluster_id\tcluster_name\tstate\tcreator"
    echo "$BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
clusters = data.get('clusters', [])
for c in clusters:
    state = c.get('state', 'UNKNOWN')
    cid = c.get('cluster_id', '')
    name = c.get('cluster_name', 'unnamed')
    creator = c.get('creator_user_name', 'unknown')
    source = c.get('cluster_source', '')
    # Show RUNNING and PENDING clusters
    if state in ('RUNNING', 'RESIZING', 'PENDING'):
        print(f'{cid}\t{name}\t{state}\t{creator}')
" 2>/dev/null
}

# ─── Check cluster status ───────────────────────────────────────────────────
check_cluster_status() {
    local cluster_id="$1"
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X GET "${HOST}/api/2.0/clusters/get" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"cluster_id\": \"${cluster_id}\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        echo "ERROR"
        return 1
    fi

    echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','UNKNOWN'))" 2>/dev/null
}

# ─── Create execution context ───────────────────────────────────────────────
create_context() {
    local cluster_id="$1"
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "${HOST}/api/1.2/contexts/create" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"clusterId\": \"${cluster_id}\", \"language\": \"python\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        return 1
    fi

    echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null
}

# ─── Execute command ─────────────────────────────────────────────────────────
execute_command() {
    local cluster_id="$1"
    local context_id="$2"

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "${HOST}/api/1.2/commands/execute" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"clusterId\": \"${cluster_id}\",
            \"contextId\": \"${context_id}\",
            \"language\": \"python\",
            \"command\": \"result = spark.sql('SELECT 1 as keep_alive').collect(); print(f'keep-alive OK: {result}')\"
        }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" != "200" ]; then
        return 1
    fi

    echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','unknown'))" 2>/dev/null
}

# ─── Destroy context (cleanup) ──────────────────────────────────────────────
destroy_context() {
    local cluster_id="$1"
    local context_id="$2"
    curl -s -X POST "${HOST}/api/1.2/contexts/destroy" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"clusterId\": \"${cluster_id}\", \"contextId\": \"${context_id}\"}" > /dev/null 2>&1
}

# ─── Ping one cluster ───────────────────────────────────────────────────────
ping_cluster() {
    local cluster_id="$1"
    local cluster_name="$2"

    # Check cluster state
    local state
    state=$(check_cluster_status "$cluster_id" 2>/dev/null)
    if [ "$state" != "RUNNING" ]; then
        warn "  [${cluster_name}] state=${state}, skipping"
        return 1
    fi

    # Create context, execute, cleanup
    local ctx_id
    ctx_id=$(create_context "$cluster_id" 2>/dev/null)
    if [ -z "$ctx_id" ]; then
        warn "  [${cluster_name}] context creation failed"
        return 1
    fi

    local cmd_id
    cmd_id=$(execute_command "$cluster_id" "$ctx_id" 2>/dev/null)
    destroy_context "$cluster_id" "$ctx_id"

    if [ -z "$cmd_id" ]; then
        warn "  [${cluster_name}] command execution failed"
        return 1
    fi

    info "  [${cluster_name}] ping OK"
    return 0
}

###############################################################################
#  Interactive Cluster Selection
###############################################################################

# Arrays to hold selected clusters
SELECTED_IDS=()
SELECTED_NAMES=()

if [ -n "$CLUSTER" ]; then
    # --cluster was provided, use it directly
    SELECTED_IDS+=("$CLUSTER")
    SELECTED_NAMES+=("$CLUSTER")
else
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Databricks API Keep-Alive                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Fetching running clusters from ${HOST} ..."
    echo ""

    # Fetch cluster list
    CLUSTER_LIST=$(list_running_clusters)

    if [ -z "$CLUSTER_LIST" ]; then
        error "No running clusters found. Start a cluster first."
        exit 1
    fi

    # Parse into arrays
    CL_IDS=()
    CL_NAMES=()
    CL_STATES=()
    CL_CREATORS=()

    while IFS=$'\t' read -r cid cname cstate ccreator; do
        CL_IDS+=("$cid")
        CL_NAMES+=("$cname")
        CL_STATES+=("$cstate")
        CL_CREATORS+=("$ccreator")
    done <<< "$CLUSTER_LIST"

    COUNT=${#CL_IDS[@]}

    # Display table
    echo -e "  ${BOLD}#   Cluster Name                          State      Creator${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${NC}"
    for i in $(seq 0 $((COUNT - 1))); do
        local_state="${CL_STATES[$i]}"
        if [ "$local_state" = "RUNNING" ]; then
            state_color="${GREEN}"
        else
            state_color="${YELLOW}"
        fi
        printf "  ${BOLD}%-3s${NC} %-40s ${state_color}%-10s${NC} %s\n" \
            "$((i + 1))" "${CL_NAMES[$i]}" "${CL_STATES[$i]}" "${CL_CREATORS[$i]}"
    done
    echo ""

    # Prompt for selection
    echo -e "  Enter cluster numbers to keep alive (space-separated, or ${BOLD}a${NC} for all):"
    echo -ne "  > "
    read -r SELECTION

    if [ -z "$SELECTION" ]; then
        error "No selection made. Exiting."
        exit 1
    fi

    if [ "$SELECTION" = "a" ] || [ "$SELECTION" = "A" ] || [ "$SELECTION" = "all" ]; then
        SELECTED_IDS=("${CL_IDS[@]}")
        SELECTED_NAMES=("${CL_NAMES[@]}")
    else
        for num in $SELECTION; do
            # Validate number
            if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$COUNT" ]; then
                warn "Ignoring invalid selection: $num"
                continue
            fi
            idx=$((num - 1))
            SELECTED_IDS+=("${CL_IDS[$idx]}")
            SELECTED_NAMES+=("${CL_NAMES[$idx]}")
        done
    fi

    if [ ${#SELECTED_IDS[@]} -eq 0 ]; then
        error "No valid clusters selected. Exiting."
        exit 1
    fi
fi

###############################################################################
#  Main Loop
###############################################################################
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  Keep-Alive Active                                          ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Host:     ${HOST}"
echo -e "  Interval: ${INTERVAL}s"
echo -e "  Targets:  ${#SELECTED_IDS[@]} cluster(s)"
for i in $(seq 0 $((${#SELECTED_IDS[@]} - 1))); do
    echo -e "    - ${SELECTED_NAMES[$i]} ${DIM}(${SELECTED_IDS[$i]})${NC}"
done
echo ""

PING_COUNT=0
FAIL_COUNT=0
SUCCESS_COUNT=0

# Trap Ctrl+C for clean exit
cleanup() {
    echo ""
    info "Stopping keep-alive..."
    info "Total rounds: ${PING_COUNT}, Successes: ${SUCCESS_COUNT}, Failures: ${FAIL_COUNT}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Main loop
while true; do
    PING_COUNT=$((PING_COUNT + 1))
    info "Round #${PING_COUNT} — pinging ${#SELECTED_IDS[@]} cluster(s)..."

    for i in $(seq 0 $((${#SELECTED_IDS[@]} - 1))); do
        if ping_cluster "${SELECTED_IDS[$i]}" "${SELECTED_NAMES[$i]}"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done

    echo ""
    sleep "${INTERVAL}"
done
