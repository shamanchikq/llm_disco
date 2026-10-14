import 'package:flutter/foundation.dart';
import '../services/ollama_service.dart';

/// Creates the service used for a connection. Injectable so tests can
/// stand in a mock instead of hitting the network.
typedef OllamaServiceFactory = OllamaService Function(
    String baseUrl, {String? authHeader});

class ConnectionProvider extends ChangeNotifier {
  final OllamaServiceFactory _createService;
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

  ConnectionProvider({OllamaServiceFactory? serviceFactory})
      : _createService =
            serviceFactory ?? ((baseUrl, {authHeader}) => OllamaService(
                  baseUrl,
                  authHeader: authHeader,
                ));

  /// Records [message] and resets to the idle, disconnected state.
  bool _fail(String message) {
    _error = message;
    _isConnecting = false;
    _service = null;
    notifyListeners();
    return false;
  }

  Future<bool> connect({
    required String ip,
    required String port,
    required bool useHttp,
    String? authToken,
  }) async {
    _isConnecting = true;
    _error = null;
    notifyListeners();

    // Validate before building the URL so bad input fails with a specific
    // message instead of a generic "could not connect" further downstream.
    var host = ip.trim();
    // "192.168.1.5/" is a harmless slip; drop the slashes before judging it.
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    final portNum = int.tryParse(port.trim());
    if (host.isEmpty) {
      return _fail('Enter a server address');
    }
    // The URL is built here, so a pasted scheme or path would end up
    // inside the host part.
    if (host.contains('/')) {
      return _fail('Enter just the host or IP — no http:// prefix or path');
    }
    if (portNum == null || portNum < 1 || portNum > 65535) {
      return _fail('Port must be a number between 1 and 65535');
    }

    final hostSegment = _urlHost(host);
    if (hostSegment == null) {
      return _fail(host.startsWith('[') && host.endsWith(']')
          ? 'That is not a valid IPv6 address'
          : 'Put the port in the Port field, not in the address');
    }

    final token = authToken?.trim() ?? '';
    // Anything outside printable ASCII (line breaks from a sloppy paste,
    // control or non-ASCII characters) makes the HTTP client throw while
    // building the header — which would surface as "Could not reach".
    if (token.contains(RegExp(r'[^\x20-\x7E]'))) {
      return _fail('The API key/token contains invalid characters '
          '(line breaks or non-ASCII) — paste it again');
    }

    final protocol = useHttp ? 'http' : 'https';
    _baseUrl = '$protocol://$hostSegment:$portNum';
    // A bare token becomes "Bearer <token>"; a value that already names a
    // scheme ("Basic xyz…") is used as-is.
    final authHeader = token.isEmpty
        ? null
        : token.contains(' ')
            ? token
            : 'Bearer $token';
    _service = _createService(_baseUrl, authHeader: authHeader);

    try {
      final status = await _service!.testConnectionStatus();
      if (status == 200) {
        _isConnected = true;
        _isConnecting = false;
        notifyListeners();
        return true;
      } else if (status == 401 || status == 403) {
        return _fail(
            'Authentication failed at $_baseUrl — check the API key/token');
      } else if (status == 0) {
        return _fail('Could not reach Ollama at $_baseUrl');
      } else {
        return _fail('Ollama at $_baseUrl responded with HTTP $status');
      }
    } catch (e) {
      _error = 'Connection failed: $e';
      _isConnecting = false;
      _service = null;
      notifyListeners();
      return false;
    }
  }

  /// [host] as it belongs in a URL authority: IPv6 literals bracketed
  /// (an already-bracketed one is kept), everything else untouched. Null when
  /// the value contains a colon but isn't a genuine IPv6 address — i.e. the
  /// user typed `host:port`.
  static String? _urlHost(String host) {
    final bracketed = host.startsWith('[') && host.endsWith(']');
    if (!bracketed && !host.contains(':')) return host;
    try {
      Uri.parseIPv6Address(
          bracketed ? host.substring(1, host.length - 1) : host);
    } on FormatException {
      return null;
    }
    return bracketed ? host : '[$host]';
  }

  void disconnect() {
    _service = null;
    _isConnected = false;
    _baseUrl = '';
    _error = null;
    notifyListeners();
  }
}
