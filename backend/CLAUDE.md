# CLAUDE.md

Этот файл содержит руководство для Claude Code (claude.ai/code) при работе с кодом в этом репозитории.

## Обзор проекта

YandexDeepResearch — это система супер-агентов на базе LangGraph с полностековой архитектурой. Бэкенд предоставляет «супер-агента» с выполнением в песочнице, постоянной памятью, делегированием подагентам и расширяемой интеграцией инструментов — все это работает в изолированных средах для каждого потока (thread).

**Архитектура**:
- **Сервер LangGraph** (порт 2024): Среда выполнения агентов и рабочих процессов
- **Gateway API** (порт 8001): REST API для моделей, MCP, навыков (skills), памяти, артефактов, загрузок и очистки локальных потоков
- **Provisioner** (порт 8002, опционально в Docker dev): Запускается только когда песочница настроена для режима provisioner/Kubernetes

**Режимы выполнения**:
- **Стандартный режим** (`make dev`): Сервер LangGraph обрабатывает выполнение агента как отдельный процесс. Всего 4 процесса.
- **Режим Gateway** (`make dev-pro`, экспериментальный): Среда выполнения агента встроена в Gateway через `RunManager` + `run_agent()` + `StreamBridge` (`packages/harness/yandex_deep_research/runtime/`). Сервис управляет собственным параллелизмом через асинхронные задачи. Всего 3 процесса, без сервера LangGraph.

**Структура проекта**:
```
deer-flow/
├── Makefile                    # Корневые команды (check, install, dev, stop)
├── config.yaml                 # Основная конфигурация приложения
├── extensions_config.json      # Конфигурация MCP-серверов и навыков
├── backend/                    # Бэкенд-приложение (эта директория)
│   ├── Makefile               # Команды только для бэкенда (dev, gateway, lint)
│   ├── langgraph.json         # Конфигурация сервера LangGraph
│   ├── packages/
│   │   └── harness/           # Пакет yandex-deep-research-harness (импорт: yandex_deep_research.*)
│   │       ├── pyproject.toml
│   │       └── yandex-deep-research/
│   │           ├── agents/            # Система агентов LangGraph
│   │           │   ├── lead_agent/    # Главный агент (фабрика + системный промпт)
│   │           │   ├── middlewares/   # 10 компонентов промежуточного ПО (middleware)
│   │           │   ├── memory/        # Извлечение памяти, очередь, промпты
│   │           │   └── thread_state.py # Схема ThreadState
│   │           ├── sandbox/           # Система выполнения в песочнице
│   │           │   ├── local/         # Локальный файловый провайдер
│   │           │   ├── sandbox.py     # Абстрактный интерфейс Sandbox
│   │           │   ├── tools.py       # bash, ls, read/write/str_replace
│   │           │   └── middleware.py  # Управление жизненным циклом песочницы
│   │           ├── subagents/         # Система делегирования подагентам
│   │           │   ├── builtins/      # general-purpose, bash агенты
│   │           │   ├── executor.py    # Механизм фонового выполнения
│   │           │   └── registry.py    # Реестр агентов
│   │           ├── tools/builtins/    # Встроенные инструменты (present_files, ask_clarification, view_image)
│   │           ├── mcp/               # Интеграция MCP (инструменты, кэш, клиент)
│   │           ├── models/            # Фабрика моделей с поддержкой thinking/vision
│   │           ├── skills/            # Обнаружение навыков, загрузка, парсинг
│   │           ├── config/            # Система конфигурации (app, model, sandbox, tool и т.д.)
│   │           ├── community/         # Инструменты сообщества (tavily, jina_ai, firecrawl, image_search, aio_sandbox)
│   │           ├── reflection/        # Динамическая загрузка модулей (resolve_variable, resolve_class)
│   │           ├── utils/             # Утилиты (сеть, читаемость)
│   │           └── client.py          # Встроенный Python-клиент (YandexDeepResearchClient)
│   ├── app/                   # Слой приложения (импорт: app.*)
│   │   ├── gateway/           # FastAPI Gateway API
│   │   │   ├── app.py         # Приложение FastAPI
│   │   │   └── routers/       # Модули маршрутов FastAPI (models, mcp, memory, skills, uploads, threads, artifacts, agents, suggestions)
│   ├── tests/                 # Набор тестов
│   └── docs/                  # Документация
└── skills/                     # Директория навыков агента
    ├── public/                # Публичные навыки (в коммитах)
    └── custom/                # Пользовательские навыки (в gitignore)
```

## Важные руководства по разработке

### Политика обновления документации
**КРИТИЧЕСКИ ВАЖНО: Всегда обновляйте README.md и CLAUDE.md после каждого изменения кода**

При внесении изменений в код вы ДОЛЖНЫ обновить соответствующую документацию:
- Обновите `README.md` для изменений, ориентированных на пользователя (функции, настройка, инструкции по использованию)
- Обновите `CLAUDE.md` для изменений, связанных с разработкой (архитектура, команды, рабочие процессы, внутренние системы)
- Всегда поддерживайте синхронизацию документации с кодовой базой
- Обеспечивайте точность и актуальность всей документации

## Команды

**Корневая директория** (для всего приложения):
```bash
make check      # Проверка системных требований
make install    # Установка всех зависимостей (бэкенд)
make dev        # Запуск всех сервисов (LangGraph + Gateway + Nginx) с предпроверкой config.yaml
make dev-pro    # Режим Gateway (экспериментальный): пропуск LangGraph, среда выполнения агента встроена в Gateway
make start-pro  # Production + режим Gateway (экспериментальный)
make stop       # Остановка всех сервисов
```

**Директория бэкенда** (только для разработки бэкенда):
```bash
make install    # Установка зависимостей бэкенда
make dev        # Запуск только сервера LangGraph (порт 2024)
make gateway    # Запуск только Gateway API (порт 8001)
make test       # Запуск всех тестов бэкенда
make lint       # Линтинг с помощью ruff
make format     # Форматирование кода с помощью ruff
```

Регрессионные тесты, связанные с поведением Docker/provisioner:
- `tests/test_docker_sandbox_mode_detection.py` (определение режима из `config.yaml`)
- `tests/test_provisioner_kubeconfig.py` (обработка файла/директории kubeconfig)

Проверка границ (файрвол импортов harness → app):
- `tests/test_harness_boundary.py` — гарантирует, что `packages/harness/yandex_deep_research/` никогда не импортирует из `app.*`

CI запускает эти регрессионные тесты для каждого pull request через [.github/workflows/backend-unit-tests.yml](../.github/workflows/backend-unit-tests.yml).

## Архитектура

### Разделение Harness / App

Бэкенд разделен на два слоя со строгим направлением зависимостей:

- **Harness** (`packages/harness/yandex_deep_research/`): Публикуемый пакет фреймворка агентов (`yandex-deep-research-harness`). Префикс импорта: `yandex_deep_research.*`. Содержит оркестрацию агентов, инструменты, песочницу, модели, MCP, навыки, конфигурацию — всё необходимое для создания и запуска агентов.
- **App** (`app/`): Непубликуемый код приложения. Префикс импорта: `app.*`. Содержит FastAPI Gateway API.

**Правило зависимостей**: App импортирует yandex_deep_research, но yandex_deep_research никогда не импортирует app. Эта граница обеспечивается тестом `tests/test_harness_boundary.py`, который выполняется в CI.

**Соглашения об импорте**:
```python
# Внутренний импорт Harness
from yandex_deep_research.agents import make_lead_agent
from yandex_deep_research.models import create_chat_model

# Внутренний импорт App
from app.gateway.app import app

# App → Harness (разрешено)
from yandex_deep_research.config import get_app_config

# Harness → App (ЗАПРЕЩЕНО — обеспечивается тестом test_harness_boundary.py)
# from app.gateway.routers.uploads import ...  # ← вызовет ошибку в CI
```

### Система агентов

**Главный агент (Lead Agent)** (`packages/harness/yandex_deep_research/agents/lead_agent/agent.py`):
- Точка входа: `make_lead_agent(config: RunnableConfig)`, зарегистрирована в `langgraph.json`
- Динамический выбор модели через `create_chat_model()` с поддержкой thinking/vision
- Инструменты загружаются через `get_available_tools()` - объединяет инструменты песочницы, встроенные, MCP, сообщества и подагентов
- Системный промпт генерируется через `apply_prompt_template()` с инструкциями по навыкам, памяти и подагентам

**Состояние потока (ThreadState)** (`packages/harness/yandex_deep_research/agents/thread_state.py`):
- Расширяет `AgentState` следующими полями: `sandbox`, `thread_data`, `title`, `artifacts`, `todos`, `uploaded_files`, `viewed_images`
- Использует кастомные редьюсеры: `merge_artifacts` (дедупликация), `merge_viewed_images` (объединение/очистка)

**Конфигурация среды выполнения** (через `config.configurable`):
- `thinking_enabled` - Включение расширенного мышления модели
- `model_name` - Выбор конкретной модели LLM
- `is_plan_mode` - Включение middleware TodoList
- `subagent_enabled` - Включение инструмента делегирования задач

### Цепочка Middleware

Middleware выполняются в строгом порядке в `packages/harness/yandex_deep_research/agents/lead_agent/agent.py`:

1. **ThreadDataMiddleware** - Создает директории для каждого потока (`backend/.yandex-deep-research/threads/{thread_id}/user-data/{workspace,uploads,outputs}`); Удаление потока в веб-интерфейсе теперь следует за удалением потока в LangGraph с очисткой локальной директории `.yandex-deep-research/threads/{thread_id}` через Gateway
2. **UploadsMiddleware** - Отслеживает и внедряет недавно загруженные файлы в разговор
3. **SandboxMiddleware** - Получает песочницу, сохраняет `sandbox_id` в состоянии
4. **DanglingToolCallMiddleware** - Внедряет временные ToolMessages для tool_calls в AIMessage, которые не имеют ответов (например, из-за прерывания пользователем)
5. **GuardrailMiddleware** - Авторизация перед вызовом инструмента через подключаемый протокол `GuardrailProvider` (опционально, если `guardrails.enabled` в конфиге). Оценивает каждый вызов инструмента и возвращает ToolMessage с ошибкой при отказе. Три варианта провайдеров: встроенный `AllowlistProvider` (без зависимостей), OAP policy providers (например, `aport-agent-guardrails`) или кастомные провайдеры. См. [docs/GUARDRAILS.md](docs/GUARDRAILS.md) для настройки, использования и создания провайдера.
6. **SummarizationMiddleware** - Сокращение контекста при приближении к лимиту токенов (опционально, если включено)
7. **TodoListMiddleware** - Отслеживание задач с помощью инструмента `write_todos` (опционально, если включен plan_mode)
8. **TitleMiddleware** - Автоматически генерирует заголовок потока после первого полного обмена сообщениями и нормализует структурированное содержимое сообщения перед запросом к модели заголовка
9. **MemoryMiddleware** - Ставит разговоры в очередь для асинхронного обновления памяти (фильтрует пользовательские и финальные ответы ИИ)
10. **ViewImageMiddleware** - Внедряет данные изображения в формате base64 перед вызовом LLM (при условии поддержки vision)
11. **SubagentLimitMiddleware** - Усекает лишние вызовы инструмента `task` из ответа модели для обеспечения лимита `MAX_CONCURRENT_SUBAGENTS` (опционально, если включен subagent_enabled)
12. **ClarificationMiddleware** - Перехватывает вызовы инструмента `ask_clarification`, прерывает выполнение через `Command(goto=END)` (должно быть последним)

### Система конфигурации

**Основная конфигурация** (`config.yaml`):

Настройка: Скопируйте `config.example.yaml` в `config.yaml` в **корневой директории** проекта.

**Версионирование конфигурации**: В `config.example.yaml` есть поле `config_version`. При запуске `AppConfig.from_file()` сравнивает версию пользователя с версией примера и выдает предупреждение, если она устарела. Отсутствие `config_version` = версия 0. Выполните `make config-upgrade` для автоматического слияния недостающих полей. При изменении схемы конфигурации увеличивайте `config_version` в `config.example.yaml`.

**Кэширование конфигурации**: `get_app_config()` кэширует разобранную конфигурацию, но автоматически перезагружает ее, когда изменяется разрешенный путь к конфигурации или увеличивается mtime файла. Это позволяет Gateway и LangGraph синхронизироваться с изменениями в `config.yaml` без необходимости ручного перезапуска процесса.

Приоритет конфигурации:
1. Явный аргумент `config_path`
2. Переменная окружения `DEER_FLOW_CONFIG_PATH`
3. `config.yaml` в текущей директории (backend/)
4. `config.yaml` в родительской директории (корень проекта - **рекомендуемое расположение**)

Значения конфигурации, начинающиеся с `$`, разрешаются как переменные окружения (например, `$OPENAI_API_KEY`).
`ModelConfig` также объявляет `use_responses_api` и `output_version`, чтобы можно было явно включить OpenAI `/v1/responses` при использовании `langchain_openai:ChatOpenAI`.

**Конфигурация расширений** (`extensions_config.json`):

MCP-серверы и навыки настраиваются вместе в `extensions_config.json` в корне проекта:

Приоритет конфигурации:
1. Явный аргумент `config_path`
2. Переменная окружения `DEER_FLOW_EXTENSIONS_CONFIG_PATH`
3. `extensions_config.json` в текущей директории (backend/)
4. `extensions_config.json` в родительской директории (корень проекта - **рекомендуемое расположение**)

### Gateway API (`app/gateway/`)

Приложение FastAPI на порту 8001 с проверкой работоспособности по адресу `GET /health`.

**Маршруты (Routers)**:

| Маршрут | Эндпоинты |
|--------|-----------|
| **Модели (Models)** (`/api/models`) | `GET /` - список моделей; `GET /{name}` - детали модели |
| **MCP** (`/api/mcp`) | `GET /config` - получение конфигурации; `PUT /config` - обновление конфигурации (сохраняет в extensions_config.json) |
| **Навыки (Skills)** (`/api/skills`) | `GET /` - список навыков; `GET /{name}` - детали; `PUT /{name}` - обновление статуса включения; `POST /install` - установка из архива .skill (принимает стандартный опциональный frontmatter, такой как `version`, `author`, `compatibility`) |
| **Память (Memory)** (`/api/memory`) | `GET /` - данные памяти; `POST /reload` - принудительная перезагрузка; `GET /config` - конфигурация; `GET /status` - конфигурация + данные |
| **Загрузки (Uploads)** (`/api/threads/{id}/uploads`) | `POST /` - загрузка файлов (авто-конвертация PDF/PPT/Excel/Word); `GET /list` - список; `DELETE /{filename}` - удаление |
| **Потоки (Threads)** (`/api/threads/{id}`) | `DELETE /` - удаление локальных данных потока, управляемых YandexDeepResearch, после удаления потока LangGraph; неожиданные сбои логируются на стороне сервера и возвращают общую деталь 500 |
| **Артефакты (Artifacts)** (`/api/threads/{id}/artifacts`) | `GET /{path}` - выдача артефактов; активные типы контента (`text/html`, `application/xhtml+xml`, `image/svg+xml`) всегда принудительно скачиваются как вложения для снижения риска XSS; `?download=true` по-прежнему принудительно скачивает для других типов файлов |
| **Предложения (Suggestions)** (`/api/threads/{id}/suggestions`) | `POST /` - генерация уточняющих вопросов; богатый контент модели в виде списков/блоков нормализуется перед парсингом JSON |

Проксирование через nginx: `/api/langgraph/*` → LangGraph, все остальные `/api/*` → Gateway.

### Система песочницы (`packages/harness/yandex_deep_research/sandbox/`)

**Интерфейс**: Абстрактный `Sandbox` с методами `execute_command`, `read_file`, `write_file`, `list_dir`
**Паттерн провайдера**: `SandboxProvider` с жизненным циклом `acquire`, `get`, `release`
**Реализации**:
- `LocalSandboxProvider` - Синглтон выполнения в локальной файловой системе с отображением путей
- `AioSandboxProvider` (`packages/harness/yandex_deep_research/community/`) - Изоляция на базе Docker

**Система виртуальных путей**:
- Агент видит: `/mnt/user-data/{workspace,uploads,outputs}`, `/mnt/skills`
- Физические пути: `backend/.yandex-deep-research/threads/{thread_id}/user-data/...`, `skills/`
- Трансляция: `replace_virtual_path()` / `replace_virtual_paths_in_command()`
- Обнаружение: `is_local_sandbox()` проверяет `sandbox_id == "local"`

**Инструменты песочницы** (в `packages/harness/yandex_deep_research/sandbox/tools.py`):
- `bash` - Выполнение команд с трансляцией путей и обработкой ошибок
- `ls` - Просмотр директорий (формат дерева, максимум 2 уровня)
- `read_file` - Чтение содержимого файла с опциональным диапазоном строк
- `write_file` - Запись/добавление в файлы, создание директорий
- `str_replace` - Замена подстроки (однократная или всех вхождений); сериализация по одному пути ограничена `(sandbox.id, path)`, поэтому изолированные песочницы не конфликтуют на идентичных виртуальных путях внутри одного процесса

### Система подагентов (`packages/harness/yandex_deep_research/subagents/`)

**Встроенные агенты**: `general-purpose` (все инструменты, кроме `task`) и `bash` (специалист по командам)
**Выполнение**: Двойной пул потоков - `_scheduler_pool` (3 воркера) + `_execution_pool` (3 воркера)
**Параллелизм**: `MAX_CONCURRENT_SUBAGENTS = 3` обеспечивается через `SubagentLimitMiddleware` (усекает лишние вызовы инструментов в `after_model`), 15-минутный таймаут
**Поток**: Инструмент `task()` → `SubagentExecutor` → фоновый поток → опрос каждые 5с → события SSE → результат
**События**: `task_started`, `task_running`, `task_completed`/`task_failed`/`task_timed_out`

### Система инструментов (`packages/harness/yandex_deep_research/tools/`)

`get_available_tools(groups, include_mcp, model_name, subagent_enabled)` собирает:
1. **Инструменты, определенные в конфиге** - Разрешаются из `config.yaml` через `resolve_variable()`
2. **Инструменты MCP** - Из включенных MCP-серверов (ленивая инициализация, кэширование с инвалидацией по mtime)
3. **Встроенные инструменты**:
   - `present_files` - Сделать выходные файлы видимыми для пользователя (только `/mnt/user-data/outputs`)
   - `ask_clarification` - Запрос уточнения (перехватывается ClarificationMiddleware → прерывает выполнение)
   - `view_image` - Чтение изображения в формате base64 (добавляется только если модель поддерживает vision)
4. **Инструмент подагента** (если включен):
   - `task` - Делегирование подагенту (описание, промпт, тип подагента, макс. количество ходов)

**Инструменты сообщества** (`packages/harness/yandex_deep_research/community/`):
- `tavily/` - Веб-поиск (по умолчанию 5 результатов) и получение веб-страниц (лимит 4КБ)
- `jina_ai/` - Получение веб-страниц через Jina reader API с извлечением читабельного текста
- `firecrawl/` - Веб-скрейпинг через API Firecrawl

**Инструменты агентов ACP**:
- `invoke_acp_agent` - Вызывает внешние ACP-совместимые агенты из `config.yaml`
- Запускаемые файлы ACP должны быть настоящими ACP-адаптерами. Стандартный CLI `codex` сам по себе не совместим с ACP; настройте обертку, например `npx -y @zed-industries/codex-acp`, или установленный бинарный файл `codex-acp`
- Отсутствующие исполняемые файлы ACP теперь возвращают понятное сообщение об ошибке вместо сырого `[Errno 2]`
- Каждый агент ACP использует рабочую область для конкретного потока в `{base_dir}/threads/{thread_id}/acp-workspace/`. Рабочая область доступна главному агенту через виртуальный путь `/mnt/acp-workspace/` (только для чтения). В режиме Docker-песочницы директория монтируется как том в контейнер по пути `/mnt/acp-workspace` (только для чтения); в режиме локальной песочницы трансляция путей обрабатывается в `tools.py`
- `image_search/` - Поиск изображений через DuckDuckGo

### Система MCP (`packages/harness/yandex_deep_research/mcp/`)

- Использует `MultiServerMCPClient` из `langchain-mcp-adapters` для управления несколькими серверами
- **Ленивая инициализация**: Инструменты загружаются при первом использовании через `get_cached_mcp_tools()`
- **Инвалидация кэша**: Обнаруживает изменения файла конфигурации путем сравнения mtime
- **Транспорты**: stdio (на основе команд), SSE, HTTP
- **OAuth (HTTP/SSE)**: Поддерживает потоки конечных точек токенов (`client_credentials`, `refresh_token`) с автоматическим обновлением токенов + внедрением заголовка Authorization
- **Обновления во время выполнения**: Gateway API сохраняет в extensions_config.json; LangGraph обнаруживает изменения через mtime

### Система навыков (`packages/harness/yandex_deep_research/skills/`)

- **Расположение**: `skills/{public,custom}/`
- **Формат**: Директория с `SKILL.md` (YAML frontmatter: name, description, license, allowed-tools)
- **Загрузка**: `load_skills()` рекурсивно сканирует `skills/{public,custom}` в поисках `SKILL.md`, анализирует метаданные и читает состояние включения из extensions_config.json
- **Внедрение**: Включенные навыки перечисляются в системном промпте агента с путями контейнера
- **Установка**: `POST /api/skills/install` извлекает ZIP-архив .skill в директорию custom/

### Фабрика моделей (`packages/harness/yandex_deep_research/models/factory.py`)

- `create_chat_model(name, thinking_enabled)` создает экземпляр LLM из конфигурации с помощью рефлексии
- Поддерживает флаг `thinking_enabled` с переопределениями `when_thinking_enabled` для конкретных моделей
- Поддерживает переключатели мышления в стиле vLLM через `when_thinking_enabled.extra_body.chat_template_kwargs.enable_thinking` для моделей рассуждений Qwen, при этом нормализуя устаревшие конфигурации `thinking` для обратной совместимости
- Поддерживает флаг `supports_vision` для моделей понимания изображений
- Значения конфигурации, начинающиеся с `$`, разрешаются как переменные окружения
- Отсутствующие модули провайдеров выводят полезные подсказки по установке из распознавателей рефлексии (например, `uv add langchain-google-genai`)

### Провайдер vLLM (`packages/harness/yandex_deep_research/models/vllm_provider.py`)

- `VllmChatModel` наследуется от `langchain_openai:ChatOpenAI` для OpenAI-совместимых эндпоинтов vLLM 0.19.0
- Сохраняет нестандартное поле `reasoning` ассистента vLLM в полных ответах, потоковых дельтах и последующих ходах вызова инструментов
- Разработан для конфигураций, которые включают мышление через `extra_body.chat_template_kwargs.enable_thinking` на моделях рассуждений Qwen vLLM 0.19.0, при этом принимая старый псевдоним `thinking`

### Система памяти (`packages/harness/yandex_deep_research/agents/memory/`)

**Компоненты**:
- `updater.py` - Обновление памяти на базе LLM с извлечением фактов, дедупликацией фактов с нормализацией пробелов (обрезает начальные/конечные пробелы перед сравнением) и атомарным вводом-выводом файлов
- `queue.py` - Очередь обновлений с дебаунсом (дедупликация по потокам, настраиваемое время ожидания)
- `prompt.py` - Шаблоны промптов для обновлений памяти

**Структура данных** (хранится в `backend/.yandex-deep-research/memory.json`):
- **Пользовательский контекст**: `workContext`, `personalContext`, `topOfMind` (сводки из 1-3 предложений)
- **История**: `recentMonths`, `earlierContext`, `longTermBackground`
- **Факты**: Отдельные факты с `id`, `content`, `category` (preference/knowledge/context/behavior/goal), `confidence` (0-1), `createdAt`, `source`

**Рабочий процесс**:
1. `MemoryMiddleware` фильтрует сообщения (вводы пользователя + финальные ответы ИИ) и ставит разговор в очередь
2. Очередь применяет дебаунс (по умолчанию 30с), объединяет обновления в пакеты, дедуплицирует по потокам
3. Фоновый поток вызывает LLM для извлечения обновлений контекста и фактов
4. Применяет обновления атомарно (временный файл + переименование) с инвалидацией кэша, пропуская дубликаты фактов перед добавлением
5. Следующее взаимодействие внедряет топ-15 фактов + контекст в теги `<memory>` в системном промпте

Сфокусированное регрессионное покрытие для апдейтера находится в `backend/tests/test_memory_updater.py`.

**Конфигурация** (`config.yaml` → `memory`):
- `enabled` / `injection_enabled` - Главные переключатели
- `storage_path` - Путь к memory.json
- `debounce_seconds` - Время ожидания перед обработкой (по умолчанию: 30)
- `model_name` - LLM для обновлений (null = модель по умолчанию)
- `max_facts` / `fact_confidence_threshold` - Лимиты хранения фактов (100 / 0.7)
- `max_injection_tokens` - Лимит токенов для внедрения промпта (2000)

### Система рефлексии (`packages/harness/yandex_deep_research/reflection/`)

- `resolve_variable(path)` - Импортирует модуль и возвращает переменную (например, `module.path:variable_name`)
- `resolve_class(path, base_class)` - Импортирует и проверяет класс на соответствие базовому классу

### Схема конфигурации

**Ключевые разделы `config.yaml`**:
- `models[]` - Конфигурации LLM с путем к классу `use`, `supports_thinking`, `supports_vision` и специфичными для провайдера полями
- Модели рассуждений vLLM должны использовать `yandex_deep_research.models.vllm_provider:VllmChatModel`; для парсеров в стиле Qwen предпочтительнее `when_thinking_enabled.extra_body.chat_template_kwargs.enable_thinking`, и YandexDeepResearch также нормализует старый псевдоним `thinking`
- `tools[]` - Конфигурации инструментов с путем к переменной `use` и `group`
- `tool_groups[]` - Логические группировки для инструментов
- `sandbox.use` - Путь к классу провайдера песочницы
- `skills.path` / `skills.container_path` - Пути хоста и контейнера к директории навыков
- `title` - Автоматическая генерация заголовков (enabled, max_words, max_chars, prompt_template)
- `summarization` - Сокращение контекста (enabled, trigger conditions, keep policy)
- `subagents.enabled` - Главный переключатель для делегирования подагентам
- `memory` - Система памяти (enabled, storage_path, debounce_seconds, model_name, max_facts, fact_confidence_threshold, injection_enabled, max_injection_tokens)

**`extensions_config.json`**:
- `mcpServers` - Карта имя сервера → конфигурация (enabled, type, command, args, env, url, headers, oauth, description)
- `skills` - Карта имя навыка → состояние (enabled)

Оба файла можно изменять во время выполнения через эндпоинты Gateway API или методы `YandexDeepResearchClient`.

### Встроенный клиент (`packages/harness/yandex_deep_research/client.py`)

`YandexDeepResearchClient` предоставляет прямой внутрипроцессный доступ ко всем возможностям YandexDeepResearch без HTTP-сервисов. Все типы возвращаемых значений совпадают со схемами ответов Gateway API, поэтому потребительский код работает идентично в HTTP и встроенном режимах.

**Архитектура**: Импортирует те же модули `yandex_deep_research`, которые используют сервер LangGraph и Gateway API. Разделяет те же конфигурационные файлы и директории данных. Нет зависимости от FastAPI.

**Разговор с агентом** (заменяет сервер LangGraph):
- `chat(message, thread_id)` — синхронный, возвращает финальный текст
- `stream(message, thread_id)` — возвращает `StreamEvent`, соответствующий протоколу LangGraph SSE:
  - `"values"` — полный снимок состояния (заголовок, сообщения, артефакты)
  - `"messages-tuple"` — обновление для каждого сообщения (текст ИИ, вызовы инструментов, результаты инструментов)
  - `"end"` — поток завершен
- Агент создается лениво через `create_agent()` + `_build_middlewares()`, аналогично `make_lead_agent`
- Поддерживает параметр `checkpointer` для сохранения состояния между ходами
- `reset_agent()` принудительно пересоздает агента (например, после изменения памяти или навыков)

**Эквивалентные методы Gateway** (заменяют Gateway API):

| Категория | Методы | Формат возврата |
|----------|---------|---------------|
| Модели | `list_models()`, `get_model(name)` | `{"models": [...]}`, `{name, display_name, ...}` |
| MCP | `get_mcp_config()`, `update_mcp_config(servers)` | `{"mcp_servers": {...}}` |
| Навыки | `list_skills()`, `get_skill(name)`, `update_skill(name, enabled)`, `install_skill(path)` | `{"skills": [...]}` |
| Память | `get_memory()`, `reload_memory()`, `get_memory_config()`, `get_memory_status()` | dict |
| Загрузки | `upload_files(thread_id, files)`, `list_uploads(thread_id)`, `delete_upload(thread_id, filename)` | `{"success": true, "files": [...]}`, `{"files": [...], "count": N}` |
| Артефакты | `get_artifact(thread_id, path)` → `(bytes, mime_type)` | кортеж (tuple) |

**Ключевое отличие от Gateway**: Загрузка принимает локальные объекты `Path` вместо HTTP `UploadFile`, отклоняет пути к директориям перед копированием и повторно использует одного воркера, когда конвертация документа должна выполняться внутри активного цикла событий. Артефакт возвращает `(bytes, mime_type)` вместо HTTP Response. Новый маршрут очистки потоков, доступный только в Gateway, удаляет `.yandex-deep-research/threads/{thread_id}` после удаления потока LangGraph; соответствующего метода в `YandexDeepResearchClient` пока нет. `update_mcp_config()` и `update_skill()` автоматически инвалидируют кэшированного агента.

**Тесты**: `tests/test_client.py` (77 юнит-тестов, включая `TestGatewayConformance`), `tests/test_client_live.py` (живые интеграционные тесты, требуется config.yaml)

**Тесты на соответствие Gateway** (`TestGatewayConformance`): Проверяют, что каждый метод клиента, возвращающий словарь, соответствует соответствующей модели ответа Pydantic в Gateway. Каждый тест парсит вывод клиента через модель Gateway — если Gateway добавляет обязательное поле, которое клиент не предоставляет, Pydantic вызывает `ValidationError`, и CI фиксирует расхождение. Покрывает: `ModelsListResponse`, `ModelResponse`, `SkillsListResponse`, `SkillResponse`, `SkillInstallResponse`, `McpConfigResponse`, `UploadResponse`, `MemoryConfigResponse`, `MemoryStatusResponse`.

## Рабочий процесс разработки

### Разработка через тестирование (TDD) — ОБЯЗАТЕЛЬНО

**Каждая новая функция или исправление ошибки ДОЛЖНЫ сопровождаться юнит-тестами. Без исключений.**

- Пишите тесты в `backend/tests/`, следуя существующему соглашению об именовании `test_<feature>.py`
- Запускайте полный набор тестов до и после вашего изменения: `make test`
- Тесты должны проходить успешно, прежде чем функция будет считаться завершенной
- Для легковесных модулей конфигурации/утилит предпочитайте чистые юнит-тесты без внешних зависимостей
- Если модуль вызывает проблемы с циклическим импортом в тестах, добавьте мок `sys.modules` в `tests/conftest.py` (см. существующий пример для `yandex_deep_research.subagents.executor`)

```bash
# Запуск всех тестов
make test

# Запуск определенного файла тестов
PYTHONPATH=. uv run pytest tests/test_<feature>.py -v
```

### Запуск полного приложения

Из **корневой директории** проекта:
```bash
make dev
```

Это запустит все сервисы и сделает приложение доступным по адресу `http://localhost:2026`.

**Все режимы запуска:**

| | **Local Foreground** | **Local Daemon** | **Docker Dev** | **Docker Prod** |
|---|---|---|---|---|
| **Dev** | `./scripts/serve.sh --dev`<br/>`make dev` | `./scripts/serve.sh --dev --daemon`<br/>`make dev-daemon` | `./scripts/docker.sh start`<br/>`make docker-start` | — |
| **Dev + Gateway** | `./scripts/serve.sh --dev --gateway`<br/>`make dev-pro` | `./scripts/serve.sh --dev --gateway --daemon`<br/>`make dev-daemon-pro` | `./scripts/docker.sh start --gateway`<br/>`make docker-start-pro` | — |
| **Prod** | `./scripts/serve.sh --prod`<br/>`make start` | `./scripts/serve.sh --prod --daemon`<br/>`make start-daemon` | — | `./scripts/deploy.sh`<br/>`make up` |
| **Prod + Gateway** | `./scripts/serve.sh --prod --gateway`<br/>`make start-pro` | `./scripts/serve.sh --prod --gateway --daemon`<br/>`make start-daemon-pro` | — | `./scripts/deploy.sh --gateway`<br/>`make up-pro` |

| Действие | Local | Docker Dev | Docker Prod |
|---|---|---|---|
| **Остановка** | `./scripts/serve.sh --stop`<br/>`make stop` | `./scripts/docker.sh stop`<br/>`make docker-stop` | `./scripts/deploy.sh down`<br/>`make down` |
| **Перезапуск** | `./scripts/serve.sh --restart [flags]` | `./scripts/docker.sh restart` | — |

Режим Gateway встраивает среду выполнения агента в Gateway, без сервера LangGraph.

**Маршрутизация Nginx**:
- Стандартный режим: `/api/langgraph/*` → Сервер LangGraph (2024)
- Режим Gateway: `/api/langgraph/*` → Встроенная среда выполнения Gateway (8001) (через envsubst)
- `/api/*` (остальное) → Gateway API (8001)

### Запуск сервисов бэкенда по отдельности

Из директории **backend**:

```bash
# Терминал 1: Сервер LangGraph
make dev

# Терминал 2: Gateway API
make gateway
```

Прямой доступ (без nginx):
- LangGraph: `http://localhost:2024`
- Gateway: `http://localhost:8001`


## Ключевые функции

### Загрузка файлов

Загрузка нескольких файлов с автоматической конвертацией документов:
- Эндпоинт: `POST /api/threads/{thread_id}/uploads`
- Поддерживает: документы PDF, PPT, Excel, Word (конвертируются через `markitdown`)
- Отклоняет ввод директорий перед копированием, чтобы загрузки оставались по принципу «всё или ничего»
- Повторно использует один воркер конвертации на запрос при вызове из активного цикла событий
- Файлы хранятся в изолированных для каждого потока директориях
- Агент получает список загруженных файлов через `UploadsMiddleware`

См. [docs/FILE_UPLOAD.md](docs/FILE_UPLOAD.md) для подробностей.

### Режим планирования (Plan Mode)

Middleware TodoList для сложных многошаговых задач:
- Управляется через конфигурацию среды выполнения: `config.configurable.is_plan_mode = True`
- Предоставляет инструмент `write_todos` для отслеживания задач
- Выполняется одна задача за раз (in_progress), обновления в реальном времени

См. [docs/plan_mode_usage.md](docs/plan_mode_usage.md) для подробностей.

### Сокращение контекста (Summarization)

Автоматическое сокращение (суммаризация) разговора при приближении к лимиту токенов:
- Настраивается в `config.yaml` в разделе `summarization`
- Типы триггеров: токены, сообщения или доля от максимального ввода
- Сохраняет недавние сообщения, сокращая старые

См. [docs/summarization.md](docs/summarization.md) для подробностей.

### Поддержка зрения (Vision)

Для моделей с `supports_vision: true`:
- `ViewImageMiddleware` обрабатывает изображения в разговоре
- `view_image_tool` добавляется в набор инструментов агента
- Изображения автоматически конвертируются в base64 и внедряются в состояние

## Стиль кода

- Использует `ruff` для линтинга и форматирования
- Длина строки: 240 символов
- Python 3.12+ с аннотациями типов (type hints)
- Двойные кавычки, отступы пробелами

## Документация

См. директорию `docs/` для подробной документации:
- [CONFIGURATION.md](docs/CONFIGURATION.md) - Параметры конфигурации
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Детали архитектуры
- [API.md](docs/API.md) - Справочник по API
- [SETUP.md](docs/SETUP.md) - Руководство по настройке
- [FILE_UPLOAD.md](docs/FILE_UPLOAD.md) - Функция загрузки файлов
- [PATH_EXAMPLES.md](docs/PATH_EXAMPLES.md) - Типы путей и использование
- [summarization.md](docs/summarization.md) - Сокращение контекста
- [plan_mode_usage.md](docs/plan_mode_usage.md) - Режим планирования с TodoList