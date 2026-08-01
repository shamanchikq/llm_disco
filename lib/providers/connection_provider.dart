import 'package:flutter/foundation.dart';
import '../services/ollama_service.dart';

class ConnectionProvider extends ChangeNotifier {
  OllamaService? _service;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _error;
  String _baseUrl = '';

  OllamaService? get service => _service;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get error => _error;
  String get baseUrl => _baseUrl;

  Future<bool> connect({
    required String ip,
    required String port,
    required bool useHttp,
    String? authToken,
  }) async {
    _isConnecting = true;
    _error = null;
    notifyListeners();

    final protocol = useHttp ? 'http' : 'https';
    _baseUrl = '$protocol://$ip:$port';
    // A bare token becomes "Bearer <token>"; a value that already names a
    // scheme ("Basic xyz…") is used as-is.
    final token = authToken?.trim() ?? '';
    final authHeader = token.isEmpty
        ? null
        : token.contains(' ')
            ? token
            : 'Bearer $token';
    _service = OllamaService(_baseUrl, authHeader: authHeader);

    try {
      final success = await _service!.testConnection();
      if (success) {
        _isConnected = true;
        _isConnecting = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Could not connect to Ollama at $_baseUrl';
        _isConnecting = false;
        _service = null;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Connection failed: $e';
      _isConnecting = false;
      _service = null;
      notifyListeners();
      return false;
    }
  }

  void disconnect() {
    _service = null;
    _isConnected = false;
    _baseUrl = '';
    _error = null;
    notifyListeners();
  }
}
