import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/connection_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/model_provider.dart';
import 'screens/connection_screen.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'models/conversation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  final saved = await storage.loadConversations();
  runApp(LLMChatApp(storageService: storage, savedConversations: saved));
}

class LLMChatApp extends StatelessWidget {
  final StorageService storageService;
  final List<Conversation> savedConversations;

  const LLMChatApp({
    super.key,
    required this.storageService,
    required this.savedConversations,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(
            storageService: storageService,
            initialConversations: savedConversations,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ModelProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LLM Chat',
        theme: AppTheme.dark,
        home: const ConnectionScreen(),
      ),
    );
  }
}
