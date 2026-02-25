---
title: API Reference
nav_order: 5
has_children: true
---

[Home](../index.md) > API Reference

# API Reference

REST endpoint reference and WebSocket channel documentation.

---

## API Overview

Sound Forge Alchemy exposes three API surfaces:

| Surface | Base Path | Auth | Rate Limit |
|---------|-----------|------|-----------|
| [REST API](rest.md) | `/api` | Bearer token | 60 req/min (standard), 10 req/min (heavy) |
| [WebSocket](websocket.md) | `/socket` (Phoenix Channel) | Session or token | N/A |
| [LiveView WebSocket](websocket.md#livesocket) | `/live` | Session cookie | N/A |

---

## Authentication

All `/api` endpoints require authentication via the `api_auth` pipeline.

```
Authorization: Bearer {api_token}
```

API tokens are generated in user Settings → API Keys.

---

## Rate Limits

| Pipeline | Limit | Window | Applies To |
|----------|-------|--------|-----------|
| `api_auth` | 60 requests | 60 seconds | All API routes |
| `api_heavy` | 10 requests | 60 seconds | `POST /api/download/track`, `POST /api/processing/separate`, `POST /api/analysis/analyze` |

Rate limit headers returned on all responses:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 58
X-RateLimit-Reset: 1708900000
```

---

## Response Format

All responses use JSON. Successful responses:

```json
{"data": {...}}
```

Error responses:

```json
{"error": "description", "code": "ERROR_CODE"}
```

---

## Sections

- [REST Endpoints](rest.md)
- [WebSocket Channels](websocket.md)

---

## See Also

- [Architecture: Routes](../architecture/index.md)
- [Configuration: API keys](../guides/configuration.md)

---

[Next: REST Endpoints →](rest.md)
