# Profiles Index

Use this index to detect which profile fits the user's request. Read the matching profile file and follow its instructions strictly.

## Bug Fix
**File**: `profiles/bug-fix.md`
**Triggers**: сообщение об ошибке, краш, баг, не работает, сломалось, падает, exception, crash, error, unexpected behavior, «не то поведение», «вылетает», «не компилируется», «билд фейлится»

## Research
**File**: `profiles/research.md`
**Triggers**: как устроено, объясни архитектуру, расскажи о, как работает, где находится, какие файлы, найди все места, покажи зависимости, не трогай код — просто объясни, покрытие тестами, какие эндпоинты, «how does X work», «where is X», «what is X»

## New Agent
**File**: `profiles/new-agent.md`
**Triggers**: добавь агента, создай нового агента, новый агент, реализуй агент, new agent, add agent, implement agent

## Unit Test Writer
**File**: `profiles/unit-test-writer.md`
**Triggers**: напиши тесты, покрой тестами, unit тесты, unit tests, добавь тесты, найди непокрытые модули, test coverage, написать тесты

## Unit Test Arbiter
**File**: `profiles/unit-test-arbiter.md`
**Triggers**: тест упал, тест красный, failing test, red test, тест не проходит, исправь тест, fix test, тест фейлится

## Smoke Writer
**File**: `profiles/smoke-writer.md`
**Triggers**: напиши сценарии, UI сценарии, smoke сценарии, пользовательские сценарии, smoke scenarios, создай сценарии для UI

## Smoke Runner
**File**: `profiles/smoke-runner.md`
**Triggers**: прогони smoke, запусти UI тесты, smoke тесты, протыкай UI, run smoke, UI smoke, прогони сценарии, протестируй UI

## Detection Rules

1. Read the user's request.
2. Match against **Triggers** above (keywords / intent).
3. If matched — announce the profile name, then read the profile file and follow it strictly.
4. If multiple profiles match — prefer the most specific one (Bug Fix > Unit Test Arbiter > Unit Test Writer > Smoke Runner > Smoke Writer > Research > New Agent).
5. If no profile matches — continue without a profile (no announcement needed).
