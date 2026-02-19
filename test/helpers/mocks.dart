import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';
import 'package:llm_disco_test1/services/storage_service.dart';

class MockOllamaService extends Mock implements OllamaService {}

class MockStorageService extends Mock implements StorageService {}
