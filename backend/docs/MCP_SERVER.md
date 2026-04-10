# Конфигурация MCP (Model Context Protocol)

Yandex Deep Research поддерживает настраиваемые MCP-серверы и навыки (skills) для расширения своих возможностей, которые загружаются из специального файла `extensions_config.json` в корневой директории проекта.

## Установка

1. Скопируйте `extensions_config.example.json` в `extensions_config.json` в корневой директории проекта.
   ```bash
   # Копирование примера конфигурации
   cp extensions_config.example.json extensions_config.json
   ```
   
2. Включите нужные MCP-серверы или навыки, установив `"enabled": true`.
3. Настройте команду, аргументы и переменные окружения для каждого сервера по мере необходимости.
4. Перезапустите приложение для загрузки и регистрации инструментов MCP.

## Поддержка OAuth (MCP-серверы HTTP/SSE)

Для MCP-серверов типов `http` и `sse` Yandex Deep Research поддерживает получение токенов OAuth и их автоматическое обновление.

- Поддерживаемые типы разрешений (grants): `client_credentials`, `refresh_token`
- Настройте блок `oauth` для каждого сервера в `extensions_config.json`
- Секреты должны передаваться через переменные окружения (например: `$MCP_OAUTH_CLIENT_SECRET`)

Пример:

```json
{
   "mcpServers": {
      "secure-http-server": {
         "enabled": true,
         "type": "http",
         "url": "https://api.example.com/mcp",
         "oauth": {
            "enabled": true,
            "token_url": "https://auth.example.com/oauth/token",
            "grant_type": "client_credentials",
            "client_id": "$MCP_OAUTH_CLIENT_ID",
            "client_secret": "$MCP_OAUTH_CLIENT_SECRET",
            "scope": "mcp.read",
            "refresh_skew_seconds": 60
         }
      }
   }
}
```

## Как это работает

MCP-серверы предоставляют инструменты, которые автоматически обнаруживаются и интегрируются в систему агентов Yandex Deep Research во время выполнения (runtime). После включения эти инструменты становятся доступными для агентов без дополнительных изменений в коде.

## Примеры возможностей

MCP-серверы могут предоставлять доступ к:

- **Файловым системам**
- **Базам данных** (например, PostgreSQL)
- **Внешним API** (например, GitHub, Brave Search)
- **Автоматизации браузера** (например, Puppeteer)
- **Пользовательским реализациям MCP-серверов**

## Узнать больше

Для получения подробной документации о Model Context Protocol посетите:  
https://modelcontextprotocol.io
