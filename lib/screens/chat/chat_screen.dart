import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../services/chat_service.dart'; 
import '../../theme/colors.dart';
import 'widgets/chat_composer.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  List<EfocMessage> _messages = [];
  bool _loading = true;
  String? _error;

  EfocMessage? _replyTo;

  Timer? _debounce;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = ChatService.instance.subscribe(
      groupId: widget.groupId,
      onChange: _onRealtime,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  void _onRealtime() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _load);
  }

  Future<void> _load() async {
    try {
      final msgs = await ChatService.instance.fetchMessages(
        groupId: widget.groupId,
      );
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText(String text) async {
    try {
      await ChatService.instance.sendText(
        groupId: widget.groupId,
        text: text,
        replyToId: _replyTo?.id,
      );
      if (!mounted) return;
      setState(() => _replyTo = null);
      // Server will notify via realtime; but do a fetch anyway for snappiness.
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
      rethrow;
    }
  }

  Future<void> _showMessageMenu(EfocMessage msg) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MessageMenu(
        message: msg,
        onReply: () {
          Navigator.of(context).pop();
          setState(() => _replyTo = msg);
        },
        onReact: (emoji) async {
          Navigator.of(context).pop();
          await ChatService.instance.toggleReaction(
            messageId: msg.id,
            emoji: emoji,
          );
          _load();
        },
        onDelete: msg.isMe
            ? () async {
                Navigator.of(context).pop();
                await ChatService.instance.deleteMessage(msg.id);
                _load();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EfocColors.bg,
      appBar: AppBar(
        backgroundColor: EfocColors.bg,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Chat',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EfocColors.accent,
                      ),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? const _EmptyChat()
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final msg =
                                  _messages[_messages.length - 1 - i];
                              final isGrouped = i < _messages.length - 1 &&
                                  _messages[_messages.length - 2 - i]
                                          .userId ==
                                      msg.userId;
                              return MessageBubble(
                                message: msg,
                                isGrouped: isGrouped,
                                onLongPress: () => _showMessageMenu(msg),
                              );
                            },
                          ),
          ),
          ChatComposer(
            replySenderName: _replyTo?.senderName,
            replyPreviewText: _replyTo?.text ??
                (_replyTo?.clipStoragePath != null ? 'Clip' : null),
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _sendText,
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 14),
            Text(
              'Say hi to your Log',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Text messages, replies, and clips appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageMenu extends StatelessWidget {
  final EfocMessage message;
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  final VoidCallback? onDelete;

  const _MessageMenu({
    required this.message,
    required this.onReply,
    required this.onReact,
    required this.onDelete,
  });

  static const _emojis = ['❤️', '😂', '😮', '👏', '🔥', '😢'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () => onReact(e),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: EfocColors.surface,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          _MenuItem(
            icon: Icons.reply_rounded,
            label: 'Reply',
            onTap: onReply,
          ),
          if (onDelete != null)
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: EfocColors.danger,
              onTap: onDelete!,
            ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}