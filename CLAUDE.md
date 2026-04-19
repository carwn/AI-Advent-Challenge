# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by multiple LLM providers (OpenAI, Anthropic, Google Gemini via ProxyAPI.ru, and local Ollama). Users can create multiple named conversations, each tied to one of 12 specialized agents, switch between 16 models (10 cloud + 6 local Ollama), and agents can call tools (weather, calculator, search, Tavily MCP) as part of their responses. Conversations can be branched, creating a tree of forked chats. Thinking/reasoning models stream their reasoning process live as a collapsible 🤔 block.

## Build & Run

This is a standard Xcode project with no external package manager (no SPM packages, no Podfile).

- **Build/Run**: Open `AI Advent Challenge.xcodeproj` in Xcode and run on a simulator or device.
- **New files**: The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — Swift source files and plain resources are automatically included. **Exception**: `.mlpackage` bundles require an explicit `PBXFileReference` + `PBXBuildFile` entry in `project.pbxproj` and an `explicitFileReferences` key in the sync root group, because the build system needs to trigger `CoreMLModelCompile` for them.
- **API Key**: The app requires a ProxyAPI.ru key entered via the in-app Settings screen; it is stored in Keychain under service name `com.aiapp.openai`. A single key is used for all providers (OpenAI, Anthropic, Gemini).

## Running Tests

The project has an integration test target **AI Advent Challenge Tests** (`ProviderIntegrationTests.swift`) that sends "Привет" to each provider and verifies a non-empty response.

**Run via xcodebuild (preferred for Claude Code):**

```bash
xcodebuild test \
  -project "AI Advent Challenge.xcodeproj" \
  -scheme "AI Advent Challenge" \
  -destination "platform=iOS Simulator,id=FE23BF87-929B-442B-A282-75EA7997265A" \
  -testPlan "AI Advent Challenge"
```

Simulator ID `FE23BF87-929B-442B-A282-75EA7997265A` = **iPhone 17, iOS 26.2**. If it becomes unavailable, find a replacement with:

```bash
xcodebuild -project "AI Advent Challenge.xcodeproj" -scheme "AI Advent Challenge" -showdestinations 2>&1 | grep "iOS Simulator"
```

**API key**: Tests read the key from `AI Advent Challenge Tests/Secrets.txt` (gitignored). The file contains the raw key on a single line. As a fallback, the env var `TEST_API_KEY` is also checked. If neither is present, tests are skipped (`XCTSkip`), not failed.

## CI/CD

GitHub Actions workflow at `.github/workflows/ai-review.yml` runs on every pull request (opened, synchronize, reopened):

1. Gets the PR diff (`git diff origin/<base>...HEAD`)
2. Clones the `carwn/dev-assistant` repo, builds it with Swift, runs the `--review` command against the diff
3. Posts the AI review result as a PR comment via `gh pr comment`

Requires `PROXYAPI_KEY` GitHub Actions secret. The workflow uses `macos-latest` and caches the Hugging Face MiniLM model to speed up subsequent runs.

## Architecture

The project follows **Clean Architecture** with these layers (all under `AI Advent Challenge/`):

```
Domain/
  Models/        — Message, Conversation, ConversationRecord, AgentResponse,
                   ToolDefinition, LLMMessage, LLMResponse
  Protocols/     — Agent, LLMProvider, ToolExecutor, ContextCompressionPolicy
  Agents/        — BaseAgent (base class), 12 concrete agent classes
    Compression/ — SummaryContextCompressionPolicy,
                   SlidingWindowContextCompressionPolicy,
                   StickyFactsCompressionPolicy,
                   TripleMemoryCompressionPolicy,
                   KeyValueMemoryExtractor (shared LLM key-value extraction),
                   LongTermMemoryStore (ObservableObject, shared per-agent-type)
  UseCases/      — SendMessageToLMMUseCase (protocol), SendMessageToLMMInteractor,
                   BranchConversationUseCase

Data/
  Providers/
    OpenAI/      — OpenAIProvider (implements LLMProvider), OpenAIModels
    Anthropic/   — AnthropicProvider, AnthropicModels
    Gemini/      — GeminiProvider, GeminiModels
    ProviderFactory.swift  — ProviderType enum (16 models: 10 cloud + 6 local) + pricing in RUB
    Ollama/        — OllamaProvider, OllamaModels (local models via localhost:11434)

Infrastructure/
  Network/       — NetworkClient (URLSession-based + SSE streamLines()), APIEndpoint, HTTPMethod,
                   NetworkError, NetworkLogger (protocol), OSNetworkLogger,
                   MCPClient (JSON-RPC 2.0 MCP client, Streamable HTTP + SSE),
                   MCPModels (DTOs: JSONRPCRequest, MCPTool, AnyCodableValue, etc.)
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService
  Persistence/   — ConversationPersistenceService (save/load/delete Conversation JSON by UUID)
  RAG/           — RAGService (façade), EmbeddingService (protocol), VectorIndex (~8400 chunks),
                   BertTokenizer, chunks.json, vocab.txt, BAAI_bge-small-en-v1.5.mlpackage

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow,
                   AppIconView (1024×1024 icon preview for Xcode Canvas)
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel,
                   MessageHistoryStore, ModelStore (@MainActor)

App/
  AI_Advent_ChallengeApp.swift  — App entry point (@main)
  DependencyContainer.swift     — Manual DI root, @MainActor ObservableObject
```

## Agent Protocol

Defined in `Domain/Protocols/Agent.swift`. Requires `AnyObject` (class-only) so that `conversation` can be read through an existential `any Agent`.

```swift
protocol Agent: AnyObject {
    var name: String { get }
    var icon: String { get }              // SF Symbol name
    var description: String { get }
    var conversation: Conversation { get }
    var compressionPolicy: (any ContextCompressionPolicy)? { get }
    func send(_ text: String) async throws
    func clearConversation()
}
```

## BaseAgent

`Domain/Agents/BaseAgent.swift` — base class for all agents. Holds shared dependencies and provides implementations of `send(_:)` and `clearConversation()`.

**Stored properties** (initialized via `super.init`):
- `sendMessage: any SendMessageToLMMUseCase`
- `persistence: ConversationPersistenceService`
- `compressionPolicy: (any ContextCompressionPolicy)?` — optional
- `conversation: Conversation` — loaded from persistence or built from systemPrompt
- `systemPrompt: String` — passed from subclass
- `conversationId: UUID` — identifies the persisted file; passed from `DependencyContainer`

**Overridable computed properties** (defaults in `BaseAgent`):
- `var temperature: Double { 0.7 }`
- `var maxTokens: Int { 1000 }`
- `var stopWords: [String]? { nil }`
- `var availableTools: [ToolDefinition] { [] }`

**Abstract** (subclass must override, otherwise `fatalError`):
- `var name: String`, `var icon: String`, `var description: String`

**`send(_:)`** implements the full cycle with compression policy support: compresses context via `compressionPolicy?.compress(conversation)`, then branches:
- If `sendMessage.supportsStreaming && availableTools.isEmpty` → **streaming path** via `sendWithStreaming(text:apiConv:summaryUsage:compressionDetails:)`: adds user message, optional compression summaryUsage, then iterates `StreamEvent`s — showing 🤔 thinking block and assistant message live, finalises with metadata on `.completed`.
- Otherwise → **non-streaming path**: calls `sendMessage.execute(...)`, appends new messages, adds summaryUsage if needed.

**`streamThinkingAndGetResponse(systemPrompt:userMessage:temperature:maxTokens:stopWords:)`** — helper for agents with custom `send()` (MCPAgent, RAGAgent). Streams thinking chunks into conversation as a 🤔 summaryUsage block, accumulates content, and returns the full `AgentResponse`. Falls back to `execute(systemPrompt:userMessage:...)` if provider doesn't support streaming.

**`clearConversation()`** resets `conversation` to the initial systemPrompt, calls `compressionPolicy?.reset()`, and deletes the persistence file.

## Concrete Agents

Each agent is a `final class` in `Domain/Agents/`, inheriting from `BaseAgent`. Only properties differing from defaults need to be overridden.

| Class | Name | Icon | temperature | maxTokens | availableTools | Compression Policy |
|---|---|---|---|---|---|---|
| `GeneralAgent` | Универсальный ассистент | brain | — | — | — | None |
| `WeatherAgent` | Агент погоды | cloud.sun | — | **500** | **get_weather** | None |
| `WeatherJSONAgent` | Агент погоды (JSON) | cloud.sun.fill | — | **500** | **get_weather** | None |
| `ContextManagedAgent` | Агент с памятью | memorychip | — | — | — | SummaryContextCompressionPolicy |
| `SlidingWindowAgent` | Агент скользящего окна | rectangle.3.offgrid | — | — | — | SlidingWindowContextCompressionPolicy (window=5) |
| `StickyFactsAgent` | Агент с фактами | tag.fill | — | — | — | StickyFactsCompressionPolicy (window=5) |
| `TripleMemoryAgent` | Агент с тройной памятью | brain.filled.head.profile | — | — | — | TripleMemoryCompressionPolicy (window=5) |
| `UserProfileAgent` | Профайлер | person.text.rectangle.fill | **0.2** | **500** | — | None |
| `TaskStateMachineAgent` | Менеджер задач | checklist | — | — | — | None |
| `SolverAgent` | Автономный решатель | cpu | — | — | — | None |
| `MCPAgent` | MCP агент | network | **0.2** (dispatch) | **500** (dispatch) | — | None |
| `RAGAgent` | SwiftUI Docs | book.pages | — | **1500** | — | None |

_(— means BaseAgent default: temperature 0.7, maxTokens 1000, stopWords nil, availableTools [])_

`WeatherJSONAgent` has a detailed system prompt requiring JSON-only output with specific fields (location, temperature, condition, humidity, summary).

`UserProfileAgent` implements a three-phase profiling cycle: (1) **profiling** — asks 5 questions (response style, format, constraints, expertise, language), validating each answer via LLM; (2) **editing** — detects intent to edit the profile and re-enters profiling; (3) **chat** — normal conversation using the collected profile. Profile state is persisted to `AgentState/<conversationId>_profile.json`. On completion, the profile is saved to the shared `LongTermMemoryStore` of `TripleMemoryAgent` so it can be used by that agent.

`MCPAgent` connects to multiple MCP servers simultaneously: **Tavily** (`https://mcp.tavily.com/mcp/?tavilyApiKey=KEY`, requires Tavily API key) and **Carwn** (`https://carwn-carwnmcp-39c3.twc1.net/mcp`, no auth). Both use Streamable HTTP transport (POST /mcp). Uses a **two-step LLM dispatch scheme**: (1) LLM receives a list of all MCP tools (prefixed with server label) + last 5 conversation messages and returns JSON `{"action":"list"|"call"|"chat"|"schedule"|"cancel_task"|"cancel_all_tasks"|"list_tasks", ...}`; (2) agent routes the tool call to the correct server via `toolRegistry`, shows `⚙️ summaryUsage` messages for request/response, then calls LLM again with (user question + MCP result) to produce a natural-language answer. Tavily API key stored in Keychain (`com.aiapp.tavily`), managed via Settings → «MCP серверы». JSON parsing uses balanced-brace extraction + fallback for non-standard `action` values.

**Scheduled tasks**: `MCPAgent` supports periodic background tasks. `ScheduledTask` (Codable, Identifiable) stores `id`, `description`, `intervalSeconds` (≥10), `createdAt`. Active tasks run as unstructured Swift `Task` objects stored in `timerTasks: [UUID: Task<Void, Never>]`. On each tick, `executeTimerFire` calls the LLM dispatch cycle and appends results prefixed with "⏱". `backgroundMessagePublisher: AnyPublisher<Void, Never>` (Combine `PassthroughSubject`) fires after each tick — `ChatViewModel` subscribes and refreshes `messages` without user interaction. Tasks are persisted to `AgentState/<conversationId>_mcp_tasks.json` and restored on init. `clearConversation()` cancels all tasks and deletes the persistence file. MCP call logic is factored into `executeCallAction(toolName:args:originalText:allEntries:)` (used by `executeTimerFire`) and `executeMCPCall(toolName:args:)` (used by the agentic loop in `send()`).

**Agentic loop (ReAct pattern)**: `send(_:)` runs a `while` loop (up to `maxIterations = 5`). On each iteration the LLM dispatcher returns a JSON action. If `action == "call"` — the agent calls `executeMCPCall`, appends the raw result to `iterationContext`, and loops again. If `action == "chat"` — the final reply is appended and the loop exits. Non-loop actions (`list`, `schedule`, `cancel_task`, etc.) exit immediately. If `maxIterations` is reached without `"chat"`, a final LLM call summarises all accumulated results. `buildDispatchMessage(currentText:mcpContext:)` injects `iterationContext` into the dispatch prompt on subsequent iterations.

`SolverAgent` is an autonomous task solver that executes tasks through a chain of LLM calls. Phases: `awaitingTask → clarifying → gatheringAnswers → analyzing → confirmingPlan → executing → validating → done`. On confirm, it autonomously executes all steps in one `send()` call, showing internal LLM calls as `.summaryUsage` messages with "⚙️" prefix. Validates results and retries from a failed step (up to 3 global failures). Invariants persisted to `AgentState/<conversationId>_solver_invariants.json` (not deleted on `clearConversation()`). State persisted to `AgentState/<conversationId>_solver_state.json`.

`TaskStateMachineAgent` is a finite state machine that manages user tasks through five phases: `idle → planning → execution → validation → done`. It decomposes tasks into steps via LLM, guides the user step-by-step, supports pause/resume without repeating the full plan, and auto-validates results after the last step. State machine uses `TaskTransition` enum with `canApply()` / `apply()` guards; all mutations immediately call `saveTaskState()`. Phase state is persisted to `AgentState/<conversationId>_task_state.json`. Supports plan revision during planning and re-planning during execution.

Supports **invariants** — user-defined constraints enforced across all phases. Invariants are stored in `AgentState/<conversationId>_invariants.json` (not deleted on `clearConversation()`). Commands (any phase): `инвариант: <rule>` adds, `инварианты` lists, `удалить инвариант N` removes, `очистить инварианты` clears all. On `idle` phase: a new task is checked against invariants via LLM before decomposition; conflicting tasks are blocked with an explanation. Invariants are also injected into the `decomposeTask()` system prompt so generated steps comply with them.

`RAGAgent` answers questions about SwiftUI API using a built-in knowledge base (~8400 chunks from Apple docs). LLM is called via `sendMessage.execute(systemPrompt:userMessage:...)` with a composed `userMessage` containing: (1) last 3 user+assistant pairs as conversation history (`historyWindowSize=3`), (2) RAG context chunks, (3) current question — enabling coherent multi-turn dialogue. Uses `CoreMLEmbeddingService` with BAAI/bge-small-en-v1.5 (offline, Neural Engine). Resources live in `Infrastructure/RAG/`: `chunks.json` and `vocab.txt` (auto-included by sync group), `BAAI_bge-small-en-v1.5.mlpackage` (explicit PBXFileReference, compiled to `.mlmodelc`). System prompt enforces a structured response template (`## Ответ` / `## Цитаты` / `## Источники`) with mandatory in-text citations `[1]`, `[2]`, `[3]` — LLM must answer strictly from provided context. **Anti-hallucination**: if `ragMode != .off` and `maxScore < noKnowledgeThreshold` (0.60) — `send()` returns a pre-built "не знаю" message without an LLM call. Stores `agentSystemPrompt` and `agentConversationId` as private properties for direct use in `send()`.

**RAG modes** (`RAGMode` enum in `Domain/Agents/RAGMode.swift`, `Codable & CaseIterable`):
- `.off` — RAG отключён, plain LLM call
- `.basic` — top-3, minScore=0.25, cosine similarity (legacy behavior)
- `.rerank` — top-10 candidates → MMR diversification → top-3 (minFinalScore=0.35, lambda=0.7)
- `.rewrite` — LLM rewrites query to English (`temperature=0.1, maxTokens=100`) using conversation history to resolve coreferences → basic search
- `.full` — rewrite (with history) + rerank together

**RAG mode switching**: toolbar button opens `.confirmationDialog` showing all 5 modes. Text commands: `rag on`/`rag basic`/`rag реранк`/`rag rerank`/`rag rewrite`/`rag перефраз`/`rag full`/`rag полный`/`rag off`/`rag выкл` (plus `/` prefix variants). Backward compat: `rag on` → `.basic`. `ChatViewModel` exposes `@Published var ragMode: RAGMode` and computed `ragEnabled: Bool { ragMode != .off }`. Icon colors: off=.secondary, basic=.blue, rerank=.orange, rewrite=.green, full=.purple.

## SendMessageUseCase

`Domain/UseCases/SendMessageToLMMUseCase.swift` — use case encapsulating the full LLM request cycle.

**Protocol** `SendMessageToLMMUseCase` — методы:
```swift
protocol SendMessageToLMMUseCase {
    var supportsStreaming: Bool { get }
    // Full cycle with Conversation; returns updated Conversation
    func execute(userText:conversation:tools:temperature:maxTokens:stopWords:) async throws -> Conversation
    // Simplified call without Conversation; returns AgentResponse
    func execute(systemPrompt:userMessage:tools:temperature:maxTokens:stopWords:) async throws -> AgentResponse
    // Streaming (Conversation-based) — yields thinkingChunk / contentChunk / completed
    func executeStreaming(userText:conversation:tools:temperature:maxTokens:stopWords:) -> AsyncThrowingStream<StreamEvent, Error>
    // Streaming (systemPrompt+userMessage) — для агентов с кастомным send()
    func executeStreaming(systemPrompt:userMessage:temperature:maxTokens:stopWords:) -> AsyncThrowingStream<StreamEvent, Error>
}
```

`StreamEvent` enum: `.thinkingChunk(String)`, `.contentChunk(String)`, `.completed(response: AgentResponse, elapsed: TimeInterval)`.

**Class** `SendMessageToLMMInteractor: SendMessageToLMMUseCase` takes `LLMProvider` and `ToolExecutor` in `init`. `execute(...)` receives only the variable request data:

1. Appends the user message to a local copy of `conversation`
2. Calls `provider.complete(...)` with `max(maxTokens, provider.minMaxTokens)`
3. If the response requires tool execution: appends a tool-call message, executes each tool via `ToolExecutor`, appends tool-result messages, calls `provider.complete(...)` again
4. Builds the final `Message` with `responseTime`, `modelName`, and token counts from `usage`
5. Returns the updated `Conversation`

`DependencyContainer` creates one `SendMessageToLMMInteractor` instance and shares it across all agents for the current model. `BaseAgent` holds `any SendMessageToLMMUseCase` — the protocol allows swapping implementations (e.g. mocks in tests).

## LLM Providers & Models

Most requests go through **ProxyAPI.ru** with a single API key. Ollama runs locally on `localhost:11434`. Defined in the `ProviderType` enum with pricing in RUB per 1M tokens:

| Model | Input (₽/1M) | Output (₽/1M) | Notes |
|-------|-------------|--------------|-------|
| gpt-3.5-turbo | 129 | 387 | Default on first launch |
| gpt-4.1-nano | 26 | 104 | |
| gpt-4.1-mini | 104 | 413 | |
| gpt-4.1 | 516 | 2 062 | |
| claude-haiku-4-5 | 295 | 1 474 | |
| claude-sonnet-4-5 | 774 | 3 866 | |
| claude-opus-4-5 | 1 516 | 7 579 | |
| gemini-2.5-flash-lite | 26 | 129 | minMaxTokens=0 |
| gemini-2.5-flash | 78 | 645 | minMaxTokens=8000 |
| gemini-2.5-pro | 323 | 2 577 | minMaxTokens=8000 |
| qwen3.5:4b (Ollama) | 0 | 0 | local, supportsStreaming=true, no max_tokens |
| qwen3.5:4b-high-temp (Ollama) | 0 | 0 | overrideTemperature=1.5 |
| qwen3.5:4b-q8 (Ollama) | 0 | 0 | Q8_0 quantization, higher quality |
| qwen3.5:4b-pirate (Ollama) | 0 | 0 | systemPromptOverride — пиратский стиль |
| qwen3.5:4b (Win PC) | 0 | 0 | remote Ollama on 192.168.1.141, host param |
| qwen3:14b (Win PC) | 0 | 0 | remote Ollama on 192.168.1.141, 14B model |

Selected model is persisted to `UserDefaults` (`selectedProvider`) via `ModelStore`.

## Multi-Conversation & Branching

The app supports multiple named conversations, each identified by a `UUID`. Conversations are tracked via `ConversationRecord` objects stored in an index file.

**`ConversationRecord`** — metadata stored in `AgentState/conversations_index.json`:
```swift
struct ConversationRecord: Identifiable, Codable {
    let id: UUID           // primary key for persistence
    let agentKey: String   // e.g. "general_agent"
    let agentName: String
    let agentIcon: String
    var title: String      // set from first user message
    var lastMessagePreview: String?
    var lastMessageDate: Date?
    let createdAt: Date
    var parentId: UUID?    // nil = root; set when branching
}
```

**`BranchConversationUseCase`** (`Domain/UseCases/`) creates a branched conversation from an existing one: copies the conversation data and any compression policy caches, assigns a new `UUID`, sets `parentId`, and prefixes the title with "↳".

**`DependencyContainer`** key methods:
- `agentTemplates: [AgentTemplate]` — returns the 12 available agent templates
- `createConversation(agentKey:)` — creates a new `ConversationRecord` and saves it to the index
- `makeAgent(record: ConversationRecord)` — instantiates an agent with the given conversation ID
- `makeChatViewModel(agent:)` — wraps an agent in a `ChatViewModel`
- `makeAgentSelectionViewModel()` — for the agent selection UI
- `makeSettingsViewModel()` — for the settings UI
- `longTermMemoryStore` — shared `LongTermMemoryStore` instance for `TripleMemoryAgent`

## Persistence

**Conversation data** — `Application Support/AgentState/<conversationId>.json`
- Loaded during `BaseAgent.init` (restores state across launches)
- Saved after each successful `send()`
- Deleted by `clearConversation()`

**Compression policy caches** (keyed by `conversationId`):
- Summary: `AgentState/<conversationId>_summary.json` (text + messageCount)
- Facts: `AgentState/<conversationId>_facts.json` (key-value dict + messageCount)
- Working memory: `AgentState/<conversationId>_working.json` (key-value dict + messageCount)
- Profile: `AgentState/<conversationId>_profile.json` (UserProfileAgent profiling state)
- All files are copied when branching a conversation

**Long-term memory** — `AgentState/long_term_memory_triple_memory_agent.txt`
- Free-form text edited by the user in Settings → «Долговременная память»
- Shared across all conversations of `TripleMemoryAgent`; never reset by `clearConversation()`

**Conversation index** — `AgentState/conversations_index.json`
- Array of `ConversationRecord`; updated after each message (title, preview, date)

**Model selection** — `UserDefaults` key `"selectedProvider"`; managed by `ModelStore`.

**Message history** — `UserDefaults` key `"messageHistory"`; last 10 sent messages via `MessageHistoryStore`.

## Context Compression Policies

Defined in `Domain/Protocols/ContextCompressionPolicy.swift` as a class-only protocol:

```swift
protocol ContextCompressionPolicy: AnyObject {
    var description: String { get }
    func compress(_ conversation: Conversation) async -> (
        apiConversation: Conversation,
        summaryUsage: UsageInfo?,
        details: String?
    )
    func reset()
}
```

`compress(_:)` receives the agent's full conversation, returns a compressed context for the LLM, optional `UsageInfo` for tokens spent on compression, and an optional `details` string for UI display. The agent creates a `.summaryUsage` message from `UsageInfo` and appends it to its own `conversation`. `reset()` is called by the agent in `clearConversation()`.

### SummaryContextCompressionPolicy

`Domain/Agents/SummaryContextCompressionPolicy.swift` — summary-based compression.

Takes `sendMessage: any SendMessageToLMMUseCase` for its own LLM calls, `summaryTriggerTokens` (default 500), and `conversationId`. On `compress(_:)`:
1. Checks `promptTokens` of the last assistant message; if over the threshold — calls LLM to generate/update a summary of uncompressed messages.
2. Builds API context: system + summary pseudo-turn (`user`/`assistant`) + remaining messages.
3. Returns compressed conversation and `UsageInfo` (or `nil` if no summary was generated).

Summary state (`text` + `messageCount`) persisted to `AgentState/<conversationId>_summary.json`.

### SlidingWindowContextCompressionPolicy

`Domain/Agents/SlidingWindowContextCompressionPolicy.swift` — keeps only the last N non-system messages in the API context. Default window size: 5. Stateless — no persistence. `details` reports "история: последние X сообщений, отброшено Y" when messages are dropped.

### KeyValueMemoryExtractor

`Domain/Agents/KeyValueMemoryExtractor.swift` — shared helper encapsulating the full LLM key-value extraction cycle. Used by both `StickyFactsCompressionPolicy` and `TripleMemoryCompressionPolicy`. Calls LLM with existing entries + new dialog text, merges flat JSON result into `entries`. Parameter `useLargerValueMerge`: `true` keeps longer value (StickyFacts), `false` always replaces (WorkingMemory). Persists state to `AgentState/<persistenceKey>.json`.

### StickyFactsCompressionPolicy

`Domain/Agents/StickyFactsCompressionPolicy.swift` — extracts key-value facts (goals, preferences, decisions, constraints) via LLM and injects them into every API call.

Takes `sendMessage`, window size (default 5 messages), and `persistenceKey`. Internally uses `KeyValueMemoryExtractor` with `useLargerValueMerge: true`. On `compress(_:)`:
1. Calls `extractor.update(from:)` if new messages exist.
2. Builds API context: system + facts pseudo-turn (`user`/`assistant`) + last N messages.

Facts state persisted to `AgentState/<conversationId>_facts.json`.

### TripleMemoryCompressionPolicy

`Domain/Agents/TripleMemoryCompressionPolicy.swift` — combines three memory tiers in a single policy.

```
API context sent to LLM:
[system: agent system prompt + "\n\nДолговременная память:\n{free-form text}"]  ← long-term embedded in system prompt
[user:  "Рабочая память:\n{- key: value ...}"]        ← only if non-empty
[assistant: "Принял к сведению."]
[last windowSize messages]                             ← short-term
```

- **Short-term** — sliding window of last N messages (default 5)
- **Working** — `KeyValueMemoryExtractor` with `useLargerValueMerge: false`; task-focused key-value pairs extracted every round; persisted to `AgentState/<conversationId>_working.json`
- **Long-term** — `LongTermMemoryStore`; free-form text managed by user in Settings; shared across all conversations of this agent

`reset()` clears only working memory; long-term memory is user-managed and persists.

### LongTermMemoryStore

`Domain/Agents/LongTermMemoryStore.swift` — `ObservableObject` shared via `DependencyContainer`. Persists free-form text to `AgentState/long_term_memory_<agentKey>.txt`. Exposes `@Published var text` (bound to `TextEditor` in Settings) and a synchronous `currentText()` reader for the compression policy.

## Tool System

**Available tools** (registered in `DefaultToolExecutor`):
- `get_weather` — WeatherResult with location, temperature, condition, humidity. Mock: 0.5 s delay, random values.
- `calculate` — operations: add/subtract/multiply/divide on an array of operands. Synchronous.
- `search` — SearchResults with title, snippet, url arrays. Mock: 0.7 s delay, 3 hardcoded results.

`ToolDefinition` factory methods for all tools live in `Domain/Models/ToolDefinition.swift`.

## Key Patterns

**Dependency Injection**: `DependencyContainer` (@MainActor ObservableObject, injected via `.environmentObject`) wires all layers using `lazy var` properties. `ConversationPersistenceService` is shared across all agents.

**Agent / Tool Flow**:
1. `DependencyContainer.makeAgent(record:)` creates an agent instance with a `conversationId` and a shared `SendMessageUseCase`.
2. `ChatViewModel` holds a reference to `any Agent`. Calling `sendMessage()` calls `agent.send(text)`.
3. Inside `send()`, the agent optionally compresses context, delegates to `sendMessage.execute(...)`, and appends new messages to `conversation`.
4. After `send()` returns, `ChatViewModel` reads `agent.conversation.messages` to refresh the UI.

**Temperature**: Fixed per agent class — not user-configurable.

**Model switching**: Changing the model in Settings creates a new `SendMessageToLMMInteractor` and rebuilds agents on demand. Existing conversations remain on disk and are restored when re-opened.

**Conversation ownership**: `BaseAgent` owns `conversation` as a stored property. `clearConversation()` resets it to the initial system prompt, calls `compressionPolicy?.reset()`, and deletes the persistence file.

**Token Tracking & Costs**: Token counts and `responseTime` are set in `SendMessageToLMMInteractor` on the final `Message`. `ChatViewModel` sums `promptTokens` / `completionTokens` / `thoughtsTokens` across all messages. Real-time RUB cost is calculated from `ProviderType` pricing and displayed in `ContentView`. `.summaryUsage` messages are hidden in the UI but included in cost totals.

**Response Time**: `Message.responseTime: TimeInterval?` covers the entire round-trip including tool calls. Displayed in `MessageRow` as "X.X с".

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`. Both `request()` and `streamLines()` log requests, responses, and errors.

**Streaming (SSE)**: `NetworkClient.streamLines()` uses `URLSession.bytes(for:)`, parses `data: <json>` lines, stops at `data: [DONE]`. `LLMProvider.streamComplete()` returns `AsyncThrowingStream<StreamChunk, Error>` (`.thinking`, `.content`, `.usage`). Default extension wraps `complete()` for non-streaming providers. `OllamaProvider` overrides with `supportsStreaming = true`; does not send `max_tokens` (local model, no cost limit). Supports `host: String` (default `"localhost"`, override for remote Ollama instances), `overrideTemperature: Double?` (replaces agent temperature) and `systemPromptOverride: String?` (replaces system message) for per-model customization via Modelfile variants. `APIEndpoint.ollamaChatCompletion(host:)` builds the URL dynamically from the host parameter. `LLMResponse` has `reasoning: String?` for thinking models.

**Thinking block in UI**: `MessageRow` detects `.summaryUsage` messages whose content starts with "🤔" (`isThinkingMessage`) and renders a `thinkingRow` with orange background, `brain` icon, and monospaced text. Thinking blocks are generated live during streaming via `conversation.updateMessageContent(id:content:)` (mutates message in-place by replacing it in the array).

**Message History**: `MessageHistoryStore` stores the last 10 sent messages in `UserDefaults`. `ChatView` shows them as chips above the input field — tap to fill input, ✕ to delete.

## Settings

`SettingsView` + `SettingsViewModel` contain four sections:
1. **LLM Провайдер** — model selection (dismisses sheet on tap)
2. **Настройка ProxyAPI.ru** — API key management (Keychain)
3. **Долговременная память** — `TextEditor` bound to `LongTermMemoryStore.text`; «Сохранить» / «Очистить» buttons; available only to `TripleMemoryAgent`
4. **Danger Zone** — «Очистить все данные» button

`SettingsViewModel` holds a reference to `LongTermMemoryStore` (injected via `DependencyContainer.makeSettingsViewModel()`). `ContentView` passes `container.longTermMemoryStore` to `SettingsView`.

**Internal ⚙️ messages** — `SolverAgent` creates `.summaryUsage` messages with content starting with "⚙️". `MessageRow` detects these via `isInternalMessage` computed property: shows the content as multiline text, and uses a `gearshape` icon instead of `arrow.triangle.2.circlepath`. All `.summaryUsage` messages (both internal and compression) are rendered in a card with a purple-tinted background and border (`Color.purple.opacity(0.06)` fill + `0.5pt` stroke) to visually separate consecutive system messages.

**Tavily API key** — stored in Keychain under `com.aiapp.tavily`. Added `case tavily` to `APIKeyProvider`. Settings → «MCP серверы» section with `SecureField`, Save, Delete buttons.

**`MCPClient`** (`Infrastructure/Network/MCPClient.swift`) — URLSession-based JSON-RPC 2.0 client using Streamable HTTP transport. Two inits: `init(apiKey:)` for Tavily (builds URL with `?tavilyApiKey=`), `init(url:)` for arbitrary servers. Supports SSE (`Content-Type: text/event-stream`) by parsing first `data:` line. Stores `Mcp-Session-Id`. Calls `initialize` on first use (failures ignored).

**`MCPModels`** (`Infrastructure/Network/MCPModels.swift`) — DTO types: `JSONRPCRequest`, `InitializeParams`, `ToolCallParams`, `JSONObject`, `AnyCodableValue` (recursive enum), `MCPTool` (with raw `[String: AnyCodableValue]?` inputSchema and `parameters()` helper), `MCPToolsListResponse`, `MCPToolCallResponse`, `MCPClientError: LocalizedError`.

**«Очистить все данные»** — calls `viewModel.clearAllData()`: deletes all persisted conversation data via `ConversationPersistenceService.deleteAllData()` and resets `LongTermMemoryStore.text` to `""`. A confirmation alert is shown before proceeding.

## Adding a New Agent

1. Create `Domain/Agents/MyAgent.swift` as `final class MyAgent: BaseAgent`.
2. Override `var name: String`, `var icon: String`, `var description: String`.
3. Override only properties that differ from BaseAgent defaults (`temperature 0.7`, `maxTokens 1000`, `stopWords nil`, `availableTools []`).
4. Add `init(sendMessage:persistence:conversationId:)` that calls:
   ```swift
   super.init(
       sendMessage: sendMessage,
       persistence: persistence,
       systemPrompt: "...",
       conversationId: conversationId
   )
   ```
   If the agent uses context compression, construct the policy inside `init` and pass it to `super.init(compressionPolicy:)`.
5. Register the agent in `DependencyContainer.agentTemplates` and handle its `agentKey` in `makeAgent(record:)`.
6. If the agent needs a new tool: implement it in `DefaultToolExecutor`, add its `ToolDefinition` factory in `ToolDefinition.swift`, and register it in `canExecute(toolName:)`.
7. If the agent needs shared long-term memory: add a `LongTermMemoryStore` property to `DependencyContainer` and inject it into the compression policy.

## Claude Code Preferences

- **Инструменты**: при работе с этим проектом использовать MCP Xcode инструменты (`mcp__xcode__XcodeRead`, `mcp__xcode__XcodeWrite`, `mcp__xcode__XcodeUpdate`, `mcp__xcode__BuildProject`, `mcp__xcode__XcodeGrep`, `mcp__xcode__XcodeGlob`) вместо стандартных (`Read`, `Edit`, `Bash xcodebuild`, `Grep`, `Glob`). Если MCP Xcode не справляется — вернуться к стандартным и объяснить почему.
- **Git**: никогда не коммитить автоматически — всегда показывать summary и ждать явного подтверждения пользователя.
- **Язык**: всегда отвечать на русском.

## Adding a New LLM Provider

1. Add a provider directory under `Data/Providers/` with `*Provider.swift` (conforming to `LLMProvider`) and `*Models.swift` (request/response types).
2. Add endpoint cases to `APIEndpoint.swift`.
3. Add model cases to `ProviderType` enum in `ProviderFactory.swift` with display name and pricing.
4. Handle new cases in `ProviderFactory.createProvider()`.
5. To support streaming: override `supportsStreaming: Bool { true }` and implement `streamComplete()` returning `AsyncThrowingStream<StreamChunk, Error>`. Yield `.thinking(delta)` for reasoning tokens, `.content(delta)` for response tokens, `.usage(info)` for final stats. See `OllamaProvider` as reference. Note: local providers (Ollama) pass `maxTokens: nil` to avoid cutting off responses.

## Code Style & Conventions

### Good code examples

**1. Minimal agent (no tools, no compression)**

```swift
// Domain/Agents/GeneralAgent.swift
import Foundation

final class GeneralAgent: BaseAgent {
    override var name: String { "Универсальный ассистент" }
    override var icon: String { "brain" }
    override var description: String { "Универсальный помощник для любых задач" }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService, conversationId: UUID) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant.",
            conversationId: conversationId
        )
    }
}
```

**2. Agent with tool (override `availableTools` + `maxTokens`)**

```swift
// Domain/Agents/WeatherAgent.swift
import Foundation

final class WeatherAgent: BaseAgent {
    override var name: String { "Агент погоды" }
    override var icon: String { "cloud.sun" }
    override var description: String { "Специализируется на предоставлении информации о погоде в любом месте" }
    override var maxTokens: Int { 500 }
    override var availableTools: [ToolDefinition] { [.weatherTool()] }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService, conversationId: UUID) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a weather assistant...",
            conversationId: conversationId
        )
    }
}
```

**3. Agent with compression policy (injected from DependencyContainer)**

```swift
// Domain/Agents/ContextManagedAgent.swift
import Foundation

final class ContextManagedAgent: BaseAgent {
    override var name: String { "Агент с памятью" }
    override var icon: String { "memorychip" }
    override var description: String { "..." }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "...",
            conversationId: conversationId,
            compressionPolicy: compressionPolicy
        )
    }
}
```

**4. ToolDefinition factory method (in `ToolDefinition.swift`)**

```swift
static func myTool() -> ToolDefinition {
    ToolDefinition(
        type: "function",
        function: FunctionDefinition(
            name: "my_tool_name",
            description: "What this tool does",
            parameters: ParametersSchema(
                type: "object",
                properties: [
                    "param": PropertySchema(type: "string", description: "...", enumValues: nil, items: nil)
                ],
                required: ["param"]
            )
        )
    )
}
```

**5. Tool registration in `DefaultToolExecutor`**

```swift
// canExecute — добавить кейс
case "my_tool_name": return true

// execute — добавить кейс
case "my_tool_name": return try await executeMyTool(arguments: arguments)

// приватный метод
private func executeMyTool(arguments: String) async throws -> String {
    guard let data = arguments.data(using: .utf8),
          let params = try? JSONDecoder().decode(MyToolParams.self, from: data) else {
        throw ToolExecutionError.invalidArguments(arguments)
    }
    // реализация
    return result.toJSON()
}
```

---

### Anti-patterns (запрещено)

**1. Прямой доступ к FileManager вместо `ConversationPersistenceService`**

```swift
// ❌ НЕЛЬЗЯ — обходит абстракцию персистентности
let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("notes/\(title).txt")
try content.write(to: url, atomically: true, encoding: .utf8)

// ✅ НАДО — использовать ConversationPersistenceService или создавать отдельный сервис
// с инъекцией через DependencyContainer
```

**2. Создание `SendMessageToLMMInteractor` внутри агента**

```swift
// ❌ НЕЛЬЗЯ — агент не должен создавать провайдер сам
final class BadAgent: BaseAgent {
    init(conversationId: UUID) {
        let provider = OpenAIProvider(...)  // прямая зависимость
        let useCase = SendMessageToLMMInteractor(provider: provider, ...)
        super.init(sendMessage: useCase, ...)
    }
}

// ✅ НАДО — получать `any SendMessageToLMMUseCase` через init
init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService, conversationId: UUID)
```

**3. Хранение состояния агента без персистентности**

```swift
// ❌ НЕЛЬЗЯ — состояние теряется при перезапуске
final class BadAgent: BaseAgent {
    var notes: [String] = []  // не сохраняется
}

// ✅ НАДО — сохранять в AgentState/<conversationId>_<suffix>.json через JSONEncoder/JSONDecoder
// или использовать ConversationPersistenceService
```

**4. Использование `print()` для логирования**

```swift
// ❌ НЕЛЬЗЯ
print("Request sent: \(url)")

// ✅ НАДО — NetworkLogger через DependencyContainer, или os.Logger напрямую
```

**5. Регистрация агента без шаблона в `agentTemplates`**

```swift
// ❌ НЕЛЬЗЯ — агент без шаблона невидим в UI
case "my_agent": return MyAgent(...)  // только в makeAgent, без AgentTemplate

// ✅ НАДО — добавить AgentTemplate в agentTemplates И case в makeAgent
```

**6. Неправильный модификатор доступа для сервисов в `DependencyContainer`**

```swift
// ❌ НЕЛЬЗЯ — сервисы, используемые только внутри DependencyContainer, торчат наружу
lazy var notesPersistenceService = NotesPersistenceService()   // видно всем

// ✅ НАДО — private lazy var для всего, что не нужно SwiftUI-слою
private lazy var notesPersistenceService = NotesPersistenceService()
```

Правило доступа в `DependencyContainer`:
- `private lazy var` — инфраструктура и сервисы, нужные только для создания других зависимостей (`keychainService`, `networkClient`, `providerFactory`, `toolExecutor`)
- `lazy var` (без private) — только то, что напрямую используется из SwiftUI: `apiKeyManager`, `conversationPersistence`, `messageHistoryStore`, `modelStore`, `longTermMemoryStore`

**7. Мёртвый код в новых сервисах**

```swift
// ❌ НЕЛЬЗЯ — добавлять методы, не подключённые ни к одному инструменту/flow
final class NotesPersistenceService {
    func saveNote(...) { ... }   // используется
    func listNotes() -> [String] { ... }  // не подключено к инструменту — мёртвый код
}

// ✅ НАДО — добавлять только то, что реально вызывается в текущей задаче
```

---

### Шаблон нового агента

```swift
//
//  MyAgent.swift
//  AI Advent Challenge
//

import Foundation

final class MyAgent: BaseAgent {
    // MARK: - Identity (обязательно переопределить)
    override var name: String { "Имя агента" }
    override var icon: String { "sf.symbol.name" }
    override var description: String { "Краткое описание для UI выбора агента" }

    // MARK: - Overrides (только то, что отличается от BaseAgent defaults)
    // override var temperature: Double { 0.7 }   // default
    // override var maxTokens: Int { 1000 }        // default
    // override var availableTools: [ToolDefinition] { [] }  // default

    // MARK: - Init (сигнатура строго фиксирована)
    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "System prompt for this agent.",
            conversationId: conversationId
            // compressionPolicy: nil  // передать если нужна компрессия
        )
    }
}
```

**Регистрация в `DependencyContainer`:**

```swift
// 1. В agentTemplates:
AgentTemplate(
    id: "my_agent",
    name: "Имя агента",
    icon: "sf.symbol.name",
    description: "Описание",
    compressionPolicyDescription: nil
)

// 2. В makeAgent(record:):
case "my_agent":
    return MyAgent(sendMessage: useCase, persistence: conversationPersistence, conversationId: id)
```

**Если агенту нужен новый сервис (не `ConversationPersistenceService`):**

```swift
// DependencyContainer — сервис всегда private lazy var (только для внутреннего DI)
private lazy var myService = MyService()
private lazy var toolExecutor: ToolExecutor = DefaultToolExecutor(myService: myService)
```

Не делать сервис `lazy var` без `private`, если он не нужен SwiftUI-слою напрямую.
