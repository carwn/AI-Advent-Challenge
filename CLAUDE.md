# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by multiple LLM providers (OpenAI, Anthropic, Google Gemini) via ProxyAPI.ru. Users can select from different specialized agent types, switch between 9 models, adjust temperature, and agents can call tools (weather, calculator, search) as part of their responses.

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
  Models/        — Message, Conversation, AgentType, AgentResponse, ToolDefinition
  Protocols/     — Agent (+ DefaultAgent), LLMProvider, ToolExecutor
  UseCases/      — CreateAgentUseCase, SendMessageUseCase

Data/
  Providers/
    OpenAI/      — OpenAIProvider (implements LLMProvider), OpenAIModels
    Anthropic/   — AnthropicProvider, AnthropicModels
    Gemini/      — GeminiProvider, GeminiModels
    ProviderFactory.swift  — ProviderType enum (9 models) + pricing in RUB
  Repositories/  — ConversationRepository (in-memory, thread-safe via NSLock)

Infrastructure/
  Network/       — NetworkClient (URLSession-based), APIEndpoint, HTTPMethod,
                   NetworkError, NetworkLogger (protocol), OSNetworkLogger
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel,
                   MessageHistoryStore, TemperatureStore, ModelStore (@MainActor)

App/
  DependencyContainer.swift  — Manual DI root, @MainActor ObservableObject
```

## Agent Types

Defined in `AgentType.swift` (enum with `CaseIterable`). Each case provides `systemPrompt`, `icon` (SF Symbol), `description`, `availableTools`, `maxTokens`, and optionally `stopWords`.

| Case | Max Tokens | Tools | Description |
|------|-----------|-------|-------------|
| `general` | 1000 | — | Universal assistant |
| `weather` | 500 | get_weather | Weather specialist, plain text output |
| `weatherJSON` | 500 | get_weather | Weather specialist, always returns JSON |
| `bulletList` | 300 | — | Responds only with bullet lists (max 5 items) |
| `stop13` | 1000 | — | Stops generation when `"13"` appears (stop sequence demo) |
| `stepByStep` | 1000 | — | Breaks tasks into numbered steps |
| `promptCrafter` | 800 | — | Crafts effective prompts for other AI agents |
| `multiExpert` | 2000 | — | Consults 3 expert roles and synthesizes conclusions |
| `customPrompt` | 1000 | — | User-defined system prompt (populated via promptCrafter) |

**Note**: `maxTokens` is now defined per agent type (not a global 1000 cap).

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

**Dependency Injection**: `DependencyContainer` (injected via `.environmentObject`) wires all layers together using `lazy var` properties and factory methods. ViewModels are created on-demand via `make*ViewModel()` methods. `MessageHistoryStore`, `TemperatureStore` are `lazy var` properties; `ModelStore` is a non-lazy property (needed throughout app lifecycle).

**Agent / Tool Flow**:
1. `CreateAgentUseCase` creates a `DefaultAgent` wrapping an `LLMProvider` + `ToolExecutor` + `TemperatureStore` + `ModelStore`.
2. `SendMessageUseCase.execute()` sends the user message, then calls `agent.executeToolsAndContinue()` if the response requires tool use.
3. `Agent` protocol extension (in `Agent.swift`) provides default `sendMessage` and `executeToolsAndContinue` implementations — tool calls are dispatched to `DefaultToolExecutor`. `maxTokens` is read from `AgentType`.

**Tool implementations** (`DefaultToolExecutor`) use **mock services** — `DefaultWeatherService`, `DefaultCalculatorService`, `DefaultSearchService` — returning simulated data with artificial delays. Tools are enabled per agent type via `AgentType.availableTools` (weather agents have `get_weather`; others return `[]`).

**Stores**:
- `TemperatureStore` — observable temperature value (0.0–2.0, default 0.7), shown as a slider in ChatView.
- `ModelStore` — observable selected `ProviderType`, persisted to `UserDefaults`.
- `MessageHistoryStore` — last 10 sent messages, persisted to `UserDefaults` (key `"messageHistory"`). `ChatView` shows history chips above the input field — tapping a chip fills the input, the ✕ button deletes the entry.

**Token Tracking & Costs**: `Conversation` accumulates `totalPromptTokens` / `totalCompletionTokens` across messages. `ChatViewModel` exposes these to the UI. Real-time RUB cost is calculated from `ProviderType` pricing and displayed in `ContentView`.

**Response Time**: `Message` has a `responseTime: TimeInterval?` property. `ChatViewModel` measures elapsed time from request start to response and stores it on the message. Displayed in `MessageRow` as "X.X с".

**Custom Prompts**: `ConversationRepository.setSystemPromptForAgent()` allows overriding the system prompt for `customPrompt` agent. `ChatViewModel.useAsCustomAgentPrompt()` exposes this to the UI (used via context menu on assistant messages from `promptCrafter`).

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`.

## Adding New Agent Types

1. Add a case to `AgentType` with `systemPrompt`, `icon`, `description`, `availableTools`, `maxTokens`, and (optionally) `stopWords`.
2. If the agent needs a new tool: implement the tool in `DefaultToolExecutor`, add its `ToolDefinition` factory in `ToolDefinition.swift`, and register it in `canExecute(toolName:)`.

## Adding a New LLM Provider

1. Add a provider directory under `Data/Providers/` with `*Provider.swift` (conforming to `LLMProvider`) and `*Models.swift` (request/response types).
2. Add endpoint cases to `APIEndpoint.swift`.
3. Add model cases to `ProviderType` enum in `ProviderFactory.swift` with display name and pricing.
4. Handle new cases in `ProviderFactory.makeProvider()`.
