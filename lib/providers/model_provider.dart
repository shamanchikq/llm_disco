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
  final Map<String, DateTime> _capabilitiesFailedAt = {};
  static const _retryCooldown = Duration(seconds: 30);

  bool _isPulling = false;
  String _pullStatus = '';
  double? _pullProgress;
  String? _pullError;
  String? _pullingModelName;

  List<String> get models => _models;
  String? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPulling => _isPulling;
  String get pullStatus => _pullStatus;
  double? get pullProgress => _pullProgress;
  String? get pullError => _pullError;
  String? get pullingModelName => _pullingModelName;

  ModelCapabilities? getCapabilities(String model) => _capabilities[model];

  Future<void> fetchModels(OllamaService service) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _models = await service.fetchModels();
      if (_models.isNotEmpty) {
        // Keep the user's selection across refetches (e.g. after a pull);
        // only fall back to the first model when it's gone or unset.
        if (_selectedModel == null || !_models.contains(_selectedModel)) {
          _selectedModel = _models.first;
        }
        fetchCapabilities(service, _selectedModel!);
      } else {
        _selectedModel = null;
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
    // After a failed fetch, wait out the cooldown before retrying so a dead
    // server isn't hammered on every rebuild.
    final failedAt = _capabilitiesFailedAt[model];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _retryCooldown) {
      return;
    }

    _capabilitiesLoading.add(model);
    try {
      final info = await service.fetchModelInfo(model);
      _capabilities[model] = _parseCapabilities(info, model);
      _capabilitiesFailedAt.remove(model);
    } catch (_) {
      // Leave the entry absent so the fetch is retried later — caching
      // all-false capabilities would permanently hide vision/thinking UI
      // for the model after one transient network error.
      _capabilitiesFailedAt[model] = DateTime.now();
    } finally {
      _capabilitiesLoading.remove(model);
      notifyListeners();
    }
  }

  ModelCapabilities _parseCapabilities(Map<String, dynamic> info, String model) {
    final caps = info['capabilities'] as List<dynamic>? ?? [];
    final capStrings = caps.map((e) => e.toString()).toSet();

    final supportsVision = capStrings.contains('vision');
    final supportsTools = capStrings.contains('tools');
    final supportsThinking = capStrings.contains('thinking');
    final supportsAudio = capStrings.contains('audio');

    String? thinkingMode;
    if (supportsThinking) {
      final lowerModel = model.toLowerCase();
      // GPT-OSS models expose effort levels but can't disable thinking.
      // Every other thinking-capable model accepts think true/false (and
      // optionally an effort level) via the Ollama API.
      if (lowerModel.startsWith('gpt-oss')) {
        thinkingMode = 'levels';
      } else {
        thinkingMode = 'toggle';
      }
    }

    return ModelCapabilities(
      supportsVision: supportsVision,
      supportsThinking: supportsThinking,
      thinkingMode: thinkingMode,
      supportsTools: supportsTools,
      supportsAudio: supportsAudio,
    );
  }

  Future<void> pullModel(OllamaService service, String modelName) async {
    _pullingModelName = modelName;
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
    _pullingModelName = null;
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
    _capabilitiesFailedAt.clear();
    notifyListeners();
  }
}
