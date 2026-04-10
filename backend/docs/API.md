# Справочник API

В этом документе представлен полный справочник по API бэкенда Yandex Deep Research.

## Обзор

Бэкенд Yandex Deep Research предоставляет два набора API:

1. **LangGraph API** - Взаимодействие с агентами, треды (потоки) и потоковая передача (streaming) (`/api/langgraph/*`)
2. **Gateway API** - Модели, MCP, навыки, загрузки и артефакты (`/api/*`)

Доступ ко всем API осуществляется через обратный прокси-сервер Nginx на порту 2026.

## LangGraph API

Базовый URL: `/api/langgraph`

LangGraph API предоставляется сервером LangGraph и следует соглашениям LangGraph SDK.

### Треды (Threads)

#### Создание треда

```http
POST /api/langgraph/threads
Content-Type: application/json
```

**Тело запроса:**
```json
{
  "metadata": {}
}
```

**Ответ:**
```json
{
  "thread_id": "abc123",
  "created_at": "2024-01-15T10:30:00Z",
  "metadata": {}
}
```

#### Получение состояния треда

```http
GET /api/langgraph/threads/{thread_id}/state
```

**Ответ:**
```json
{
  "values": {
    "messages": [...],
    "sandbox": {...},
    "artifacts": [...],
    "thread_data": {...},
    "title": "Conversation Title"
  },
  "next": [],
  "config": {...}
}
```

### Запуски (Runs)

#### Создание запуска

Запуск агента с входными данными.

```http
POST /api/langgraph/threads/{thread_id}/runs
Content-Type: application/json
```

**Тело запроса:**
```json
{
  "input": {
    "messages": [
      {
        "role": "user",
        "content": "Hello, can you help me?"
      }
    ]
  },
  "config": {
    "configurable": {
      "model_name": "gpt-4",
      "thinking_enabled": false,
      "is_plan_mode": false
    }
  },
  "stream_mode": ["values", "messages-tuple", "custom"]
}
```

**Совместимость режимов потоковой передачи (Stream Mode):**
- Использовать: `values`, `messages-tuple`, `custom`, `updates`, `events`, `debug`, `tasks`, `checkpoints`
- Не использовать: `tools` (устарело/недействительно в текущем `langgraph-api` и вызовет ошибки валидации схемы)

**Настраиваемые параметры (Configurable Options):**
- `model_name` (строка): Переопределить модель по умолчанию
- `thinking_enabled` (логическое): Включить расширенное мышление для поддерживаемых моделей
- `is_plan_mode` (логическое): Включить промежуточное ПО (middleware) TodoList для отслеживания задач

**Ответ:** Поток событий сервера (Server-Sent Events, SSE)

```
event: values
data: {"messages": [...], "title": "..."}

event: messages
data: {"content": "Hello! I'd be happy to help.", "role": "assistant"}

event: end
data: {}
```

#### Получение истории запусков

```http
GET /api/langgraph/threads/{thread_id}/runs
```

**Ответ:**
```json
{
  "runs": [
    {
      "run_id": "run123",
      "status": "success",
      "created_at": "2024-01-15T10:30:00Z"
    }
  ]
}
```

#### Потоковый запуск (Stream Run)

Потоковая передача ответов в реальном времени.

```http
POST /api/langgraph/threads/{thread_id}/runs/stream
Content-Type: application/json
```

Тело запроса такое же, как и при создании запуска (Create Run). Возвращает поток SSE.

---

## Gateway API

Базовый URL: `/api`

### Модели (Models)

#### Список моделей

Получение всех доступных моделей LLM из конфигурации.

```http
GET /api/models
```

**Ответ:**
```json
{
  "models": [
    {
      "name": "gpt-4",
      "display_name": "GPT-4",
      "supports_thinking": false,
      "supports_vision": true
    },
    {
      "name": "claude-3-opus",
      "display_name": "Claude 3 Opus",
      "supports_thinking": false,
      "supports_vision": true
    },
    {
      "name": "deepseek-v3",
      "display_name": "DeepSeek V3",
      "supports_thinking": true,
      "supports_vision": false
    }
  ]
}
```

#### Детали модели

```http
GET /api/models/{model_name}
```

**Ответ:**
```json
{
  "name": "gpt-4",
  "display_name": "GPT-4",
  "model": "gpt-4",
  "max_tokens": 4096,
  "supports_thinking": false,
  "supports_vision": true
}
```

### Конфигурация MCP

#### Получение конфигурации MCP

Получение текущих конфигураций серверов MCP.

```http
GET /api/mcp/config
```

**Ответ:**
```json
{
  "mcpServers": {
    "github": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "***"
      },
      "description": "GitHub operations"
    },
    "filesystem": {
      "enabled": false,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"],
      "description": "File system access"
    }
  }
}
```

#### Обновление конфигурации MCP

Обновление конфигураций серверов MCP.

```http
PUT /api/mcp/config
Content-Type: application/json
```

**Тело запроса:**
```json
{
  "mcpServers": {
    "github": {
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "$GITHUB_TOKEN"
      },
      "description": "GitHub operations"
    }
  }
}
```

**Ответ:**
```json
{
  "success": true,
  "message": "MCP configuration updated"
}
```

### Навыки (Skills)

#### Список навыков

Получение всех доступных навыков.

```http
GET /api/skills
```

**Ответ:**
```json
{
  "skills": [
    {
      "name": "pdf-processing",
      "display_name": "PDF Processing",
      "description": "Handle PDF documents efficiently",
      "enabled": true,
      "license": "MIT",
      "path": "public/pdf-processing"
    },
    {
    config={"configurable": {"model_name": "gpt-4"}},
    stream_mode=["values", "messages-tuple", "custom"],
):
    print(event)
```

### JavaScript/TypeScript

```typescript
// Использование fetch для Gateway API
const response = await fetch('/api/models');
const data = await response.json();
console.log(data.models);

// Использование EventSource для потоковой передачи
const eventSource = new EventSource(
  `/api/langgraph/threads/${threadId}/runs/stream`
);
eventSource.onmessage = (event) => {
  console.log(JSON.parse(event.data));
};
```

### Примеры cURL

```bash
# Список моделей
curl http://localhost:2026/api/models

# Получение конфигурации MCP
curl http://localhost:2026/api/mcp/config

# Загрузка файла
curl -X POST http://localhost:2026/api/threads/abc123/uploads \
  -F "files=@document.pdf"

# Включение навыка
curl -X POST http://localhost:2026/api/skills/pdf-processing/enable

# Создание треда и запуск агента
curl -X POST http://localhost:2026/api/langgraph/threads \
  -H "Content-Type: application/json" \
  -d '{}'

curl -X POST http://localhost:2026/api/langgraph/threads/abc123/runs \
  -H "Content-Type: application/json" \
  -d '{
    "input": {"messages": [{"role": "user", "content": "Hello"}]},
    "config": {"configurable": {"model_name": "gpt-4"}}
  }'
```