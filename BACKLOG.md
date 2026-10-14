# Backlog

Known bugs, unfinished wiring, and proposed features/design work. Grouped by
priority; checkboxes track what's done.

---

## 1. Bugs (reliability pass)

### 1.1 Mid-stream Ollama errors are silently swallowed
`lib/services/ollama_service.dart` → `streamChat()`

Each NDJSON line is parsed, but an error line like
`{"error": "model requires more system memory"}` has no `message` field and no
`done: true`, so nothing is yielded — the stream just quietly ends. The user
sees a partial or empty response that looks complete. Ollama emits these lines
mid-stream on OOM, model-load failure, etc.

**Fix:** check `json['error']` on every parsed line and `throw Exception(...)`
so the existing error path (error bubble + retry) kicks in.

- [x] Fixed

### 1.2 Pulling a model resets the selected model
`lib/providers/model_provider.dart` → `fetchModels()`

`_selectedModel = _models.first` runs unconditionally, and `pullModel()` calls
`fetchModels()` on completion — so downloading a new model silently switches
the dropdown to whatever sorts first.

**Fix:** keep the current selection when it's still present in the refreshed
list; only fall back to `first` when the selection is gone or unset.

- [x] Fixed

### 1.3 Tool-calling history malformed on the second round-trip
`lib/models/chat_message.dart` → `toApiMap()` and
`lib/providers/chat_provider.dart` → `_streamResponse()`

Two related problems:
1. `toApiMap()` never includes `tool_calls`, so the assistant message that
   requested the tool is sent back without it.
2. The `messagesToSend` filter drops assistant messages with empty content —
   which is exactly what a pure tool-call response is.

Result: the follow-up request contains a `tool` message with no preceding
assistant `tool_calls` message. Models with strict tool templates (qwen3,
llama3.1+) degrade or re-call the tool in a loop.

**Fix:** include `tool_calls` in `toApiMap()`; keep assistant messages in
`messagesToSend` when they carry tool calls, even with empty content.

- [x] Fixed

### 1.4 A killed app can wipe all chat history
`lib/services/storage_service.dart` → `saveConversations()`

`conversations.json` is rewritten in place — every second during streaming. If
Android kills the process mid-write the file is truncated, and
`loadConversations()` catches the parse error and returns `[]`: every
conversation is gone, silently. `_persist()` is also fired unawaited from a
periodic timer, so writes can overlap.

**Fix:** write to a temp file then rename (atomic on the same filesystem);
serialize writes with an in-flight guard. Optionally keep a `.bak` of the last
good file and fall back to it on parse failure.

- [x] Fixed

### 1.5 Tapping Stop early shows a scary error
`lib/providers/chat_provider.dart` → `sendMessage()` catch block

`stopStreaming()` closes the HTTP client, which throws inside the stream. If no
content had arrived yet, the catch renders
`[Error: ClientException: Connection closed...]` with a retry chip. A
user-initiated cancel should show "Stopped" (or just remove the empty bubble),
not an error.

**Fix:** set a `_cancelRequested` flag in `stopStreaming()`; in the catch,
when the flag is set, remove the empty assistant message (or mark it
interrupted) instead of writing an error.

- [x] Fixed

### 1.6 SearXNG URLs with a path prefix break
`lib/services/ollama_service.dart` → `searchSearXNG()`

`Uri.parse(searxngUrl).replace(path: '/search')` discards a base path like
`http://host/searxng`, so reverse-proxied SearXNG instances can't be used.

**Fix:** resolve `/search` relative to the configured URL instead of replacing
the path.

- [x] Fixed

---

## 2. Dead code: sampling parameters plumbed but disconnected

`Conversation` carries `temperature`, `topK`, `topP`, `repeatPenalty`, `seed`
(all serialized), and `OllamaService.streamChat()` accepts all five and builds
the `options` map — but `ChatProvider._streamResponse()` only ever passes
`numCtx`, and no UI sets any of them. Both ends exist; the middle is missing.

**Fix:** add a per-chat "Model parameters" sheet (reachable from the ctx pill
or app bar) with temperature / top_p / top_k / repeat_penalty / seed, and pass
them through in `_streamResponse()` (one call-site change).

- [x] Wired up — Chat settings sheet (ctx pill) covers system prompt,
  context size, and all sampling parameters

---

## 3. Feature proposals

- [x] **Per-conversation system prompt.** In the Chat settings sheet;
  injected per-request as a leading `system` message.
- [x] **Edit & resend a user message.** Long-press a user bubble →
  Edit & resend; history is rewritten from that point.
- [x] **Delete a message pair.** Long-press a user bubble → Delete message
  & response (with confirmation).
- [x] **Auto-reconnect on launch.** Saved server is attempted automatically;
  the sidebar's "Connection settings" opens the form without reconnecting.
- [x] **Model-generated chat titles.** Background `/api/generate` call after
  the first exchange; never overwrites a manual rename.
- [x] **Context usage in the ctx pill.** Shows "3.1K / 8K" from
  `prompt_eval_count` + `eval_count`.
- [x] **Switch model mid-conversation.** Tap the model name in the app bar.
- [x] **Search/filter conversations** in the sidebar (titles + message text).
- [x] **Export as Markdown** alongside JSON (long-press a conversation).
- [x] **Optional auth header** (Bearer/Basic) in connection settings.
  Bare tokens become `Bearer <token>`; values with a scheme are used as-is;
  never sent to ollama.com or SearXNG.
- [x] **Multi-image attach** with per-image remove, gallery multi-pick, and
  a camera source; bubbles render every image; retry/edit restore them all.

---

## 4. Design proposals

- [x] **Scroll-to-bottom pill.** Floating "↓" button appears after scrolling
  ~400 px away from the newest message.
- [x] **Undo for deleted conversations.** Inline "Chat deleted — UNDO" bar in
  the drawer for 5 s after a swipe-delete.
- [x] **Model picker as a bottom sheet.** Shared graphite sheet (footer +
  app-bar switcher) with capability badges for cached models.
- [x] **Streaming polish.** Markdown re-rendered on a 250 ms throttle with a
  blinking `▍` tail cursor; no more end-of-stream reflow jump.
- [x] **Empty-state suggestion chips.** Three starter chips pre-fill the
  input via a provider draft.
- [x] **Haptics** on send, stop, and chip toggles.

---

## 4b. Post-review fixes (found while auditing the change set)

### Streaming state was not scoped to its conversation
`lib/providers/chat_provider.dart`

`_streamResponse()` captured its conversation locally, but the error handler
in `sendMessage()` read `_activeConversation`. Switching chats mid-stream and
then hitting a stream failure applied the fallout to the **wrong**
conversation — overwriting its last answer with the error text, or removing
it outright. `isStreaming` and `lastTokensPerSec` were also provider-global,
so an unrelated chat showed the Stop button and a stale tok/s label.

**Fixed:** the conversation is captured once in `sendMessage()` and threaded
through streaming, error handling and titling. `_streamingConversationId`
scopes `isStreaming` to the chat on screen; `isAnyStreaming` blocks a second
concurrent send (the service shares one cancellable client) and dims the send
button in other chats. `lastTokensPerSec` moved onto `Conversation`.
Deleting the streaming conversation now cancels its stream.

- [x] Fixed

### Conversation ids could collide
`createConversation()` used `millisecondsSinceEpoch` alone, so two chats made
in the same millisecond shared an id — breaking delete-by-id (removes both)
and producing duplicate `Dismissible` keys. Now timestamp + counter, checked
against existing ids.

- [x] Fixed

### Dead code / unreachable features
- [x] `lib/screens/pull_model_screen.dart` deleted — superseded by
  `ModelManagementScreen`, referenced nowhere.
- [x] Backup & restore UI added to the sidebar, wiring up the already-written
  `exportAllConversations` / `importConversations` / `deleteAll`, which had no
  entry point. Delete-all sits behind a confirmation dialog.

## 5. Maintenance

- [x] **`flutter_markdown` is discontinued** (archived by the Flutter team).
  Migrated to `flutter_markdown_plus` (now 1.0.12).
- [x] **Dependency bumps:** `image_picker` → 1.1.2, `file_picker` → 11.0.2,
  `google_fonts` → 8.2.0, `flutter_lints` → 6.0.0, plus patch bumps
  (`markdown`, `path_provider`, `mocktail`, `cupertino_icons`).
  - `file_picker` 11 moved to **static** methods — `FilePicker.pickFiles(...)`
    replaced `FilePicker.platform.pickFiles(...)` at both call sites.
  - `flutter_lints` 6 added `unnecessary_underscores` and
    `use_null_aware_elements`; fixed rather than suppressed (the
    `'Authorization': ?authHeader` map syntax is the modern form).
- [ ] **`share_plus` is stuck at 10.1.4.** Every release from 11 up needs
  `win32 ^6`, while all stable `file_picker` versions pin `win32 ^5.9`, so
  pub cannot solve for both. Only `file_picker` 12 (currently beta) lifts
  this — not worth a beta dependency for a share API that already works.
- [x] **Android toolchain:** Gradle 8.12 → 8.14.3, AGP 8.9.1 → 8.11.1,
  Kotlin 2.1.0 → 2.2.20. Clears the "support will soon be dropped" warnings
  Flutter printed on every build.
- [x] **Release signing** is wired: `android/app/build.gradle.kts` reads
  `android/key.properties` (gitignored) and falls back to debug signing when
  absent, so a fresh clone still builds.
- [x] Auto-title truncation is grapheme-aware (`characters`) and collapses
  newlines/whitespace.
- [x] Sidebar row renamed to "Switch server" (it disconnects and returns to
  the connection screen without auto-reconnecting).
- [x] Error detection now uses a serialized `isError` flag on `ChatMessage`;
  error bubbles are also excluded from the history sent to the model.

---

## 6. Second audit pass

Found by re-reading the whole codebase against the docs. All fixed, with
test coverage added alongside.

### Keyboard send silently dropped the message while another chat generated
`lib/widgets/chat_input.dart` → `_send()`

The send button is dimmed for `busyElsewhere`, but the keyboard's send
action bypassed it: `_send()` checked only `isStreaming` (this chat), then
cleared the field — and `sendMessage()` refused the send on its
one-generation-at-a-time guard. Text gone without feedback.

**Fix:** `_send()` bails on `isAnyStreaming` *before* clearing the field.

- [x] Fixed

### Cancelling a model pull showed "Pull failed"
`lib/providers/model_provider.dart`

`cancelPull()` closes the HTTP client, so the in-flight stream throws — and
`pullModel()`'s catch wrote that exception into `_pullError` *after* the
cancel had already reset state. A deliberate cancel rendered as a failed
download in the sheet and the Discover tab banner.

**Fix:** a `_pullCancelRequested` flag (same pattern as the chat stream's
cancel) makes the catch recognize the abort and stay quiet.

- [x] Fixed

### A failure mid-tool-loop left malformed history behind
`lib/providers/chat_provider.dart` → `sendMessage()`

When the post-web_search stream died, the error landed on the newest empty
assistant bubble — which is filtered out of resent history — while tool
results from earlier iterations survived it. The next request could carry
tool results whose parent bubble was gone (BACKLOG §1.3's malformation,
reintroduced through the error path).

**Fix:** every exchange records a history mark after appending its user
message; on failure the tail rolls back to that mark and is rebuilt —
partial content kept as interrupted, thinking-only stops kept as
"[Stopped]", genuine failures get one clean error bubble. Preserved
partials drop their tool calls along with their discarded results.

- [x] Fixed

### Retrying or editing the opening message downgraded its title
`lib/providers/chat_provider.dart`

Auto-titling fired whenever the conversation was back to a single user
message — so retrying or editing an opener overwrote the model-generated
title with the truncated fallback.

**Fix:** the fallback title is only ever written while the title is still
the untouched "New Chat" default; editing an opener moves a *fallback*
title in step with the edit, and retries/edits never touch generated or
manual titles.

- [x] Fixed

### Destructive helpers mutated history before their guards ran
`lib/providers/chat_provider.dart`

`retryLastMessage()` / `editAndResend()` truncated the conversation first
and called `sendMessage()` second — whose early returns (no service,
another chat generating) left the truncation unreverted. Relatedly,
`disconnectService()` / `clear()` dropped the service without stopping an
in-flight stream, leaving an orphaned generation running against a
detached conversation.

**Fix:** both helpers refuse disconnected/busy states before touching
history; disconnect/clear call `stopStreaming()` first.

- [x] Fixed

### One int in stored JSON could fail the entire history load
`lib/models/conversation.dart` → `fromJson()`

`json['temperature'] as double?` throws when jsonDecode yields an int
(`"temperature": 1`) — one bad field made `loadConversations()` fall back
to the `.bak`, and killed imports outright.

**Fix:** all numeric fields coerce through `num?` (`?.toDouble()` /
`?.toInt()`), so ints degrade instead of throwing.

- [x] Fixed

### Connection input accepted junk, auth failures looked like dead servers
`lib/providers/connection_provider.dart`, `lib/services/ollama_service.dart`

No port validation (empty or non-numeric ports built malformed URLs that
failed downstream with generic errors), bare IPv6 literals broke URL
construction, and a wrong API token surfaced as "Could not connect" —
indistinguishable from a typo'd IP.

**Fix:** provider validates ip/port up front (ports 1–65535) and brackets
IPv6; `OllamaService.testConnectionStatus()` exposes the raw HTTP status so
401/403 report as authentication failures, unreachable as unreachable.
Service creation is injectable for tests.

- [x] Fixed

### Smaller loose ends
- [x] `deleteModel()` leaked an unclosed `http.Client` per call — now closed
  in a `finally`.
- [x] Think/Search chip toggles mutated the conversation without persisting;
  they now go through `conversationSettingsChanged()` like every other
  setting.
- [x] Saving a connection profile with an existing name replaces it instead
  of piling up duplicates.
- [x] The launcher icon source moved from the git-excluded `FYP/` snapshot to
  `assets/app_icon.png` (a fresh clone couldn't regenerate icons).
- [x] Whole-repo CRLF churn fixed at the source: working tree restored to LF
  and `.gitattributes` now forces LF for all text files.
- [x] Branding/doc drift cleaned up: `MaterialApp.title` says "LLM Disco"
  (was "LLM Chat"), pubspec description filled in, theme comment corrected,
  README no longer claims syntax-highlighted code blocks or the
  discontinued `flutter_markdown`.
