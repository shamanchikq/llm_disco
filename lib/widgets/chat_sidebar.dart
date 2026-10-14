import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../screens/connection_screen.dart';
import '../screens/model_management_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'model_selector.dart';

/// Sidebar age bucket for a chat created at [createdAt]. Day counts come from
/// UTC dates built out of each side's local calendar date: subtracting two
/// local midnights across a clock change gives 23 or 25 hours, which
/// `inDays` truncates to the wrong day.
String conversationGroupFor(DateTime createdAt, DateTime now) {
  final local = createdAt.toLocal();
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff <= 7) return 'Previous 7 days';
  return 'Older';
}

class ChatSidebar extends StatefulWidget {
  const ChatSidebar({super.key});

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  ChatProvider? _chatProvider;
  int _lastHash = 0;
  final _searchController = TextEditingController();

  int _computeHash(ChatProvider cp) => Object.hash(
    cp.activeConversation?.id,
    // so the undo bar appears and expires without another list change
    cp.undoableDeletes,
    Object.hashAll(cp.conversations.map((c) => Object.hash(
      c.id, c.title, c.messages.length,
    ))),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Use context.read to avoid registering as an InheritedNotifier dependent.
    final newProvider = context.read<ChatProvider>();
    if (_chatProvider != newProvider) {
      _chatProvider?.removeListener(_onChanged);
      _chatProvider = newProvider;
      _lastHash = _computeHash(newProvider);
      _chatProvider!.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final hash = _computeHash(_chatProvider!);
    if (hash != _lastHash) {
      _lastHash = hash;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _chatProvider?.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Dismisses the open options/backup sheet and the drawer behind it. The
  /// result of what follows is reported in a snackbar, which the drawer would
  /// otherwise paint over.
  void _closeSheetAndDrawer(BuildContext sheetContext, BuildContext context) {
    Navigator.pop(sheetContext);
    Scaffold.maybeOf(context)?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = _chatProvider!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;
    final baseUrl = context.watch<ConnectionProvider>().baseUrl;
    final host = baseUrl.replaceFirst(RegExp(r'^https?://'), '');

    // Filter by search query (title or message text), then group by age,
    // preserving provider order within groups.
    final query = _searchController.text.trim().toLowerCase();
    bool matches(Conversation c) =>
        query.isEmpty ||
        c.title.toLowerCase().contains(query) ||
        c.messages.any((m) => m.content.toLowerCase().contains(query));

    final now = DateTime.now();
    final grouped = <String, List<Conversation>>{};
    for (final c in chatProvider.conversations.where(matches)) {
      grouped
          .putIfAbsent(conversationGroupFor(c.createdAt, now), () => [])
          .add(c);
    }
    const groupOrder = ['Today', 'Yesterday', 'Previous 7 days', 'Older'];

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand header
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'D',
                          style: AppTheme.display(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: tokens.accentInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'LLM Disco',
                        style: AppTheme.display(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: tokens.good,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tokens.good.withValues(alpha: 0.22),
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          host.isEmpty ? 'not connected' : '$host · connected',
                          style: AppTheme.mono(
                            fontSize: 11,
                            color: tokens.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // New chat
            Padding(
              padding: const EdgeInsets.all(12),
              child: _DashedBorderButton(
                color: tokens.lineStrong,
                radius: 12,
                onTap: () => _createNewConversation(context),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 17, color: colors.onSurface),
                    const SizedBox(width: 9),
                    Text(
                      'New chat',
                      style:
                          TextStyle(fontSize: 14, color: colors.onSurface),
                    ),
                  ],
                ),
              ),
            ),
            // Search
            if (chatProvider.conversations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search chats…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: tokens.textFaint),
                    suffixIcon: query.isEmpty
                        ? null
                        : GestureDetector(
                            onTap: () => setState(_searchController.clear),
                            child: Icon(Icons.close_rounded,
                                size: 16, color: tokens.textFaint),
                          ),
                  ),
                ),
              ),
            // Conversation list
            Expanded(
              child: grouped.isEmpty && query.isNotEmpty
                  ? Center(
                      child: Text(
                        'No matching chats',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    )
                  : chatProvider.conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 36,
                            color: tokens.textFaint,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No conversations yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final group in groupOrder)
                          if (grouped.containsKey(group)) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 12, 10, 6),
                              child: Text(
                                group.toUpperCase(),
                                style: AppTheme.mono(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  color: tokens.textFaint,
                                ),
                              ),
                            ),
                            for (final conversation in grouped[group]!)
                              _buildConversationTile(
                                context,
                                chatProvider,
                                conversation,
                                theme,
                                colors,
                                tokens,
                              ),
                          ],
                      ],
                    ),
            ),
            // Undo bar for just-deleted conversations. The pending deletes
            // live in ChatProvider: this state is rebuilt each time the
            // drawer opens, so holding them here lost the offer on close.
            if (chatProvider.undoableDeletes > 0)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: tokens.line)),
                  color: colors.surfaceContainer,
                ),
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chatProvider.undoableDeletes == 1
                            ? 'Chat deleted'
                            : '${chatProvider.undoableDeletes} chats deleted',
                        style: TextStyle(
                            fontSize: 13, color: tokens.textMuted),
                      ),
                    ),
                    TextButton(
                      onPressed: chatProvider.undoDelete,
                      child: const Text('UNDO'),
                    ),
                  ],
                ),
              ),
            // Footer
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.line)),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(3, 0, 3, 4),
                    child: ModelSelector(compact: false),
                  ),
                  _footerRow(
                    context: context,
                    icon: Icons.view_in_ar_rounded,
                    label: 'Manage models',
                    tokens: tokens,
                    onTap: () => _manageModels(context),
                  ),
                  _footerRow(
                    context: context,
                    icon: Icons.inventory_2_outlined,
                    label: 'Backup & restore',
                    tokens: tokens,
                    onTap: () => _showBackupSheet(context, chatProvider),
                  ),
                  _footerRow(
                    context: context,
                    icon: Icons.swap_horiz_rounded,
                    label: 'Switch server',
                    tokens: tokens,
                    onTap: () => _disconnect(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    ChatProvider chatProvider,
    Conversation conversation,
    ThemeData theme,
    ColorScheme colors,
    DiscoTokens tokens,
  ) {
    final isActive = chatProvider.activeConversation?.id == conversation.id;
    final msgCount = conversation.messages.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Dismissible(
        key: Key(conversation.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: colors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Icon(Icons.delete_outline_rounded, color: colors.error),
        ),
        onDismissed: (_) =>
            chatProvider.deleteConversationWithUndo(conversation.id),
        child: Material(
          color: isActive ? colors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              chatProvider.setActiveConversation(conversation);
              Navigator.pop(context);
            },
            onLongPress: () {
              _showConversationOptions(context, chatProvider, conversation);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversation.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            color:
                                isActive ? colors.primary : colors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${conversation.model} · $msgCount msgs',
                          style: AppTheme.mono(
                            fontSize: 10.5,
                            color: tokens.textFaint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Visible entry point to rename/export — long-press
                  // still works as a shortcut.
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: 'Options',
                      icon: Icon(Icons.more_horiz_rounded,
                          color: tokens.textFaint),
                      onPressed: () => _showConversationOptions(
                          context, chatProvider, conversation),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required DiscoTokens tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 19, color: tokens.textMuted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: tokens.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createNewConversation(BuildContext context) {
    // Close the drawer first: a "no model" snackbar would paint under it.
    Navigator.pop(context);
    startNewChat(context);
  }

  void _manageModels(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ModelManagementScreen()));
  }

  void _disconnect(BuildContext context) {
    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    connectionProvider.disconnect();
    chatProvider.disconnectService();
    modelProvider.clear();
    // Intentional disconnect — don't bounce straight back via auto-connect.
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const ConnectionScreen(autoConnect: false)));
  }

  void _showBackupSheet(BuildContext context, ChatProvider chatProvider) {
    final storage = context.read<StorageService>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Export all conversations'),
              subtitle: Text('${chatProvider.conversations.length} chats'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                _closeSheetAndDrawer(ctx, context);
                try {
                  final file = await storage
                      .exportAllConversations(chatProvider.conversations);
                  await SharePlus.instance
                      .share(ShareParams(files: [XFile(file.path)]));
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Import from file'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                _closeSheetAndDrawer(ctx, context);
                try {
                  final picked = await FilePicker.pickFile(
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );
                  final path = picked?.path;
                  if (path == null) return;
                  final imported = await storage.importConversations(path);
                  final added = chatProvider.importConversations(imported);
                  messenger.showSnackBar(SnackBar(
                    content: Text(added == 0
                        ? 'Nothing new to import'
                        : 'Imported $added conversation(s)'),
                  ));
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Import failed: $e')));
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Delete all conversations',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Delete all conversations?'),
                    content: const Text(
                        'Every chat and its history will be permanently '
                        'removed from this device. This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        child: const Text('Delete all'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await chatProvider.deleteAllConversations();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationOptions(
    BuildContext context,
    ChatProvider chatProvider,
    Conversation conversation,
  ) {
    final storage = context.read<StorageService>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, chatProvider, conversation);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Export as Markdown'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                _closeSheetAndDrawer(ctx, context);
                try {
                  final file =
                      await storage.exportConversationMarkdown(conversation);
                  await SharePlus.instance
                      .share(ShareParams(files: [XFile(file.path)]));
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Export as JSON'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                _closeSheetAndDrawer(ctx, context);
                try {
                  final file =
                      await storage.exportConversation(conversation);
                  await SharePlus.instance
                      .share(ShareParams(files: [XFile(file.path)]));
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    ChatProvider chatProvider,
    Conversation conversation,
  ) {
    final controller = TextEditingController(text: conversation.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Conversation title'),
          onSubmitted: (_) {
            chatProvider.renameConversation(
                conversation.id, controller.text);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chatProvider.renameConversation(
                  conversation.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Rounded-rect button with a dashed border, matching the mockup's
/// "New chat" affordance.
class _DashedBorderButton extends StatelessWidget {
  final Color color;
  final double radius;
  final VoidCallback onTap;
  final Widget child;

  const _DashedBorderButton({
    required this.color,
    required this.radius,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    const dashLength = 5.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
