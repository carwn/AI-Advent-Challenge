# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by multiple LLM providers (OpenAI, Anthropic, Google Gemini) via ProxyAPI.ru. Users can create multiple named conversations, each tied to one of 8 specialized agents, switch between 10 LLM models, and agents can call tools (weather, calculator, search) as part of their responses. Conversations can be branched, creating a tree of forked chats.

## Git

When the user explicitly asks to make a commit:
1. Run `git diff HEAD` to inspect all staged and unstaged changes.
2. Update this CLAUDE.md file to reflect any architectural, behavioral, or structural changes introduced by those changes (new agents, new policies, new files, changed patterns, etc.).
3. Run `git commit` immediately — do not ask for additional confirmation. Show a summary of what will be committed, but proceed without waiting for approval.

## Build & Run

This is a standard Xcode project with no external package manager (no SPM packages, no Podfile).

- **Build/Run**: Open `AI Advent Challenge.xcodeproj` in Xcode and run on a simulator or device.
- **New files**: The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — files are automatically included in the build when added to the directory. No need to manually edit `project.pbxproj`.
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

## Architecture

The project follows **Clean Architecture** with these layers (all under `AI Advent Challenge/`):

```
Domain/
  Models/        — Message, Conversation, ConversationRecord, AgentResponse,
                   ToolDefinition, LLMMessage, LLMResponse
  Protocols/     — Agent, LLMProvider, ToolExecutor, ContextCompressionPolicy
  Agents/        — SendMessageToLMMUseCase (protocol), SendMessageToLMMInteractor,
                   BaseAgent (base class), 8 concrete agent classes,
                   SummaryContextCompressionPolicy,
                   SlidingWindowContextCompressionPolicy,
                   StickyFactsCompressionPolicy,
                   TripleMemoryCompressionPolicy,
                   KeyValueMemoryExtractor (shared LLM key-value extraction),
                   LongTermMemoryStore (ObservableObject, shared per-agent-type)
  UseCases/      — BranchConversationUseCase

Data/
  Providers/
    OpenAI/      — OpenAIProvider (implements LLMProvider), OpenAIModels
    Anthropic/   — AnthropicProvider, AnthropicModels
    Gemini/      — GeminiProvider, GeminiModels
    ProviderFactory.swift  — ProviderType enum (10 models) + pricing in RUB

Infrastructure/
  Network/       — NetworkClient (URLSession-based), APIEndpoint, HTTPMethod,
                   NetworkError, NetworkLogger (protocol), OSNetworkLogger
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService
  ConversationPersistenceService.swift  — save/load/delete Conversation JSON by UUID

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel,
                   MessageHistoryStore, ModelStore (@MainActor)

App/
  DependencyContainer.swift  — Manual DI root, @MainActor ObservableObject
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

**`send(_:)`** implements the full cycle with compression policy support: compresses context via `compressionPolicy?.compress(conversation)`, calls `sendMessage.execute(...)`, appends only new messages to `conversation`, optionally adds a `.summaryUsage` message if the policy returned `UsageInfo`, saves via persistence, and updates the `ConversationRecord` metadata.

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

_(— means BaseAgent default: temperature 0.7, maxTokens 1000, stopWords nil, availableTools [])_

`WeatherJSONAgent` has a detailed system prompt requiring JSON-only output with specific fields (location, temperature, condition, humidity, summary).

`UserProfileAgent` implements a three-phase profiling cycle: (1) **profiling** — asks 5 questions (response style, format, constraints, expertise, language), validating each answer via LLM; (2) **editing** — detects intent to edit the profile and re-enters profiling; (3) **chat** — normal conversation using the collected profile. Profile state is persisted to `AgentState/<conversationId>_profile.json`. On completion, the profile is saved to the shared `LongTermMemoryStore` of `TripleMemoryAgent` so it can be used by that agent.

## SendMessageUseCase

`Domain/Agents/AgentSending.swift` — use case encapsulating the full LLM request cycle.

**Protocol** `SendMessageToLMMUseCase` — two methods:
```swift
protocol SendMessageToLMMUseCase {
    // Full cycle with Conversation; returns updated Conversation
    func execute(userText:conversation:tools:temperature:maxTokens:stopWords:) async throws -> Conversation
    // Simplified call without Conversation; returns AgentResponse
    func execute(systemPrompt:userMessage:tools:temperature:maxTokens:stopWords:) async throws -> AgentResponse
}
```

**Class** `SendMessageToLMMInteractor: SendMessageToLMMUseCase` takes `LLMProvider` and `ToolExecutor` in `init`. `execute(...)` receives only the variable request data:

1. Appends the user message to a local copy of `conversation`
2. Calls `provider.complete(...)` with `max(maxTokens, provider.minMaxTokens)`
3. If the response requires tool execution: appends a tool-call message, executes each tool via `ToolExecutor`, appends tool-result messages, calls `provider.complete(...)` again
4. Builds the final `Message` with `responseTime`, `modelName`, and token counts from `usage`
5. Returns the updated `Conversation`

`DependencyContainer` creates one `SendMessageToLMMInteractor` instance and shares it across all agents for the current model. `BaseAgent` holds `any SendMessageToLMMUseCase` — the protocol allows swapping implementations (e.g. mocks in tests).

## LLM Message Models

Defined in `Domain/Models/LLMMessage.swift`. Separates outgoing and incoming provider data:

**`LLMMessage`** — outgoing message in an API request (`LLMProvider.complete(messages:)`). Contains only fields needed for the request; not used in `Conversation`.
```swift
struct LLMMessage {
    let role: MessageRole      // system / user / assistant / tool
    let content: String
    let toolCalls: [ToolCall]? // assistant message with tool call requests
    let toolCallId: String?    // only for .tool messages (reference to tool call)
}
```

**`LLMResponse`** — incoming response from the provider (`AgentResponse.message`). Role is always `.assistant`, so the field is absent; `toolCallId` is impossible in a response.
```swift
struct LLMResponse {
    let content: String
    let toolCalls: [ToolCall]? // if LLM requests tool execution
}
```

`Message.toLLMMessage()` (extension in the same file) converts `Conversation.messages` into `[LLMMessage]` before calling the provider. `SendMessageUseCase` builds the final `Message` from `LLMResponse`, adding `role: .assistant`, `responseTime`, `modelName`, and token counts.

## LLM Providers & Models

All requests go through **ProxyAPI.ru** with a single API key. Defined in the `ProviderType` enum with pricing in RUB per 1M tokens:

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
- `agentTemplates: [AgentTemplate]` — returns the 8 available agent templates
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

`Domain/Agents/KeyValueMemoryExtractor.swift` — shared helper encapsulating the full LLM key-value extraction cycle. Used by both `StickyFactsCompressionPolicy` and `TripleMemoryCompressionPolicy`.

```swift
final class KeyValueMemoryExtractor {
    private(set) var entries: [String: String]
    private(set) var processedMessageCount: Int

    init(
        sendMessage: any SendMessageToLMMUseCase,
        extractionSystemPrompt: String,   // parametrized per use case
        persistenceKey: String,           // file saved as AgentState/<key>.json
        useLargerValueMerge: Bool = true  // true: keep longer value (StickyFacts); false: always replace (WorkingMemory)
    )

    func update(from conversation: Conversation) async -> UsageInfo?
    func reset()
}
```

On `update(from:)`:
1. Finds messages not yet processed (`dropFirst(processedMessageCount)`), filtered to user/assistant.
2. Calls LLM with existing entries + new dialog text; expects flat JSON response.
3. Merges result into `entries`: with `useLargerValueMerge=true` keeps longer value (prevents truncation of accumulated lists); with `false` always replaces (correct for task-focused working memory).
4. Updates `processedMessageCount` and persists state on successful JSON parse.

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

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`.

**Message History**: `MessageHistoryStore` stores the last 10 sent messages in `UserDefaults`. `ChatView` shows them as chips above the input field — tap to fill input, ✕ to delete.

## Settings

`SettingsView` + `SettingsViewModel` contain three sections:
1. **LLM Провайдер** — model selection (dismisses sheet on tap)
2. **Настройка ProxyAPI.ru** — API key management (Keychain)
3. **Долговременная память** — `TextEditor` bound to `LongTermMemoryStore.text`; «Сохранить» / «Очистить» buttons; available only to `TripleMemoryAgent`

`SettingsViewModel` holds a reference to `LongTermMemoryStore` (injected via `DependencyContainer.makeSettingsViewModel()`). `ContentView` passes `container.longTermMemoryStore` to `SettingsView`.

**«Очистить все данные»** — a fourth "Danger Zone" section with a button that calls `viewModel.clearAllData()`. This deletes all persisted conversation data via `ConversationPersistenceService.deleteAllData()` and resets `LongTermMemoryStore.text` to `""`. A confirmation alert is shown before proceeding.

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

## Adding a New LLM Provider

1. Add a provider directory under `Data/Providers/` with `*Provider.swift` (conforming to `LLMProvider`) and `*Models.swift` (request/response types).
2. Add endpoint cases to `APIEndpoint.swift`.
3. Add model cases to `ProviderType` enum in `ProviderFactory.swift` with display name and pricing.
4. Handle new cases in `ProviderFactory.createProvider()`.
