# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Advent Challenge** is an iOS SwiftUI app that lets users chat with AI agents powered by the OpenAI API. Users can select from different specialized agent types, and agents can call tools (weather, calculator, search) as part of their responses.

## Git

Never commit changes automatically. Always show a summary of what will be committed and wait for explicit user confirmation before running `git commit`.

## Build & Run

This is a standard Xcode project with no external package manager (no SPM packages, no Podfile).

- **Build/Run**: Open `AI Advent Challenge.xcodeproj` in Xcode and run on a simulator or device.
- **API Key**: The app requires an OpenAI API key entered via the in-app Settings screen; it is stored in Keychain under service name `com.aiapp.openai`.

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
    ProviderFactory.swift
  Repositories/  — ConversationRepository (in-memory, thread-safe via NSLock)

Infrastructure/
  Network/       — NetworkClient (URLSession-based), APIEndpoint, HTTPMethod,
                   NetworkError, NetworkLogger (protocol), OSNetworkLogger
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel,
                   MessageHistoryStore (@MainActor)

App/
  DependencyContainer.swift  — Manual DI root, @MainActor ObservableObject
```

## Agent Types

Defined in `AgentType.swift` (enum with `CaseIterable`):

| Case | Description |
|------|-------------|
| `general` | Universal assistant, no tools |
| `weather` | Uses `get_weather` tool, returns plain text |
| `weatherJSON` | Uses `get_weather` tool, always returns JSON |
| `bulletList` | Responds only with bullet lists (max 5 items), no tools |
| `stop13` | Stops generation when the string `"13"` appears (stop sequence demo) |

Each `AgentType` provides: `systemPrompt`, `icon` (SF Symbol), `description`, `availableTools`, and optionally `stopWords`.

## Key Patterns

**Dependency Injection**: `DependencyContainer` (injected via `.environmentObject`) wires all layers together using `lazy var` properties and factory methods. ViewModels are created on-demand via `make*ViewModel()` methods. `MessageHistoryStore` is a `lazy var` property on the container and passed into `ChatViewModel`.

**Agent / Tool Flow**:
1. `CreateAgentUseCase` creates a `DefaultAgent` wrapping an `LLMProvider` + `ToolExecutor`.
2. `SendMessageUseCase.execute()` sends the user message, then calls `agent.executeToolsAndContinue()` if the response requires tool use.
3. `Agent` protocol extension (in `Agent.swift`) provides default `sendMessage` and `executeToolsAndContinue` implementations — tool calls are dispatched to `DefaultToolExecutor`. `maxTokens` is capped at **1000** in both calls.

**Tool implementations** (`DefaultToolExecutor`) use **mock services** — `DefaultWeatherService`, `DefaultCalculatorService`, `DefaultSearchService` — returning simulated data with artificial delays. Tools are enabled per agent type via `AgentType.availableTools` (weather agents have `get_weather` enabled; others return `[]`).

**Message History**: `MessageHistoryStore` persists sent messages to `UserDefaults` (key `"messageHistory"`). `ChatView` shows history chips above the input field — tapping a chip fills the input, the ✕ button deletes the entry.

**Network Logging**: `NetworkLogger` protocol with `OSNetworkLogger` implementation (uses `os.Logger`). Injected into `NetworkClient` via `DependencyContainer`.

**OpenAI Provider**: Uses model `gpt-4-turbo-preview` by default. Supports `tools`, `temperature`, `maxTokens`, and `stop` sequences.

## Adding New Agent Types

1. Add a case to `AgentType` with `systemPrompt`, `icon`, `description`, `availableTools`, and (optionally) `stopWords`.
2. If the agent needs a new tool: implement the tool in `DefaultToolExecutor`, add its `ToolDefinition` factory in `ToolDefinition.swift`, and register it in `canExecute(toolName:)`.

## Adding a New LLM Provider

Conform to `LLMProvider`, add a case to `ProviderType`, and handle it in `ProviderFactory`.
