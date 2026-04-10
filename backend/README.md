# Yandex Deep Research Backend

Yandex Deep Research is a LangGraph-based AI super agent with sandbox execution, persistent memory, and extensible tool integration. The backend enables AI agents to execute code, browse the web, manage files, delegate tasks to subagents, and retain context across conversations - all in isolated, per-thread environments.

---

## Architecture

```
               ┌────────────────────────┐
               │    Gateway API (8000)  │
               │    FastAPI REST        │
               │                        │
               │  Models, MCP, Skills,  │
               │  Memory, Uploads,      │
               │  Artifacts             │
               └──────────┬─────────────┘
                          │
               ┌──────────▼─────────┐
               │ LangGraph Server   │
               │    (Port 8123)     │
               │                    │
               │ ┌────────────────┐ │
               │ │  Lead Agent    │ │
               │ │  ┌──────────┐  │ │
               │ │  │Middleware│  │ │
               │ │  │  Chain   │  │ │
               │ │  └──────────┘  │ │
               │ │  ┌──────────┐  │ │
               │ │  │  Tools   │  │ │
               │ │  └──────────┘  │ │
               │ │  ┌──────────┐  │ │
               │ │  │Subagents │  │ │
               │ │  └──────────┘  │ │
               │ └────────────────┘ │
               └────────────────────┘
```

**Request Routing**:
- `/api/langgraph/*` → LangGraph Server - agent interactions, threads, streaming
- `/api/*` (other) → Gateway API - models, MCP, skills, memory, artifacts, uploads, thread-local cleanup

---

## Core Components

### Lead Agent

The single LangGraph agent (`lead_agent`) is the runtime entry point. It combines:
- **Dynamic model selection** with thinking and vision support
- **Middleware chain** for cross-cutting concerns (9 middlewares)
- **Tool system** with sandbox, MCP, community, and built-in tools
- **Subagent delegation** for parallel task execution
- **System prompt** with skills injection, memory context, and working directory guidance

### Middleware Chain

Middlewares execute in strict order, each handling a specific concern:
ThreadDataMiddleware -> UploadsMiddleware -> SandboxMiddleware -> SummarizationMiddleware -> TodoListMiddleware -> TitleMiddleware -> MemoryMiddleware -> ViewImageMiddleware -> ClarificationMiddleware

### Sandbox System

Per-thread isolated execution with virtual path translation:
- **Abstract interface**: `execute_command`, `read_file`, `write_file`, `list_dir`
- **Providers**: `LocalSandboxProvider` (filesystem) and `AioSandboxProvider` (Docker)
- **Virtual paths**: `/mnt/user-data/{workspace,uploads,outputs}` → thread-specific physical directories

### Memory System

LLM-powered persistent context retention across conversations:
- **Automatic extraction**: Analyzes conversations for user context, facts, and preferences
- **Structured storage**: User context (work, personal, top-of-mind), history, and confidence-scored facts
- **Debounced updates**: Batches updates to minimize LLM calls (configurable wait time)

### Gateway API

FastAPI application providing REST endpoints for integration:

| Route | Purpose |
|-------|---------|
| `GET /api/models` | List available LLM models |
| `GET/PUT /api/mcp/config` | Manage MCP server configurations |
| `GET/PUT /api/skills` | List and manage skills |
| `POST /api/skills/install` | Install skill from `.skill` archive |
| `GET /api/memory` | Retrieve memory data |
| `POST /api/memory/reload` | Force memory reload |
| `GET /api/memory/config` | Memory configuration |
| `GET /api/memory/status` | Combined config + data |
| `POST /api/threads/{id}/uploads` | Upload files (auto-converts PDF/PPT/Excel/Word to Markdown) |
| `GET /api/threads/{id}/uploads/list` | List uploaded files |
| `DELETE /api/threads/{id}` | Delete Yandex Deep Research-managed local thread data |
| `GET /api/threads/{id}/artifacts/{path}` | Serve generated artifacts |

---

## Quick Start

### Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) package manager

### Running

From the project root:

```bash
./scripts/serve.sh --dev
```

- **Gateway API:** `http://localhost:8000`
- **LangGraph API:** `http://localhost:8123`

Please see the root `README.md` for more complete instructions.
