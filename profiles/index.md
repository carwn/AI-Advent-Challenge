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

## Detection Rules

1. Read the user's request.
2. Match against **Triggers** above (keywords / intent).
3. If matched — announce the profile name, then read the profile file and follow it strictly.
4. If multiple profiles match — prefer the most specific one (Bug Fix > Research > New Agent).
5. If no profile matches — continue without a profile (no announcement needed).
