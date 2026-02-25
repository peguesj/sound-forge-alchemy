---
title: API Reference
nav_order: 5
has_children: true
---

[Home](../index.md) > API Reference

# API Reference

Sound Forge Alchemy exposes REST endpoints and WebSocket channels for programmatic access to tracks, jobs, analysis, stem separation, AI agents, and administration.

---

## Base URLs

| Environment | Base URL |
|-------------|----------|
| Development | `http://localhost:4000` |
| Production | `https://sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io` |

All paths below are relative to the base URL.

---

## API Surfaces

| Surface | Base Path | Protocol | Auth Method |
|---------|-----------|----------|-------------|
| [REST API](rest.md) | `/api` | HTTPS | Bearer token |
| [WebSocket Channels](websocket.md) | `/socket` | WSS (Phoenix Channel) | Session cookie or token |
| [LiveView WebSocket](websocket.md#livesocket) | `/live/websocket` | WSS | Session cookie |

---

## Authentication

### Session Cookie (Browser Clients)

The web UI authenticates via a Phoenix session cookie set at login. Browser clients do not need to manage tokens explicitly — the cookie is issued by `POST /users/log_in` and automatically included in all subsequent requests.

```
POST /users/log_in
Content-Type: application/x-www-form-urlencoded

user[email]=you@example.com&user[password]=secret
```

### Spotify OAuth

Spotify OAuth is initiated at `/auth/spotify` and handled by the callback at `/auth/spotify/callback`. On successful authorization the user is either created or linked and a session cookie is set. The Spotify access token is stored server-side and refreshed automatically.

```
GET /auth/spotify
→ redirects to Spotify authorization page

GET /auth/spotify/callback?code=...&state=...
→ exchanges code, sets session cookie, redirects to /
```

### Bearer Token (API Clients)

Programmatic clients authenticate with a bearer token generated in user Settings under "API Keys". Include the token in the `Authorization` header on every request:

```
Authorization: Bearer {api_token}
```

Tokens are tied to the generating user account and inherit that user's role permissions.

---

## Route Groups

### `/api/tracks`

Track resource CRUD and metadata.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/tracks` | List tracks for the authenticated user (paginated) |
| `GET` | `/api/tracks/:id` | Fetch a single track with full metadata |
| `PATCH` | `/api/tracks/:id` | Update track metadata (title, BPM, key, tags) |
| `DELETE` | `/api/tracks/:id` | Delete track and associated files |

---

### `/api/jobs`

Oban job queue inspection and control.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/jobs` | List recent jobs for the authenticated user |
| `GET` | `/api/jobs/:id` | Fetch job status and progress |
| `DELETE` | `/api/jobs/:id` | Cancel a pending job |

---

### `/api/spotify`

Spotify metadata and track search.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/spotify/search` | Search Spotify catalog (`?q=query`) |
| `GET` | `/api/spotify/track/:spotify_id` | Fetch Spotify track metadata |
| `POST` | `/api/spotify/import` | Import a Spotify URL (creates download job) |

---

### `/api/analysis`

Audio feature analysis.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/analysis/:track_id` | Fetch stored analysis features for a track |
| `POST` | `/api/analysis/analyze` | Trigger analysis for a track (rate-limited: `api_heavy`) |

---

### `/api/agents`

AI agent invocation and conversation history.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/agents/conversations` | List agent conversation threads |
| `GET` | `/api/agents/conversations/:id` | Fetch a conversation thread |
| `POST` | `/api/agents/chat` | Send a message to the AI agent Orchestrator |

---

### `/api/admin`

Administration endpoints. Requires `admin` role or higher.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/admin/users` | List all users with roles |
| `PATCH` | `/api/admin/users/:id` | Update user role or status |
| `GET` | `/api/admin/llm/health` | LLM provider health status |
| `GET` | `/api/admin/jobs` | System-wide job queue overview |

---

## Rate Limits

| Pipeline | Limit | Window | Applies To |
|----------|-------|--------|-----------|
| `api_auth` | 60 requests | 60 seconds | All `/api` routes |
| `api_heavy` | 10 requests | 60 seconds | `POST /api/spotify/import`, `POST /api/analysis/analyze`, stem separation endpoints |

Rate limit headers are returned on every response:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 58
X-RateLimit-Reset: 1708900000
```

When the limit is exceeded the server returns `429 Too Many Requests`:

```json
{"error": "rate limit exceeded", "code": "RATE_LIMITED", "retry_after": 42}
```

---

## WebSocket

### LiveView Socket

Phoenix LiveView connects over:

```
ws://localhost:4000/live/websocket
```

The LiveView socket is used exclusively by the browser for server-rendered component updates. It is not intended for external programmatic access.

### User Socket

The user-facing Phoenix Channel socket connects at:

```
ws://localhost:4000/socket/websocket
```

After connecting, clients join topic channels to receive real-time events. See [WebSocket Channels](websocket.md) for channel topics and message schemas.

---

## Response Format

All REST endpoints return JSON. The envelope is consistent across all routes.

**Success:**

```json
{"data": {...}}
```

**Paginated list:**

```json
{
  "data": [...],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total_count": 143,
    "total_pages": 8
  }
}
```

**Error:**

```json
{"error": "human-readable description", "code": "ERROR_CODE"}
```

**Validation error (422):**

```json
{
  "error": "validation failed",
  "code": "VALIDATION_ERROR",
  "details": {"field_name": ["can't be blank"]}
}
```

---

## HTTP Status Codes

| Code | Meaning |
|------|---------|
| `200` | Success |
| `201` | Created |
| `204` | No content (DELETE success) |
| `400` | Bad request — malformed input |
| `401` | Unauthorized — missing or invalid token |
| `403` | Forbidden — insufficient role |
| `404` | Not found |
| `422` | Unprocessable entity — validation failure |
| `429` | Too many requests — rate limit exceeded |
| `500` | Internal server error |

---

## Sections

- [REST Endpoints](rest.md)
- [WebSocket Channels](websocket.md)

---

## See Also

- [Architecture Overview](../architecture/index.md)
- [Configuration: API keys](../guides/configuration.md)
- [Features: AI Agents](../features/ai-agents.md)

---

[Next: REST Endpoints →](rest.md)
