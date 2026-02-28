#!/bin/bash
###############################################################################
#  Databricks Dev Setup — VS Code Tunnel + Keep-Alive
#
#  Usage:
#    curl -sL <YOUR_URL>/databricks_dev_setup.sh | bash
#
#    Or with custom keep-alive interval:
#    curl -sL <YOUR_URL>/databricks_dev_setup.sh | bash -s -- --interval 300
#
#  What it does:
#    1. Detects and prints cluster metadata (Cluster ID, Spark version, etc.)
#    2. Installs & starts VS Code Tunnel for remote development
#    3. Starts a Spark keep-alive loop to prevent auto-termination
###############################################################################

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
KEEPALIVE_INTERVAL=${KEEPALIVE_INTERVAL:-300}   # seconds between pings (default: 5 min)
TUNNEL_NAME=${TUNNEL_NAME:-"databricks-dev"}    # VS Code Tunnel display name
LOG_DIR="/tmp/devsetup"
TUNNEL_LOG="${LOG_DIR}/tunnel.log"
KEEPALIVE_LOG="${LOG_DIR}/keepalive.log"
SETUP_INFO="${LOG_DIR}/cluster_info.txt"

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)  KEEPALIVE_INTERVAL="$2"; shift 2 ;;
        --name)      TUNNEL_NAME="$2"; shift 2 ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "${LOG_DIR}"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🚀 Databricks Dev Environment Setup${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${NC}"; }

###############################################################################
#  STEP 1: Collect & Display Cluster Metadata
###############################################################################
collect_cluster_info() {
    section "📋 Cluster Information"

    # -- Cluster ID
    CLUSTER_ID=""
    if [ -f /databricks/init_scripts/.current_cluster_id ]; then
        CLUSTER_ID=$(cat /databricks/init_scripts/.current_cluster_id 2>/dev/null || true)
    fi
    if [ -z "$CLUSTER_ID" ] && [ -n "${DB_CLUSTER_ID:-}" ]; then
        CLUSTER_ID="${DB_CLUSTER_ID}"
    fi
    if [ -z "$CLUSTER_ID" ]; then
        CLUSTER_ID=$(grep -oP 'spark\.databricks\.clusterUsageTags\.clusterId\s+\K\S+' \
            /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")
    fi

    # -- Workspace URL
    WORKSPACE_URL=""
    if [ -n "${DATABRICKS_HOST:-}" ]; then
        WORKSPACE_URL="${DATABRICKS_HOST}"
    fi
    if [ -z "$WORKSPACE_URL" ]; then
        WORKSPACE_URL=$(grep -oP 'spark\.databricks\.workspaceUrl\s+\K\S+' \
            /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")
        if [ "$WORKSPACE_URL" != "unknown" ] && [[ ! "$WORKSPACE_URL" =~ ^https:// ]]; then
            WORKSPACE_URL="https://${WORKSPACE_URL}"
        fi
    fi

    # -- Cluster Name
    CLUSTER_NAME=$(grep -oP 'spark\.databricks\.clusterUsageTags\.clusterName\s+\K.*' \
        /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")

    # -- Spark / DBR Version
    SPARK_VERSION=$(grep -oP 'spark\.databricks\.clusterUsageTags\.sparkVersion\s+\K\S+' \
        /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")

    # -- Driver IP
    DRIVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

    # -- Python Path & Version
    PYTHON_PATH=$(which python3 2>/dev/null || which python 2>/dev/null || echo "/databricks/python3/bin/python")
    PYTHON_VERSION=$($PYTHON_PATH --version 2>&1 || echo "unknown")

    # -- Node type
    NODE_TYPE=$(grep -oP 'spark\.databricks\.clusterUsageTags\.clusterNodeType\s+\K\S+' \
        /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")

    # -- Num workers
    NUM_WORKERS=$(grep -oP 'spark\.databricks\.clusterUsageTags\.clusterWorkers\s+\K\S+' \
        /databricks/common/conf/deploy.conf 2>/dev/null || echo "unknown")

    # Print info
    echo -e "  ${BOLD}Cluster ID:${NC}     ${CYAN}${CLUSTER_ID}${NC}"
    echo -e "  ${BOLD}Cluster Name:${NC}   ${CLUSTER_NAME}"
    echo -e "  ${BOLD}Workspace URL:${NC}  ${WORKSPACE_URL}"
    echo -e "  ${BOLD}Spark/DBR:${NC}      ${SPARK_VERSION}"
    echo -e "  ${BOLD}Node Type:${NC}      ${NODE_TYPE}"
    echo -e "  ${BOLD}Workers:${NC}        ${NUM_WORKERS}"
    echo -e "  ${BOLD}Driver IP:${NC}      ${DRIVER_IP}"
    echo -e "  ${BOLD}Python:${NC}         ${PYTHON_VERSION} (${PYTHON_PATH})"
    echo ""

    # Save to file for easy reference
    cat > "${SETUP_INFO}" <<EOF
============================================================
  Databricks Cluster Info  —  $(date)
============================================================
  Cluster ID:     ${CLUSTER_ID}
  Cluster Name:   ${CLUSTER_NAME}
  Workspace URL:  ${WORKSPACE_URL}
  Spark/DBR:      ${SPARK_VERSION}
  Node Type:      ${NODE_TYPE}
  Workers:        ${NUM_WORKERS}
  Driver IP:      ${DRIVER_IP}
  Python:         ${PYTHON_VERSION} (${PYTHON_PATH})
============================================================

  ── For Keep-Alive API Script ──

  export DATABRICKS_HOST="${WORKSPACE_URL}"
  export DATABRICKS_TOKEN="dapi_YOUR_TOKEN_HERE"
  export DATABRICKS_CLUSTER_ID="${CLUSTER_ID}"

  ── Or use in curl ──

  WORKSPACE_URL="${WORKSPACE_URL}"
  TOKEN="dapi_YOUR_TOKEN_HERE"
  CLUSTER_ID="${CLUSTER_ID}"

============================================================
EOF

    info "Cluster info saved to: ${SETUP_INFO}"
}

###############################################################################
#  STEP 2: Install & Start VS Code Tunnel
###############################################################################
setup_vscode_tunnel() {
    section "🔗 VS Code Tunnel Setup"

    VSCODE_CLI="/tmp/code"

    # Check if already running
    if pgrep -f "code tunnel" > /dev/null 2>&1; then
        warn "VS Code Tunnel is already running!"
        warn "To restart: kill \$(pgrep -f 'code tunnel') && re-run this script"
        return 0
    fi

    # Download VS Code CLI if not present
    if [ ! -f "${VSCODE_CLI}" ]; then
        info "Downloading VS Code CLI..."
        curl -sLk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
            -o /tmp/vscode_cli.tar.gz

        if [ $? -ne 0 ]; then
            error "Failed to download VS Code CLI. Check network/firewall settings."
            error "Your company may block outbound connections to code.visualstudio.com"
            return 1
        fi

        tar -xzf /tmp/vscode_cli.tar.gz -C /tmp/ 2>/dev/null
        chmod +x "${VSCODE_CLI}"
        rm -f /tmp/vscode_cli.tar.gz
        info "VS Code CLI installed."
    else
        info "VS Code CLI already exists, reusing."
    fi

    # Start tunnel
    info "Starting VS Code Tunnel (name: ${TUNNEL_NAME})..."
    nohup "${VSCODE_CLI}" tunnel --accept-server-license-terms --name "${TUNNEL_NAME}" \
        > "${TUNNEL_LOG}" 2>&1 &
    TUNNEL_PID=$!

    # Wait and check for auth prompt
    sleep 3

    if ! kill -0 ${TUNNEL_PID} 2>/dev/null; then
        error "Tunnel process died. Check log: cat ${TUNNEL_LOG}"
        return 1
    fi

    # Check if auth is needed
    if grep -q "github.com/login/device" "${TUNNEL_LOG}" 2>/dev/null; then
        echo ""
        echo -e "  ${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${YELLOW}║  🔑 Authentication Required                             ║${NC}"
        echo -e "  ${YELLOW}╠══════════════════════════════════════════════════════════╣${NC}"
        AUTH_URL=$(grep -oP 'https://github.com/login/device' "${TUNNEL_LOG}" | head -1)
        AUTH_CODE=$(grep -oP 'code \K[A-Z0-9]{4}-[A-Z0-9]{4}' "${TUNNEL_LOG}" | head -1)
        echo -e "  ${YELLOW}║${NC}  1. Open: ${CYAN}${AUTH_URL}${NC}"
        echo -e "  ${YELLOW}║${NC}  2. Enter code: ${BOLD}${AUTH_CODE}${NC}"
        echo -e "  ${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        warn "After authenticating, the tunnel will be ready."
    else
        info "Tunnel starting... Check log for auth if needed: cat ${TUNNEL_LOG}"
    fi

    info "Tunnel PID: ${TUNNEL_PID}"
    info "Tunnel log: ${TUNNEL_LOG}"
    echo ""
    echo -e "  ${GREEN}Connect from VS Code:${NC}"
    echo -e "  ${BOLD}  Remote Explorer → Tunnels → ${TUNNEL_NAME}${NC}"
    echo -e "  ${BOLD}  Or: Ctrl+Shift+P → 'Remote-Tunnels: Connect to Tunnel'${NC}"
}

###############################################################################
#  STEP 3: Start Spark Keep-Alive
###############################################################################
start_keepalive() {
    section "💓 Keep-Alive Service"

    # Check if already running
    if pgrep -f "keepalive_worker" > /dev/null 2>&1; then
        warn "Keep-alive is already running!"
        warn "To restart: kill \$(pgrep -f 'keepalive_worker') && re-run this script"
        return 0
    fi

    info "Starting keep-alive (interval: ${KEEPALIVE_INTERVAL}s)..."

    # Create the keep-alive worker script
    cat > "${LOG_DIR}/keepalive_worker.sh" <<'KEEPALIVE_SCRIPT'
#!/bin/bash
LOG_FILE="${1}"
INTERVAL="${2}"

keepalive_spark() {
    # Method 1: Use pyspark directly on the cluster
    python3 -c "
from pyspark.sql import SparkSession
try:
    spark = SparkSession.builder.getOrCreate()
    spark.sql('SELECT 1').collect()
    print('OK: Spark ping succeeded')
except Exception as e:
    print(f'WARN: Spark ping failed: {e}')
" 2>&1
}

keepalive_notebook_api() {
    # Method 2: Execute via Databricks notebook-style context
    # This simulates notebook activity
    python3 -c "
import subprocess
try:
    result = subprocess.run(
        ['databricks', 'clusters', 'get', '--cluster-id', '$(cat /databricks/init_scripts/.current_cluster_id 2>/dev/null || echo unknown)'],
        capture_output=True, text=True, timeout=30
    )
    print('OK: API ping succeeded')
except Exception as e:
    print(f'WARN: API ping failed: {e}')
" 2>&1
}

echo "$(date '+%Y-%m-%d %H:%M:%S') | Keep-alive started (interval: ${INTERVAL}s)" >> "${LOG_FILE}"

while true; do
    RESULT=$(keepalive_spark 2>&1)
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${RESULT}" >> "${LOG_FILE}"

    # Trim log file if too large (keep last 500 lines)
    if [ "$(wc -l < "${LOG_FILE}" 2>/dev/null || echo 0)" -gt 500 ]; then
        tail -200 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    fi

    sleep "${INTERVAL}"
done
KEEPALIVE_SCRIPT

    chmod +x "${LOG_DIR}/keepalive_worker.sh"
    nohup bash "${LOG_DIR}/keepalive_worker.sh" "${KEEPALIVE_LOG}" "${KEEPALIVE_INTERVAL}" \
        > /dev/null 2>&1 &
    KEEPALIVE_PID=$!

    info "Keep-alive PID: ${KEEPALIVE_PID}"
    info "Keep-alive log: ${KEEPALIVE_LOG}"
}

###############################################################################
#  STEP 4: Print Summary & Quick-Reference
###############################################################################
print_summary() {
    section "✅ Setup Complete"

    echo ""
    echo -e "  ${BOLD}Quick Reference:${NC}"
    echo ""
    echo -e "  ${CYAN}View cluster info:${NC}     cat ${SETUP_INFO}"
    echo -e "  ${CYAN}View tunnel log:${NC}       cat ${TUNNEL_LOG}"
    echo -e "  ${CYAN}View keep-alive log:${NC}   tail -f ${KEEPALIVE_LOG}"
    echo ""
    echo -e "  ${CYAN}Stop tunnel:${NC}           kill \$(pgrep -f 'code tunnel')"
    echo -e "  ${CYAN}Stop keep-alive:${NC}       kill \$(pgrep -f 'keepalive_worker')"
    echo -e "  ${CYAN}Stop everything:${NC}       kill \$(pgrep -f 'code tunnel') \$(pgrep -f 'keepalive_worker')"
    echo ""

    # Print API keep-alive helper (for external use if Spark method fails)
    echo -e "  ${YELLOW}── If Spark keep-alive fails, use the API method from your local machine ──${NC}"
    echo ""
    echo -e "  ${BOLD}export DATABRICKS_HOST=\"${WORKSPACE_URL}\"${NC}"
    echo -e "  ${BOLD}export DATABRICKS_TOKEN=\"dapi_YOUR_TOKEN_HERE\"${NC}"
    echo -e "  ${BOLD}export DATABRICKS_CLUSTER_ID=\"${CLUSTER_ID}\"${NC}"
    echo ""
}

###############################################################################
#  Main
###############################################################################
banner
collect_cluster_info
setup_vscode_tunnel
start_keepalive
print_summary