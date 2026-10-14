import 'dart:async';
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
  group('OllamaService.pullModel', () {
    String line(Map<String, dynamic> m) => '${jsonEncode(m)}\n';

    test('yields progress events and completes after success', () async {
      final server = await _serve((req) {
        req.response
          ..write(line({'status': 'pulling manifest'}))
          ..write(line({
            'status': 'pulling abc',
            'digest': 'sha256:abc',
            'total': 1000,
            'completed': 250,
          }))
          ..write(line({'status': 'success'}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final events = await service.pullModel('m').toList();

      expect(events.map((e) => e.status),
          ['pulling manifest', 'pulling abc', 'success']);
      expect(events[1].digest, 'sha256:abc');
      expect(events[1].total, 1000);
      expect(events[1].completed, 250);
      expect(events[1].progress, 0.25);
    });

    test('throws when a line carries an error field', () async {
      // e.g. a model name that doesn't exist: Ollama answers 200 and puts
      // the failure in the stream. It must not read as a finished pull.
      final server = await _serve((req) {
        req.response
          ..write(line({'status': 'pulling manifest'}))
          ..write(line(
              {'error': 'pull model manifest: file does not exist'}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final seen = <String>[];
      final pulling = service.pullModel('nope').map((e) {
        seen.add(e.status);
        return e;
      }).toList();

      await expectLater(
        pulling,
        throwsA(predicate((e) =>
            e.toString().contains('pull model manifest: file does not exist'))),
      );
      expect(seen, ['pulling manifest']);
    });

    test('throws when the stream ends without a success status', () async {
      final server = await _serve((req) {
        req.response
          ..write(line({'status': 'pulling manifest'}))
          ..write(line({
            'status': 'pulling abc',
            'total': 1000,
            'completed': 10,
          }));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');

      await expectLater(
        service.pullModel('m').toList(),
        throwsA(predicate((e) => e.toString().contains('success'))),
      );
    });

    test('accepts non-int numbers and skips only malformed lines', () async {
      final server = await _serve((req) {
        req.response
          ..write('not json at all\n')
          ..write('{"status":"pulling abc","total":1.5e3,"completed":500.0}\n')
          ..write('\n')
          ..write(line({'status': 'success'}));
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final events = await service.pullModel('m').toList();

      expect(events.map((e) => e.status), ['pulling abc', 'success']);
      expect(events.first.total, 1500);
      expect(events.first.completed, 500);
    });

    test('throws on a non-200 response', () async {
      final server = await _serve((req) {
        req.response
          ..statusCode = 500
          ..write('boom');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');

      await expectLater(
        service.pullModel('m').toList(),
        throwsA(predicate((e) => e.toString().contains('HTTP 500'))),
      );
    });

    test('cancelPull aborts an in-flight pull with an error, not completion',
        () async {
      // ModelProvider relies on a cancelled pull *throwing* so it can route
      // it through its user-cancel path instead of "Pull complete".
      final server = await _serve((req) async {
        req.response.bufferOutput = false;
        req.response.write(line({'status': 'pulling manifest'}));
        await req.response.flush();
        // Never finishes on its own.
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      final first = Completer<void>();
      final outcome = Completer<Object?>();
      service.pullModel('m').listen(
        (_) {
          if (!first.isCompleted) first.complete();
        },
        onError: (Object e) {
          if (!outcome.isCompleted) outcome.complete(e);
        },
        onDone: () {
          if (!outcome.isCompleted) outcome.complete(null);
        },
      );

      await first.future;
      service.cancelPull();

      expect(await outcome.future.timeout(const Duration(seconds: 5)),
          isNotNull);
    });
  });

  group('OllamaService.deleteModel', () {
    test('sends DELETE with the model name', () async {
      String? method;
      String? body;
      final server = await _serve((req) async {
        method = req.method;
        body = await utf8.decoder.bind(req).join();
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');
      await service.deleteModel('llama3');

      expect(method, 'DELETE');
      expect(jsonDecode(body!), {'model': 'llama3'});
    });

    test('throws on a non-200 response', () async {
      final server = await _serve((req) {
        req.response
          ..statusCode = 404
          ..write('model not found');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final service = OllamaService('http://127.0.0.1:${server.port}');

      await expectLater(
        service.deleteModel('ghost'),
        throwsA(predicate((e) => e.toString().contains('HTTP 404'))),
      );
    });
  });

  group('OllamaService.normalizeSearxngUrl', () {
    String? n(String s) => OllamaService.normalizeSearxngUrl(s);

    test('keeps a well-formed http(s) URL', () {
      expect(n('http://192.168.1.5:8080'), 'http://192.168.1.5:8080');
      expect(n('https://searx.example.com/searxng'),
          'https://searx.example.com/searxng');
    });

    test('prepends http:// when the scheme is missing', () {
      expect(n('192.168.1.5:8080'), 'http://192.168.1.5:8080');
      expect(n('localhost:8080'), 'http://localhost:8080');
      expect(n('searx.local'), 'http://searx.local');
    });

    test('strips surrounding whitespace', () {
      expect(n('  http://searx.local:8080 \n'), 'http://searx.local:8080');
    });

    test('rejects what cannot be a SearXNG base URL', () {
      expect(n(''), isNull);
      expect(n('   '), isNull);
      expect(n('ftp://searx.local'), isNull);
      expect(n('http://'), isNull);
      expect(n('http://searx.local:notaport'), isNull);
      expect(n('http://my host'), isNull);
    });
  });

  group('OllamaService.parseSearchResults', () {
    // Trimmed-down shape of ollama.com/search: one <a> block per model.
    const html = """
<ul>
  <li><a href="/library/llama3.2" class="group w-full">
    <h2><span>llama3.2</span></h2>
    <p class="max-w-lg">Meta&#39;s Llama 3.2 goes small
       with 1B &amp; 3B models.
       Try &lt;b&gt; &quot;quoted&quot; &#x41;&#66; &apos;x&apos;</p>
    <span class="inline-flex tag">tools</span>
    <span class="inline-flex tag">1b &amp; 3b</span>
    <span>2.1M Pulls</span>
  </a></li>
  <li><a href="/library/llama3.2"><p>Second anchor, same model</p></a></li>
  <li><a href="/library/phi4"><p>Plain description</p><span>500K Pulls</span></a></li>
  <li><a href="/library/nodesc"><span>1.2K Pulls</span></a></li>
</ul>
""";

    test('decodes entities and keeps multi-line descriptions', () {
      final results = OllamaService.parseSearchResults(html);

      expect(results.first.name, 'llama3.2');
      expect(
        results.first.description,
        'Meta\'s Llama 3.2 goes small with 1B & 3B models. '
        'Try <b> "quoted" AB \'x\'',
      );
      expect(results.first.pullCount, '2.1M');
      expect(results.first.tags, ['tools', '1b & 3b']);
    });

    test('dedupes repeated anchors by name', () {
      final results = OllamaService.parseSearchResults(html);

      expect(results.map((r) => r.name), ['llama3.2', 'phi4', 'nodesc']);
      // First occurrence wins.
      expect(results.first.description, startsWith('Meta'));
    });

    test('models without a description get null', () {
      final results = OllamaService.parseSearchResults(html);

      expect(results.last.description, isNull);
      expect(results.last.pullCount, '1.2K');
    });

    test('decodes in a single pass and leaves bogus references alone', () {
      final results = OllamaService.parseSearchResults(
          '<a href="/library/x"><p>&amp;lt; &#0; &#xD800; &#99999999; ok</p></a>');

      expect(results.single.description, '&lt; &#0; &#xD800; &#99999999; ok');
    });

    test('returns an empty list for a page with no models', () {
      expect(OllamaService.parseSearchResults('<html></html>'), isEmpty);
    });
  });
}
