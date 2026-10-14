import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import 'package:llm_disco_test1/widgets/chat_input.dart';
import '../helpers/mocks.dart';

class MockImagePicker extends Mock implements ImagePicker {}

/// A picked photo whose bytes can't be read (revoked access, vanished file).
class _UnreadableXFile extends XFile {
  _UnreadableXFile() : super('/picked/photo.jpg');

  @override
  Future<Uint8List> readAsBytes() =>
      Future.error(const FileSystemException('Permission denied'));
}

// 1x1 PNG
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Widget _wrap(ChatProvider chat,
    {ModelProvider? models, ImagePicker? picker}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: models ?? ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: ChatInput(imagePicker: picker)),
    ),
  );
}

/// A ModelProvider that already knows [model]'s capabilities.
Future<ModelProvider> _modelsWith(WidgetTester tester, String model,
    {required bool vision}) async {
  final models = ModelProvider();
  final service = MockOllamaService();
  when(() => service.fetchModels()).thenAnswer((_) async => [model]);
  when(() => service.fetchModelInfo(any())).thenAnswer((_) async =>
      <String, dynamic>{
        'capabilities': ['completion', if (vision) 'vision'],
      });
  await models.fetchModels(service);
  await tester.pump(); // let the capability fetch it started finish
  expect(models.getCapabilities(model), isNotNull);
  return models;
}

MockOllamaService _answeringService() {
  final service = MockOllamaService();
  when(() => service.streamChat(
        any(),
        any(),
        think: any(named: 'think'),
        tools: any(named: 'tools'),
        numCtx: any(named: 'numCtx'),
      )).thenAnswer((_) => Stream.fromIterable(
      [const ChatStreamEvent(contentToken: 'ok', done: true)]));
  return service;
}

void main() {
  setUpAll(() {
    registerFallbackValue(ImageSource.camera);
  });

  testWidgets('a draft set while the input is mounted fills the field',
      (tester) async {
    final chat = ChatProvider();
    addTearDown(chat.dispose);
    chat.createConversation('llama3');

    await tester.pumpWidget(_wrap(chat));
    await tester.pumpAndSettle();

    // Empty-state starter chip fires this after the input is already built.
    chat.setDraft('Summarize this: ');
    await tester.pumpAndSettle();

    // Must not throw "markNeedsBuild during build" and must show the draft.
    expect(tester.takeException(), isNull);
    expect(find.text('Summarize this: '), findsOneWidget);
  });

  group('pending images and the current model', () {
    testWidgets('are not sent to a model without vision', (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.setService(_answeringService());
      chat.createConversation('llama3');
      chat.addPendingImage(_png);
      final models = await _modelsWith(tester, 'llama3', vision: false);

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'what is this?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // Nothing was sent; text and attachment are still there to act on.
      expect(chat.activeConversation!.messages, isEmpty);
      expect(chat.pendingImages, hasLength(1));
      expect(find.text('what is this?'), findsOneWidget);
      expect(find.textContaining("can't read images"), findsOneWidget);
    });

    testWidgets('an attached image file is held back the same way',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.setService(_answeringService());
      chat.createConversation('llama3');
      chat.setPendingFile('photo.png', _png, 'image/png');
      final models = await _modelsWith(tester, 'llama3', vision: false);

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'what is this?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(chat.activeConversation!.messages, isEmpty);
      expect(chat.pendingFileName, 'photo.png');
    });

    testWidgets('go through on a vision model', (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.setService(_answeringService());
      chat.createConversation('llava');
      chat.addPendingImage(_png);
      final models = await _modelsWith(tester, 'llava', vision: true);

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'what is this?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      final sent = chat.activeConversation!.messages.first;
      expect(sent.content, 'what is this?');
      expect(sent.images, [_png]);
    });

    testWidgets('are not blocked while capabilities are still unknown',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.setService(_answeringService());
      chat.createConversation('llama3');
      chat.addPendingImage(_png);

      // ModelProvider knows nothing about llama3 yet.
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'what is this?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(chat.activeConversation!.messages.first.images, [_png]);
    });
  });

  group('composer layout', () {
    testWidgets('a very long model name keeps the empty field one line',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<double> fieldHeight(String model) async {
        final chat = ChatProvider();
        addTearDown(chat.dispose);
        chat.createConversation(model);
        await tester.pumpWidget(_wrap(chat));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(TextField)).height;
      }

      final short = await fieldHeight('llama3');
      final long = await fieldHeight(
          'hf.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M');

      expect(long, short);
    });
  });

  group('attachment pickers', () {
    Future<ChatProvider> pumpWithVision(
        WidgetTester tester, MockImagePicker picker) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.createConversation('llava');
      final models = await _modelsWith(tester, 'llava', vision: true);
      await tester.pumpWidget(_wrap(chat, models: models, picker: picker));
      await tester.pumpAndSettle();
      return chat;
    }

    Future<void> choose(WidgetTester tester, String source) async {
      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source));
      await tester.pumpAndSettle();
    }

    MockImagePicker newPicker() => MockImagePicker();

    When<Future<XFile?>> camera(MockImagePicker picker) =>
        when(() => picker.pickImage(
              source: ImageSource.camera,
              maxWidth: any(named: 'maxWidth'),
              maxHeight: any(named: 'maxHeight'),
              imageQuality: any(named: 'imageQuality'),
            ));

    When<Future<List<XFile>>> gallery(MockImagePicker picker) =>
        when(() => picker.pickMultiImage(
              maxWidth: any(named: 'maxWidth'),
              maxHeight: any(named: 'maxHeight'),
              imageQuality: any(named: 'imageQuality'),
            ));

    testWidgets('a camera failure shows a message instead of throwing',
        (tester) async {
      final picker = newPicker();
      camera(picker).thenAnswer(
          (_) async => throw PlatformException(code: 'no_available_camera'));
      final chat = await pumpWithVision(tester, picker);

      await choose(tester, 'Camera');

      expect(tester.takeException(), isNull);
      expect(find.textContaining("Couldn't open the camera"), findsOneWidget);
      expect(chat.pendingImages, isEmpty);
    });

    testWidgets('a cancelled camera stays silent', (tester) async {
      final picker = newPicker();
      camera(picker).thenAnswer((_) async => null);
      final chat = await pumpWithVision(tester, picker);

      await choose(tester, 'Camera');

      expect(find.byType(SnackBar), findsNothing);
      expect(chat.pendingImages, isEmpty);
    });

    testWidgets('a picked photo is attached', (tester) async {
      final picker = newPicker();
      final bytes = base64Decode(_png);
      camera(picker).thenAnswer((_) async => XFile.fromData(bytes));
      final chat = await pumpWithVision(tester, picker);

      await choose(tester, 'Camera');

      expect(chat.pendingImages, [_png]);
    });

    testWidgets('a gallery failure shows a message', (tester) async {
      final picker = newPicker();
      gallery(picker).thenAnswer(
          (_) async => throw PlatformException(code: 'photo_access_denied'));
      final chat = await pumpWithVision(tester, picker);

      await choose(tester, 'Photo library');

      expect(tester.takeException(), isNull);
      expect(find.textContaining("Couldn't open the photo library"),
          findsOneWidget);
      expect(chat.pendingImages, isEmpty);
    });

    testWidgets('a picked photo that cannot be read shows a message',
        (tester) async {
      final picker = newPicker();
      gallery(picker).thenAnswer((_) async => [_UnreadableXFile()]);
      final chat = await pumpWithVision(tester, picker);

      await choose(tester, 'Photo library');

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(chat.pendingImages, isEmpty);
    });

    test('classifyPickedFile separates cancel from an unreadable file', () {
      expect(classifyPickedFile(null), PickedFileStatus.cancelled);
      expect(classifyPickedFile(FilePickerResult([])),
          PickedFileStatus.cancelled);
      expect(
        classifyPickedFile(FilePickerResult(
            [PlatformFile(name: 'notes.txt', size: 12)])),
        PickedFileStatus.unreadable,
      );
      expect(
        classifyPickedFile(FilePickerResult([
          PlatformFile(
              name: 'notes.txt', size: 2, bytes: Uint8List.fromList([104, 105])),
        ])),
        PickedFileStatus.ok,
      );
    });
  });

  group('pending thumbnails', () {
    testWidgets('malformed base64 shows a broken-image icon', (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.createConversation('llava');
      chat.addPendingImage('definitely !!! not base64');

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
