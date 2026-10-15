import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/models/conversation.dart';
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

/// A file as the picker returns it: [read] stands in for the platform read,
/// which fails for revoked access or a vanished file. [size] is what the
/// picker reports up front (null when it can't say); [statSize] is what a
/// follow-up `length()` finds out.
base class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.read, {this.size, this.statSize});

  final Future<Uint8List> Function() read;
  final int? size;
  final int? statSize;

  @override
  final String name;

  @override
  Uri get uri => Uri.file('/picked/$name');

  @override
  XFile get xFile => XFile(uri.toFilePath());

  @override
  int? lengthSync() => size;

  @override
  Future<int?> length() async => statSize;

  @override
  Future<Uint8List> readAsBytes() => read();

  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(read());
}

// 1x1 PNG
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Widget _wrap(ChatProvider chat,
    {ModelProvider? models,
    ImagePicker? picker,
    Future<PlatformFile?> Function()? filePicker}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: models ?? ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ChatInput(imagePicker: picker, filePicker: filePicker),
      ),
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

    testWidgets('camera photos are downscaled when picked', (tester) async {
      final picker = newPicker();
      camera(picker).thenAnswer((_) async => null);
      await pumpWithVision(tester, picker);

      await choose(tester, 'Camera');

      verify(() => picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 85,
          )).called(1);
    });

    testWidgets('gallery photos are downscaled when picked', (tester) async {
      final picker = newPicker();
      gallery(picker).thenAnswer((_) async => []);
      await pumpWithVision(tester, picker);

      await choose(tester, 'Photo library');

      verify(() => picker.pickMultiImage(
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 85,
          )).called(1);
    });

    test('the limits are named constants with the agreed values', () {
      expect(maxTextAttachmentBytes, 1024 * 1024);
      expect(maxImageAttachmentBytes, 10 * 1024 * 1024);
      expect(maxPickedImageDimension, 1024);
      expect(pickedImageQuality, 85);
    });

    test('classifyPickedFile separates cancel from an unreadable file', () {
      final file = _PickedFile('notes.txt', () async => Uint8List(0));
      expect(classifyPickedFile(null, null), PickedFileStatus.cancelled);
      expect(classifyPickedFile(file, null), PickedFileStatus.unreadable);
      expect(
        classifyPickedFile(file, Uint8List.fromList([104, 105])),
        PickedFileStatus.ok,
      );
    });

    test('readPickedFile returns the bytes, or null when they cannot be read',
        () async {
      final bytes = Uint8List.fromList([104, 105]);
      expect(
        await readPickedFile(_PickedFile('notes.txt', () async => bytes)),
        bytes,
      );
      expect(
        await readPickedFile(_PickedFile(
          'notes.txt',
          () => Future.error(const FileSystemException('Permission denied')),
        )),
        isNull,
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

  group('attachment size limits', () {
    const textMessage =
        'That file is too large — text attachments are limited to 1 MB';
    const imageMessage =
        'That file is too large — image attachments are limited to 10 MB';

    /// Picks [file] through the attach button on a chat whose model [vision]
    /// may or may not read images.
    Future<ChatProvider> attach(WidgetTester tester, PlatformFile file,
        {bool vision = true}) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.createConversation('llava');
      final models = await _modelsWith(tester, 'llava', vision: vision);
      await tester.pumpWidget(
          _wrap(chat, models: models, filePicker: () async => file));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      return chat;
    }

    Uint8List bytes(int length) => Uint8List.fromList(List.filled(length, 0x61));

    testWidgets('a text file over 1 MB is refused without being read',
        (tester) async {
      var read = false;
      final chat = await attach(
        tester,
        _PickedFile('log.txt', () async {
          read = true;
          return bytes(1);
        }, size: maxTextAttachmentBytes + 1),
      );

      expect(find.text(textMessage), findsOneWidget);
      expect(chat.pendingFileName, isNull);
      expect(read, isFalse);
    });

    testWidgets('a size found by asking the file counts too', (tester) async {
      var read = false;
      final chat = await attach(
        tester,
        _PickedFile('log.txt', () async {
          read = true;
          return bytes(1);
        }, statSize: maxTextAttachmentBytes + 1),
      );

      expect(find.text(textMessage), findsOneWidget);
      expect(chat.pendingFileName, isNull);
      expect(read, isFalse);
    });

    testWidgets('a text file of unknown size is refused once it is read',
        (tester) async {
      final chat = await attach(
        tester,
        _PickedFile('log.txt', () async => bytes(maxTextAttachmentBytes + 1)),
      );

      expect(find.text(textMessage), findsOneWidget);
      expect(chat.pendingFileName, isNull);
    });

    testWidgets('a text file of exactly 1 MB is attached', (tester) async {
      final chat = await attach(
        tester,
        _PickedFile('log.txt', () async => bytes(maxTextAttachmentBytes),
            size: maxTextAttachmentBytes),
      );

      expect(find.byType(SnackBar), findsNothing);
      expect(chat.pendingFileName, 'log.txt');
    });

    testWidgets('an image file over 10 MB is refused without being read',
        (tester) async {
      var read = false;
      final chat = await attach(
        tester,
        _PickedFile('huge.png', () async {
          read = true;
          return bytes(1);
        }, size: maxImageAttachmentBytes + 1),
      );

      expect(find.text(imageMessage), findsOneWidget);
      expect(chat.pendingFileName, isNull);
      expect(read, isFalse);
    });

    testWidgets('an image file of unknown size is refused once it is read',
        (tester) async {
      final chat = await attach(
        tester,
        _PickedFile('huge.png', () async => bytes(maxImageAttachmentBytes + 1)),
      );

      expect(find.text(imageMessage), findsOneWidget);
      expect(chat.pendingFileName, isNull);
    });

    testWidgets('images get the larger limit, not the text one',
        (tester) async {
      // 2 MB: too big for a text file, fine for a photo.
      final size = 2 * maxTextAttachmentBytes;
      final chat = await attach(
        tester,
        _PickedFile('photo.png', () async => bytes(size), size: size),
      );

      expect(find.byType(SnackBar), findsNothing);
      expect(chat.pendingFileName, 'photo.png');
    });

    testWidgets('a small text file is still attached', (tester) async {
      final chat = await attach(
        tester,
        _PickedFile('notes.txt', () async => bytes(12), size: 12),
      );

      expect(chat.pendingFileName, 'notes.txt');
      expect(find.byType(SnackBar), findsNothing);
    });

    test('pickedFileSize asks the file only when the picker had no size',
        () async {
      expect(await pickedFileSize(_PickedFile('a', () async => bytes(1), size: 5, statSize: 9)), 5);
      expect(await pickedFileSize(_PickedFile('a', () async => bytes(1), statSize: 9)), 9);
      expect(await pickedFileSize(_PickedFile('a', () async => bytes(1))), isNull);
    });
  });

  group('composer text per chat', () {
    ChatProvider twoChats() {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'a', model: 'llama3', title: 'A'),
        Conversation(id: 'b', model: 'llama3', title: 'B'),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);
      return chat;
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    Future<void> showChat(WidgetTester tester, ChatProvider chat, int index) async {
      chat.setActiveConversation(chat.conversations[index]);
      await tester.pumpAndSettle();
    }

    testWidgets('half-typed text stays with its chat', (tester) async {
      final chat = twoChats();
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'half a thought');
      await showChat(tester, chat, 1);
      expect(fieldText(tester), isEmpty);

      await tester.enterText(find.byType(TextField), 'something else');
      await showChat(tester, chat, 0);
      expect(fieldText(tester), 'half a thought');

      await showChat(tester, chat, 1);
      expect(fieldText(tester), 'something else');
      expect(chat.composerTextFor('a'), 'half a thought');
      expect(chat.composerTextFor('b'), 'something else');
    });

    testWidgets('clearing the field forgets the text', (tester) async {
      final chat = twoChats();
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oops');
      await tester.enterText(find.byType(TextField), '');
      await showChat(tester, chat, 1);
      await showChat(tester, chat, 0);

      expect(fieldText(tester), isEmpty);
      expect(chat.composerTextFor('a'), isEmpty);
    });

    testWidgets('sending clears the chat\'s remembered text', (tester) async {
      final chat = twoChats();
      chat.setService(_answeringService());
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(fieldText(tester), isEmpty);
      expect(chat.composerTextFor('a'), isEmpty);
      expect(chat.activeConversation!.messages.first.content, 'hello there');

      await showChat(tester, chat, 1);
      await showChat(tester, chat, 0);
      expect(fieldText(tester), isEmpty);
    });

    testWidgets('sending from one chat leaves the other\'s text alone',
        (tester) async {
      final chat = twoChats();
      chat.setService(_answeringService());
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'for later');
      await showChat(tester, chat, 1);
      await tester.enterText(find.byType(TextField), 'send this');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      await showChat(tester, chat, 0);
      expect(fieldText(tester), 'for later');
    });

    testWidgets('a starter-chip draft fills the field and is remembered too',
        (tester) async {
      final chat = twoChats();
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      chat.setDraft('Summarize the following:\n\n');
      await tester.pumpAndSettle();
      expect(fieldText(tester), 'Summarize the following:\n\n');
      expect(chat.composerTextFor('a'), 'Summarize the following:\n\n');

      await showChat(tester, chat, 1);
      expect(fieldText(tester), isEmpty);
      await showChat(tester, chat, 0);
      expect(fieldText(tester), 'Summarize the following:\n\n');
    });

    testWidgets('a rebuilt input shows the remembered text', (tester) async {
      final chat = twoChats();
      chat.setComposerText('a', 'from before');
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'from before');
    });

    testWidgets('the field is empty again once no chat is open', (tester) async {
      final chat = twoChats();
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'typed');

      await chat.deleteAllConversations();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      chat.createConversation('llama3');
      await tester.pumpAndSettle();
      expect(fieldText(tester), isEmpty);
    });
  });

  group('accessibility', () {
    void testSemantics(
        String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await body(tester);
        } finally {
          semantics.dispose();
        }
      });
    }

    Size touchSize(WidgetTester tester, Finder finder) =>
        tester.getSemantics(finder).rect.size;

    Future<ChatProvider> pumpComposer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.createConversation('llava');
      chat.addPendingImage(_png);
      chat.addPendingImage(_png);
      chat.setPendingFile('notes.txt', _png, 'text/plain');
      final models = ModelProvider();
      final service = MockOllamaService();
      when(() => service.fetchModels()).thenAnswer((_) async => ['llava']);
      when(() => service.fetchModelInfo(any())).thenAnswer((_) async =>
          <String, dynamic>{
            'capabilities': ['completion', 'vision', 'thinking', 'tools'],
          });
      await models.fetchModels(service);
      await tester.pump();
      chat.setSearxngUrl('http://search.local');
      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a question');
      await tester.pumpAndSettle();
      return chat;
    }

    testSemantics('every control is labeled and a 48 dp target',
        (tester) async {
      await pumpComposer(tester);

      for (final label in ['Attach image', 'Attach file', 'Send message']) {
        final size = touchSize(tester, find.byTooltip(label));
        expect(size, const Size(48, 48), reason: label);
      }
      for (final label in ['Remove image 1', 'Remove image 2', 'Remove file']) {
        final size = touchSize(tester, find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(tester.getSize(find.byType(TextField)).height,
          greaterThanOrEqualTo(48));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testSemantics('the feature chips are labeled 48 dp toggles',
        (tester) async {
      final chat = await pumpComposer(tester);

      final think = find.bySemanticsLabel('Think');
      final search = find.bySemanticsLabel('Search');
      for (final chip in [think, search]) {
        final size = touchSize(tester, chip);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(
          tester.getSemantics(search),
          matchesSemantics(
            label: 'Search',
            isButton: true,
            hasSelectedState: true,
            hasTapAction: true,
          ));

      // The effort badge inside the pill is an action of the chip, not a
      // node of its own that is too small to hit.
      final thinkData = tester.getSemantics(think).getSemanticsData();
      expect(thinkData.value, 'auto');
      expect(thinkData.customSemanticsActionIds, hasLength(1));
      expect(
          CustomSemanticsAction.getAction(
                  thinkData.customSemanticsActionIds!.single)!
              .label,
          'Change thinking effort');

      // Touch: the whole 48 dp row toggles, the badge cycles the level.
      expect(chat.activeConversation!.webSearchEnabled, isFalse);
      await tester.tapAt(tester.getRect(search).center - const Offset(0, 20));
      await tester.pump();
      expect(chat.activeConversation!.webSearchEnabled, isTrue);

      await tester.tap(find.text('AUTO'));
      await tester.pump();
      expect(chat.activeConversation!.thinkingLevel, 'low');
      expect(chat.activeConversation!.thinkingEnabled, isNull);
    });

    testSemantics('the stop button is labeled while a reply streams',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final controller = StreamController<ChatStreamEvent>();
      final service = MockOllamaService();
      when(() => service.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => controller.stream);
      when(() => service.cancelStream()).thenReturn(null);
      chat.setService(service);
      chat.createConversation('llama3');
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'go');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();

      expect(find.byTooltip('Send message'), findsNothing);
      expect(touchSize(tester, find.byTooltip('Stop generating')),
          const Size(48, 48));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.tap(find.byTooltip('Stop generating'));
      await tester.pump();
      verify(() => service.cancelStream()).called(1);
      // (The cancelled stream has no listener, so close() would never finish.)
      unawaited(controller.close());
      await tester.pumpAndSettle();
      expect(chat.isStreaming, isFalse);
    });

    testSemantics('the remove buttons remove what they say', (tester) async {
      final chat = await pumpComposer(tester);
      expect(chat.pendingImages, hasLength(2));

      await tester.tap(find.bySemanticsLabel('Remove image 1'));
      await tester.pump();
      expect(chat.pendingImages, hasLength(1));

      await tester.tap(find.bySemanticsLabel('Remove file'));
      await tester.pump();
      expect(chat.pendingFileName, isNull);
    });

    testSemantics('the composer is as tall as it was', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      chat.createConversation('llama3');
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      // 48 dp targets sit inside the old 5 dp padding rather than adding to
      // it: 41 dp field + 2 x 5 dp padding + 2 dp border.
      final bar = find.ancestor(
          of: find.byType(TextField), matching: find.byType(AnimatedContainer));
      expect(tester.getSize(bar.first).height, 53);
    });
  });
}
