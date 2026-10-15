import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/widgets/message_bubble.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

/// `androidTapTargetGuideline`'s check at [size], minus read-only text
/// fields: selectable message text carries a long-press (to start selecting),
/// but it is content, not a control.
class _TapTargets extends MinimumTapTargetGuideline {
  const _TapTargets(Size size)
      : super(size: size, link: 'https://support.google.com/accessibility/android/answer/7101858');

  @override
  bool shouldSkipNode(SemanticsNode node) {
    final flags = node.getSemanticsData().flagsCollection;
    return super.shouldSkipNode(node) || (flags.isTextField && flags.isReadOnly);
  }
}

// 1x1 PNGs: red and blue.
const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
const _bluePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC';

void main() {
  group('MessageBubble.safeLinkTarget', () {
    test('allows http and https URLs with a host', () {
      expect(MessageBubble.safeLinkTarget('http://example.com/a?b=1'),
          Uri.parse('http://example.com/a?b=1'));
      expect(MessageBubble.safeLinkTarget('https://example.com'),
          Uri.parse('https://example.com'));
      expect(MessageBubble.safeLinkTarget('HTTPS://Example.com/x')?.scheme,
          'https');
    });

    test('refuses every other scheme', () {
      expect(MessageBubble.safeLinkTarget('tel:+123456789'), isNull);
      expect(MessageBubble.safeLinkTarget('sms:+123456789?body=hi'), isNull);
      expect(MessageBubble.safeLinkTarget('javascript:alert(1)'), isNull);
      expect(MessageBubble.safeLinkTarget('file:///etc/passwd'), isNull);
      expect(
          MessageBubble.safeLinkTarget('intent://x#Intent;scheme=a;end'),
          isNull);
      expect(MessageBubble.safeLinkTarget('myapp://open/deep'), isNull);
    });

    test('refuses scheme-less, hostless, null and malformed hrefs', () {
      expect(MessageBubble.safeLinkTarget('example.com/page'), isNull);
      expect(MessageBubble.safeLinkTarget('/relative/path'), isNull);
      expect(MessageBubble.safeLinkTarget('http:///nohost'), isNull);
      expect(MessageBubble.safeLinkTarget(''), isNull);
      expect(MessageBubble.safeLinkTarget(null), isNull);
      // Uri.parse throws on this one; the tap handler must not.
      expect(MessageBubble.safeLinkTarget('http://[::1'), isNull);
    });
  });

  group('MessageBubble', () {
    testWidgets('user message shows content', (tester) async {
      final msg = ChatMessage(role: 'user', content: 'Hello world');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('assistant message shows label and content', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Hi there');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // Flag header shows the model name (or fallback) in uppercase
      expect(find.text('ASSISTANT'), findsOneWidget);
      expect(
        find.textContaining('Hi there', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('error message shows retry button', (tester) async {
      bool retried = false;
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Connection failed',
        isError: true,
      );

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      // verify retry button works
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('thinking section renders and collapses', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'The answer is 42',
        thinking: 'Deep thought process here',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // thinking header should be there
      expect(find.text('Thinking'), findsOneWidget);

      // content should be hidden initially
      expect(find.text('Deep thought process here'), findsNothing);

      // tap to expand
      await tester.tap(find.text('Thinking'));
      await tester.pump();
      expect(find.text('Deep thought process here'), findsOneWidget);
    });

    testWidgets('assistant message shows copy button', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Some response');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets('user message shows visible copy and edit actions',
        (tester) async {
      bool edited = false;
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onEdit: () => edited = true),
      ));
      await tester.pump();

      // discoverable without long-pressing
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited, isTrue);
    });

    testWidgets('user message renders every attached image', (tester) async {
      // 1x1 transparent PNG
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final msg = ChatMessage(
        role: 'user',
        content: 'two pics',
        images: [png, png],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('user message without onEdit shows no edit action',
        (tester) async {
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('user message shows a delete action when onDelete is set',
        (tester) async {
      var deleted = false;
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(
          message: msg,
          onEdit: () {},
          onDelete: () => deleted = true,
        ),
      ));
      await tester.pump();

      // reachable without the long-press sheet (which SelectableText eats)
      expect(find.byTooltip('Delete'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      expect(deleted, isTrue);
    });

    testWidgets('user message without onDelete shows no delete action',
        (tester) async {
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onEdit: () {}),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('empty finished response still offers retry, not copy',
        (tester) async {
      var retried = false;
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(retried, isTrue);
    });

    testWidgets('empty response without onRetry shows no actions',
        (tester) async {
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    });

    testWidgets('a streaming bubble hides retry even with onRetry',
        (tester) async {
      final msg = ChatMessage(role: 'assistant', content: '');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, isStreaming: true, onRetry: () {}),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stop the typing animation
    });
  });

  group('markdown images', () {
    testWidgets('are never fetched: a placeholder replaces them',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Look: ![a chart](http://x.test/y.png?q=secret) done',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.text('a chart'), findsOneWidget);
    });

    testWidgets('file and scheme-less sources get a placeholder too',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![local](file:///etc/hostname)\n\n![rel](pics/a.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('local'), findsOneWidget);
      expect(find.text('rel'), findsOneWidget);
    });

    testWidgets('without alt text the placeholder shows the host',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![](https://img.example.org/p.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('img.example.org'), findsOneWidget);
    });

    testWidgets('tapping a placeholder is safe for any URL', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '![web](http://x.test/a.png)\n\n![local](file:///etc/hostname)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // http(s) goes to the launcher (absent in tests: the failure must be
      // swallowed); anything else is dropped before it gets that far.
      await tester.tap(find.text('web'));
      await tester.pump();
      await tester.tap(find.text('local'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long alt text is truncated, not overflowed',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final msg = ChatMessage(
        role: 'assistant',
        content: '![${'wide ' * 60}](http://x.test/a.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('are not fetched while streaming either', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'partial ![pic](http://x.test/y.png)',
      );

      await tester.pumpWidget(
          _wrap(MessageBubble(message: msg, isStreaming: true)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('pic'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // cancel the render timer
    });
  });

  group('attached image data', () {
    testWidgets('malformed base64 shows a broken-image icon, not an error',
        (tester) async {
      final msg = ChatMessage(
        role: 'user',
        content: 'bad pic',
        images: ['this is !!! not base64'],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('undecodable image bytes fall back to the broken icon',
        (tester) async {
      final msg = ChatMessage(
        role: 'user',
        content: 'garbage pic',
        images: [base64Encode([1, 2, 3, 4, 5, 6, 7, 8])],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      // The engine decodes outside the fake clock; give it real time.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('a reused bubble element shows the new message\'s image',
        (tester) async {
      Uint8List shownBytes() {
        final image = tester.widget<Image>(find.byType(Image));
        return (image.image as MemoryImage).bytes;
      }

      final first = ChatMessage(role: 'user', content: 'one', images: [_redPng]);
      final second =
          ChatMessage(role: 'user', content: 'two', images: [_bluePng]);

      await tester.pumpWidget(_wrap(MessageBubble(message: first)));
      expect(shownBytes(), base64Decode(_redPng));

      // Same widget type and position -> the element and its state are
      // reused for a different message, as in an unkeyed list.
      await tester.pumpWidget(_wrap(MessageBubble(message: second)));
      expect(shownBytes(), base64Decode(_bluePng));
    });
  });

  group('cut-off note', () {
    const note = 'Cut off — the model hit its length limit';

    testWidgets('an assistant reply that hit the length limit says so',
        (tester) async {
      final msg =
          ChatMessage(role: 'assistant', content: 'The story begins', cutOff: true);

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text(note), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      // under the content, above the action row
      final noteTop = tester.getTopLeft(find.text(note)).dy;
      expect(noteTop,
          greaterThan(tester.getBottomLeft(find.textContaining('The story begins',
                  findRichText: true)).dy));
      expect(noteTop, lessThan(tester.getTopLeft(find.byIcon(Icons.copy_rounded)).dy));
    });

    testWidgets('a complete reply has no note', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Done.');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text(note), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });

    testWidgets('thinking with no answer still shows it', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: '',
        thinking: 'Still working it out',
        cutOff: true,
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text(note), findsOneWidget);
    });

    testWidgets('a cut-off reply with a retry offers both', (tester) async {
      var retried = false;
      final msg = ChatMessage(role: 'assistant', content: 'Half an answ', cutOff: true);

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('Retry'));

      expect(find.text(note), findsOneWidget);
      expect(retried, isTrue);
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

    testSemantics('message actions are labeled 40 dp touch targets',
        (tester) async {
      await tester.pumpWidget(_wrap(Column(children: [
        MessageBubble(
          message: ChatMessage(role: 'user', content: 'hello'),
          onEdit: () {},
          onDelete: () {},
        ),
        MessageBubble(
          message: ChatMessage(role: 'assistant', content: 'Hi there'),
          onRetry: () {},
        ),
      ])));
      await tester.pump();

      for (final tooltip in ['Copy', 'Edit & resend', 'Delete', 'Retry']) {
        final buttons = find.byTooltip(tooltip);
        expect(buttons, findsWidgets, reason: tooltip);
        for (final button in buttons.evaluate()) {
          final size = touchSize(tester, find.byWidget(button.widget));
          expect(size.width, greaterThanOrEqualTo(40), reason: tooltip);
          expect(size.height, greaterThanOrEqualTo(40), reason: tooltip);
        }
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testSemantics('the error bubble\'s Retry is a labeled 48 dp target',
        (tester) async {
      var retried = false;
      final msg = ChatMessage(
          role: 'assistant', content: 'Connection failed', isError: true);

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      final retry = find.bySemanticsLabel('Retry');
      expect(retry, findsOneWidget);
      expect(touchSize(tester, retry).width, greaterThanOrEqualTo(48));
      expect(touchSize(tester, retry).height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(const _TapTargets(Size(48, 48))));

      // The transparent padding above the pill is part of the button.
      final pill = tester.getRect(find
          .ancestor(of: find.text('Retry'), matching: find.byType(Container))
          .first);
      final target = tester.getRect(retry);
      final inPadding = Offset(pill.center.dx, (target.top + pill.top) / 2);
      expect(pill.contains(inPadding), isFalse);
      expect(target.contains(inPadding), isTrue);
      await tester.tapAt(inPadding);
      expect(retried, isTrue);
    });

    testSemantics('thinking, code and image chips reach 40 dp',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        thinking: 'pondering',
        content: 'Look:\n\n```dart\nvoid main() {}\n```\n\n'
            '![a chart](https://example.com/chart.png)',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text('a chart'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(
          tester, meetsGuideline(const _TapTargets(Size(40, 40))));
    });

    testSemantics('a user bubble offers its actions as buttons only',
        (tester) async {
      var edited = false;
      await tester.pumpWidget(_wrap(MessageBubble(
        message: ChatMessage(role: 'user', content: 'My question'),
        onEdit: () => edited = true,
        onDelete: () {},
      )));
      await tester.pump();

      // The bubble's long-press duplicates the buttons below it, so it isn't
      // announced as a second, bubble-sized action: the only node with a
      // long-press left is the selectable text itself.
      final longPressable = <SemanticsData>[];
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.hasAction(SemanticsAction.longPress)) longPressable.add(data);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(RendererBinding.instance.renderViews.first.owner!.semanticsOwner!
          .rootSemanticsNode!);
      expect(longPressable, hasLength(1));
      expect(longPressable.single.flagsCollection.isTextField, isTrue);

      // ...but it still works for sighted users (on the bubble's padding; the
      // selectable text takes long-presses on itself).
      await tester.longPressAt(
          tester.getTopLeft(find.text('My question')) - const Offset(6, 6));
      await tester.pumpAndSettle();
      expect(find.text('Delete message & response'), findsOneWidget);
      await tester.tap(find.text('Edit & resend'));
      await tester.pumpAndSettle();
      expect(edited, isTrue);
    });
  });
}
