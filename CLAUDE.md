# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by multiple LLM providers (OpenAI, Anthropic, Google Gemini) via ProxyAPI.ru. Users can select from 8 specialized agents, switch between 9 models, and agents can call tools (weather, calculator, search) as part of their responses.

## Git

Never commit changes automatically. Always show a summary of what will be committed and wait for explicit user confirmation before running `git commit`.

## Build & Run

This is a standard Xcode project with no external package manager (no SPM packages, no Podfile).

- **Build/Run**: Open `AI Advent Challenge.xcodeproj` in Xcode and run on a simulator or device.
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
  Models/        — Message, Conversation, AgentResponse, ToolDefinition
  Protocols/     — Agent, LLMProvider, ToolExecutor
  Agents/        — AgentSending (static helper) + 8 concrete agent classes

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

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel,
                   MessageHistoryStore, ModelStore (@MainActor)

App/
  DependencyContainer.swift  — Manual DI root, @MainActor ObservableObject
```

## Agent Protocol

Defined in `Domain/Protocols/Agent.swift`. Requires `AnyObject` (class-only) so that `conversation` can be mutated through an existential `any Agent`.

```swift
protocol Agent: AnyObject {
    var name: String { get }
    var icon: String { get }        // SF Symbol name
    var description: String { get }
    var conversation: Conversation { get set }
    func send(_ text: String) async throws -> AgentResponse
    func clearConversation()
}
```

No default implementations — each agent class is self-contained.

## Concrete Agents

Each agent lives in `Domain/Agents/` as a `final class`. All configuration (system prompt, temperature, maxTokens, stopWords, tools) is private to the class.

| Class | temperature | maxTokens | stopWords | tools |
|---|---|---|---|---|
| `GeneralAgent` | 0.7 | 1000 | — | — |
| `WeatherAgent` | 0.7 | 500 | — | get_weather |
| `WeatherJSONAgent` | 0.7 | 500 | — | get_weather |
| `BulletListAgent` | 0.7 | 300 | — | — |
| `Stop13Agent` | 0.7 | 1000 | `["13"]` | — |
| `StepByStepAgent` | 0.7 | 1000 | — | — |
| `PromptCrafterAgent` | 0.7 | 800 | — | — |
| `MultiExpertAgent` | 0.5 | 2000 | — | — |

Each agent's `send(_:)` delegates to `AgentSending.send(...)` and stores the returned `Conversation` back to `self.conversation`.

## AgentSending

`Domain/Agents/AgentSending.swift` — static helper that handles the full request cycle:

1. Adds the user message to a local copy of `conversation`
2. Calls `provider.complete(...)` with `max(maxTokens, provider.minMaxTokens)`
3. If the response requires tool execution: adds the assistant tool-call message, executes each tool via `ToolExecutor`, adds tool result messages, calls `provider.complete(...)` again
4. Builds the final `Message` with `responseTime`, `modelName`, and token counts from `usage`
5. Returns `(AgentResponse, updated Conversation)` — uses value return instead of `inout` to avoid concurrency issues

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

**Dependency Injection**: `DependencyContainer` (injected via `.environmentObject`) wires all layers together using `lazy var` properties. `makeAgents()` creates all 8 agent instances for the currently selected provider and caches them in `_agents`. When `modelStore.selectedProvider` changes, `_agents` is set to `nil` so the next call to `makeAgents()` creates fresh agents with the new provider. `ModelStore` is a non-lazy property; `MessageHistoryStore` is lazy.

**Agent / Tool Flow**:
1. `DependencyContainer.makeAgents()` creates all agents sharing one `LLMProvider` instance.
2. `ChatViewModel` holds a reference to `any Agent`. Calling `sendMessage()` calls `agent.send(text)`.
3. Inside `send()`, the agent delegates to `AgentSending.send(...)`, which handles the full LLM call (including tool execution if needed) and returns the updated `Conversation`.
4. After `send()` returns, `ChatViewModel` reads `agent.conversation.messages` to refresh the UI.

**Temperature**: Fixed per agent class — not user-configurable. There is no `TemperatureStore`.

**Model switching**: Changing the model in Settings nil-s `_agents` in `DependencyContainer`. `ContentView` reacts to `modelStore.selectedProvider` changes and calls `makeAgents()` + `activateAgent()`, which creates a new `ChatViewModel` with a freshly constructed agent (empty conversation).

**Conversation ownership**: Each agent owns its `Conversation` as a stored property. There is no separate repository. `clearConversation()` replaces it with a fresh `Conversation(systemPrompt:)`.

**Tool implementations** (`DefaultToolExecutor`) use **mock services** — `DefaultWeatherService`, `DefaultCalculatorService`, `DefaultSearchService` — returning simulated data with artificial delays.

**Stores**:
- `ModelStore` — observable selected `ProviderType`, persisted to `UserDefaults`.
- `MessageHistoryStore` — last 10 sent messages, persisted to `UserDefaults` (key `"messageHistory"`). `ChatView` shows history chips above the input field — tapping a chip fills the input, the ✕ button deletes the entry.

**Token Tracking & Costs**: Token counts and `responseTime` are set directly in `AgentSending` on the final `Message`. `ChatViewModel` computes totals by summing `promptTokens` / `completionTokens` / `thoughtsTokens` across all messages. Real-time RUB cost is calculated from `ProviderType` pricing and displayed in `ContentView`.

**Response Time**: `Message.responseTime: TimeInterval?` is set in `AgentSending` as `Date().timeIntervalSince(startTime)` covering the entire round-trip (including tool calls). Displayed in `MessageRow` as "X.X с".

**Selected agent persistence**: `ContentView` uses `@AppStorage("selectedAgentName")` to persist the active agent's `name` string across launches. On startup it calls `makeAgents()` and finds the matching agent by name.

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`.

## Adding a New Agent

1. Create `Domain/Agents/MyAgent.swift` as a `final class` conforming to `Agent`.
2. Set `name`, `icon`, `description`, `systemPrompt`, `temperature`, `maxTokens`, `stopWords`, `availableTools` as private properties.
3. Implement `send(_:)` by delegating to `AgentSending.send(...)` and updating `conversation`.
4. Implement `clearConversation()` by replacing `conversation` with `Conversation(systemPrompt: systemPrompt)`.
5. Add an instance to the array in `DependencyContainer.makeAgents()`.
6. If the agent needs a new tool: implement it in `DefaultToolExecutor`, add its `ToolDefinition` factory in `ToolDefinition.swift`, and register it in `canExecute(toolName:)`.

## Adding a New LLM Provider

1. Add a provider directory under `Data/Providers/` with `*Provider.swift` (conforming to `LLMProvider`) and `*Models.swift` (request/response types).
2. Add endpoint cases to `APIEndpoint.swift`.
3. Add model cases to `ProviderType` enum in `ProviderFactory.swift` with display name and pricing.
4. Handle new cases in `ProviderFactory.createProvider()`.
