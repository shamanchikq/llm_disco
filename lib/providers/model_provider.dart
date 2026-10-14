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

  /// Set by [cancelPull] so the aborted stream's exception (closing the
  /// client makes it throw) isn't rendered as a failed download.
  bool _pullCancelRequested = false;

  /// Bumped by [clear]. Async work captures it up front and drops its result
  /// once it has moved on, so a slow response from the server we left can't
  /// write into the next server's state.
  int _generation = 0;

  /// The service the running pull was started on, so [clear] can abort the
  /// real download rather than whatever service is current by then.
  OllamaService? _pullService;

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

  /// True when the last capability fetch for [model] failed and no retry is
  /// in flight — lets the UI show a "couldn't load" state instead of an
  /// endless spinner.
  bool capabilitiesFailed(String model) =>
      !_capabilities.containsKey(model) &&
      !_capabilitiesLoading.contains(model) &&
      _capabilitiesFailedAt.containsKey(model);

  Future<void> fetchModels(OllamaService service) async {
    final generation = _generation;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = await service.fetchModels();
      if (generation != _generation) return;
      _models = fetched;
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
      if (generation != _generation) return;
      // Keep the last good list and selection — one transient failure
      // shouldn't make installed models vanish; the error is surfaced
      // separately.
      _error = 'Failed to load models: $e';
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
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

    final generation = _generation;
    _capabilitiesLoading.add(model);
    try {
      final info = await service.fetchModelInfo(model);
      if (generation != _generation) return;
      _capabilities[model] = _parseCapabilities(info, model);
      _capabilitiesFailedAt.remove(model);
    } catch (_) {
      if (generation != _generation) return;
      // Leave the entry absent so the fetch is retried later — caching
      // all-false capabilities would permanently hide vision/thinking UI
      // for the model after one transient network error.
      _capabilitiesFailedAt[model] = DateTime.now();
    } finally {
      if (generation == _generation) {
        _capabilitiesLoading.remove(model);
        notifyListeners();
      }
    }
  }

  /// A user-initiated retry: skips the failure cooldown that
  /// [fetchCapabilities] applies to automatic fetches.
  Future<void> retryCapabilities(OllamaService service, String model) {
    _capabilitiesFailedAt.remove(model);
    final fetch = fetchCapabilities(service, model);
    notifyListeners(); // show the loading state right away
    return fetch;
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
    // One download at a time; the UI disables the buttons but doesn't own
    // this guarantee.
    if (_isPulling) return;

    final generation = _generation;
    _pullService = service;
    _pullingModelName = modelName;
    _isPulling = true;
    _pullStatus = 'Starting pull...';
    _pullProgress = null;
    _pullError = null;
    _pullCancelRequested = false;
    notifyListeners();

    try {
      await for (final event in service.pullModel(modelName)) {
        if (generation != _generation) return;
        _pullStatus = event.status;
        _pullProgress = event.progress;
        notifyListeners();
      }
      if (generation != _generation || _pullCancelRequested) return;
      _pullStatus = 'Pull complete';
      _pullError = null;
      notifyListeners();
      await fetchModels(service);
    } catch (e) {
      // A user-initiated cancel closes the client, which surfaces here as
      // an exception — that's the expected path, not a failed download.
      // Likewise for a pull aborted by [clear].
      if (generation == _generation && !_pullCancelRequested) {
        _pullError = e.toString();
        notifyListeners();
      }
    } finally {
      if (generation == _generation) {
        _isPulling = false;
        _pullService = null;
        notifyListeners();
      }
    }
  }

  void cancelPull(OllamaService service) {
    _pullCancelRequested = true;
    service.cancelPull();
    _isPulling = false;
    _pullStatus = '';
    _pullProgress = null;
    _pullError = null;
    _pullingModelName = null;
    _pullService = null;
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
    _generation++;
    // Abort a download still running against the server we're leaving — as
    // a user-style cancel, so its aborted stream doesn't render as a failure.
    if (_pullService != null) {
      _pullCancelRequested = true;
      _pullService!.cancelPull();
    }
    _pullService = null;
    _isPulling = false;
    _pullStatus = '';
    _pullProgress = null;
    _pullError = null;
    _pullingModelName = null;
    _models = [];
    _selectedModel = null;
    _isLoading = false;
    _error = null;
    _capabilities.clear();
    _capabilitiesLoading.clear();
    _capabilitiesFailedAt.clear();
    notifyListeners();
  }
}
