# Обзор Архитектуры

Этот документ предоставляет полный обзор архитектуры бэкенда Yandex Deep Research.

## Архитектура Системы

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              Client (Browser)                             │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                          Nginx (Port 2026)                               │
│                    Unified Reverse Proxy Entry Point                      │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  /api/langgraph/*  →  LangGraph Server (2024)                      │  │
│  │  /api/*            →  Gateway API (8001)                           │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
          ┌───────────────────────┴───────────────────────┐
          │                                               │
          ▼                                               ▼
┌─────────────────────┐                 ┌─────────────────────┐
│   LangGraph Server  │                 │    Gateway API      │
│     (Port 2024)     │                 │    (Port 8001)      │
│                     │                 │                     │
│  - Agent Runtime    │                 │  - Models API       │
│  - Thread Mgmt      │                 │  - MCP Config       │
│  - SSE Streaming    │                 │  - Skills Mgmt      │
│  - Checkpointing    │                 │  - File Uploads     │
│                     │                 │  - Thread Cleanup   │
│                     │                 │  - Artifacts        │
└─────────────────────┘                 └─────────────────────┘
          │                       │
          │     ┌─────────────────┘
          │     │
          ▼     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         Shared Configuration                              │
│  ┌─────────────────────────┐  ┌────────────────────────────────────────┐ │
│  │      config.yaml        │  │      extensions_config.json            │ │
│  │  - Models               │  │  - MCP Servers                         │ │
│  │  - Tools                │  │  - Skills State                        │ │
│  │  - Sandbox              │  │                                        │ │
│  │  - Summarization        │  │                                        │ │
│  └─────────────────────────┘  └────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

## Детали Компонентов

### Сервер LangGraph

Сервер LangGraph является ядром среды выполнения агента, построенным на базе LangGraph для надежной оркестрации многоагентных рабочих процессов.

**Точка входа**: `packages/harness/yandex-deep-research/agents/lead_agent/agent.py:make_lead_agent`

**Ключевые обязанности**:
- Создание и настройка агента
- Управление состоянием потока (thread)
- Выполнение цепочки промежуточного ПО (middleware)
- Оркестрация выполнения инструментов
- Потоковая передача SSE для ответов в реальном времени

**Конфигурация**: `langgraph.json`

```json
{
  "agent": {
    "type": "agent",
    "path": "yandex-deep-research.agents:make_lead_agent"
  }
}
```

### API Шлюза (Gateway API)

FastAPI приложение, предоставляющее REST эндпоинты для операций, не связанных с агентами.

**Точка входа**: `app/gateway/app.py`

**Роутеры**:
- `models.py` - `/api/models` - Список моделей и их детали
- `mcp.py` - `/api/mcp` - Конфигурация серверов MCP
- `skills.py` - `/api/skills` - Управление навыками (skills)
- `uploads.py` - `/api/threads/{id}/uploads` - Загрузка файлов
- `threads.py` - `/api/threads/{id}` - Очистка данных локального потока Yandex Deep Research после удаления в LangGraph
- `artifacts.py` - `/api/threads/{id}/artifacts` - Раздача артефактов
- `suggestions.py` - `/api/threads/{id}/suggestions` - Генерация предложений для последующих действий

Процесс удаления веб-беседы теперь разделен между двумя частями бэкенда: LangGraph обрабатывает `DELETE /api/langgraph/threads/{thread_id}` для состояния потока, затем роутер `threads.py` в шлюзе (Gateway) удаляет данные файловой системы, управляемые Yandex Deep Research, с помощью `Paths.delete_thread_dir()`.

### Архитектура Агента

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           make_lead_agent(config)                        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            Middleware Chain                              │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ 1. ThreadDataMiddleware  - Initialize workspace/uploads/outputs  │   │
│  │ 2. UploadsMiddleware     - Process uploaded files               │   │
│  │ 3. SandboxMiddleware     - Acquire sandbox environment          │   │
│  │ 4. SummarizationMiddleware - Context reduction (if enabled)     │   │
│  │ 5. TitleMiddleware       - Auto-generate titles                 │   │
│  │ 6. TodoListMiddleware    - Task tracking (if plan_mode)         │   │
│  │ 7. ViewImageMiddleware   - Vision model support                 │   │
│  │ 8. ClarificationMiddleware - Handle clarifications              │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              Agent Core                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │      Model       │  │      Tools       │  │    System Prompt     │   │
│  │  (from factory)  │  │  (configured +   │  │  (with skills)       │   │
│  │                  │  │   MCP + builtin) │  │                      │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Состояние Потока (Thread State)

`ThreadState` расширяет `AgentState` из LangGraph дополнительными полями:

```python
class ThreadState(AgentState):
    # Базовое состояние из AgentState
    messages: list[BaseMessage]

    # Расширения Yandex Deep Research
    sandbox: dict             # Информация о среде песочницы
    artifacts: list[str]      # Пути к сгенерированным файлам
    thread_data: dict         # Пути {workspace, uploads, outputs}
    title: str | None         # Автоматически сгенерированный заголовок беседы
    todos: list[dict]         # Отслеживание задач (в режиме планирования)
    viewed_images: dict       # Данные изображений для моделей компьютерного зрения
```

### Система Песочницы (Sandbox System)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Sandbox Architecture                           │
└─────────────────────────────────────────────────────────────────────────┘

                      ┌─────────────────────────┐
                      │    SandboxProvider      │ (Abstract)
                      │  - acquire()            │
                      │  - get()                │
                      │  - release()            │
                      └────────────┬────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                                         │
              ▼                                         ▼
┌─────────────────────────┐              ┌─────────────────────────┐
│  LocalSandboxProvider   │              │  AioSandboxProvider     │
│  (packages/harness/yandex-deep-research/sandbox/local.py) │              │  (packages/harness/yandex-deep-research/community/)       │
│                         │              │                         │
│  - Singleton instance   │              │  - Docker-based         │
│  - Direct execution     │              │  - Isolated containers  │
│  - Development use      │              │  - Production use       │
└─────────────────────────┘              └─────────────────────────┘

                      ┌─────────────────────────┐
                      │        Sandbox          │ (Abstract)
                      │  - execute_command()    │
                      │  - read_file()          │
                      │  - write_file()         │
                      │  - list_dir()           │
                      └─────────────────────────┘
```

**Маппинг виртуальных путей**:

| Виртуальный путь | Физический путь |
|-------------|---------------|
| `/mnt/user-data/workspace` | `backend/.yandex-deep-research/threads/{thread_id}/user-data/workspace` |
| `/mnt/user-data/uploads` | `backend/.yandex-deep-research/threads/{thread_id}/user-data/uploads` |
| `/mnt/user-data/outputs` | `backend/.yandex-deep-research/threads/{thread_id}/user-data/outputs` |
| `/mnt/skills` | `yandex-deep-research/skills/` |

### Система Инструментов (Tool System)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Tool Sources                                  │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│   Built-in Tools    │  │  Configured Tools   │  │     MCP Tools       │
│  (packages/harness/yandex-deep-research/tools/)       │  │  (config.yaml)      │  │  (extensions.json)  │
├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤
│ - present_file      │  │ - web_search        │  │ - github            │
│ - ask_clarification │  │ - web_fetch         │  │ - filesystem        │
│ - view_image        │  │ - bash              │  │ - postgres          │
│                     │  │ - read_file         │  │ - brave-search      │
│                     │  │ - write_file        │  │ - puppeteer         │
│                     │  │ - str_replace       │  │ - ...               │
│                     │  │ - ls                │  │                     │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
           │                       │                       │
           └───────────────────────┴───────────────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │   get_available_tools() │
                      │   (packages/harness/yandex-deep-research/tools/__init__)  │
                      └─────────────────────────┘
```

### Фабрика Моделей (Model Factory)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Model Factory                                   │
│                     (packages/harness/yandex-deep-research/models/factory.py)                              │
└─────────────────────────────────────────────────────────────────────────┘

config.yaml:
┌─────────────────────────────────────────────────────────────────────────┐
│ models:                                                                  │
│   - name: gpt-4                                                         │
│     display_name: GPT-4                                                 │
│     use: langchain_openai:ChatOpenAI                                    │
│     model: gpt-4                                                        │
│     api_key: $OPENAI_API_KEY                                            │
│     max_tokens: 4096                                                    │
│     supports_thinking: false                                            │
│     supports_vision: true                                               │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │   create_chat_model()   │
                      │  - name: str            │
                      │  - thinking_enabled     │
                      └────────────┬────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │   resolve_class()       │
                      │  (reflection system)    │
                      └────────────┬────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │   BaseChatModel         │
                      │  (LangChain instance)   │
                      └─────────────────────────┘
```

**Поддерживаемые провайдеры**:
- OpenAI (`langchain_openai:ChatOpenAI`)
- Anthropic (`langchain_anthropic:ChatAnthropic`)
- DeepSeek (`langchain_deepseek:ChatDeepSeek`)
- Пользовательские через интеграции LangChain

### Интеграция MCP (Model Context Protocol)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          MCP Integration                                 │
│                        (packages/harness/yandex-deep-research/mcp/manager.py)                              │
└─────────────────────────────────────────────────────────────────────────┘

extensions_config.json:
┌─────────────────────────────────────────────────────────────────────────┐
│ {                                                                        │
│   "mcpServers": {                                                       │
│     "github": {                                                         │
│       "enabled": true,                                                  │
│       "type": "stdio",                                                  │
│       "command": "npx",                                                 │
│       "args": ["-y", "@modelcontextprotocol/server-github"],           │
│       "env": {"GITHUB_TOKEN": "$GITHUB_TOKEN"}                          │
│     }                                                                   │
│   }                                                                     │
│ }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │  MultiServerMCPClient   │
                      │  (langchain-mcp-adapters)│
                      └────────────┬────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
       ┌───────────┐        ┌───────────┐        ┌───────────┐
       │  stdio    │        │   SSE     │        │   HTTP    │
       │ transport │        │ transport │        │ transport │
       └───────────┘        └───────────┘        └───────────┘
```

### Система Навыков (Skills System)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Skills System                                   │
│                       (packages/harness/yandex-deep-research/skills/loader.py)                             │
└─────────────────────────────────────────────────────────────────────────┘

Структура директорий:
┌─────────────────────────────────────────────────────────────────────────┐
│ skills/                                                                  │
│ ├── public/                        # Публичные навыки (в репозитории)    │
│ │   ├── pdf-processing/                                                 │
│ │   │   └── SKILL.md                                                    │
│ │   └── ...                                                             │
│ └── custom/                        # Пользовательские навыки (gitignored)│
│     └── user-installed/                                                 │
│         └── SKILL.md                                                    │
└─────────────────────────────────────────────────────────────────────────┘

Формат SKILL.md:
┌─────────────────────────────────────────────────────────────────────────┐
│ ---                                                                      │
│ name: PDF Processing                                                     │
│ description: Handle PDF documents efficiently                            │
│ license: MIT                                                            │
│ allowed-tools:                                                          │
│   - read_file                                                           │
│   - write_file                                                          │
│   - bash                                                                │
│ ---                                                                      │
│                                                                          │
│ # Skill Instructions                                                     │
│ Контент внедряется в системный промпт...                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### Поток Запросов (Request Flow)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Request Flow Example                             │
│                    Пользователь отправляет сообщение агенту              │
└─────────────────────────────────────────────────────────────────────────┘

1. Client → Nginx
   POST /api/langgraph/threads/{thread_id}/runs
   {"input": {"messages": [{"role": "user", "content": "Hello"}]}}

2. Nginx → LangGraph Server (2024)
   Проксируется на сервер LangGraph

3. LangGraph Server
   a. Загрузка/создание состояния потока
   b. Выполнение цепочки middleware:
      - ThreadDataMiddleware: Настройка путей
      - UploadsMiddleware: Внедрение списка файлов
      - SandboxMiddleware: Получение песочницы
      - SummarizationMiddleware: Проверка лимитов токенов
      - TitleMiddleware: Генерация заголовка при необходимости
      - TodoListMiddleware: Загрузка задач (в режиме планирования)
      - ViewImageMiddleware: Обработка изображений
      - ClarificationMiddleware: Проверка на наличие уточнений

   c. Выполнение агента:
      - Модель обрабатывает сообщения
      - Может вызывать инструменты (bash, web_search и т.д.)
      - Инструменты выполняются через песочницу
      - Результаты добавляются к сообщениям

   d. Потоковая передача ответа через SSE

4. Клиент получает потоковый ответ
```

## Потоки Данных (Data Flow)

### Поток Загрузки Файлов (File Upload Flow)

```
1. Клиент загружает файл
   POST /api/threads/{thread_id}/uploads
   Content-Type: multipart/form-data

2. Gateway получает файл
   - Проверяет файл
   - Сохраняет в .yandex-deep-research/threads/{thread_id}/user-data/uploads/
   - Если это документ: конвертирует в Markdown через markitdown

3. Возвращает ответ
   {
     "files": [{
       "filename": "doc.pdf",
       "path": ".yandex-deep-research/.../uploads/doc.pdf",
       "virtual_path": "/mnt/user-data/uploads/doc.pdf",
       "artifact_url": "/api/threads/.../artifacts/mnt/.../doc.pdf"
     }]
   }

4. Следующий запуск агента
   - UploadsMiddleware составляет список файлов
   - Внедряет список файлов в сообщения
   - Агент может получить к ним доступ через virtual_path
```

### Поток Очистки Потока (Thread Cleanup Flow)

```
1. Клиент удаляет беседу через LangGraph
   DELETE /api/langgraph/threads/{thread_id}

2. Web UI инициирует очистку в Gateway
   DELETE /api/threads/{thread_id}

3. Gateway удаляет локальные файлы, управляемые Yandex Deep Research
   - Рекурсивно удаляет .yandex-deep-research/threads/{thread_id}/
   - Отсутствующие директории обрабатываются как отсутствие операций (no-op)
   - Недействительные ID потоков отклоняются до обращения к файловой системе
```

### Перезагрузка Конфигурации (Configuration Reload)

```
1. Клиент обновляет конфигурацию MCP
   PUT /api/mcp/config

2. Gateway записывает extensions_config.json
   - Обновляет раздел mcpServers
   - Изменяется время модификации файла (mtime)

3. MCP Manager обнаруживает изменение
   - get_cached_mcp_tools() проверяет mtime
   - Если изменено: переинициализирует клиент MCP
   - Загружает обновленные конфигурации серверов

4. Следующий запуск агента использует новые инструменты
```

## Соображения Безопасности (Security Considerations)

### Изоляция Песочницы (Sandbox Isolation)

- Код агента выполняется в границах песочницы
- Локальная песочница: Прямое выполнение (только для разработки)
- Docker песочница: Изоляция контейнеров (рекомендуется для продакшена)
- Предотвращение обхода пути (path traversal) в файловых операциях

### Безопасность API (API Security)

- Изоляция потоков: Каждый поток имеет отдельные каталоги данных
- Проверка файлов: Загрузки проверяются на безопасность путей
- Разрешение переменных окружения: Секреты не хранятся в конфигурации

### Безопасность MCP (MCP Security)

- Каждый сервер MCP работает в собственном процессе
- Переменные окружения разрешаются во время выполнения
- Серверы могут быть включены/выключены независимо

## Соображения Производительности (Performance Considerations)

### Кэширование (Caching)

- Инструменты MCP кэшируются с инвалидацией по времени изменения файла (mtime)
- Конфигурация загружается один раз, перезагружается при изменении файла
- Навыки (skills) парсятся один раз при запуске, кэшируются в памяти

### Потоковая Передача (Streaming)

- SSE используется для потоковой передачи ответов в реальном времени
- Уменьшает время до появления первого токена (time to first token)
- Обеспечивает видимость прогресса для длительных операций

### Управление Контекстом (Context Management)

- Summarization middleware уменьшает контекст при приближении к лимитам
- Настраиваемые триггеры: токены, сообщения или доли
- Сохраняет последние сообщения, сокращая (суммируя) более старые
