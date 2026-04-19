# MCP Server & Client in Spring AI
### Verified, Runnable Solution · exesolution.com

> **Stack:** Java 17 · Spring Boot 3.3.x · Spring AI 1.0.x · MCP Java SDK · Docker Compose  
> **Status:** Verified · v1.0.0

---

## What This Solution Does

Two independently deployable Spring Boot services demonstrating the Model Context Protocol (MCP) in a production-representative setup:

| Service | Port | Role |
|---|---|---|
| `mcp-tool-server` | 8080 | MCP Server — exposes 6 tools via `@McpTool` over Streamable HTTP |
| `ai-chat-service` | 8081 | AI Host — ChatClient + MCP Client, user-facing REST API |

**Tools registered on the server:**

| Tool | Description |
|---|---|
| `getOrderStatus` | Look up a single order by ID |
| `getOrderHistory` | List all orders for a customer |
| `searchProducts` | Keyword search across product catalog |
| `checkInventory` | Real-time stock level for a SKU |
| `getWeather` | Current weather by GPS coordinates (live, open-meteo.com) |
| `getCityWeather` | Current weather by city name (10 major cities) |

---

## Prerequisites

- **Docker Desktop** (or Docker Engine + Compose v2)
- **JDK 17** — only needed for running tests locally
- **OpenAI API key** — set in `.env` (see below)
- **Available ports:** 8080 and 8081

---

## Quick Start

```bash
# 1. Clone and enter the directory
git clone <repo-url>
cd mcp-solution

# 2. Create your .env file
cp .env.template .env
# Edit .env and set: OPENAI_API_KEY=sk-your-key-here

# 3. Start both services
docker compose up -d --build

# 4. Wait ~30s for startup, then verify
curl -s http://localhost:8080/actuator/health | jq .
curl -s http://localhost:8081/actuator/health | jq .
```

---

## Verification Steps (Evidence Pack)

Run these in order to generate all evidence artifacts.

### Step 1 — Both services healthy

```bash
curl -s http://localhost:8080/actuator/health | jq .
# Expected: {"status":"UP", ...}

curl -s http://localhost:8081/actuator/health | jq .
# Expected: {"status":"UP", ...}
```

### Step 2 — MCP tools registered (server-side)

```bash
curl -s -u admin:admin-secret http://localhost:8080/admin/tools | jq .
```

Expected response — 6 tools with names, descriptions, and auto-generated input schemas:
```json
{
  "toolCount": 6,
  "tools": [
    { "name": "getOrderStatus",  "description": "Get the current status...", "inputSchema": "..." },
    { "name": "getOrderHistory", "description": "Get the recent order history...", "inputSchema": "..." },
    { "name": "searchProducts",  "description": "Search the product catalog...", "inputSchema": "..." },
    { "name": "checkInventory",  "description": "Check the current inventory...", "inputSchema": "..." },
    { "name": "getWeather",      "description": "Get current weather conditions...", "inputSchema": "..." },
    { "name": "getCityWeather",  "description": "Get current weather for a major city...", "inputSchema": "..." }
  ]
}
```

### Step 3 — Tool call: order status lookup

```bash
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-001", "message": "What is the status of order ORD-1001?"}' \
  | jq .
```

Expected: The LLM calls `getOrderStatus("ORD-1001")` and returns status + estimated delivery.

```json
{
  "sessionId": "sess-001",
  "reply": "Order ORD-1001 is currently SHIPPED. It contains 2 items (Laptop Stand, USB-C Hub) with an estimated delivery date of 2026-04-20. The total amount is $89.99.",
  "model": "gpt-4o-mini",
  "durationMs": 1843,
  "timestamp": "2026-04-18T10:00:00Z"
}
```

### Step 4 — Tool call: live weather (verifiable external data)

```bash
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-001", "message": "What is the weather like in Tokyo right now?"}' \
  | jq .
```

Expected: The LLM calls `getCityWeather("Tokyo")` which makes a real HTTP request to `open-meteo.com`. The temperature in the response is **live data**, making this verifiably real.

### Step 5 — Multi-turn conversation memory

```bash
# Turn 1: ask about an order
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-mem-01", "message": "Check order ORD-1002 for me"}' \
  | jq .reply

# Turn 2: follow-up in same session (LLM has context from turn 1)
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-mem-01", "message": "What items are in that order?"}' \
  | jq .reply
# Expected: LLM recalls ORD-1002 from context and answers without re-calling the tool
```

### Step 6 — Conversation history

```bash
curl -s -u user:user-secret \
  http://localhost:8081/api/chat/sess-mem-01/history \
  | jq .
```

Expected: 4 turns — 2 USER + 2 ASSISTANT — confirming history is persisted correctly.

### Step 7 — Product search tool

```bash
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-002", "message": "Search for ergonomic products and tell me which ones are in stock"}' \
  | jq .
```

Expected: LLM calls `searchProducts("ergonomic", "")`, filters by `inStock: true`, and returns a formatted list.

### Step 8 — Out-of-stock detection

```bash
curl -s -u user:user-secret -X POST http://localhost:8081/api/chat \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "sess-002", "message": "Is the ergonomic mouse (SKU-006) available?"}' \
  | jq .
```

Expected: LLM calls `checkInventory("SKU-006")` which returns `OUT_OF_STOCK`. LLM communicates this to the user.

### Step 9 — Verify MCP tool calls in server logs

```bash
docker compose logs mcp-tool-server | grep "\[MCP\]"
```

Expected output — one log line per tool invocation:
```
[MCP] getOrderStatus called: orderId=ORD-1001
[MCP] getOrderStatus: found orderId=ORD-1001 status=SHIPPED
[MCP] getCityWeather called: city='Tokyo'
[MCP] getWeather called: lat=35.6762 lon=139.6503
[MCP] getWeather: lat=35.6762 lon=139.6503 temp=22.4°C wind=14.2km/h condition=Partly cloudy
[MCP] searchProducts called: keyword='ergonomic' category=''
[MCP] checkInventory called: sku=SKU-006
[MCP] checkInventory: sku=SKU-006 qty=0 status=OUT_OF_STOCK
```

### Step 10 — Tool refresh (dynamic discovery demo)

```bash
curl -s -u admin:admin-secret -X POST \
  http://localhost:8080/admin/tools/refresh \
  | jq .
```

Expected:
```json
{
  "status": "refreshed",
  "toolCount": 6,
  "registered": ["getOrderStatus", "getOrderHistory", "searchProducts",
                  "checkInventory", "getWeather", "getCityWeather"],
  "timestamp": "2026-04-18T10:05:00Z"
}
```

---

## Running Tests Locally

```bash
# Run mcp-tool-server tests (no external dependencies required)
cd mcp-tool-server
./mvnw test

# Run ai-chat-service tests (uses mock ChatClient, no LLM call)
cd ../ai-chat-service
./mvnw test
```

---

## Project Structure

```
mcp-solution/
├── docker-compose.yml
├── .env.template                    ← copy to .env, add OPENAI_API_KEY
├── pom.xml                          ← parent POM (dependency management)
│
├── mcp-tool-server/                 ← MCP Server module
│   ├── Dockerfile
│   ├── pom.xml
│   └── src/main/java/.../
│       ├── McpToolServerApplication.java
│       ├── tools/
│       │   ├── OrderTool.java       ← @Tool: getOrderStatus, getOrderHistory
│       │   ├── ProductTool.java     ← @Tool: searchProducts, checkInventory
│       │   └── WeatherTool.java     ← @Tool: getWeather, getCityWeather (live API)
│       ├── config/
│       │   └── SecurityConfig.java  ← /mcp open, /admin requires ADMIN role
│       └── admin/
│           └── AdminToolController.java  ← GET /admin/tools, POST /admin/tools/refresh
│
└── ai-chat-service/                 ← AI Host module
    ├── Dockerfile
    ├── pom.xml
    └── src/main/java/.../
        ├── AiChatServiceApplication.java
        ├── config/
        │   ├── ChatConfig.java      ← wires ChatClient + MCP ToolCallbackProvider
        │   └── SecurityConfig.java  ← /api/chat requires USER role
        ├── service/
        │   ├── ChatService.java     ← orchestrates ChatClient + conversation history
        │   └── ConversationStore.java  ← in-memory session store (replace with Redis)
        └── api/
            └── ChatController.java  ← POST /api/chat, GET /api/chat/{id}/history
```

---

## Configuration Reference

### mcp-tool-server

| Property | Default | Description |
|---|---|---|
| `server.port` | 8080 | HTTP port |
| `spring.ai.mcp.server.protocol` | `STREAMABLE` | Transport: `STREAMABLE`, `STATELESS`, `SSE`, `STDIO` |
| `spring.ai.mcp.server.name` | `exesolution-tool-server` | Server identifier sent during MCP handshake |

### ai-chat-service

| Property / Env Var | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | — | **Required.** OpenAI API key |
| `MCP_SERVER_URL` | `http://localhost:8080` | Base URL of the MCP Tool Server |
| `spring.ai.openai.chat.options.model` | `gpt-4o-mini` | LLM model |
| `spring.ai.mcp.client.connections.tool-server.transport` | `STREAMABLE_HTTP` | MCP transport type |

---

## Known Limitations

See the full Solution article for the complete Known Limitations section. Brief summary:

- **In-memory conversation history** — does not survive restarts. Replace `ConversationStore` with Spring AI's `JdbcChatMemory` for production.
- **No MCP-level auth on `/mcp`** — the endpoint is network-internal only. Add `X-MCP-Api-Key` header validation for zero-trust environments.
- **Single MCP server** — to connect multiple MCP servers, register multiple `SyncMcpClient` beans and compose their providers.
- **Spring AI 1.0.x** — stable release. Spring AI 1.1.x (milestone) adds `@McpTool` annotation support and MCP Java SDK 0.13.x. Upgrade path is straightforward.

---

## Stopping the Stack

```bash
docker compose down

# Remove volumes and images for a clean slate
docker compose down --volumes --rmi local
```

---

*Part of the [Executable Solution](https://exesolution.com) verified solution library.*
