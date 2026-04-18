# 20 задач для тестирования автономных агентов

Все задачи проверены по реальному коду проекта (апрель 2026).
Критерий «готово» — конкретный, проверяемый.

---

## Новые фичи

### 1. Экспорт чата в Markdown
**Статус**: не реализовано  
Добавить кнопку «Поделиться» в toolbar `ChatView`. При нажатии — формировать `.md`-строку из всех сообщений и открывать `ShareLink` / `UIActivityViewController`.  
**Готово**: файл `.md` открывается через стандартный шаринг iOS.

### 2. Поиск по сообщениям в чате
**Статус**: не реализовано  
Добавить `.searchable()` к `ChatView`. При вводе строки фильтровать `messages` или скроллить к первому совпадению.  
**Готово**: введённая фраза находится среди сообщений, нерелевантные скрыты или подсвечены.

### 3. Счётчик символов под полем ввода
**Статус**: не реализовано  
Рядом с кнопкой отправки (или под `TextField`) отображать `"\(text.count) симв."` серым цветом, обновляется в реальном времени.  
**Готово**: счётчик виден и меняется при наборе текста.

### 4. Кнопка «Копировать» по long-press на сообщении
**Статус**: не реализовано  
Добавить `.contextMenu` к `MessageRow` с пунктом «Копировать текст» (`UIPasteboard.general.string = message.content`).  
**Готово**: текст попадает в буфер обмена после long-press → «Копировать».

### 5. `NotepadAgent` — агент-блокнот
**Статус**: не реализовано  
Новый `final class NotepadAgent: BaseAgent` с инструментом `save_note(title, content)`. Заметки сохраняются в `AgentState/notes/<title>.txt`. Зарегистрировать в `DependencyContainer`.  
**Готово**: после команды «Сохрани заметку: …» файл появляется в `AgentState/notes/`, следующий запрос «покажи заметки» возвращает список.

### 6. `DeepSeek` провайдер
**Статус**: не реализовано  
Создать `Data/Providers/DeepSeek/DeepSeekProvider.swift` + `DeepSeekModels.swift`. Эндпоинт `api.deepseek.com/v1/chat/completions` (OpenAI-совместимый формат). Добавить кейс в `ProviderType` с ценой.  
**Готово**: модель появляется в Settings, интеграционный тест проходит.

### 7. Алерт об ошибке сети в `ChatView`
**Статус**: не реализовано (ошибки молча глотаются в `ChatViewModel`)  
Когда `agent.send()` бросает ошибку — показывать `.alert` с текстом ошибки. `ChatViewModel` должен публиковать `@Published var errorMessage: String?`.  
**Готово**: при недоступном API появляется алерт с описанием ошибки.

### 8. `LazyVStack` для длинных чатов
**Статус**: не реализовано (используется `VStack`)  
В `ChatView` заменить `VStack` внутри `ScrollView` на `LazyVStack`, чтобы рендерить только видимые сообщения.  
**Готово**: в чате с 200+ сообщениями нет зависания при открытии, `instruments` показывает отложенный рендер.

---

## Рефакторинг

### 9. Разбить `DependencyContainer.swift` на extensions
**Статус**: 247 строк, один монолитный class  
Разбить на: `DependencyContainer+Agents.swift`, `DependencyContainer+ViewModels.swift`, `DependencyContainer+Persistence.swift`. Основной файл должен содержать только свойства и `init`.  
**Готово**: основной файл < 60 строк, проект компилируется без ошибок.

### 10. Вынести сетевые константы в `NetworkConstants.swift`
**Статус**: строки `"data: "`, `"[DONE]"`, таймауты разбросаны по `NetworkClient.swift`  
Создать `Infrastructure/Network/NetworkConstants.swift` с `enum NetworkConstants`. Заменить все магические строки.  
**Готово**: в `NetworkClient.swift` нет строковых литералов SSE-протокола.

### 11. Унифицировать `[String: AnyCodableValue]` и `JSONObject` в `MCPModels`
**Статус**: оба типа используются вперемешку (`MCPTool.inputSchema` — `[String: AnyCodableValue]?`, аргументы в `MCPAgent` — тоже)  
Заменить все вхождения `[String: AnyCodableValue]` на `JSONObject` там, где используется как словарь верхнего уровня.  
**Готово**: `[String: AnyCodableValue]` не встречается вне определения `JSONObject` и `AnyCodableValue`.

### 12. Добавить `Sendable` к `Message` и `Conversation`
**Статус**: модели передаются между акторами без `Sendable`-аннотации, Swift 6 будет ругаться  
Добавить `Sendable` conformance (или `@unchecked Sendable`) к `Message`, `Conversation`, `AgentResponse`.  
**Готово**: проект компилируется с `-strict-concurrency=complete` без предупреждений по этим типам.

---

## Тесты

### 13. Unit-тесты `CalculatorService`
**Статус**: не существует  
Файл `AI Advent Challenge Tests/CalculatorServiceTests.swift`. Покрыть: сложение, вычитание, умножение, деление, деление на ноль.  
**Готово**: 5 тест-кейсов, все зелёные при `xcodebuild test`.

### 14. Unit-тест `SlidingWindowContextCompressionPolicy`
**Статус**: не существует  
Создать `Conversation` с 10 сообщениями, вызвать `compress()`, проверить что `apiConversation.messages.count == windowSize + 1` (system + 5).  
**Готово**: assertion проходит, `xcodebuild test` зелёный.

### 15. Unit-тест `BranchConversationUseCase`
**Статус**: не существует  
Проверить: `parentId` ветки == `id` оригинала, `id` ветки уникален, `title` содержит «↳».  
**Готово**: 3 assertion, `xcodebuild test` зелёный.

### 16. Unit-тест `ConversationPersistenceService`
**Статус**: не существует  
Сохранить `Conversation`, загрузить, сравнить `messages.count`. Затем удалить — убедиться что файл исчез.  
**Готово**: save/load/delete цикл проходит, `xcodebuild test` зелёный.

### 17. Unit-тест `SummaryContextCompressionPolicy`
**Статус**: не существует  
Создать разговор > 500 токенов (мок LLM), вызвать `compress()`, проверить что `summaryUsage != nil` и `apiConversation` содержит summary-сообщение.  
**Готово**: тест с моком `SendMessageToLMMUseCase` проходит.

### 18. Интеграционный тест `RAGService`
**Статус**: не существует  
Запрос `"What is @State?"` → `results.count >= 1`, `maxScore >= 0.60`. Работает полностью офлайн (CoreML).  
**Готово**: тест проходит без сети, `xcodebuild test` зелёный.

---

## Документация

### 19. Doc-comments для всех методов протокола `LLMProvider`
**Статус**: есть частично — некоторые свойства задокументированы, методы — нет  
Добавить `///`-комментарии ко всем методам: `complete(...)`, `streamComplete(...)`, `minMaxTokens`, `supportsStreaming`. Swift DocC формат с `- Parameter` и `- Returns`.  
**Готово**: Xcode Quick Help показывает описание для каждого метода и свойства протокола.

### 20. `ARCHITECTURE.md` — диаграмма слоёв проекта
**Статус**: не существует (есть `CLAUDE.md` для Claude, но нет читаемой для людей диаграммы)  
Создать `ARCHITECTURE.md` в корне с: ASCII-диаграммой слоёв (Domain → Data → Infrastructure → Presentation), таблицей всех 12 агентов, описанием flow сообщения от UI до LLM и обратно.  
**Готово**: файл существует, содержит диаграмму и все 12 агентов из `DependencyContainer`.

---

## Краткая сводка

| Категория | Задачи |
|-----------|--------|
| Новые фичи | 1–8 |
| Рефакторинг | 9–12 |
| Тесты | 13–18 |
| Документация | 19–20 |

Все задачи проверены: не реализованы в коде на момент составления списка.
