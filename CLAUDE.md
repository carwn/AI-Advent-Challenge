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

There are no test targets, lint scripts, or CI configuration in this repo currently.

## Architecture

The project follows **Clean Architecture** with these layers (all under `AI Advent Challenge/`):

```
Domain/          — Pure Swift, no framework dependencies
  Models/        — Message, Conversation, AgentType, AgentResponse, ToolDefinition
  Protocols/     — Agent, LLMProvider, ToolExecutor
  UseCases/      — CreateAgentUseCase, SendMessageUseCase

Data/
  Providers/     — OpenAIProvider (implements LLMProvider), ProviderFactory
  Repositories/  — ConversationRepository (in-memory, thread-safe via NSLock)

Infrastructure/
  Network/       — NetworkClient (URLSession-based), APIEndpoint, HTTPMethod, NetworkError
  Security/      — KeychainService, APIKeyManager
  Tools/         — DefaultToolExecutor with mock WeatherService, CalculatorService, SearchService

Presentation/
  Views/         — ContentView, ChatView, AgentSelectionView, SettingsView, MessageRow
  ViewModels/    — ChatViewModel, AgentSelectionViewModel, SettingsViewModel (@MainActor)

App/
  DependencyContainer.swift  — Manual DI root, @MainActor ObservableObject
```

## Key Patterns

**Dependency Injection**: `DependencyContainer` (injected via `.environmentObject`) wires all layers together using `lazy var` properties and factory methods. ViewModels are created on-demand via `make*ViewModel()` methods.

**Agent / Tool Flow**:
1. `CreateAgentUseCase` creates a `DefaultAgent` wrapping an `LLMProvider` + `ToolExecutor`.
2. `SendMessageUseCase.execute()` sends the user message, then calls `agent.executeToolsAndContinue()` if the response requires tool use.
3. `DefaultAgent` protocol extension provides default `sendMessage` and `executeToolsAndContinue` implementations — tool calls are dispatched to `DefaultToolExecutor`.

**Tool implementations** (`DefaultToolExecutor`) currently use **mock services** — `DefaultWeatherService`, `DefaultCalculatorService`, `DefaultSearchService` — returning simulated data with artificial delays. The tool definitions in `AgentType.availableTools` are **commented out**, so tool calling is disabled by default.

**Adding a new agent type**: Add a case to `AgentType`, provide `systemPrompt`, `icon`, `description`, and `availableTools`. Implement any new tool in `DefaultToolExecutor` and add its `ToolDefinition`.

**Adding a new LLM provider**: Conform to `LLMProvider`, add a case to `ProviderType`, and handle it in `ProviderFactory`.
