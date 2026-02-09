import 'package:flutter/foundation.dart';
import '../services/ollama_service.dart';

class ModelProvider extends ChangeNotifier {
  List<String> _models = [];
  String? _selectedModel;
  bool _isLoading = false;
  String? _error;

  List<String> get models => _models;
  String? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchModels(OllamaService service) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _models = await service.fetchModels();
      if (_models.isNotEmpty) {
        _selectedModel = _models.first;
      }
    } catch (e) {
      _error = 'Failed to load models: $e';
      _models = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectModel(String model) {
    _selectedModel = model;
    notifyListeners();
  }

  void clear() {
    _models = [];
    _selectedModel = null;
    _error = null;
    notifyListeners();
  }
}
