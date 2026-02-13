import 'package:flutter/foundation.dart';
import '../models/model_capabilities.dart';
import '../services/ollama_service.dart';

class ModelProvider extends ChangeNotifier {
  List<String> _models = [];
  String? _selectedModel;
  bool _isLoading = false;
  String? _error;
  final Map<String, ModelCapabilities> _capabilities = {};
  final Set<String> _capabilitiesLoading = {};

  bool _isPulling = false;
  String _pullStatus = '';
  double? _pullProgress;
  String? _pullError;

  List<String> get models => _models;
  String? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPulling => _isPulling;
  String get pullStatus => _pullStatus;
  double? get pullProgress => _pullProgress;
  String? get pullError => _pullError;

  ModelCapabilities? getCapabilities(String model) => _capabilities[model];

  Future<void> fetchModels(OllamaService service) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _models = await service.fetchModels();
      if (_models.isNotEmpty) {
        _selectedModel = _models.first;
        fetchCapabilities(service, _selectedModel!);
      }
    } catch (e) {
      _error = 'Failed to load models: $e';
      _models = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCapabilities(OllamaService service, String model) async {
    if (_capabilities.containsKey(model) ||
        _capabilitiesLoading.contains(model)) {
      return;
    }

    _capabilitiesLoading.add(model);
    try {
      final info = await service.fetchModelInfo(model);
      _capabilities[model] = _parseCapabilities(info);
      notifyListeners();
    } catch (_) {
      _capabilities[model] = const ModelCapabilities();
    } finally {
      _capabilitiesLoading.remove(model);
    }
  }

  ModelCapabilities _parseCapabilities(Map<String, dynamic> info) {
    final caps = info['capabilities'] as List<dynamic>? ?? [];
    final capStrings = caps.map((e) => e.toString()).toSet();

    final supportsVision = capStrings.contains('vision');
    final supportsTools = capStrings.contains('tools');
    final supportsThinking = capStrings.contains('thinking');

    String? thinkingMode;
    if (supportsThinking) {
      final family =
          (info['model_info'] as Map<String, dynamic>?)?['general.family']
              as String?;
      // QwQ models support thinking levels; others use boolean toggle
      if (family != null && family.toLowerCase().contains('qwen')) {
        thinkingMode = 'levels';
      } else {
        thinkingMode = 'boolean';
      }
    }

    return ModelCapabilities(
      supportsVision: supportsVision,
      supportsThinking: supportsThinking,
      thinkingMode: thinkingMode,
      supportsTools: supportsTools,
    );
  }

  Future<void> pullModel(OllamaService service, String modelName) async {
    _isPulling = true;
    _pullStatus = 'Starting pull...';
    _pullProgress = null;
    _pullError = null;
    notifyListeners();

    try {
      await for (final event in service.pullModel(modelName)) {
        _pullStatus = event.status;
        _pullProgress = event.progress;
        notifyListeners();
      }
      _pullStatus = 'Pull complete';
      _pullError = null;
      notifyListeners();
      await fetchModels(service);
    } catch (e) {
      _pullError = e.toString();
      notifyListeners();
    } finally {
      _isPulling = false;
      notifyListeners();
    }
  }

  void cancelPull(OllamaService service) {
    service.cancelPull();
    _isPulling = false;
    _pullStatus = '';
    _pullProgress = null;
    _pullError = null;
    notifyListeners();
  }

  void selectModel(String model, {OllamaService? service}) {
    _selectedModel = model;
    notifyListeners();
    if (service != null && !_capabilities.containsKey(model)) {
      fetchCapabilities(service, model);
    }
  }

  void clear() {
    _models = [];
    _selectedModel = null;
    _error = null;
    _capabilities.clear();
    _capabilitiesLoading.clear();
    notifyListeners();
  }
}
