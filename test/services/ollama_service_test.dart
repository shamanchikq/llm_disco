import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';

// NOTE: no TestWidgetsFlutterBinding here — these tests do real HTTP
// against a local server, which the widget binding would block.

Future<HttpServer> _serve(void Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

void main() {
  group('OllamaService.streamChat', () {
    test('yields content tokens from NDJSON lines', () async {
      final server = await _serve((req) {
        req.response
          ..write('${jsonEncode({
                'message': {'role': 'assistant', 'content': 'Hel'},
                'done': false,
              })}\n')
          ..write('${jsonEncode({
                'message': {'role': 'assistant', 'content': 'lo'},
                'done': true,
              })}\n');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final events = await service
          .streamChat('m', [ChatMessage(role: 'user', content: 'hi')]).toList();

      final content =
          events.map((e) => e.contentToken ?? '').join();
      expect(content, 'Hello');
    });

    test('done event carries prompt_eval_count for context tracking',
        () async {
      final server = await _serve((req) {
        req.response.write('${jsonEncode({
              'message': {'role': 'assistant', 'content': 'hi'},
              'done': true,
              'eval_count': 20,
              'eval_duration': 1000000000,
              'prompt_eval_count': 100,
            })}\n');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final events = await service
          .streamChat('m', [ChatMessage(role: 'user', content: 'hi')]).toList();

      expect(events.last.promptEvalCount, 100);
      expect(events.last.evalCount, 20);
    });

    test('throws when a stream line carries an error field', () async {
      // Ollama reports OOM / model-load failures as an in-stream
      // {"error": ...} line on an otherwise-200 response. Silently
      // dropping it makes a failed response look complete.
      final server = await _serve((req) {
        req.response
          ..write('${jsonEncode({
                'message': {'role': 'assistant', 'content': 'par'},
                'done': false,
              })}\n')
          ..write('${jsonEncode({
                'error': 'model requires more system memory',
              })}\n');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final events =
          service.streamChat('m', [ChatMessage(role: 'user', content: 'hi')]);

      await expectLater(
        events.toList(),
        throwsA(predicate((e) =>
            e.toString().contains('model requires more system memory'))),
      );
    });
  });

  group('OllamaService auth header', () {
    test('is sent to Ollama endpoints when configured', () async {
      final seen = <String?>[];
      final server = await _serve((req) {
        seen.add(req.headers.value('authorization'));
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'models': []}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}',
          authHeader: 'Bearer secret-token');
      await service.fetchModels();
      await service
          .streamChat('m', [ChatMessage(role: 'user', content: 'hi')]).toList();

      expect(seen, ['Bearer secret-token', 'Bearer secret-token']);
    });

    test('is absent when not configured', () async {
      String? seen = 'unset';
      final server = await _serve((req) {
        seen = req.headers.value('authorization');
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'models': []}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      await service.fetchModels();

      expect(seen, isNull);
    });
  });

  group('OllamaService.generateText', () {
    test('posts a non-streaming generate request and returns the text',
        () async {
      String? capturedBody;
      final server = await _serve((req) async {
        capturedBody = await utf8.decoder.bind(req).join();
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'response': 'A Title'}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final result = await service.generateText('llama3', 'Name this chat',
          think: false);

      expect(result, 'A Title');
      expect(capturedBody, isNotNull);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['model'], 'llama3');
      expect(body['prompt'], 'Name this chat');
      expect(body['stream'], false);
      expect(body['think'], false);
    });
  });

  group('OllamaService.searchSearXNG', () {
    test('appends /search to a base URL with a path prefix', () async {
      late Uri requested;
      final server = await _serve((req) {
        requested = req.uri;
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'results': []}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://unused');
      await service.searchSearXNG(
          'http://127.0.0.1:${server.port}/searxng', 'flutter');

      expect(requested.path, '/searxng/search');
      expect(requested.queryParameters['q'], 'flutter');
      expect(requested.queryParameters['format'], 'json');
    });

    test('uses /search when the base URL has no path', () async {
      late Uri requested;
      final server = await _serve((req) {
        requested = req.uri;
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'results': []}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://unused');
      await service.searchSearXNG(
          'http://127.0.0.1:${server.port}', 'flutter');

      expect(requested.path, '/search');
    });
  });
}
