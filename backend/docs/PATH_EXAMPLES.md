# Примеры использования путей файлов

## Три типа путей

Система загрузки файлов Yandex Deep Research возвращает три различных типа путей, каждый из которых используется для разных сценариев:

### 1. Фактический путь файловой системы (path)

```
.yandex-deep-research/threads/{thread_id}/user-data/uploads/document.pdf
```

**Использование:**
- Фактическое расположение файла в файловой системе сервера
- Относительно директории `backend/`
- Используется для прямого доступа к файловой системе, резервного копирования, отладки и т.д.

**Пример:**
```python
# Прямой доступ в коде Python
from pathlib import Path
file_path = Path("backend/.yandex-deep-research/threads/abc123/user-data/uploads/document.pdf")
content = file_path.read_bytes()
```

### 2. Виртуальный путь (virtual_path)

```
/mnt/user-data/uploads/document.pdf
```

**Использование:**
- Путь, используемый агентом в среде песочницы
- Система песочницы автоматически отображает его на фактический путь
- Все инструменты агента для работы с файлами используют этот путь

**Пример:**
Использование агентом в диалоге:
```python
# Агент использует инструмент read_file
read_file(path="/mnt/user-data/uploads/document.pdf")

# Агент использует инструмент bash
bash(command="cat /mnt/user-data/uploads/document.pdf")
```

### 3. URL для HTTP доступа (artifact_url)

```
/api/threads/{thread_id}/artifacts/mnt/user-data/uploads/document.pdf
```

**Использование:**
- Фронтенд получает доступ к файлу через HTTP
- Используется для скачивания, предварительного просмотра файлов
- Можно открыть непосредственно в браузере

**Пример:**
```typescript
// Код TypeScript/JavaScript на фронтенде
const threadId = 'abc123';
const filename = 'document.pdf';

// Скачать файл
const downloadUrl = `/api/threads/${threadId}/artifacts/mnt/user-data/uploads/${filename}?download=true`;
window.open(downloadUrl);

// Предварительный просмотр в новом окне
const viewUrl = `/api/threads/${threadId}/artifacts/mnt/user-data/uploads/${filename}`;
window.open(viewUrl, '_blank');

// Получение с использованием fetch API
const response = await fetch(viewUrl);
const blob = await response.blob();
```

## Пример полного процесса использования

### Сценарий: Фронтенд загружает файл и позволяет агенту его обработать

```typescript
// 1. Фронтенд загружает файл
async function uploadAndProcess(threadId: string, file: File) {
  // Загрузка файла
  const formData = new FormData();
  formData.append('files', file);

  const uploadResponse = await fetch(
    `/api/threads/${threadId}/uploads`,
    {
      method: 'POST',
      body: formData
    }
  );

  const uploadData = await uploadResponse.json();
  const fileInfo = uploadData.files[0];

  console.log('Информация о файле：', fileInfo);
  // {
  //   filename: "report.pdf",
  //   path: ".yandex-deep-research/threads/abc123/user-data/uploads/report.pdf",
  //   virtual_path: "/mnt/user-data/uploads/report.pdf",
  //   artifact_url: "/api/threads/abc123/artifacts/mnt/user-data/uploads/report.pdf",
  //   markdown_file: "report.md",
  //   markdown_path: ".yandex-deep-research/threads/abc123/user-data/uploads/report.md",
  //   markdown_virtual_path: "/mnt/user-data/uploads/report.md",
  //   markdown_artifact_url: "/api/threads/abc123/artifacts/mnt/user-data/uploads/report.md"
  // }

  // 2. Отправка сообщения агенту
  await sendMessage(threadId, "Пожалуйста, проанализируйте только что загруженный PDF-файл");

  // Агент автоматически увидит список файлов, включая:
  // - report.pdf (виртуальный путь: /mnt/user-data/uploads/report.pdf)
  // - report.md (виртуальный путь: /mnt/user-data/uploads/report.md)

  // 3. Фронтенд может получить прямой доступ к преобразованному Markdown
  const mdResponse = await fetch(fileInfo.markdown_artifact_url);
  const markdownContent = await mdResponse.text();
  console.log('Содержимое Markdown：', markdownContent);

  // 4. Или скачать оригинальный PDF
  const downloadLink = document.createElement('a');
  downloadLink.href = fileInfo.artifact_url + '?download=true';
  downloadLink.download = fileInfo.filename;
  downloadLink.click();
}
```

## Таблица преобразования путей

| Сценарий | Используемый тип пути | Пример |
|------|---------------|------|
| Прямой доступ серверного кода (backend) | `path` | `.yandex-deep-research/threads/abc123/user-data/uploads/file.pdf` |
| Вызов инструмента агента | `virtual_path` | `/mnt/user-data/uploads/file.pdf` |
| Фронтенд скачивание/предпросмотр | `artifact_url` | `/api/threads/abc123/artifacts/mnt/user-data/uploads/file.pdf` |
| Скрипт резервного копирования | `path` | `.yandex-deep-research/threads/abc123/user-data/uploads/file.pdf` |
| Логирование | `path` | `.yandex-deep-research/threads/abc123/user-data/uploads/file.pdf` |

## Набор примеров кода

### Python - Обработка на бэкенде

```python
from pathlib import Path
from yandex-deep-research.agents.middlewares.thread_data_middleware import THREAD_DATA_BASE_DIR

def process_uploaded_file(thread_id: str, filename: str):
    # Использование фактического пути
    base_dir = Path.cwd() / THREAD_DATA_BASE_DIR / thread_id / "user-data" / "uploads"
    file_path = base_dir / filename

    # Прямое чтение
    with open(file_path, 'rb') as f:
        content = f.read()

    return content
```

### JavaScript - Доступ с фронтенда

```javascript
// Получение списка загруженных файлов
async function listUploadedFiles(threadId) {
  const response = await fetch(`/api/threads/${threadId}/uploads/list`);
  const data = await response.json();

  // Создание ссылок на скачивание для каждого файла
  data.files.forEach(file => {
    console.log(`Файл: ${file.filename}`);
    console.log(`Скачать: ${file.artifact_url}?download=true`);
    console.log(`Предпросмотр: ${file.artifact_url}`);

    // Если это документ, также есть Markdown версия
    if (file.markdown_artifact_url) {
      console.log(`Markdown: ${file.markdown_artifact_url}`);
    }
  });

  return data.files;
}

// Удаление файла
async function deleteFile(threadId, filename) {
  const response = await fetch(
    `/api/threads/${threadId}/uploads/${filename}`,
    { method: 'DELETE' }
  );
  return response.json();
}
```

### Пример компонента React

```tsx
import React, { useState, useEffect } from 'react';

interface UploadedFile {
  filename: string;
  size: number;
  path: string;
  virtual_path: string;
  artifact_url: string;
  extension: string;
  modified: number;
  markdown_artifact_url?: string;
}

function FileUploadList({ threadId }: { threadId: string }) {
  const [files, setFiles] = useState<UploadedFile[]>([]);

  useEffect(() => {
    fetchFiles();
  }, [threadId]);

  async function fetchFiles() {
    const response = await fetch(`/api/threads/${threadId}/uploads/list`);
    const data = await response.json();
    setFiles(data.files);
  }

  async function handleUpload(event: React.ChangeEvent<HTMLInputElement>) {
    const fileList = event.target.files;
    if (!fileList) return;

    const formData = new FormData();
    Array.from(fileList).forEach(file => {
      formData.append('files', file);
    });

    await fetch(`/api/threads/${threadId}/uploads`, {
      method: 'POST',
      body: formData
    });

    fetchFiles(); // Обновить список
  }

  async function handleDelete(filename: string) {
    await fetch(`/api/threads/${threadId}/uploads/${filename}`, {
      method: 'DELETE'
    });
    fetchFiles(); // Обновить список
  }

  return (
    <div>
      <input type="file" multiple onChange={handleUpload} />

      <ul>
        {files.map(file => (
          <li key={file.filename}>
            <span>{file.filename}</span>
            <a href={file.artifact_url} target="_blank">Предпросмотр</a>
            <a href={`${file.artifact_url}?download=true`}>Скачать</a>
            {file.markdown_artifact_url && (
              <a href={file.markdown_artifact_url} target="_blank">Markdown</a>
            )}
            <button onClick={() => handleDelete(file.filename)}>Удалить</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

## Примечания

1. **Безопасность путей**
   - Фактический путь (`path`) содержит ID потока, обеспечивая изоляцию.
   - API проверяет пути для предотвращения атак обхода каталога.
   - Фронтенд не должен использовать `path` напрямую, вместо этого следует использовать `artifact_url`.

2. **Использование агентом**
   - Агент может видеть и использовать только `virtual_path`.
   - Система песочницы автоматически отображает его на фактический путь.
   - Агенту не нужно знать фактическую структуру файловой системы.

3. **Интеграция с фронтендом**
   - Всегда используйте `artifact_url` для доступа к файлам.
   - Не пытайтесь получить прямой доступ к путям файловой системы.
   - Используйте параметр `?download=true` для принудительного скачивания.

4. **Конвертация в Markdown**
   - При успешной конвертации возвращаются дополнительные поля `markdown_*`.
   - Рекомендуется отдавать предпочтение версии Markdown (ее легче обрабатывать).
   - Исходный файл всегда сохраняется.
