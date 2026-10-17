import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/message.dart';
import '../../services/chat_service.dart';
import '../../theme/colors.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_context_menu.dart';
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
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
      rethrow;
    }
  }

  Future<void> _deleteMessage(EfocMessage msg) async {
    try {
      await ChatService.instance.deleteMessage(msg.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _toggleReaction(EfocMessage msg, String emoji) async {
    try {
      await ChatService.instance.toggleReaction(
        messageId: msg.id,
        emoji: emoji,
      );
      _load();
    } catch (_) {
      // Silent — reaction is a low-stakes action.
    }
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
                                onLongPress: (globalPos) =>
                                    showChatContextMenu(
                                  context: context,
                                  message: msg,
                                  tapPosition: globalPos,
                                  onReply: () =>
                                      setState(() => _replyTo = msg),
                                  onReact: (emoji) =>
                                      _toggleReaction(msg, emoji),
                                  onDelete: msg.isMe
                                      ? () => _deleteMessage(msg)
                                      : null,
                                ),
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