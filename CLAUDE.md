# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by multiple LLM providers (OpenAI, Anthropic, Google Gemini) via ProxyAPI.ru. Users can select from 9 specialized agents, switch between 9 models, and agents can call tools (weather, calculator, search) as part of their responses.

## Git

Never commit changes automatically. Always show a summary of what will be committed and wait for explicit user confirmation before running `git commit`.

## Build & Run

This is a standard Xcode project with no external package manager (no SPM packages, no Podfile).

- **Build/Run**: Open `AI Advent Challenge.xcodeproj` in Xcode and run on a simulator or device.
- **Новые файлы**: Проект использует `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — файлы автоматически включаются в build при добавлении в директорию. Вручную редактировать `project.pbxproj` не нужно.
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
Domain/          — Pure Swift, no framework dependencies
  Models/        — Message, Conversation, AgentResponse, ToolDefinition, LLMMessage, LLMResponse
  Protocols/     — Agent, LLMProvider, ToolExecutor, ContextCompressionPolicy
  Agents/        — SendMessageToLMMUseCase (protocol), SendMessageToLMMInteractor,
                   BaseAgent (base class), 9 concrete agent classes,
                   SummaryContextCompressionPolicy

Data/
  Providers/
    OpenAI/      — OpenAIProvider (implements LLMProvider), OpenAIModels
    Anthropic/   — AnthropicProvider, AnthropicModels
    Gemini/      — GeminiProvider, GeminiModels
    ProviderFactory.swift  — ProviderType enum (9 models) + pricing in RUB

Infrastructure/
  Network/       — NetworkClient (URLSession-based), APIEndpoint, HTTPMethod,
                   NetworkError, NetworkLogger (protocol), OSNetworkLogger
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService
  ConversationPersistenceService.swift  — save/load/delete Conversation JSON per agent key

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
    var icon: String { get }        // SF Symbol name
    var description: String { get }
    var conversation: Conversation { get }
    func send(_ text: String) async throws
    func clearConversation()
}
```

## BaseAgent

`Domain/Agents/BaseAgent.swift` — базовый класс для всех агентов. Хранит общие зависимости и предоставляет реализации `send(_:)` и `clearConversation()`.

**Хранимые свойства** (инициализируются через `super.init`):
- `sendMessage: any SendMessageToLMMUseCase`
- `persistence: ConversationPersistenceService`
- `compressionPolicy: (any ContextCompressionPolicy)?` — опционально
- `conversation: Conversation` — загружается из persistence или создаётся из systemPrompt
- `systemPrompt: String`, `persistenceKey: String` — передаются из подкласса

**Переопределяемые вычисляемые свойства** (дефолты в `BaseAgent`):
- `var temperature: Double { 0.7 }`
- `var maxTokens: Int { 1000 }`
- `var stopWords: [String]? { nil }`
- `var availableTools: [ToolDefinition] { [] }`

**Абстрактные** (подкласс обязан переопределить, иначе `fatalError`):
- `var name: String`, `var icon: String`, `var description: String`

**`send(_:)`** реализует полный цикл с поддержкой compression policy: сжимает контекст через `compressionPolicy?.compress(conversation)`, вызывает `sendMessage.execute(...)`, добавляет только новые сообщения в `conversation`, при необходимости добавляет `.summaryUsage`-сообщение, сохраняет через persistence.

**`clearConversation()`** сбрасывает `conversation` к начальному systemPrompt, вызывает `compressionPolicy?.reset()`, удаляет файл persistence.

## Concrete Agents

Каждый агент — `final class` в `Domain/Agents/`, наследует `BaseAgent`. Переопределяет только те свойства, которые отличаются от дефолтов.

| Class | temperature | maxTokens | stopWords | availableTools |
|---|---|---|---|---|
| `GeneralAgent` | — | — | — | — |
| `WeatherAgent` | — | **500** | — | **get_weather** |
| `WeatherJSONAgent` | — | **500** | — | **get_weather** |
| `BulletListAgent` | — | **300** | — | — |
| `Stop13Agent` | — | — | **`["13"]`** | — |
| `StepByStepAgent` | — | — | — | — |
| `PromptCrafterAgent` | — | **800** | — | — |
| `MultiExpertAgent` | **0.5** | **2000** | — | — |
| `ContextManagedAgent` | — | — | — | — |

_(— означает дефолт BaseAgent: temperature 0.7, maxTokens 1000, stopWords nil, availableTools [])_

`ContextManagedAgent` дополнительно принимает `compressionPolicy: (any ContextCompressionPolicy)?` в `init`.

## SendMessageUseCase

`Domain/Agents/AgentSending.swift` — use case, инкапсулирующий полный цикл запроса к LLM.

**Протокол** `SendMessageToLMMUseCase` (в том же файле) — два метода:
```swift
protocol SendMessageToLMMUseCase {
    // Полный цикл с Conversation; возвращает обновлённый Conversation
    func execute(userText:conversation:tools:temperature:maxTokens:stopWords:) async throws -> Conversation
    // Упрощённый вызов без Conversation; возвращает AgentResponse
    func execute(systemPrompt:userMessage:tools:temperature:maxTokens:stopWords:) async throws -> AgentResponse
}
```

**Класс** `SendMessageToLMMInteractor: SendMessageToLMMUseCase` принимает `LLMProvider` и `ToolExecutor` в `init`; `execute(...)` получает только варьируемые данные запроса:

1. Добавляет user-сообщение в локальную копию `conversation`
2. Вызывает `provider.complete(...)` с `max(maxTokens, provider.minMaxTokens)`
3. Если ответ требует выполнения инструментов: добавляет tool-call сообщение, выполняет каждый инструмент через `ToolExecutor`, добавляет tool-result сообщения, повторно вызывает `provider.complete(...)`
4. Строит финальный `Message` с `responseTime`, `modelName` и счётчиками токенов из `usage`
5. Возвращает обновлённый `Conversation`

`DependencyContainer` создаёт один `SendMessageToLMMInteractor` на все агенты текущей модели. `BaseAgent` хранит `any SendMessageToLMMUseCase` — протокол позволяет подменять реализацию (например, мок в тестах).

## LLM Message Models

Определены в `Domain/Models/LLMMessage.swift`. Разделяют исходящие и входящие данные провайдера:

**`LLMMessage`** — исходящее сообщение в API-запросе (`LLMProvider.complete(messages:)`). Содержит только поля, нужные для запроса; не используется в `Conversation`.
```swift
struct LLMMessage {
    let role: MessageRole      // system / user / assistant / tool
    let content: String
    let toolCalls: [ToolCall]? // assistant-сообщение с вызовами инструментов
    let toolCallId: String?    // только для .tool-сообщений (ссылка на tool call)
}
```

**`LLMResponse`** — входящий ответ от провайдера (`AgentResponse.message`). Роль всегда `.assistant`, поэтому поле `role` отсутствует; `toolCallId` невозможен в ответе.
```swift
struct LLMResponse {
    let content: String
    let toolCalls: [ToolCall]? // если LLM запрашивает выполнение инструментов
}
```

`Message.toLLMMessage()` (extension в том же файле) конвертирует `Conversation.messages` в `[LLMMessage]` перед вызовом провайдера. `SendMessageUseCase` строит финальный `Message` из `LLMResponse`, добавляя `role: .assistant`, `responseTime`, `modelName` и счётчики токенов.

## LLM Providers & Models

All requests go through **ProxyAPI.ru** with a single API key. Defined in `ProviderType` enum with pricing in RUB per 1M tokens:

| Model | Input (₽/1M) | Output (₽/1M) |
|-------|-------------|--------------|
| gpt-4.1-nano | 26 | 104 |
| gpt-4.1-mini | 104 | 413 |
| gpt-4.1 | 516 | 2 062 |
| claude-haiku-4-5 | 295 | 1 474 |
| claude-sonnet-4-5 | 774 | 3 866 |
| claude-opus-4-5 | 1 516 | 7 579 |
| gemini-2.5-flash-lite | 26 | 129 |
| gemini-2.5-flash | 78 | 645 |
| gemini-2.5-pro | 323 | 2 577 |

Selected model is persisted to `UserDefaults` (`selectedProvider`) via `ModelStore`.

## Key Patterns

**Dependency Injection**: `DependencyContainer` (injected via `.environmentObject`) wires all layers together using `lazy var` properties. `makeAgents()` creates all 9 agent instances for the currently selected provider and caches them in `_agents`. When `modelStore.selectedProvider` changes, `_agents` is set to `nil` so the next call to `makeAgents()` creates fresh agents with the new provider. `ModelStore` is a non-lazy property; `MessageHistoryStore` is lazy.

**Agent / Tool Flow**:
1. `DependencyContainer.makeAgents()` создаёт один `SendMessageUseCase` и передаёт его всем агентам.
2. `ChatViewModel` holds a reference to `any Agent`. Calling `sendMessage()` calls `agent.send(text)`.
3. Inside `send()`, the agent delegates to `sendMessage.execute(...)`, which handles the full LLM call (including tool execution if needed) and returns the updated `Conversation`.
4. After `send()` returns, `ChatViewModel` reads `agent.conversation.messages` to refresh the UI.

**Temperature**: Fixed per agent class — not user-configurable. There is no `TemperatureStore`.

**Model switching**: Changing the model in Settings nil-s `_agents` in `DependencyContainer`. `ContentView` reacts to `modelStore.selectedProvider` changes and calls `makeAgents()` + `activateAgent()`, which creates a new `ChatViewModel` with a freshly constructed agent (empty conversation).

**Conversation ownership**: `BaseAgent` owns `conversation` as a stored property. `clearConversation()` replaces it with a fresh `Conversation(systemPrompt:)`, вызывает `compressionPolicy?.reset()` и удаляет файл persistence.

**Conversation persistence**: `BaseAgent` persists `conversation` to `Application Support/AgentState/<key>.json` via `ConversationPersistenceService`. Loading happens in `BaseAgent.init` (restores state across launches); saving happens after each successful `send()`; deletion happens in `clearConversation()`. Each agent subclass passes a unique `persistenceKey` string (e.g. `"general_agent"`) to `super.init` — independent of the display `name`. `ConversationPersistenceService` is a single `lazy var` in `DependencyContainer`, shared by all agents.

**Tool implementations** (`DefaultToolExecutor`) use **mock services** — `DefaultWeatherService`, `DefaultCalculatorService`, `DefaultSearchService` — returning simulated data with artificial delays.

**Stores**:
- `ModelStore` — observable selected `ProviderType`, persisted to `UserDefaults`.
- `MessageHistoryStore` — last 10 sent messages, persisted to `UserDefaults` (key `"messageHistory"`). `ChatView` shows history chips above the input field — tapping a chip fills the input, the ✕ button deletes the entry.

**Token Tracking & Costs**: Token counts and `responseTime` are set directly in `SendMessageUseCase` on the final `Message`. `ChatViewModel` computes totals by summing `promptTokens` / `completionTokens` / `thoughtsTokens` across all messages. Real-time RUB cost is calculated from `ProviderType` pricing and displayed in `ContentView`.

**Context Compression Policy**: Defined in `Domain/Protocols/ContextCompressionPolicy.swift` as a class-only protocol:

```swift
protocol ContextCompressionPolicy: AnyObject {
    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?)
    func reset()
}
```

`compress(_:)` принимает полный Conversation агента, возвращает сжатый контекст для LLM и опциональный `UsageInfo` токенов, потраченных на генерацию summary. Агент сам создаёт из `UsageInfo` сообщение `MessageRole.summaryUsage` и добавляет его в свой `conversation`. `reset()` вызывается агентом при `clearConversation()`.

**`SummaryContextCompressionPolicy`** (`Domain/Agents/SummaryContextCompressionPolicy.swift`) — реализация на основе summary. Принимает `sendMessage: any SendMessageToLMMUseCase` для собственных LLM-вызовов, `summaryTriggerTokens` (по умолчанию 1 500) и `persistenceKey`. При вызове `compress(_:)`:
1. Проверяет `promptTokens` последнего assistant-сообщения; если превышен порог — вызывает LLM для генерации/обновления summary по несжатым сообщениям.
2. Строит API-контекст: system + summary pseudo-turn (`user`/`assistant`) + сообщения, начиная с `summaryMessageCount`.
3. Возвращает сжатый Conversation и `UsageInfo` (или `nil`, если summary не генерировался).

Summary-состояние (`text` + `messageCount`) персистируется в `AgentState/<persistenceKey>_summary.json`.

**Context Management (ContextManagedAgent)**: Хранит полную историю в `conversation` (для UI), перед каждым запросом вызывает `compressionPolicy?.compress(conversation)`. Если политика вернула `UsageInfo` — агент сам добавляет `Message(role: .summaryUsage, content: "", ...)` в `conversation`. `ChatView` фильтрует `.summaryUsage` из отображения, `ChatViewModel` включает их токены в итоговую стоимость. `ContextCompressionPolicy` передаётся в `init` опционально; без политики агент отправляет полный контекст.

**Response Time**: `Message.responseTime: TimeInterval?` is set in `SendMessageUseCase` as `Date().timeIntervalSince(startTime)` covering the entire round-trip (including tool calls). Displayed in `MessageRow` as "X.X с".

**Selected agent persistence**: `ContentView` uses `@AppStorage("selectedAgentName")` to persist the active agent's `name` string across launches. On startup it calls `makeAgents()` and finds the matching agent by name.

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`.

## Adding a New Agent

1. Create `Domain/Agents/MyAgent.swift` as a `final class MyAgent: BaseAgent`.
2. Override `var name: String`, `var icon: String`, `var description: String`.
3. Override only the properties that differ from BaseAgent defaults (`temperature 0.7`, `maxTokens 1000`, `stopWords nil`, `availableTools []`).
4. Add `init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService)` that calls:
   ```swift
   super.init(sendMessage: sendMessage, persistence: persistence,
              systemPrompt: "...", persistenceKey: "my_agent")
   ```
   If the agent uses context compression, add `compressionPolicy:` parameter and pass it to `super.init`.
5. Add an instance to the array in `DependencyContainer.makeAgents()`, passing `persistence: conversationPersistence`.
6. If the agent needs a new tool: implement it in `DefaultToolExecutor`, add its `ToolDefinition` factory in `ToolDefinition.swift`, and register it in `canExecute(toolName:)`.

## Adding a New LLM Provider

1. Add a provider directory under `Data/Providers/` with `*Provider.swift` (conforming to `LLMProvider`) and `*Models.swift` (request/response types).
2. Add endpoint cases to `APIEndpoint.swift`.
3. Add model cases to `ProviderType` enum in `ProviderFactory.swift` with display name and pricing.
4. Handle new cases in `ProviderFactory.createProvider()`.
