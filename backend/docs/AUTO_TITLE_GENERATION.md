# Функция автоматической генерации заголовка (Thread Title)

## Описание функции

Автоматически генерирует заголовок для потока диалога, срабатывая после того, как пользователь задает первый вопрос и получает ответ.

## Способ реализации

Используется `TitleMiddleware` в хуке `after_model`:
1. Определяет, является ли это первым диалогом (1 сообщение пользователя + 1 ответ ассистента)
2. Проверяет, есть ли уже заголовок (title) в состоянии (state)
3. Вызывает LLM для генерации лаконичного заголовка (по умолчанию не более 6 слов)
4. Сохраняет title в `ThreadState` (будет персистентно сохранено с помощью checkpointer)

TitleMiddleware сначала нормализует структурированный контент (блоки/списки) из сообщений LangChain в простой текст, а затем подставляет в промпт для заголовка, чтобы избежать утечки оригинального repr Python/JSON в модель генерации заголовков.

## ⚠️ Важно: Механизм хранения

### Место хранения заголовка

Title хранится в **`ThreadState.title`**, а не в метаданных (metadata) потока:

```python
class ThreadState(AgentState):
    sandbox: SandboxState | None = None
    title: str | None = None  # ✅ Заголовок хранится здесь
```

### Информация о персистентности

| Способ развертывания | Персистентность | Описание |
|---------|--------|------|
| **LangGraph Studio (локально)** | ❌ Нет | Хранится только в памяти, теряется после перезапуска |
| **LangGraph Platform** | ✅ Да | Автоматически сохраняется в базу данных |
| **Пользовательский + Checkpointer** | ✅ Да | Требуется настройка PostgreSQL/SQLite checkpointer |

### Как включить персистентность

Если необходимо сохранять title при локальной разработке, нужно настроить checkpointer:

```python
# Создайте checkpointer.py в той же директории, что и langgraph.json
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver.from_conn_string(
    "postgresql://user:pass@localhost/dbname"
)
```

Затем сошлитесь на него в `langgraph.json`:

```json
{
  "graphs": {
    "lead_agent": "yandex-deep-research.agents:lead_agent"
  },
  "checkpointer": "checkpointer:checkpointer"
}
```

## Конфигурация

Добавьте в `config.yaml` (опционально):

```yaml
title:
  enabled: true
  max_words: 6
  max_chars: 60
  model_name: null  # Использовать модель по умолчанию
```

Или настройте в коде:

```python
from yandex-deep-research.config.title_config import TitleConfig, set_title_config

set_title_config(TitleConfig(
    enabled=True,
    max_words=8,
    max_chars=80,
))
```

## Использование на клиенте

### Получение заголовка потока (Thread Title)

```typescript
// Способ 1: Получение из состояния потока (thread state)
const state = await client.threads.getState(threadId);
const title = state.values.title || "New Conversation";

// Способ 2: Прослушивание событий потока (stream events)
for await (const chunk of client.runs.stream(threadId, assistantId, {
  input: { messages: [{ role: "user", content: "Hello" }] }
})) {
  if (chunk.event === "values" && chunk.data.title) {
    console.log("Title:", chunk.data.title);
  }
}
```

### Отображение заголовка

```typescript
// Отображение в списке диалогов
function ConversationList() {
  const [threads, setThreads] = useState([]);

  useEffect(() => {
    async function loadThreads() {
      const allThreads = await client.threads.list();
      
      // Получаем состояние каждого потока для чтения заголовка
      const threadsWithTitles = await Promise.all(
        allThreads.map(async (t) => {
          const state = await client.threads.getState(t.thread_id);
          return {
            id: t.thread_id,
            title: state.values.title || "New Conversation",
            updatedAt: t.updated_at,
          };
        })
      );
      
      setThreads(threadsWithTitles);
    }
    loadThreads();
  }, []);

  return (
    <ul>
      {threads.map(thread => (
        <li key={thread.id}>
          <a href={`/chat/${thread.id}`}>{thread.title}</a>
        </li>
      ))}
    </ul>
  );
}
```

## Рабочий процесс

```mermaid
sequenceDiagram
    participant User
    participant Client
    participant LangGraph
    participant TitleMiddleware
    participant LLM
    participant Checkpointer

    User->>Client: Отправляет первое сообщение
    Client->>LangGraph: POST /threads/{id}/runs
    LangGraph->>Agent: Обрабатывает сообщение
    Agent-->>LangGraph: Возвращает ответ
    LangGraph->>TitleMiddleware: after_agent()
    TitleMiddleware->>TitleMiddleware: Проверяет, нужно ли сгенерировать title
    TitleMiddleware->>LLM: Генерирует title
    LLM-->>TitleMiddleware: Возвращает title
    TitleMiddleware->>LangGraph: return {"title": "..."}
    LangGraph->>Checkpointer: Сохраняет state (включая title)
    LangGraph-->>Client: Возвращает ответ
    Client->>Client: Читает из state.values.title
```

## Преимущества

✅ **Надежная персистентность** - Использует механизм state из LangGraph, автоматическое сохранение  
✅ **Полностью серверная обработка** - Клиенту не нужна дополнительная логика  
✅ **Автоматическое срабатывание** - Автоматическая генерация после первого диалога  
✅ **Настраиваемость** - Поддерживает кастомную длину, модели и т.д.  
✅ **Отказоустойчивость** - При ошибке используется стратегия fallback  
✅ **Согласованная архитектура** - Согласуется с существующим SandboxMiddleware  

## Примечания

1. **Разница в способе чтения**: Title находится в `state.values.title`, а не в `thread.metadata.title`
2. **Вопросы производительности**: Генерация заголовка добавляет около 0.5-1 секунды задержки, можно оптимизировать, используя более быстрые модели
3. **Безопасность параллелизма**: Middleware запускается после выполнения агента и не блокирует основной процесс
4. **Стратегия Fallback**: Если вызов LLM завершился ошибкой, в качестве заголовка используются первые несколько слов из сообщения пользователя

## Тестирование

```python
# Тестирование генерации заголовка
import pytest
from yandex-deep-research.agents.title_middleware import TitleMiddleware

def test_title_generation():
    # TODO: Добавить модульные тесты
    pass
```

## Устранение неполадок

### Заголовок не генерируется

1. Проверьте, включена ли конфигурация: `get_title_config().enabled == True`
2. Проверьте логи: Ищите "Generated thread title" или сообщения об ошибках
3. Убедитесь, что это первый диалог: Срабатывает только если есть ровно 1 сообщение пользователя и 1 ответ ассистента

### Заголовок сгенерирован, но клиент его не видит

1. Убедитесь в правильности места чтения: Следует читать из `state.values.title`, а не из `thread.metadata.title`
2. Проверьте ответ API: Убедитесь, что поле title присутствует в state
3. Попробуйте получить state заново: `client.threads.getState(threadId)`

### Заголовок теряется после перезапуска

1. Проверьте, настроен ли checkpointer (необходимо для локальной разработки)
2. Уточните способ развертывания: LangGraph Platform сохраняет данные автоматически
3. Проверьте базу данных: Убедитесь, что checkpointer работает нормально

## Проектирование архитектуры

### Почему используется State, а не Metadata?

| Особенность | State | Metadata |
|------|-------|----------|
| **Персистентность** | ✅ Автоматически (через checkpointer) | ⚠️ Зависит от реализации |
| **Управление версиями** | ✅ Поддерживает перемещение во времени (time travel) | ❌ Не поддерживает |
| **Типобезопасность** | ✅ Определено через TypedDict | ❌ Произвольный словарь |
| **Отслеживаемость** | ✅ Записывается каждое обновление | ⚠️ Только последнее значение |
| **Стандартизация** | ✅ Основной механизм LangGraph | ⚠️ Расширенная функциональность |

### Детали реализации

```python
# Основная логика TitleMiddleware
@override
def after_agent(self, state: TitleMiddlewareState, runtime: Runtime) -> dict | None:
    """Generate and set thread title after the first agent response."""
    if self._should_generate_title(state, runtime):
        title = self._generate_title(runtime)
        print(f"Generated thread title: {title}")
        
        # ✅ Возвращает обновление state, которое будет автоматически сохранено через checkpointer
        return {"title": title}
    
    return None
```

## Связанные файлы

- [`packages/harness/yandex-deep-research/agents/thread_state.py`](../packages/harness/yandex-deep-research/agents/thread_state.py) - Определение ThreadState
- [`packages/harness/yandex-deep-research/agents/middlewares/title_middleware.py`](../packages/harness/yandex-deep-research/agents/middlewares/title_middleware.py) - Реализация TitleMiddleware
- [`packages/harness/yandex-deep-research/config/title_config.py`](../packages/harness/yandex-deep-research/config/title_config.py) - Управление конфигурацией
- [`config.yaml`](../../config.example.yaml) - Файл конфигурации
- [`packages/harness/yandex-deep-research/agents/lead_agent/agent.py`](../packages/harness/yandex-deep-research/agents/lead_agent/agent.py) - Регистрация Middleware

## Справочные материалы

- [Документация LangGraph Checkpointer](https://langchain-ai.github.io/langgraph/concepts/persistence/)
- [Управление состоянием LangGraph (State)](https://langchain-ai.github.io/langgraph/concepts/low_level/#state)
- [LangGraph Middleware](https://langchain-ai.github.io/langgraph/concepts/middleware/)
