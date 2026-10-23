import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/sticker.dart';
import '../../../services/sticker_service.dart';
import '../../../theme/colors.dart';

/// The sticker tray behind the sticker button in the composer. Pops with the
/// sticker to send, or null if the sheet was dismissed.
Future<EfocSticker?> showStickerPickerSheet(
  BuildContext context, {
  required String groupId,
}) {
  return showModalBottomSheet<EfocSticker>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _StickerPickerSheet(groupId: groupId),
  );
}

class _StickerPickerSheet extends StatefulWidget {
  final String groupId;

  const _StickerPickerSheet({required this.groupId});

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  List<EfocStickerPack> _packs = [];
  int _tab = 0;
  bool _loading = true;
  String? _error;

  /// Non-null while an import is uploading: "3 of 12".
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? selectPackId}) async {
    try {
      final packs = await StickerService.instance.fetchPacks(widget.groupId);
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _loading = false;
        _error = null;
        if (selectPackId != null) {
          final i = packs.indexWhere((p) => p.id == selectPackId);
          _tab = i < 0 ? 0 : i;
        } else if (_tab >= packs.length) {
          _tab = 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------
  // Imports
  // ------------------------------------------------------------

  Future<void> _importWastickers() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wastickers', 'zip'],
      withData: true,
    );
    final picked = result?.files;
    if (picked == null || picked.isEmpty) return;
    final bytes = picked.first.bytes;
    if (bytes == null) return;
    if (!mounted) return;

    final ImportedPack pack;
    try {
      pack = StickerService.parseWastickers(bytes);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    }

    final name = await _askName(pack.name);
    if (name == null || !mounted) return;

    await _createPack(
      name: name,
      drafts: pack.stickers,
      tray: pack.tray,
    );
  }

  Future<void> _importPhotos() async {
    final files = await ImagePicker().pickMultiImage(
      // Stickers read best square and fast; this is the same 512 px cap
      // WhatsApp puts on a pack, so nothing huge reaches storage.
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (files.isEmpty || !mounted) return;

    final drafts = <StickerDraft>[];
    for (final f in files) {
      try {
        drafts.add(StickerDraft.fromBytes(await f.readAsBytes()));
      } catch (_) {
        // One unreadable file shouldn't sink the rest.
      }
    }
    if (drafts.isEmpty) {
      _toast("Couldn't read those images.");
      return;
    }

    final name = await _askName(
      drafts.length == 1 ? 'My sticker' : 'My stickers',
    );
    if (name == null || !mounted) return;

    await _createPack(
      name: name,
      drafts: drafts,
      tray: StickerDraft(
        bytes: drafts.first.bytes,
        extension: drafts.first.extension,
      ),
    );
  }

  Future<void> _createPack({
    required String name,
    required List<StickerDraft> drafts,
    StickerDraft? tray,
  }) async {
    setState(() => _busy = 'Uploading 0 of ${drafts.length}');
    try {
      final pack = await StickerService.instance.createPack(
        groupId: widget.groupId,
        name: name,
        drafts: drafts,
        tray: tray,
        onProgress: (done, total) {
          if (mounted) setState(() => _busy = 'Uploading $done of $total');
        },
      );
      if (!mounted) return;
      setState(() => _busy = null);
      await _load(selectPackId: pack.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('That pack didn\'t upload: $e');
    }
  }

  Future<void> _deletePack(EfocStickerPack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EfocColors.sheetBg,
        title: Text(
          'Delete "${pack.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'The stickers already sent in the chat stay where they are.',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StickerService.instance.deletePack(pack.id);
      if (mounted) await _load();
    } catch (e) {
      _toast('Could not delete: $e');
    }
  }

  Future<String?> _askName(String suggestion) {
    final controller = TextEditingController(text: suggestion);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EfocColors.sheetBg,
        title: const Text(
          'Name this pack',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'e.g. Kopi Gang',
            hintStyle: TextStyle(color: Colors.white38),
            counterStyle: TextStyle(color: Colors.white24),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.46,
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            const SizedBox(height: 10),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: EfocColors.accent,
          ),
        ),
      );
    }
    if (_error != null) {
      return _message(
        _error!,
        action: TextButton(
          onPressed: () => _load(),
          child: const Text('Try again'),
        ),
      );
    }
    if (_packs.isEmpty) return _empty();
    return Stack(
      children: [
        Column(
          children: [
            _tabs(),
            const SizedBox(height: 6),
            Expanded(child: _grid(_packs[_tab])),
          ],
        ),
        if (_busy != null) _busyOverlay(),
      ],
    );
  }

  Widget _empty() {
    return _message(
      'No sticker packs yet.\nBring a .wastickers pack from WhatsApp,\nor make one out of photos.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _actionButton(
                icon: Icons.file_download_outlined,
                label: 'Import pack',
                onTap: _importWastickers,
              ),
              _actionButton(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Use photos',
                onTap: _importPhotos,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _message(String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: EfocColors.surface,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  /// Pack trays, then a "+" that opens the two import routes, then a delete
  /// affordance for packs you own (long-press a tray).
  Widget _tabs() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < _packs.length; i++)
            _tray(_packs[i], i),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showImportMenu,
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.add,
                  size: 20,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tray(EfocStickerPack pack, int index) {
    final selected = index == _tab;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        onLongPress: pack.isMine ? () => _deletePack(pack) : null,
        child: Container(
          width: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected
                ? EfocColors.accent.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? EfocColors.accent : Colors.white12,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: pack.iconUrl == null
                ? const Icon(Icons.auto_awesome, size: 18, color: Colors.white38)
                : Image.network(
                    pack.iconUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: Colors.white38,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _grid(EfocStickerPack pack) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: pack.stickers.length,
      itemBuilder: (context, i) {
        final sticker = pack.stickers[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(sticker),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.network(
              sticker.url,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white24,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showImportMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: EfocColors.sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.file_download_outlined,
                  color: Colors.white70),
              title: const Text(
                'Import a .wastickers pack',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                'The file a sticker maker or a friend sends',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'pack'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined,
                  color: Colors.white70),
              title: const Text(
                'Make one from photos',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                'Pick as many as you like',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'photos'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'pack') await _importWastickers();
    if (choice == 'photos') await _importPhotos();
  }

  Widget _busyOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: EfocColors.accent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _busy!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
