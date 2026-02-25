import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../models/ollama_search_result.dart';

class ChatStreamEvent {
  final String? contentToken;
  final String? thinkingToken;
  final List<Map<String, dynamic>>? toolCalls;
  final bool done;
  final int? evalCount;
  final int? evalDuration;

  const ChatStreamEvent({
    this.contentToken,
    this.thinkingToken,
    this.toolCalls,
    this.done = false,
    this.evalCount,
    this.evalDuration,
  });
}

class PullProgressEvent {
  final String status;
  final String? digest;
  final int? total;
  final int? completed;

  const PullProgressEvent({
    required this.status,
    this.digest,
    this.total,
    this.completed,
  });

  double? get progress =>
      (total != null && total! > 0 && completed != null)
          ? completed! / total!
          : null;
}

class OllamaService {
  final String baseUrl;
  http.Client? _activeClient;
  http.Client? _pullClient;

  OllamaService(this.baseUrl);

  Stream<ChatStreamEvent> streamChat(
    String model,
    List<ChatMessage> messages, {
    bool? think,
    String? thinkingLevel,
    List<Map<String, dynamic>>? tools,
    int? numCtx,
  }) async* {
    _activeClient = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat'),
      );
      request.headers['Content-Type'] = 'application/json';

      final body = <String, dynamic>{
        'model': model,
        'messages': messages.map((m) => m.toApiMap()).toList(),
        'stream': true,
      };

      if (think == true) {
        body['think'] = true;
      }

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
      }

      if (numCtx != null) {
        body['options'] = {'num_ctx': numCtx};
      }

      request.body = jsonEncode(body);

      final response = await _activeClient!.send(request);

      if (response.statusCode != 200) {
        final responseBody = await response.stream.bytesToString();
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.trim().isEmpty) continue;
        try {
          final json = jsonDecode(chunk) as Map<String, dynamic>;
          final message = json['message'] as Map<String, dynamic>?;
          final isDone = json['done'] as bool? ?? false;

          final evalCount = isDone ? json['eval_count'] as int? : null;
          final evalDuration = isDone ? json['eval_duration'] as int? : null;

          if (message != null) {
            final content = message['content'] as String? ?? '';
            final thinking = message['thinking'] as String?;
            final rawToolCalls = message['tool_calls'] as List<dynamic>?;

            List<Map<String, dynamic>>? parsedToolCalls;
            if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
              parsedToolCalls = rawToolCalls
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }

            yield ChatStreamEvent(
              contentToken: content.isNotEmpty ? content : null,
              thinkingToken: thinking != null && thinking.isNotEmpty
                  ? thinking
                  : null,
              toolCalls: parsedToolCalls,
              done: isDone,
              evalCount: evalCount,
              evalDuration: evalDuration,
            );
          } else if (isDone) {
            yield ChatStreamEvent(
              done: true,
              evalCount: evalCount,
              evalDuration: evalDuration,
            );
          }
        } catch (_) {
          // skip malformed JSON lines
        }
      }
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  Future<List<String>> fetchModels() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tags'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = data['models'] as List<dynamic>? ?? [];
      return models
          .map((m) => (m as Map<String, dynamic>)['name'] as String)
          .toList();
    } else {
      throw Exception('Failed to fetch models: HTTP ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchModelInfo(String model) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/show'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to fetch model info: HTTP ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> searchSearXNG(
    String searxngUrl,
    String query,
  ) async {
    final uri = Uri.parse(searxngUrl).replace(
      path: '/search',
      queryParameters: {'q': query, 'format': 'json'},
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      return results
          .take(5)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } else {
      throw Exception('SearXNG search failed: HTTP ${response.statusCode}');
    }
  }

  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/tags'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Stream<PullProgressEvent> pullModel(String modelName) async* {
    _pullClient = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/pull'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'model': modelName, 'stream': true});

      final response = await _pullClient!.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('HTTP ${response.statusCode}: $body');
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.trim().isEmpty) continue;
        try {
          final json = jsonDecode(chunk) as Map<String, dynamic>;
          yield PullProgressEvent(
            status: json['status'] as String? ?? '',
            digest: json['digest'] as String?,
            total: json['total'] as int?,
            completed: json['completed'] as int?,
          );
        } catch (_) {
          // skip malformed lines
        }
      }
    } finally {
      _pullClient?.close();
      _pullClient = null;
    }
  }

  Future<void> deleteModel(String name) async {
    final request = http.Request(
      'DELETE',
      Uri.parse('$baseUrl/api/delete'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({'model': name});

    final response = await http.Client().send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('Failed to delete model: HTTP ${response.statusCode}: $body');
    }
  }

  Future<List<OllamaSearchResult>> searchOllamaCom(String query) async {
    final uri = Uri.https('ollama.com', '/search', {'q': query});
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Search failed: HTTP ${response.statusCode}');
    }

    final html = response.body;
    final results = <OllamaSearchResult>[];

    // Match model entries — each model is in an <a href="/library/..."> block
    final blockPattern = RegExp(
      r'<a[^>]*href="/library/([^"]+)"[^>]*>([\s\S]*?)</a>',
    );

    for (final match in blockPattern.allMatches(html)) {
      final name = match.group(1) ?? '';
      final block = match.group(2) ?? '';

      // Extract description from <p> tags
      String? description;
      final descMatch = RegExp(r'<p[^>]*>(.*?)</p>').firstMatch(block);
      if (descMatch != null) {
        description = descMatch.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }

      // Extract pull count (e.g. "110M Pulls" or "1.2B Pulls")
      String? pullCount;
      final pullMatch = RegExp(r'([\d.]+[KMB]?)\s*Pull', caseSensitive: false).firstMatch(block);
      if (pullMatch != null) {
        pullCount = pullMatch.group(1);
      }

      // Extract tags from spans
      final tags = <String>[];
      final tagMatches = RegExp(r'<span[^>]*class="[^"]*tag[^"]*"[^>]*>(.*?)</span>').allMatches(block);
      for (final tm in tagMatches) {
        final tag = tm.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (tag != null && tag.isNotEmpty) tags.add(tag);
      }

      if (name.isNotEmpty) {
        results.add(OllamaSearchResult(
          name: name,
          description: description,
          pullCount: pullCount,
          tags: tags,
        ));
      }
    }

    return results;
  }

  Future<List<ModelTag>> fetchModelTagsFromWeb(String modelName) async {
    final uri = Uri.https('ollama.com', '/library/$modelName/tags');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tags: HTTP ${response.statusCode}');
    }

    final html = response.body;
    final tags = <ModelTag>[];
    final seen = <String>{};

    // Each tag is in an <a href="/library/modelName:tag"> block
    // Content: "modelName:tag \n hash • 3.3GB • 128K context window • ..."
    final blockPattern = RegExp(
      r'<a[^>]*href="/library/'
      '${RegExp.escape(modelName)}:([^"]+)"'
      r'[^>]*>([\s\S]*?)</a>',
    );

    for (final match in blockPattern.allMatches(html)) {
      final tagName = match.group(1) ?? '';
      final block = match.group(2) ?? '';

      if (tagName.isEmpty || seen.contains(tagName)) continue;
      seen.add(tagName);

      // Extract size like "3.3GB", "815MB", "17GB"
      String? size;
      final sizeMatch =
          RegExp(r'([\d.]+\s*(?:GB|MB|KB|TB))', caseSensitive: false)
              .firstMatch(block);
      if (sizeMatch != null) {
        size = sizeMatch.group(1);
      }

      tags.add(ModelTag(name: tagName, size: size));
    }

    return tags;
  }

  void cancelPull() {
    _pullClient?.close();
    _pullClient = null;
  }

  void cancelStream() {
    _activeClient?.close();
    _activeClient = null;
  }
}
