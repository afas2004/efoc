import 'package:flutter/material.dart';

import '../../../models/member.dart';
import '../../../models/message.dart';
import '../../../theme/colors.dart';

/// WhatsApp's "who reacted" sheet: an "All" tab plus one tab per emoji,
/// each listing people newest first. Your own row says "Tap to remove".
Future<void> showReactionsSheet({
  required BuildContext context,
  required EfocMessage message,
  required Map<String, EfocMember> members,
  required VoidCallback onRemoveMine,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ReactionsSheet(
      message: message,
      members: members,
      onRemoveMine: onRemoveMine,
    ),
  );
}

class _ReactionsSheet extends StatefulWidget {
  final EfocMessage message;
  final Map<String, EfocMember> members;
  final VoidCallback onRemoveMine;

  const _ReactionsSheet({
    required this.message,
    required this.members,
    required this.onRemoveMine,
  });

  @override
  State<_ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<_ReactionsSheet> {
  /// null = "All".
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final reactions = widget.message.reactions;
    final emojis = widget.message.topEmojis;
    final shown = _filter == null
        ? reactions
        : reactions.where((r) => r.emoji == _filter).toList();
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _Tab(
                    label: 'All ${reactions.length}',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final e in emojis)
                    _Tab(
                      label:
                          '$e ${reactions.where((r) => r.emoji == e).length}',
                      selected: _filter == e,
                      onTap: () => setState(() => _filter = e),
                    ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.only(top: 6),
              color: Colors.white.withValues(alpha: 0.06),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final r in shown)
                    _ReactorRow(
                      reaction: r,
                      member: widget.members[r.userId],
                      onTap: r.isMe
                          ? () {
                              Navigator.of(context).pop();
                              widget.onRemoveMine();
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? EfocColors.accentBright : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ReactorRow extends StatelessWidget {
  final EfocReaction reaction;
  final EfocMember? member;
  final VoidCallback? onTap;

  const _ReactorRow({
    required this.reaction,
    required this.member,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = reaction.isMe ? 'You' : (member?.name ?? 'Former member');
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final url = member?.avatarUrl;
    final hasAvatar = url != null && url.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: member?.color ?? Colors.white24,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: hasAvatar
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                      errorBuilder: (_, _, _) => _Initial(initial),
                    )
                  : _Initial(initial),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (reaction.isMe)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Tap to remove',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Text(reaction.emoji, style: const TextStyle(fontSize: 24)),
          ],
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String text;

  const _Initial(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
