# Guardrails (Ограничители): Авторизация перед вызовом инструмента

> **Контекст:** [Issue #1213](https://github.com/yandex/yandex-deep-research/issues/1213) — Yandex Deep Research имеет Docker-песочницу и ручное подтверждение через `ask_clarification`, но не имеет детерминированного слоя авторизации на основе политик для вызовов инструментов. Агент, выполняющий автономные многошаговые задачи, может выполнить любой загруженный инструмент с любыми аргументами. Guardrails (Ограничители) добавляют промежуточный слой (middleware), который проверяет каждый вызов инструмента на соответствие политике **перед** его выполнением.

## Зачем нужны Guardrails

```
Без ограничителей:                       С ограничителями:

  Агент                                    Агент
    │                                        │
    ▼                                        ▼
  ┌──────────┐                             ┌──────────┐
  │ bash     │──▶ выполняется сразу        │ bash     │──▶ GuardrailMiddleware
  │ rm -rf / │                             │ rm -rf / │        │
  └──────────┘                             └──────────┘        ▼
                                                         ┌──────────────┐
                                                         │  Провайдер   │
                                                         │  проверяет   │
                                                         │  по политике │
                                                         └──────┬───────┘
                                                                │
                                                          ┌─────┴─────┐
                                                          │           │
                                                        ALLOW       DENY
                                                        (РАЗРЕШИТЬ) (ЗАПРЕТИТЬ)
                                                          │           │
                                                          ▼           ▼
                                                     Инструмент   Агент видит:
                                                     выполняется  "Guardrail denied:
                                                     обычно        rm -rf blocked"
```

- **Песочница (Sandboxing)** обеспечивает изоляцию процессов, но не семантическую авторизацию. Внутри песочницы `bash` все еще может отправить данные наружу через `curl`.
- **Ручное подтверждение** (`ask_clarification`) требует участия человека в цикле для каждого действия. Это не подходит для автономных рабочих процессов.
- **Guardrails (Ограничители)** обеспечивают детерминированную авторизацию на основе политик, которая работает без вмешательства человека.

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Цепочка Middleware                             │
│                                                                      │
│  1. ThreadDataMiddleware     ─── директории для потоков              │
│  2. UploadsMiddleware        ─── отслеживание загрузки файлов        │
│  3. SandboxMiddleware        ─── получение песочницы                 │
│  4. DanglingToolCallMiddleware ── исправление незавершенных вызовов   │
│  5. GuardrailMiddleware ◄──── ПРОВЕРЯЕТ КАЖДЫЙ ВЫЗОВ ИНСТРУМЕНТА    │
│  6. ToolErrorHandlingMiddleware ── преобразование исключений в сообщ.│
│  7-12. (Summarization, Title, Memory, Vision, Subagent, Clarify)    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                         │
                         ▼
           ┌──────────────────────────┐
           │    GuardrailProvider     │  ◄── подключаемый: любой класс
           │    (настроен в YAML)     │      с evaluate/aevaluate
           └────────────┬─────────────┘
                        │
              ┌─────────┼──────────────┐
              │         │              │
              ▼         ▼              ▼
         Встроенный OAP Passport    Пользовательский
         Allowlist  Провайдер       Провайдер
         (без завис)(открытый станд.)(ваш код)
                        │
                  Любая реализация
                  (например, APort, или
                   ваш собственный)
```

`GuardrailMiddleware` реализует `wrap_tool_call` / `awrap_tool_call` (тот же паттерн `AgentMiddleware`, который используется в `ToolErrorHandlingMiddleware`). Он:

1. Создает `GuardrailRequest` с именем инструмента, аргументами и ссылкой на паспорт.
2. Вызывает `provider.evaluate(request)` у любого настроенного провайдера.
3. Если **запрещено (deny)**: возвращает `ToolMessage(status="error")` с причиной -- агент видит отказ и адаптируется.
4. Если **разрешено (allow)**: пропускает вызов к фактическому обработчику инструмента.
5. Если **ошибка провайдера** и `fail_closed=true` (по умолчанию): блокирует вызов.
6. Исключения `GraphBubbleUp` (управляющие сигналы LangGraph) всегда пробрасываются дальше и никогда не перехватываются.

## Три варианта провайдера

### Вариант 1: Встроенный AllowlistProvider (Без зависимостей)

Самый простой вариант. Поставляется вместе с Yandex Deep Research. Блокирует или разрешает инструменты по имени. Не требует внешних пакетов, паспортов или сети.

**config.yaml:**
```yaml
guardrails:
  enabled: true
  provider:
    use: yandex-deep-research.guardrails.builtin:AllowlistProvider
    config:
      denied_tools: ["bash", "write_file"]
```

Это блокирует `bash` и `write_file` для всех запросов. Все остальные инструменты проходят.

Вы также можете использовать белый список (allowlist) (разрешены только эти инструменты):
```yaml
guardrails:
  enabled: true
  provider:
    use: yandex-deep-research.guardrails.builtin:AllowlistProvider
    config:
      allowed_tools: ["web_search", "read_file", "ls"]
```

**Попробуйте:**
1. Добавьте конфигурацию выше в ваш `config.yaml`
2. Запустите Yandex Deep Research: `make dev`
3. Попросите агента: "Используй bash, чтобы запустить echo hello"
4. Агент увидит: `Guardrail denied: tool 'bash' was blocked (oap.tool_not_allowed)`

### Вариант 2: OAP Passport Провайдер (На основе политик)

Для применения политик на основе открытого стандарта [Open Agent Passport (OAP)](https://github.com/aporthq/aport-spec). OAP паспорт — это JSON-документ, который объявляет личность агента, его возможности и эксплуатационные ограничения. Любой провайдер, который читает OAP паспорт и возвращает OAP-совместимые решения, работает с Yandex Deep Research.

```
┌─────────────────────────────────────────────────────────────┐
│                    OAP Passport (JSON)                        │
│                   (открытый стандарт, любой провайдер)       │
│  {                                                           │
│    "spec_version": "oap/1.0",                                │
│    "status": "active",                                       │
│    "capabilities": [                                         │
│      {"id": "system.command.execute"},                       │
│      {"id": "data.file.read"},                               │
│      {"id": "data.file.write"},                              │
│      {"id": "web.fetch"},                                    │
│      {"id": "mcp.tool.execute"}                              │
│    ],                                                        │
│    "limits": {                                               │
│      "system.command.execute": {                             │
│        "allowed_commands": ["git", "npm", "node", "ls"],     │
│        "blocked_patterns": ["rm -rf", "sudo", "chmod 777"]   │
│      }                                                       │
│    }                                                         │
│  }                                                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
               Любой OAP-совместимый провайдер
          ┌────────────────┼────────────────┐
          │                │                │
     Ваш собственный  APort (эталонная Другие будущие
     оценщик          реализация)      реализации
```

**Создание паспорта вручную:**

OAP паспорт — это просто JSON файл. Вы можете создать его вручную, следуя [спецификации OAP](https://github.com/aporthq/aport-spec/blob/main/oap/oap-spec.md), и проверить его по [JSON схеме](https://github.com/aporthq/aport-spec/blob/main/oap/passport-schema.json). Смотрите директорию [examples](https://github.com/aporthq/aport-spec/tree/main/oap/examples) для шаблонов.

**Использование APort в качестве эталонной реализации:**

[APort Agent Guardrails](https://github.com/aporthq/aport-agent-guardrails) — это одна из open-source (Apache 2.0) реализаций OAP провайдера. Она обрабатывает создание паспорта, локальную оценку и (опционально) оценку через размещенный API.

```bash
pip install aport-agent-guardrails
aport setup --framework yandex-deep-research
```

Это создаст:
- `~/.aport/yandex-deep-research/config.yaml` -- конфигурация оценщика (локальный или API режим)
- `~/.aport/yandex-deep-research/aport/passport.json` -- OAP паспорт с возможностями и ограничениями

**config.yaml (с использованием APort в качестве провайдера):**
```yaml
guardrails:
  enabled: true
  provider:
    use: aport_guardrails.providers.generic:OAPGuardrailProvider
```

**config.yaml (с использованием вашего собственного OAP провайдера):**
```yaml
guardrails:
  enabled: true
  provider:
    use: my_oap_provider:MyOAPProvider
    config:
      passport_path: ./my-passport.json
```

Любой провайдер, который принимает `framework` в качестве kwarg и реализует `evaluate`/`aevaluate`, будет работать. Стандарт OAP определяет формат паспорта и коды решений; Yandex Deep Research не важно, какой провайдер их читает.

**Что контролирует паспорт:**

| Поле паспорта | Что оно делает | Пример |
|---|---|---|
| `capabilities[].id` | Какие категории инструментов может использовать агент | `system.command.execute`, `data.file.write` |
| `limits.*.allowed_commands` | Какие команды разрешены | `["git", "npm", "node"]` или `["*"]` для всех |
| `limits.*.blocked_patterns` | Паттерны, которые всегда запрещены | `["rm -rf", "sudo", "chmod 777"]` |
| `status` | Выключатель (Kill switch) | `active`, `suspended`, `revoked` |

**Режимы оценки (зависят от провайдера):**

Провайдеры OAP могут поддерживать различные режимы оценки. Например, эталонная реализация APort поддерживает:

| Режим | Как это работает | Сеть | Задержка |
|---|---|---|---|
| **Локальный (Local)** | Оценивает паспорт локально (bash скрипт). | Нет | ~300мс |
| **API** | Отправляет паспорт + контекст на размещенный оценщик. Подписанные решения. | Да | ~65мс |

Пользовательский OAP провайдер может реализовать любую стратегию оценки -- middleware Yandex Deep Research не важно, как провайдер принимает решение.

**Попробуйте:**
1. Установите и настройте, как описано выше
2. Запустите Yandex Deep Research и попросите: "Создай файл test.txt с содержимым hello"
3. Затем попросите: "Теперь удали его используя bash rm -rf"
4. Ограничитель заблокирует это: `oap.blocked_pattern: Command contains blocked pattern: rm -rf`

### Вариант 3: Пользовательский Провайдер (Принеси свой)

Подойдет любой класс Python с методами `evaluate(request)` и `aevaluate(request)`. Базовый класс или наследование не нужны -- это структурный протокол.

```python
# my_guardrail.py

class MyGuardrailProvider:
    name = "my-company"

    def evaluate(self, request):
        from yandex-deep-research.guardrails.provider import GuardrailDecision, GuardrailReason

        # Пример: блокировать любую команду bash, содержащую "delete"
        if request.tool_name == "bash" and "delete" in str(request.tool_input):
            return GuardrailDecision(
                allow=False,
                reasons=[GuardrailReason(code="custom.blocked", message="delete not allowed")],
                policy_id="custom.v1",
            )
        return GuardrailDecision(allow=True, reasons=[GuardrailReason(code="oap.allowed")])

    async def aevaluate(self, request):
        return self.evaluate(request)
```

**config.yaml:**
```yaml
guardrails:
  enabled: true
  provider:
    use: my_guardrail:MyGuardrailProvider
```

Убедитесь, что `my_guardrail.py` находится в пути поиска Python (например, в директории backend или установлен как пакет).

**Попробуйте:**
1. Создайте `my_guardrail.py` в директории backend
2. Добавьте конфигурацию
3. Запустите Yandex Deep Research и попросите: "Используй bash, чтобы удалить test.txt"
4. Ваш провайдер заблокирует это

## Реализация Провайдера

### Требуемый Интерфейс

```
┌──────────────────────────────────────────────────┐
│              Протокол GuardrailProvider            │
│                                                   │
│  name: str                                        │
│                                                   │
│  evaluate(request: GuardrailRequest)              │
│      -> GuardrailDecision                         │
│                                                   │
│  aevaluate(request: GuardrailRequest)   (async)   │
│      -> GuardrailDecision                         │
└──────────────────────────────────────────────────┘

┌──────────────────────────┐    ┌──────────────────────────┐
│     GuardrailRequest     │    │    GuardrailDecision     │
│                          │    │                          │
│  tool_name: str          │    │  allow: bool             │
│  tool_input: dict        │    │  reasons: [GuardrailReason]│
│  agent_id: str | None    │    │  policy_id: str | None   │
│  thread_id: str | None   │    │  metadata: dict          │
│  is_subagent: bool       │    │                          │
│  timestamp: str          │    │  GuardrailReason:        │
│                          │    │    code: str             │
└──────────────────────────┘    │    message: str          │
                                └──────────────────────────┘
```

### Имена Инструментов Yandex Deep Research

Это имена инструментов, которые ваш провайдер увидит в `request.tool_name`:

| Инструмент | Что он делает |
|---|---|
| `bash` | Выполнение команд оболочки |
| `write_file` | Создание/перезапись файла |
| `str_replace` | Редактирование файла (поиск и замена) |
| `read_file` | Чтение содержимого файла |
| `ls` | Список файлов директории |
| `web_search` | Поисковый запрос в веб |
| `web_fetch` | Получение содержимого URL |
| `image_search` | Поиск изображений |
| `present_file` | Представление файла пользователю |
| `view_image` | Отображение изображения |
| `ask_clarification` | Задать вопрос пользователю |
| `task` | Делегирование субагенту |
| `mcp__*` | Инструменты MCP (динамические) |

### Коды Причин OAP

Стандартные коды, используемые в [спецификации OAP](https://github.com/aporthq/aport-spec):

| Код | Значение |
|---|---|
| `oap.allowed` | Вызов инструмента разрешен |
| `oap.tool_not_allowed` | Инструмент не в белом списке |
| `oap.command_not_allowed` | Команда не в allowed_commands |
| `oap.blocked_pattern` | Команда совпадает с заблокированным паттерном |
| `oap.limit_exceeded` | Операция превышает лимит |
| `oap.passport_suspended` | Статус паспорта приостановлен/аннулирован |
| `oap.evaluator_error` | Ошибка провайдера (fail-closed) |

### Загрузка Провайдера

Yandex Deep Research загружает провайдеры через `resolve_variable()` -- тот же механизм используется для моделей, инструментов и провайдеров песочниц. Поле `use:` - это путь к классу Python: `package.module:ClassName`.

Провайдер инстанцируется с `**config` kwargs, если задан `config:`, плюс всегда внедряется `framework="yandex-deep-research"`. Принимайте `**kwargs`, чтобы сохранить обратную совместимость:

```python
class YourProvider:
    def __init__(self, framework: str = "generic", **kwargs):
        # framework="yandex-deep-research" сообщает вам, какую директорию конфигурации использовать
        ...
```

## Справочник по Конфигурации

```yaml
guardrails:
  # Включить/выключить middleware ограничителя (по умолчанию: false)
  enabled: true

  # Блокировать вызовы инструментов, если провайдер вызывает исключение (по умолчанию: true)
  fail_closed: true

  # Ссылка на паспорт -- передается как request.agent_id провайдеру.
  # Путь к файлу, ID размещенного агента или null (провайдер берет из своей конфигурации).
  passport: null

  # Провайдер: загружается по пути класса через resolve_variable
  provider:
    use: yandex-deep-research.guardrails.builtin:AllowlistProvider
    config:  # необязательные kwargs, передаваемые в provider.__init__
      denied_tools: ["bash"]
```

## Тестирование

```bash
cd backend
uv run python -m pytest tests/test_guardrail_middleware.py -v
```

25 тестов покрывают:
- AllowlistProvider: разрешение, запрет, и белый+черный списки, асинхронность
- GuardrailMiddleware: пропуск при разрешении, запрет с OAP кодами, fail-closed, fail-open, передача паспорта, запасной вариант для пустых причин, пустое имя инструмента, проверка протокола isinstance
- Асинхронные пути: awrap_tool_call для разрешения, запрета, fail-closed, fail-open
- GraphBubbleUp: управляющие сигналы LangGraph пробрасываются (не перехватываются)
- Config: значения по умолчанию, from_dict, загрузка/сброс синглтона

## Файлы

```
packages/harness/yandex-deep-research/guardrails/
    __init__.py              # Публичные экспорты
    provider.py              # Протокол GuardrailProvider, GuardrailRequest, GuardrailDecision
    middleware.py             # GuardrailMiddleware (подкласс AgentMiddleware)
    builtin.py               # AllowlistProvider (без зависимостей)

packages/harness/yandex-deep-research/config/
    guardrails_config.py     # Pydantic модель GuardrailsConfig + синглтон

packages/harness/yandex-deep-research/agents/middlewares/
    tool_error_handling_middleware.py  # Регистрирует GuardrailMiddleware в цепочке

config.example.yaml          # Задокументированы три варианта провайдера
tests/test_guardrail_middleware.py  # 25 тестов
docs/GUARDRAILS.md           # Этот файл
```