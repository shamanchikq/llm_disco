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
  final int? promptEvalCount;

  const ChatStreamEvent({
    this.contentToken,
    this.thinkingToken,
    this.toolCalls,
    this.done = false,
    this.evalCount,
    this.evalDuration,
    this.promptEvalCount,
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

  /// Full Authorization header value (e.g. "Bearer xyz") sent to every
  /// Ollama endpoint. Never applied to external requests (ollama.com,
  /// SearXNG).
  final String? authHeader;
  http.Client? _activeClient;
  http.Client? _pullClient;

  OllamaService(this.baseUrl, {this.authHeader});

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Authorization': ?authHeader,
      };

  Stream<ChatStreamEvent> streamChat(
    String model,
    List<ChatMessage> messages, {
    // true/false toggles thinking; a string ("low", "medium", "high",
    // "max") sets the effort level. Omit for models without the thinking
    // capability — Ollama rejects the parameter for them.
    Object? think,
    List<Map<String, dynamic>>? tools,
    int? numCtx,
    double? temperature,
    int? topK,
    double? topP,
    double? repeatPenalty,
    int? seed,
  }) async* {
    _activeClient = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat'),
      );
      request.headers.addAll(_jsonHeaders);

      final body = <String, dynamic>{
        'model': model,
        'messages': messages.map((m) => m.toApiMap()).toList(),
        'stream': true,
      };

      if (think != null) {
        body['think'] = think;
      }

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
      }

      // Build options map with any provided parameters
      final options = <String, dynamic>{};
      if (numCtx != null) options['num_ctx'] = numCtx;
      if (temperature != null) options['temperature'] = temperature;
      if (topK != null) options['top_k'] = topK;
      if (topP != null) options['top_p'] = topP;
      if (repeatPenalty != null) options['repeat_penalty'] = repeatPenalty;
      if (seed != null) options['seed'] = seed;
      if (options.isNotEmpty) {
        body['options'] = options;
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
        final Map<String, dynamic> json;
        try {
          json = jsonDecode(chunk) as Map<String, dynamic>;
        } catch (_) {
          // skip malformed JSON lines
          continue;
        }

        // Ollama reports failures (OOM, model load errors, …) as an
        // in-stream error line on an otherwise-200 response — surface it
        // instead of letting the response look complete.
        final error = json['error'];
        if (error != null) {
          throw Exception('Ollama error: $error');
        }

        final message = json['message'] as Map<String, dynamic>?;
        final isDone = json['done'] as bool? ?? false;

        final evalCount = isDone ? json['eval_count'] as int? : null;
        final evalDuration = isDone ? json['eval_duration'] as int? : null;
        final promptEvalCount =
            isDone ? json['prompt_eval_count'] as int? : null;

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
            promptEvalCount: promptEvalCount,
          );
        } else if (isDone) {
          yield ChatStreamEvent(
            done: true,
            evalCount: evalCount,
            evalDuration: evalDuration,
            promptEvalCount: promptEvalCount,
          );
        }
      }
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  /// One-shot, non-streaming completion via /api/generate. Used for
  /// utility prompts like conversation-title generation.
  Future<String> generateText(String model, String prompt,
      {Object? think}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/generate'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'stream': false,
            'think': ?think,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Failed to generate: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final error = data['error'];
    if (error != null) {
      throw Exception('Ollama error: $error');
    }
    return data['response'] as String? ?? '';
  }

  Future<List<String>> fetchModels() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tags'),
      headers: _jsonHeaders,
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
      headers: _jsonHeaders,
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
    // Append /search to whatever path the instance lives under (e.g.
    // http://host/searxng) instead of replacing it.
    final base = Uri.parse(searxngUrl);
    final basePath =
        base.path.endsWith('/') ? base.path : '${base.path}/';
    final uri = base.replace(
      path: '${basePath}search',
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
        headers: _jsonHeaders,
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
      request.headers.addAll(_jsonHeaders);
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
    request.headers.addAll(_jsonHeaders);
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

    // Match model entries, each model is in an <a href="/library/..."> block
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

      // Extract pull count
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

  /// Full tag list from `ollama.com/library/{model}/tags` — includes every
  /// quantization variant (can be 100+ entries for popular models).
  Future<List<ModelTag>> fetchModelTagsFromWeb(String modelName) async {
    return _fetchTagsFromPage(
      Uri.https('ollama.com', '/library/$modelName/tags'),
      modelName,
    );
  }

  /// Curated tag list from the model's overview page
  /// (`ollama.com/library/{model}`) — the handful of primary tags the
  /// website shows, without quantization variants.
  Future<List<ModelTag>> fetchCuratedModelTags(String modelName) async {
    return _fetchTagsFromPage(
      Uri.https('ollama.com', '/library/$modelName'),
      modelName,
    );
  }

  Future<List<ModelTag>> _fetchTagsFromPage(Uri uri, String modelName) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tags: HTTP ${response.statusCode}');
    }

    final html = response.body;
    final tags = <ModelTag>[];
    final seen = <String>{};

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
