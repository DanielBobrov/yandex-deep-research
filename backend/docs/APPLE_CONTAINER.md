# Поддержка Apple Container

Yandex Deep Research теперь поддерживает Apple Container в качестве предпочтительной среды выполнения контейнеров на macOS с автоматическим переходом на Docker.

## Обзор

Начиная с этой версии, Yandex Deep Research автоматически обнаруживает и использует Apple Container на macOS, когда он доступен, и переключается на Docker, если:
- Apple Container не установлен
- Запуск происходит на платформах, отличных от macOS

Это обеспечивает лучшую производительность на компьютерах Mac с процессорами Apple Silicon при сохранении совместимости со всеми платформами.

## Преимущества

### На компьютерах Mac с процессорами Apple Silicon при использовании Apple Container:
- **Лучшая производительность**: Нативное выполнение ARM64 без трансляции Rosetta 2
- **Меньшее потребление ресурсов**: Более легковесный, чем Docker Desktop
- **Нативная интеграция**: Использует macOS Virtualization.framework

### При переходе на Docker:
- Полная обратная совместимость
- Работает на всех платформах (macOS, Linux, Windows)
- Не требуется изменение конфигурации

## Требования

### Для Apple Container (только macOS):
- macOS 15.0 или новее
- Apple Silicon (M1/M2/M3/M4)
- Установленный Apple Container CLI

### Установка:
```bash
# Загрузите из релизов GitHub
# https://github.com/apple/container/releases

# Проверьте установку
container --version

# Запустите сервис
container system start
```

### Для Docker (все платформы):
- Docker Desktop или Docker Engine

## Как это работает

### Автоматическое обнаружение

`AioSandboxProvider` автоматически обнаруживает доступную среду выполнения контейнеров:

1. На macOS: Пытается выполнить `container --version`
   - Успех → Использовать Apple Container
   - Ошибка → Перейти на Docker

2. На других платформах: Использовать Docker напрямую

### Различия сред выполнения

Обе среды используют практически идентичный синтаксис команд:

**Запуск контейнера:**
```bash
# Apple Container
container run --rm -d -p 8080:8080 -v /host:/container -e KEY=value image

# Docker
docker run --rm -d -p 8080:8080 -v /host:/container -e KEY=value image
```

**Очистка контейнера:**
```bash
# Apple Container (с флагом --rm)
container stop <id>  # Автоматически удаляется благодаря --rm

# Docker (с флагом --rm)
docker stop <id>     # Автоматически удаляется благодаря --rm
```

### Детали реализации

Реализация находится в `backend/packages/harness/yandex-deep-research/community/aio_sandbox/aio_sandbox_provider.py`:

- `_detect_container_runtime()`: Обнаруживает доступную среду выполнения при запуске
- `_start_container()`: Использует обнаруженную среду, пропускает специфичные для Docker опции при использовании Apple Container
- `_stop_container()`: Использует соответствующую команду остановки для текущей среды

## Конфигурация

Никаких изменений конфигурации не требуется! Система работает автоматически.

Однако вы можете проверить используемую среду выполнения, просмотрев логи:

```
INFO:yandex-deep-research.community.aio_sandbox.aio_sandbox_provider:Detected Apple Container: container version 0.1.0
INFO:yandex-deep-research.community.aio_sandbox.aio_sandbox_provider:Starting sandbox container using container: ...
```

Или для Docker:
```
INFO:yandex-deep-research.community.aio_sandbox.aio_sandbox_provider:Apple Container not available, falling back to Docker
INFO:yandex-deep-research.community.aio_sandbox.aio_sandbox_provider:Starting sandbox container using docker: ...
```

## Образы контейнеров

Обе среды используют OCI-совместимые образы. Образ по умолчанию работает с обеими:

```yaml
sandbox:
  use: yandex-deep-research.community.aio_sandbox:AioSandboxProvider
  image: enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest  # Образ по умолчанию
```

Убедитесь, что ваши образы доступны для соответствующей архитектуры:
- ARM64 для Apple Container на Apple Silicon
- AMD64 для Docker на компьютерах Mac с Intel
- Мультиархитектурные образы работают на обеих платформах

### Предварительная загрузка образов (рекомендуется)

**Важно**: Образы контейнеров обычно большие (500 МБ+) и загружаются при первом использовании, что может вызвать долгое время ожидания без четкой обратной связи.

**Лучшая практика**: Предварительно загрузите образ во время настройки:

```bash
# Из корневой директории проекта
make setup-sandbox
```

Эта команда:
1. Прочитает настроенный образ из `config.yaml` (или использует образ по умолчанию)
2. Обнаружит доступную среду выполнения (Apple Container или Docker)
3. Загрузит образ с индикацией прогресса
4. Проверит, готов ли образ к использованию

**Ручная предварительная загрузка**:

```bash
# Используя Apple Container
container image pull enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest

# Используя Docker
docker pull enterprise-public-cn-beijing.cr.volces.com/vefaas-public/all-in-one-sandbox:latest
```

Если вы пропустите предварительную загрузку, образ будет автоматически загружен при первом выполнении агента, что может занять несколько минут в зависимости от скорости вашей сети.

## Скрипты очистки

Проект включает унифицированный скрипт очистки, который обрабатывает обе среды выполнения:

**Скрипт:** `scripts/cleanup-containers.sh`

**Использование:**
```bash
# Очистить все sandbox-контейнеры Yandex Deep Research
./scripts/cleanup-containers.sh yandex-deep-research-sandbox

# Пользовательский префикс
./scripts/cleanup-containers.sh my-prefix
```

**Интеграция с Makefile:**

Все команды очистки в `Makefile` автоматически поддерживают обе среды выполнения:
```bash
make stop   # Останавливает все сервисы и очищает контейнеры
make clean  # Полная очистка, включая логи
```

## Тестирование

Протестируйте обнаружение среды выполнения контейнеров:

```bash
cd backend
python test_container_runtime.py
```

Это:
1. Обнаружит доступную среду выполнения
2. Опционально запустит тестовый контейнер
3. Проверит подключение
4. Выполнит очистку

## Устранение неполадок

### Apple Container не обнаружен на macOS

1. Проверьте, установлен ли:
   ```bash
   which container
   container --version
   ```

2. Проверьте, запущен ли сервис:
   ```bash
   container system start
   ```

3. Проверьте логи на наличие сообщения об обнаружении:
   ```bash
   # Ищите сообщение об обнаружении в логах приложения
   grep "container runtime" logs/*.log
   ```

### Контейнеры не очищаются

1. Вручную проверьте запущенные контейнеры:
   ```bash
   # Apple Container
   container list

   # Docker
   docker ps
   ```

2. Запустите скрипт очистки вручную:
   ```bash
   ./scripts/cleanup-containers.sh yandex-deep-research-sandbox
   ```

### Проблемы с производительностью

- Apple Container должен быть быстрее на Apple Silicon
- Если возникают проблемы, вы можете принудительно использовать Docker, временно переименовав команду `container`:
   ```bash
   # Временное решение - не рекомендуется для постоянного использования
   sudo mv /opt/homebrew/bin/container /opt/homebrew/bin/container.bak
   ```

## Ссылки

- [Apple Container на GitHub](https://github.com/apple/container)
- [Документация Apple Container](https://github.com/apple/container/blob/main/docs/)
- [Спецификация образов OCI (OCI Image Spec)](https://github.com/opencontainers/image-spec)