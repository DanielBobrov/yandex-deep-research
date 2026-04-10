#!/usr/bin/env bash
#
# serve.sh — Unified YandexDeepResearch service launcher (Backend Only)
#
# Usage:
#   ./scripts/serve.sh [--dev|--prod] [--gateway] [--daemon] [--stop|--restart]

set -e

REPO_ROOT="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
cd "$REPO_ROOT"

# ── Load .env ────────────────────────────────────────────────────────────────

if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

# ── Argument parsing ─────────────────────────────────────────────────────────

DEV_MODE=true
GATEWAY_MODE=false
DAEMON_MODE=false
SKIP_INSTALL=false
ACTION="start"

for arg in "$@"; do
    case "$arg" in
        --dev)     DEV_MODE=true ;;
        --prod)    DEV_MODE=false ;;
        --gateway) GATEWAY_MODE=true ;;
        --daemon)  DAEMON_MODE=true ;;
        --skip-install) SKIP_INSTALL=true ;;
        --stop)    ACTION="stop" ;;
        --restart) ACTION="restart" ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# ── Stop helper ──────────────────────────────────────────────────────────────

stop_all() {
    echo "Stopping all services..."
    pkill -f "langgraph dev" 2>/dev/null || true
    pkill -f "uvicorn app.gateway.app:app" 2>/dev/null || true
    ./scripts/cleanup-containers.sh yandex-deep-research-sandbox 2>/dev/null || true
    echo "✓ All services stopped"
}

if [ "$ACTION" = "stop" ]; then
    stop_all
    exit 0
fi

ALREADY_STOPPED=false
if [ "$ACTION" = "restart" ]; then
    stop_all
    sleep 1
    ALREADY_STOPPED=true
fi

if $GATEWAY_MODE; then
    export SKIP_LANGGRAPH_SERVER=1
fi

if $DEV_MODE && $GATEWAY_MODE; then
    MODE_LABEL="DEV + GATEWAY (experimental)"
elif $DEV_MODE; then
    MODE_LABEL="DEV (hot-reload enabled)"
elif $GATEWAY_MODE; then
    MODE_LABEL="PROD + GATEWAY (experimental)"
else
    MODE_LABEL="PROD (optimized)"
fi

if $DAEMON_MODE; then
    MODE_LABEL="$MODE_LABEL [daemon]"
fi

LANGGRAPH_EXTRA_FLAGS="--no-reload"
if $DEV_MODE && ! $DAEMON_MODE; then
    GATEWAY_EXTRA_FLAGS="--reload --reload-include='*.yaml' --reload-include='.env' --reload-exclude='*.pyc' --reload-exclude='__pycache__' --reload-exclude='sandbox/' --reload-exclude='.yandex-deep-research/'"
else
    GATEWAY_EXTRA_FLAGS=""
fi

if ! $ALREADY_STOPPED; then
    stop_all
    sleep 1
fi

if ! { \
        [ -n "$YANDEX_DEEP_RESEARCH_CONFIG_PATH" ] && [ -f "$YANDEX_DEEP_RESEARCH_CONFIG_PATH" ] || \
        [ -f backend/config.yaml ] || \
        [ -f config.yaml ]; \
    }; then
    echo "✗ No YandexDeepResearch config file found."
    exit 1
fi

"$REPO_ROOT/scripts/config-upgrade.sh"

if ! $SKIP_INSTALL; then
    echo "Syncing dependencies..."
    (cd backend && uv sync --quiet) || { echo "✗ Backend dependency install failed"; exit 1; }
    echo "✓ Dependencies synced"
fi

mkdir -p logs

run_service() {
    local name="$1"
    local cmd="$2"
    
    echo "Starting $name..."
    if $DAEMON_MODE; then
        nohup bash -c "$cmd" >/dev/null 2>&1 &
    else
        eval "$cmd &"
    fi
}

echo "================================================================="
echo "  🚀 Starting YandexDeepResearch ($MODE_LABEL)"
echo "================================================================="

if ! $GATEWAY_MODE; then
    run_service "LangGraph Server" \
        "cd backend && YANDEX_DEEP_RESEARCH_CONFIG_PATH=\"$REPO_ROOT/config.yaml\" uv run langgraph dev --host 127.0.0.1 --port 8123 > ../logs/langgraph.log 2>&1"
fi

run_service "Gateway API" \
    "cd backend && YANDEX_DEEP_RESEARCH_CONFIG_PATH=\"$REPO_ROOT/config.yaml\" uv run uvicorn app.gateway.app:app --host 0.0.0.0 --port 8000 $GATEWAY_EXTRA_FLAGS > ../logs/gateway.log 2>&1"

echo "================================================================="
echo "  ✨ Services Started Successfully"
echo ""
echo "    Gateway API → localhost:8000"
if ! $GATEWAY_MODE; then
    echo "    LangGraph   → localhost:8123"
fi
echo ""
echo "  📋 Logs: logs/{langgraph,gateway}.log"
echo "================================================================="

if ! $DAEMON_MODE; then
    echo "Press Ctrl+C to stop all services."
    wait
else
    echo "Running in daemon mode. Use './scripts/serve.sh --stop' to shut down."
fi
