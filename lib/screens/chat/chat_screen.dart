import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/member.dart';
import '../../models/message.dart';
import '../../services/chat_service.dart';
import '../../services/vlog_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../vlog/vlog_viewer_screen.dart';
import 'widgets/chat_clip_popup.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_context_menu.dart';
import 'widgets/clip_card.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/reactions_sheet.dart';

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

  /// Row keys, for jumping to a quoted message.
  final Map<String, GlobalKey> _rowKeys = {};
  String? _highlightId;
  int _highlightRun = 0;

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

  /// WhatsApp rules: same emoji (or null) removes, another replaces.
  /// Applied locally first so the pill updates instantly.
  Future<void> _react(EfocMessage msg, String? emoji) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    setState(() {
      _messages = [
        for (final m in _messages)
          m.id == msg.id ? m.withMyReaction(emoji, myId) : m,
      ];
    });
    try {
      await ChatService.instance.react(messageId: msg.id, emoji: emoji);
    } catch (e) {
      debugPrint('React error: $e');
    }
    // Realtime also reloads; this covers a dropped event or a failure.
    _onRealtime();
  }

  Future<void> _pickMoreEmoji(EfocMessage msg) async {
    final emoji = await showEmojiPickerSheet(context);
    if (emoji != null && mounted) _react(msg, emoji);
  }

  void _copy(EfocMessage msg) {
    Clipboard.setData(ClipboardData(text: msg.copyText ?? ''));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.isCard ? 'Caption copied' : 'Message copied'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  /// Scrolls the quoted message to the middle and rings it (spec 6.5).
  void _jumpTo(String? id) {
    if (id == null) return;
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That message is too far back'),
          duration: Duration(milliseconds: 1400),
        ),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    final run = ++_highlightRun;
    setState(() => _highlightId = id);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && run == _highlightRun) {
        setState(() => _highlightId = null);
      }
    });
  }

  Future<void> _openCard(EfocMessage msg) async {
    if (msg.kind == MessageKind.vlog) {
      final id = msg.vlogId;
      final vlog = id == null ? null : await VlogService.instance.fetchById(id);
      if (!mounted) return;
      if (vlog == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This vlog is no longer available')),
        );
        return;
      }
      await openStitchedVlog(
        context,
        vlog,
        dayLabel: vlogDayLabel(vlog.date),
      );
      return;
    }

    final reply = await showChatClipPopup(
      context: context,
      message: msg,
      onReact: (emoji) => _react(msg, emoji),
    );
    if (reply == null || !mounted) return;
    try {
      await ChatService.instance.sendText(
        groupId: widget.groupId,
        text: reply,
        replyToId: msg.id,
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }

  /// Reply banner over the composer, with a ▶ for clips (spec 6.4).
  (String?, String?) _replyLabels(EfocMessage? m) {
    if (m == null) return (null, null);
    return switch (m.kind) {
      MessageKind.text => (m.senderName, m.text),
      MessageKind.clip => (
          [
            m.senderName,
            if (m.cardHour != null) formatHour12(m.cardHour!),
          ].join(' · '),
          '▶ ${m.previewText}',
        ),
      MessageKind.vlog => (
          m.cardDate == null
              ? 'the daily vlog'
              : 'the vlog · ${vlogDayLabel(m.cardDate!)}',
          '▶ Daily vlog',
        ),
    };
  }

  /// Names and avatars for the "who reacted" sheet.
  Map<String, EfocMember> _members() {
    final group = context
        .read<AppState>()
        .groups
        .where((g) => g.id == widget.groupId)
        .firstOrNull;
    return {for (final m in group?.members ?? const <EfocMember>[]) m.id: m};
  }

  @override
  Widget build(BuildContext context) {
    final (replyName, replyText) = _replyLabels(_replyTo);
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
                ? Center(
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
                            // Build every row (at most 100) so a quote can
                            // jump to any of them.
                            cacheExtent: 100000,
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final msg =
                                  _messages[_messages.length - 1 - i];
                              final prev = i < _messages.length - 1
                                  ? _messages[_messages.length - 2 - i]
                                  : null;
                              final isGrouped = prev != null &&
                                  prev.userId == msg.userId &&
                                  prev.kind != MessageKind.vlog &&
                                  msg.kind != MessageKind.vlog;
                              final bubble = MessageBubble(
                                message: msg,
                                isGrouped: isGrouped,
                                onCardTap: () => _openCard(msg),
                                onQuoteTap: () => _jumpTo(msg.replyToId),
                                onReactionsTap: () => showReactionsSheet(
                                  context: context,
                                  message: msg,
                                  members: _members(),
                                  onRemoveMine: () => _react(msg, null),
                                ),
                                onLongPress: (globalPos) =>
                                    showChatContextMenu(
                                  context: context,
                                  message: msg,
                                  tapPosition: globalPos,
                                  onReply: () =>
                                      setState(() => _replyTo = msg),
                                  onReact: (emoji) => _react(msg, emoji),
                                  onMoreEmojis: () => _pickMoreEmoji(msg),
                                  onCopy: msg.copyText != null
                                      ? () => _copy(msg)
                                      : null,
                                  // Cards mirror the grid, so they stay.
                                  onDelete: msg.isMe && !msg.isCard
                                      ? () => _deleteMessage(msg)
                                      : null,
                                ),
                              );
                              return _HighlightRow(
                                key: _rowKeys.putIfAbsent(
                                  msg.id,
                                  () => GlobalKey(),
                                ),
                                active: _highlightId == msg.id,
                                run: _highlightRun,
                                child: bubble,
                              );
                            },
                          ),
          ),
          ChatComposer(
            replySenderName: replyName,
            replyPreviewText: replyText,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _sendText,
          ),
        ],
      ),
    );
  }
}

/// Purple ring + glow that holds, then fades out over 1800ms (spec 6.5).
class _HighlightRow extends StatelessWidget {
  final bool active;
  final int run;
  final Widget child;

  const _HighlightRow({
    super.key,
    required this.active,
    required this.run,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(active ? run : -1),
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      builder: (_, t, child) {
        final a = !active ? 0.0 : (t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: EfocColors.accent.withValues(alpha: a),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: EfocColors.accent.withValues(alpha: 0.35 * a),
                blurRadius: 14,
              ),
            ],
          ),
          child: child,
        );
      },
      child: child,
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