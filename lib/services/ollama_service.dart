import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class OllamaService {
  final String baseUrl;
  http.Client? _activeClient;

  OllamaService(this.baseUrl);

  Stream<String> streamChat(String model, List<ChatMessage> messages) async* {
    _activeClient = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': model,
        'messages': messages.map((m) => m.toApiMap()).toList(),
        'stream': true,
      });

      final response = await _activeClient!.send(request);

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
          final message = json['message'] as Map<String, dynamic>?;
          if (message != null) {
            final content = message['content'] as String? ?? '';
            if (content.isNotEmpty) {
              yield content;
            }
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

  void cancelStream() {
    _activeClient?.close();
    _activeClient = null;
  }
}
