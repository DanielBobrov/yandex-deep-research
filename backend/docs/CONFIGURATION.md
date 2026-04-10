# Руководство по конфигурации

Это руководство объясняет, как настроить Yandex Deep Research для вашей среды.

## Версионирование конфигурации

`config.example.yaml` содержит поле `config_version`, которое отслеживает изменения схемы. Когда версия примера выше, чем в вашем локальном `config.yaml`, приложение выдает предупреждение при запуске:

```
WARNING - Your config.yaml (version 0) is outdated — the latest version is 1.
Run `make config-upgrade` to merge new fields into your config.
```

- **Отсутствие `config_version`** в вашей конфигурации считается версией 0.
- Запустите `make config-upgrade`, чтобы автоматически объединить недостающие поля (ваши существующие значения сохраняются, создается резервная копия `.bak`).
- При изменении схемы конфигурации повышайте `config_version` в `config.example.yaml`.

## Разделы конфигурации

### Модели (Models)

Настройте LLM-модели, доступные агенту:

```yaml
models:
  - name: gpt-4                    # Внутренний идентификатор
    display_name: GPT-4            # Читаемое человеком имя
    use: langchain_openai:ChatOpenAI  # Путь к классу LangChain
    model: gpt-4                   # Идентификатор модели для API
    api_key: $OPENAI_API_KEY       # API-ключ (используйте переменную окружения)
    max_tokens: 4096               # Максимум токенов на запрос
    temperature: 0.7               # Температура сэмплирования
```

**Поддерживаемые провайдеры**:
- OpenAI (`langchain_openai:ChatOpenAI`)
- Anthropic (`langchain_anthropic:ChatAnthropic`)
- DeepSeek (`langchain_deepseek:ChatDeepSeek`)
- Claude Code OAuth (`yandex-deep-research.models.claude_provider:ClaudeChatModel`)
- Codex CLI (`yandex-deep-research.models.openai_codex_provider:CodexChatModel`)
- Любой провайдер, совместимый с LangChain

Примеры провайдеров на базе CLI:

```yaml
models:
  - name: gpt-5.4
    display_name: GPT-5.4 (Codex CLI)
    use: yandex-deep-research.models.openai_codex_provider:CodexChatModel
    model: gpt-5.4
    supports_thinking: true
    supports_reasoning_effort: true

  - name: claude-sonnet-4.6
    display_name: Claude Sonnet 4.6 (Claude Code OAuth)
    use: yandex-deep-research.models.claude_provider:ClaudeChatModel
    model: claude-sonnet-4-6
    max_tokens: 4096
    supports_thinking: true
```

**Поведение авторизации для провайдеров на базе CLI**:
- `CodexChatModel` загружает авторизацию Codex CLI из `~/.codex/auth.json`
- Эндпоинт Codex Responses в настоящее время отклоняет `max_tokens` и `max_output_tokens`, поэтому `CodexChatModel` не предоставляет лимит токенов на уровне запроса
- `ClaudeChatModel` принимает `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR`, `CLAUDE_CODE_CREDENTIALS_PATH` или обычный текст `~/.claude/.credentials.json`
- В macOS Yandex Deep Research не проверяет связку ключей (Keychain) автоматически. Используйте `scripts/export_claude_code_oauth.py` для явного экспорта авторизации Claude Code при необходимости

Чтобы использовать эндпоинт `/v1/responses` от OpenAI с LangChain, продолжайте использовать `langchain_openai:ChatOpenAI` и задайте:

```yaml
models:
  - name: gpt-5-responses
    display_name: GPT-5 (Responses API)
    use: langchain_openai:ChatOpenAI
    model: gpt-5
    api_key: $OPENAI_API_KEY
    use_responses_api: true
    output_version: responses/v1
```

Для шлюзов, совместимых с OpenAI (например, Novita или OpenRouter), продолжайте использовать `langchain_openai:ChatOpenAI` и задайте `base_url`:

```yaml
models:
  - name: novita-deepseek-v3.2
    display_name: Novita DeepSeek V3.2
    use: langchain_openai:ChatOpenAI
    model: deepseek/deepseek-v3.2
    api_key: $NOVITA_API_KEY
    base_url: https://api.novita.ai/openai
    supports_thinking: true
    when_thinking_enabled:
      extra_body:
        thinking:
          type: enabled

  - name: minimax-m2.5
    display_name: MiniMax M2.5
    use: langchain_openai:ChatOpenAI
    model: MiniMax-M2.5
    api_key: $MINIMAX_API_KEY
    base_url: https://api.minimax.io/v1
    max_tokens: 4096
    temperature: 1.0  # MiniMax требует температуру в диапазоне (0.0, 1.0]
    supports_vision: true

  - name: minimax-m2.5-highspeed
    display_name: MiniMax M2.5 Highspeed
    use: langchain_openai:ChatOpenAI
    model: MiniMax-M2.5-highspeed
    api_key: $MINIMAX_API_KEY
    base_url: https://api.minimax.io/v1
    max_tokens: 4096
    temperature: 1.0  # MiniMax требует температуру в диапазоне (0.0, 1.0]
    supports_vision: true
  - name: openrouter-gemini-2.5-flash
    display_name: Gemini 2.5 Flash (OpenRouter)
    use: langchain_openai:ChatOpenAI
    model: google/gemini-2.5-flash-preview
    api_key: $OPENAI_API_KEY
    base_url: https://openrouter.ai/api/v1
```

Если ваш ключ OpenRouter находится в переменной окружения с другим именем, явно укажите `api_key` на эту переменную (например, `api_key: $OPENROUTER_API_KEY`).

**Модели с рассуждением (Thinking Models)**:
Некоторые модели поддерживают режим "размышления" (thinking) для сложных рассуждений:

```yaml
models:
  - name: deepseek-v3
    supports_thinking: true
    when_thinking_enabled:
      extra_body:
        thinking:
          type: enabled
```

**Gemini с рассуждением через шлюз, совместимый с OpenAI**:

При маршрутизации Gemini через прокси, совместимый с OpenAI (эндпоинт совместимости Vertex AI OpenAI, AI Studio или сторонние шлюзы) с включенным рассуждением, API прикрепляет `thought_signature` к каждому объекту tool-call, возвращаемому в ответе. Каждый последующий запрос, который воспроизводит эти сообщения ассистента, **должен** возвращать эти подписи обратно в записях tool-call, иначе API вернет:

```
HTTP 400 INVALID_ARGUMENT: function call `<tool>` in the N. content block is
missing a `thought_signature`.
```

Стандартный `langchain_openai:ChatOpenAI` молча отбрасывает `thought_signature` при сериализации сообщений. Используйте вместо этого `yandex-deep-research.models.patched_openai:PatchedChatOpenAI` — он заново внедряет подписи tool-call (взятые из `AIMessage.additional_kwargs["tool_calls"]`) в каждую отправляемую полезную нагрузку:

```yaml
models:
  - name: gemini-2.5-pro-thinking
    display_name: Gemini 2.5 Pro (Thinking)
    use: yandex-deep-research.models.patched_openai:PatchedChatOpenAI
    model: google/gemini-2.5-pro-preview   # имя модели, ожидаемое вашим шлюзом
    api_key: $GEMINI_API_KEY
    base_url: https://<your-openai-compat-gateway>/v1
    max_tokens: 16384
    supports_thinking: true
    supports_vision: true
    when_thinking_enabled:
      extra_body:
        thinking:
          type: enabled
```

Для доступа к Gemini **без** рассуждения (например, через OpenRouter, где рассуждение не активировано) достаточно обычного `langchain_openai:ChatOpenAI` с `supports_thinking: false`, и патч не нужен.

### Группы инструментов (Tool Groups)

Организуйте инструменты в логические группы:

```yaml
tool_groups:
  - name: web          # Веб-браузинг и поиск
  - name: file:read    # Операции чтения файлов
  - name: file:write   # Операции записи файлов
  - name: bash         # Выполнение shell-команд
```

### Инструменты (Tools)

Настройте конкретные инструменты, доступные агенту:

```yaml
tools:
  - name: web_search
    group: web
    use: yandex-deep-research.community.tavily.tools:web_search_tool
    max_results: 5
    # api_key: $TAVILY_API_KEY  # Необязательно
```

**Встроенные инструменты**:
- `web_search` - Поиск в интернете (Tavily)
- `web_fetch` - Получение веб-страниц (Jina AI)
- `ls` - Просмотр содержимого директорий
- `read_file` - Чтение содержимого файлов
- `write_file` - Запись содержимого файлов
- `str_replace` - Замена строк в файлах
- `bash` - Выполнение bash-команд

### Песочница (Sandbox)

Yandex Deep Research поддерживает несколько режимов выполнения в песочнице. Настройте предпочитаемый режим в `config.yaml`:

**Локальное выполнение** (запускает код песочницы непосредственно на хост-машине):
```yaml
sandbox:
   use: yandex-deep-research.sandbox.local:LocalSandboxProvider # Локальное выполнение
   allow_host_bash: false # по умолчанию; host bash отключен, если явно не включен
```

**Выполнение в Docker** (запускает код песочницы в изолированных контейнерах Docker):
```yaml
sandbox:
   use: yandex-deep-research.community.aio_sandbox:AioSandboxProvider # Песочница на базе Docker
```

**Выполнение в Docker с Kubernetes** (запускает код песочницы в подах Kubernetes через сервис provisioner):

Этот режим запускает каждую песочницу в изолированном поде Kubernetes в кластере вашей **хост-машины**. Требуется Docker Desktop K8s, OrbStack или аналогичная локальная настройка K8s.

```yaml
sandbox:
   use: yandex-deep-research.community.aio_sandbox:AioSandboxProvider
   provisioner_url: http://provisioner:8002
```

При использовании Docker-разработки (`make docker-start`), Yandex Deep Research запускает сервис `provisioner` только если настроен этот режим provisioner. В локальном режиме или обычном Docker-режиме песочницы `provisioner` пропускается.

Смотрите [Руководство по настройке Provisioner](../../docker/provisioner/README.md) для получения подробной информации по конфигурации, предварительным требованиям и устранению неполадок.

Выберите между локальным выполнением или изоляцией на базе Docker:

**Вариант 1: Локальная песочница** (по умолчанию, более простая настройка):
```yaml
sandbox:
  use: yandex-deep-research.sandbox.local:LocalSandboxProvider
  allow_host_bash: false
```

Параметр `allow_host_bash` намеренно установлен в `false` по умолчанию. Локальная песочница Yandex Deep Research — это удобный режим на стороне хоста, а не безопасная граница изоляции оболочки. Если вам нужен `bash`, предпочитайте `AioSandboxProvider`. Устанавливайте `allow_host_bash: true` только для полностью доверенных однопользовательских локальных рабочих процессов.

**Вариант 2: Docker-песочница** (изолированная, более безопасная):
```yaml
sandbox:
  use: yandex-deep-research.community.aio_sandbox:AioSandboxProvider
  port: 8080
  auto_start: true
  container_prefix: yandex-deep-research-sandbox

  # Необязательно: Дополнительные монтирования
  mounts:
    - host_path: /path/on/host
      container_path: /path/in/container
      read_only: false
```

Когда вы настраиваете `sandbox.mounts`, Yandex Deep Research предоставляет эти значения `container_path` в промпте агента, чтобы агент мог обнаруживать смонтированные каталоги и работать с ними напрямую, вместо того чтобы предполагать, что все должно находиться в `/mnt/user-data`.

### Навыки (Skills)

Настройте каталог навыков для специализированных рабочих процессов:

```yaml
skills:
  # Путь на хосте (необязательно, по умолчанию: ../skills)
  path: /custom/path/to/skills

  # Путь монтирования в контейнере (по умолчанию: /mnt/skills)
  container_path: /mnt/skills
```

**Как работают навыки**:
- Навыки хранятся в `yandex-deep-research/skills/{public,custom}/`
- Каждый навык имеет файл `SKILL.md` с метаданными
- Навыки автоматически обнаруживаются и загружаются
- Доступны как в локальной, так и в Docker-песочнице через маппинг путей

**Фильтрация навыков для каждого агента**:
Пользовательские агенты могут ограничивать, какие навыки они загружают, определяя поле `skills` в своем `config.yaml` (находится в `workspace/agents/<agent_name>/config.yaml`):
- **Пропущено или `null`**: Загружает все глобально включенные навыки (поведение по умолчанию).
- **`[]` (пустой список)**: Отключает все навыки для этого конкретного агента.
- **`["skill-name"]`**: Загружает только явно указанные навыки.

### Генерация заголовков (Title Generation)

Автоматическая генерация заголовков бесед:

```yaml
title:
  enabled: true
  max_words: 6
  max_chars: 60
  model_name: null  # Использовать первую модель в списке
```

### Токен API GitHub (необязательно для навыка GitHub Deep Research)

Стандартные лимиты частоты запросов API GitHub довольно строгие. Для частого исследования проектов мы рекомендуем настроить персональный токен доступа (PAT) с правами только на чтение.

**Шаги настройки**:
1. Раскомментируйте строку `GITHUB_TOKEN` в файле `.env` и добавьте свой персональный токен доступа
2. Перезапустите службу Yandex Deep Research для применения изменений

## Переменные окружения

Yandex Deep Research поддерживает подстановку переменных окружения с использованием префикса `$`:

```yaml
models:
  - api_key: $OPENAI_API_KEY  # Читает из окружения
```

**Общие переменные окружения**:
- `OPENAI_API_KEY` - API-ключ OpenAI
- `ANTHROPIC_API_KEY` - API-ключ Anthropic
- `DEEPSEEK_API_KEY` - API-ключ DeepSeek
- `NOVITA_API_KEY` - API-ключ Novita (эндпоинт, совместимый с OpenAI)
- `TAVILY_API_KEY` - API-ключ для поиска Tavily
- `DEER_FLOW_CONFIG_PATH` - Пользовательский путь к файлу конфигурации

## Расположение конфигурации

Файл конфигурации должен быть размещен в **корневом каталоге проекта** (`yandex-deep-research/config.yaml`), а не в каталоге backend.

## Приоритет конфигурации

Yandex Deep Research ищет конфигурацию в следующем порядке:

1. Путь, указанный в коде через аргумент `config_path`
2. Путь из переменной окружения `DEER_FLOW_CONFIG_PATH`
3. `config.yaml` в текущем рабочем каталоге (обычно `backend/` при запуске)
4. `config.yaml` в родительском каталоге (корень проекта: `yandex-deep-research/`)

## Лучшие практики

1. **Размещайте `config.yaml` в корне проекта** - А не в каталоге `backend/`
2. **Никогда не коммитьте `config.yaml`** - Он уже добавлен в `.gitignore`
3. **Используйте переменные окружения для секретов** - Не хардкодьте API-ключи
4. **Поддерживайте `config.example.yaml` в актуальном состоянии** - Документируйте все новые опции
5. **Тестируйте изменения конфигурации локально** - Перед развертыванием
6. **Используйте Docker-песочницу для продакшена** - Лучшая изоляция и безопасность

## Устранение неполадок

### "Config file not found" (Файл конфигурации не найден)
- Убедитесь, что `config.yaml` существует в **корневом каталоге** проекта (`yandex-deep-research/config.yaml`)
- Backend ищет в родительском каталоге по умолчанию, поэтому расположение в корне предпочтительнее
- В качестве альтернативы установите переменную окружения `DEER_FLOW_CONFIG_PATH` на пользовательское расположение

### "Invalid API key" (Неверный API-ключ)
- Убедитесь, что переменные окружения установлены правильно
- Проверьте, что префикс `$` используется для ссылок на переменные окружения

### "Skills not loading" (Навыки не загружаются)
- Проверьте, что каталог `yandex-deep-research/skills/` существует
- Убедитесь, что у навыков есть корректные файлы `SKILL.md`
- Проверьте конфигурацию `skills.path`, если используется пользовательский путь

### "Docker sandbox fails to start" (Не удается запустить Docker-песочницу)
- Убедитесь, что Docker запущен
- Проверьте, что порт 8080 (или настроенный порт) доступен
- Убедитесь, что Docker-образ доступен

## Примеры

Смотрите `config.example.yaml` для полных примеров всех опций конфигурации.