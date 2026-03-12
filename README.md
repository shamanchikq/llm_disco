# LLM Disco

A Flutter mobile app for chatting with locally-hosted large language models via [Ollama](https://ollama.com). Run your favourite model on your PC and talk to it from your phone over your home network — no cloud, no subscriptions, no data leaving your device.

Built as my Final Year Project at Maynooth University (BSc Computer Science, 2025–2026).

---

## Features

- **Real-time streaming chat** — tokens appear as they are generated
- **Model selection** — switch between any model installed on your Ollama server
- **Image & file attachments** — send photos or files to vision-capable models
- **Extended thinking mode** — see the model's reasoning process (Qwen, QwQ)
- **Web search** — models can search the web via a self-hosted SearXNG instance using tool-calling
- **Model management** — browse, download, and delete models directly from the app
- **Conversation persistence** — chats are saved locally on your device
- **Multiple server profiles** — save and switch between different Ollama instances
- **Dark theme** with syntax-highlighted code blocks

## Requirements

- Android device (iOS untested but may work via Flutter)
- A PC on the same local network running [Ollama](https://ollama.com) with at least one model installed
- *(Optional)* A self-hosted [SearXNG](https://docs.searxng.org/) instance for web search

## Getting Started

```bash
git clone https://github.com/shamanchikq/llm_disco.git
cd llm_disco
flutter pub get
flutter run
```

On first launch, enter your PC's local IP address and the Ollama port (default `11434`), then tap **Connect**.

## Build APK

```bash
flutter build apk
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

## Project Structure

```
lib/
  screens/       # ConnectionScreen, MainScreen, ModelManagementScreen
  providers/     # ChatProvider, ConnectionProvider, ModelProvider
  services/      # OllamaService (HTTP), StorageService (JSON persistence)
  models/        # ChatMessage, Conversation, ModelCapabilities
  widgets/       # MessageBubble, ChatInput, ChatSidebar, CodeBlockBuilder
  theme/         # App theme and custom ThemeExtension
test/            # Unit tests, widget tests, screen tests
```

## Tech Stack

- **Flutter / Dart** — UI and app logic
- **Provider** — state management
- **http** — streaming HTTP for Ollama API
- **flutter_markdown** — markdown rendering in chat
- **image_picker / file_picker** — attachments
- **path_provider** — local JSON storage

## Note on Commit History

The repository was created partway through development, so the early design and prototyping work is not reflected in the commit history. Active development ran from late 2024; commits start from February 2026.
