# Функция загрузки файлов

## Обзор

Бэкенд Yandex Deep Research предоставляет полноценную функцию загрузки файлов, поддерживает одновременную загрузку нескольких файлов и автоматически преобразует документы Office и PDF в формат Markdown.

## Особенности

- ✅ Поддержка одновременной загрузки нескольких файлов
- ✅ Автоматическое преобразование документов в Markdown (PDF, PPT, Excel, Word)
- ✅ Файлы хранятся в изолированных директориях потоков (threads)
- ✅ Агент автоматически распознает загруженные файлы
- ✅ Поддержка запроса списка файлов и их удаления

## API Эндпоинты

### 1. Загрузка файлов
```
POST /api/threads/{thread_id}/uploads
```

**Тело запроса:** `multipart/form-data`
- `files`: Один или несколько файлов

**Ответ:**
```json
{
  "success": true,
  "files": [
    {
      "filename": "document.pdf",
      "size": 1234567,
      "path": ".yandex-deep-research/threads/{thread_id}/user-data/uploads/document.pdf",
      "virtual_path": "/mnt/user-data/uploads/document.pdf",
      "artifact_url": "/api/threads/{thread_id}/artifacts/mnt/user-data/uploads/document.pdf",
      "markdown_file": "document.md",
      "markdown_path": ".yandex-deep-research/threads/{thread_id}/user-data/uploads/document.md",
      "markdown_virtual_path": "/mnt/user-data/uploads/document.md",
      "markdown_artifact_url": "/api/threads/{thread_id}/artifacts/mnt/user-data/uploads/document.md"
    }
  ],
  "message": "Successfully uploaded 1 file(s)"
}
```

**Описание путей:**
- `path`: Фактический путь в файловой системе (относительно директории `backend/`)
- `virtual_path`: Виртуальный путь, используемый Агентом в песочнице
- `artifact_url`: URL для доступа фронтенда к файлу по HTTP

### 2. Получение списка загруженных файлов
```
GET /api/threads/{thread_id}/uploads/list
```

**Ответ:**
```json
{
  "files": [
    {
      "filename": "document.pdf",
      "size": 1234567,
      "path": ".yandex-deep-research/threads/{thread_id}/user-data/uploads/document.pdf",
      "virtual_path": "/mnt/user-data/uploads/document.pdf",
      "artifact_url": "/api/threads/{thread_id}/artifacts/mnt/user-data/uploads/document.pdf",
      "extension": ".pdf",
      "modified": 1705997600.0
    }
  ],
  "count": 1
}
```

### 3. Удаление файла
```
DELETE /api/threads/{thread_id}/uploads/{filename}
```

**Ответ:**
```json
{
  "success": true,
  "message": "Deleted document.pdf"
}
```

## Поддерживаемые форматы документов

Следующие форматы автоматически преобразуются в Markdown:
- PDF (`.pdf`)
- PowerPoint (`.ppt`, `.pptx`)
- Excel (`.xls`, `.xlsx`)
- Word (`.doc`, `.docx`)

Преобразованный файл Markdown сохраняется в той же директории с именем исходного файла + расширение `.md`.

## Интеграция с Агентом

### Автоматическое перечисление файлов

Агент автоматически получает список загруженных файлов при каждом запросе в следующем формате:

```xml
<uploaded_files>
The following files have been uploaded and are available for use:

- document.pdf (1.2 MB)
  Path: /mnt/user-data/uploads/document.pdf

- document.md (45.3 KB)
  Path: /mnt/user-data/uploads/document.md

You can read these files using the `read_file` tool with the paths shown above.
</uploaded_files>
```

### Использование загруженных файлов

Агент работает в песочнице и использует виртуальные пути для доступа к файлам. Агент может напрямую использовать инструмент `read_file` для чтения загруженных файлов:

```python
# Чтение исходного PDF (если поддерживается)
read_file(path="/mnt/user-data/uploads/document.pdf")

# Чтение преобразованного Markdown (рекомендуется)
read_file(path="/mnt/user-data/uploads/document.md")
```

**Отображение путей:**
- Используется Агентом: `/mnt/user-data/uploads/document.pdf` (виртуальный путь)
- Фактическое хранилище: `backend/.yandex-deep-research/threads/{thread_id}/user-data/uploads/document.pdf`
- Доступ из фронтенда: `/api/threads/{thread_id}/artifacts/mnt/user-data/uploads/document.pdf` (HTTP URL)

Процесс загрузки использует стратегию "приоритет директории потока":
- Сначала записывается в `backend/.yandex-deep-research/threads/{thread_id}/user-data/uploads/` как в авторитетное хранилище
- Локальная песочница (`sandbox_id=local`) использует содержимое директории потока напрямую
- Нелокальные песочницы дополнительно синхронизируются с `/mnt/user-data/uploads/*` для обеспечения видимости во время выполнения

## Примеры тестирования

### Тестирование с помощью curl

```bash
# 1. Загрузка одного файла
curl -X POST http://localhost:2026/api/threads/test-thread/uploads \
  -F "files=@/path/to/document.pdf"

# 2. Загрузка нескольких файлов
curl -X POST http://localhost:2026/api/threads/test-thread/uploads \
  -F "files=@/path/to/document.pdf" \
  -F "files=@/path/to/presentation.pptx" \
  -F "files=@/path/to/spreadsheet.xlsx"

# 3. Получение списка загруженных файлов
curl http://localhost:2026/api/threads/test-thread/uploads/list

# 4. Удаление файла
curl -X DELETE http://localhost:2026/api/threads/test-thread/uploads/document.pdf
```

### Тестирование с помощью Python

```python
import requests

thread_id = "test-thread"
base_url = "http://localhost:2026"

# Загрузка файлов
files = [
    ("files", open("document.pdf", "rb")),
    ("files", open("presentation.pptx", "rb")),
]
response = requests.post(
    f"{base_url}/api/threads/{thread_id}/uploads",
    files=files
)
print(response.json())

# Получение списка файлов
response = requests.get(f"{base_url}/api/threads/{thread_id}/uploads/list")
print(response.json())

# Удаление файла
response = requests.delete(
    f"{base_url}/api/threads/{thread_id}/uploads/document.pdf"
)
print(response.json())
```

## Структура хранения файлов

```
backend/.yandex-deep-research/threads/
└── {thread_id}/
    └── user-data/
        └── uploads/
            ├── document.pdf          # Исходный файл
            ├── document.md           # Преобразованный Markdown
            ├── presentation.pptx
            ├── presentation.md
            └── ...
```

## Ограничения

- Максимальный размер файла: 100 МБ (можно настроить в nginx.conf через `client_max_body_size`)
- Безопасность имен файлов: Система автоматически проверяет пути к файлам для предотвращения атак обхода каталога (directory traversal)
- Изоляция потоков: Загруженные файлы каждого потока изолированы и недоступны из других потоков

## Техническая реализация

### Компоненты

1. **Upload Router** (`app/gateway/routers/uploads.py`)
   - Обрабатывает запросы на загрузку, получение списка и удаление файлов
   - Использует markitdown для преобразования документов

2. **Uploads Middleware** (`packages/harness/yandex-deep-research/agents/middlewares/uploads_middleware.py`)
   - Внедряет список файлов перед каждым запросом Агента
   - Автоматически генерирует отформатированные сообщения со списком файлов

3. **Nginx конфигурация** (`nginx.conf`)
   - Маршрутизирует запросы на загрузку к Gateway API
   - Настраивает поддержку загрузки больших файлов

### Зависимости

- `markitdown>=0.0.1a2` - Преобразование документов
- `python-multipart>=0.0.20` - Обработка загрузки файлов

## Устранение неполадок

### Ошибка загрузки файла

1. Проверьте, не превышает ли размер файла установленный лимит
2. Проверьте, нормально ли работает Gateway API
3. Проверьте, достаточно ли места на диске
4. Просмотрите логи Gateway: `make gateway`

### Ошибка преобразования документа

1. Проверьте, правильно ли установлен markitdown: `uv run python -c "import markitdown"`
2. Просмотрите конкретное сообщение об ошибке в логах
3. Некоторые поврежденные или зашифрованные документы могут не поддаваться преобразованию, но исходный файл все равно будет сохранен

### Агент не видит загруженные файлы

1. Убедитесь, что UploadsMiddleware зарегистрирован в agent.py
2. Проверьте правильность thread_id
3. Убедитесь, что файл действительно загружен в `backend/.yandex-deep-research/threads/{thread_id}/user-data/uploads/`
4. В сценариях нелокальной песочницы убедитесь, что интерфейс загрузки не выдает ошибок (синхронизация песочницы должна быть успешно завершена)

## Рекомендации по разработке

### Интеграция с фронтендом

```typescript
// Пример загрузки файлов
async function uploadFiles(threadId: string, files: File[]) {
  const formData = new FormData();
  files.forEach(file => {
    formData.append('files', file);
  });

  const response = await fetch(
    `/api/threads/${threadId}/uploads`,
    {
      method: 'POST',
      body: formData,
    }
  );

  return response.json();
}

// Получение списка файлов
async function listFiles(threadId: string) {
  const response = await fetch(
    `/api/threads/${threadId}/uploads/list`
  );
  return response.json();
}
```

### Идеи для расширения функционала

1. **Предпросмотр файлов**: Добавить эндпоинт предпросмотра для просмотра файлов прямо в браузере
2. **Пакетное удаление**: Поддержка удаления нескольких файлов одновременно
3. **Поиск файлов**: Поддержка поиска по имени или типу файла
4. **Контроль версий**: Сохранение нескольких версий файла
5. **Поддержка архивов**: Автоматическая распаковка zip-файлов
6. **OCR для изображений**: Выполнение OCR-распознавания загруженных изображений
