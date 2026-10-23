import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/sticker.dart';
import '../../../services/save_file.dart';
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

  /// Non-null while an import or export is running: "3 of 12".
  String? _busy;

  EfocStickerPack? get _selected {
    if (_packs.isEmpty) return null;
    return _packs[_tab.clamp(0, _packs.length - 1)];
  }

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
          if (i >= 0) _tab = i;
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
  // Getting stickers in
  // ------------------------------------------------------------

  /// A `.wastickers` is a zip, so the file dialog opens on *everything* and we
  /// sniff it. Filtering on the extension hides the file on web — browsers
  /// don't know `.wastickers` and grey it out.
  Future<void> _importWastickers() async {
    final result = await FilePicker.pickFiles(withData: true);
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
    await _createPack(name: name, drafts: pack.stickers, tray: pack.tray);
  }

  /// Loose image files — the `.webp` files copied out of WhatsApp's sticker
  /// folder, or anything else on disk.
  Future<void> _importFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    final picked = result?.files;
    if (picked == null || picked.isEmpty) return;
    if (!mounted) return;

    // A pack file picked here: treat it as one.
    final first = picked.first;
    if (picked.length == 1 && _looksLikePack(first.name)) {
      final bytes = first.bytes;
      if (bytes == null) return;
      final ImportedPack pack;
      try {
        pack = StickerService.parseWastickers(bytes);
      } on FormatException catch (e) {
        _toast(e.message);
        return;
      }
      final name = await _askName(pack.name);
      if (name == null || !mounted) return;
      await _createPack(name: name, drafts: pack.stickers, tray: pack.tray);
      return;
    }

    final drafts = <StickerDraft>[];
    for (final f in picked) {
      if (f.bytes == null) continue;
      drafts.add(StickerDraft.fromBytes(f.bytes!, fileName: f.name));
    }
    if (drafts.isEmpty) {
      _toast("Couldn't read those files.");
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

  Future<void> _importPhotos() async {
    final files = await ImagePicker().pickMultiImage(
      // Stickers read best square and fast; this is the same 512 px cap
      // WhatsApp puts on a pack, so nothing huge reaches storage.
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (files.isEmpty || !mounted) return;

    final drafts = await _draftsFrom(files);
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

  Future<List<StickerDraft>> _draftsFrom(List<XFile> files) async {
    final drafts = <StickerDraft>[];
    for (final f in files) {
      try {
        drafts.add(StickerDraft.fromBytes(await f.readAsBytes()));
      } catch (_) {
        // One unreadable file shouldn't sink the rest.
      }
    }
    return drafts;
  }

  static bool _looksLikePack(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.wastickers') || n.endsWith('.zip');
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
      _toast("That pack didn't upload: $e");
    }
  }

  /// Tops up a pack that already exists, from photos or from files.
  Future<void> _addToPack(EfocStickerPack pack, String source) async {
    final drafts = <StickerDraft>[];
    if (source == 'photos') {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 88,
      );
      if (files.isEmpty) return;
      drafts.addAll(await _draftsFrom(files));
    } else {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      final picked = result?.files;
      if (picked == null) return;
      for (final f in picked) {
        if (f.bytes == null || _looksLikePack(f.name)) continue;
        drafts.add(StickerDraft.fromBytes(f.bytes!, fileName: f.name));
      }
    }
    if (!mounted) return;
    if (drafts.isEmpty) {
      _toast('Nothing to add.');
      return;
    }

    setState(() => _busy = 'Uploading 0 of ${drafts.length}');
    try {
      await StickerService.instance.addStickers(
        pack: pack,
        drafts: drafts,
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
      _toast("Couldn't add those: $e");
    }
  }

  // ------------------------------------------------------------
  // Sharing a pack
  // ------------------------------------------------------------

  /// Repacks the pack as a `.wastickers` file. Web: lands in Downloads.
  /// Android/iOS: the share sheet, so it can go straight into a chat or a
  /// sticker maker.
  Future<void> _exportPack(EfocStickerPack pack) async {
    setState(() => _busy = 'Packing ${pack.name}…');
    try {
      final bytes = await StickerService.instance.exportWastickers(pack);
      if (!mounted) return;
      setState(() => _busy = null);
      await saveFile(
        bytes,
        '${_slug(pack.name)}.wastickers',
        mimeType: 'application/zip',
      );
      _toast('Pack saved — send the file to whoever wants it');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast("Couldn't build that pack: $e");
    }
  }

  static String _slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final trimmed = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'stickers' : trimmed;
  }

  // ------------------------------------------------------------
  // Small dialogs
  // ------------------------------------------------------------

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

  /// Where stickers come from, in plain words. This is the bit people get
  /// stuck on: WhatsApp has no export button, so you need the zip file a
  /// sticker maker produces.
  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EfocColors.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Where stickers come from',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12),
              _HelpLine(
                icon: Icons.file_download_outlined,
                title: 'A .wastickers file',
                body:
                    'WhatsApp has no export button, but sticker makers do. '
                    'Sticker Maker and Sticker.ly save your pack as a '
                    '.wastickers file — that is the one to import. A friend '
                    'can send you theirs too.',
              ),
              _HelpLine(
                icon: Icons.image_outlined,
                title: 'The .webp files themselves',
                body:
                    'On Android, installed packs sit in Android/media/'
                    'com.whatsapp/WhatsApp/Media/WhatsApp Stickers. Copy those '
                    '.webp files out and pick them here.',
              ),
              _HelpLine(
                icon: Icons.add_photo_alternate_outlined,
                title: 'Photos from your gallery',
                body:
                    'Make a pack out of anything in your camera roll. It gets '
                    'squared to 512 px on the way in.',
              ),
              _HelpLine(
                icon: Icons.lock_outline_rounded,
                title: 'Only this Log sees them',
                body:
                    'A pack belongs to the group you added it to. Anyone in '
                    'the Log can send it; only the person who added it can '
                    'delete it.',
              ),
            ],
          ),
        ),
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
      height: MediaQuery.of(context).size.height * 0.52,
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
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
                const SizedBox(height: 8),
                _tabs(),
                Expanded(child: _body()),
              ],
            ),
            if (_busy != null) Positioned.fill(child: _busyOverlay()),
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

    final pack = _selected;
    if (pack == null) return _empty();

    return Column(
      children: [
        _packHeader(pack),
        Expanded(child: _grid(pack)),
      ],
    );
  }

  /// Always visible, even with no packs, so "add" is never hidden behind a
  /// state you can't get out of.
  Widget _tabs() {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < _packs.length; i++) _tray(_packs[i], i),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showImportMenu,
              child: Container(
                width: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add, size: 20, color: Colors.white54),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: IconButton(
              onPressed: _showHelp,
              tooltip: 'Where do stickers come from?',
              icon: const Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: Colors.white38,
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
        child: Container(
          width: 38,
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

  /// The pack's name, its size, and what you can do to it.
  Widget _packHeader(EfocStickerPack pack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pack.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${pack.stickers.length} stickers',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          IconButton(
            onPressed: () => _showAddMenu(pack),
            tooltip: 'Add stickers to this pack',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.add_photo_alternate_outlined,
              size: 18,
              color: Colors.white54,
            ),
          ),
          IconButton(
            onPressed: () => _exportPack(pack),
            tooltip: 'Save as a .wastickers file',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.ios_share, size: 17, color: Colors.white54),
          ),
          if (pack.isMine)
            IconButton(
              onPressed: () => _deletePack(pack),
              tooltip: 'Delete pack',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Colors.white38,
              ),
            ),
        ],
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
      itemCount: pack.stickers.length + 1,
      itemBuilder: (context, i) {
        // Last cell: keep adding to this pack.
        if (i == pack.stickers.length) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAddMenu(pack),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Icon(Icons.add, size: 20, color: Colors.white38),
              ),
            ),
          );
        }

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

  Widget _empty() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        children: [
          Icon(
            Icons.interests_outlined,
            size: 34,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 10),
          const Text(
            'No sticker packs yet',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'WhatsApp has no export button, so you need the pack file a '
            'sticker maker saves — or just make one from photos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _actionButton(
                icon: Icons.file_download_outlined,
                label: 'Import .wastickers',
                onTap: _importWastickers,
              ),
              _actionButton(
                icon: Icons.image_outlined,
                label: 'Pick files',
                onTap: _importFiles,
              ),
              _actionButton(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Use photos',
                onTap: _importPhotos,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _showHelp,
            child: const Text(
              'Where do stickers come from?',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }

  Future<void> _showImportMenu() async {
    final choice = await _sheetMenu(
      title: 'Add a sticker pack',
      options: const [
        (
          value: 'pack',
          icon: Icons.file_download_outlined,
          title: 'Import a .wastickers file',
          subtitle: 'The pack file a sticker maker or a friend sends',
        ),
        (
          value: 'files',
          icon: Icons.image_outlined,
          title: 'Pick sticker files',
          subtitle: 'The .webp files copied out of WhatsApp',
        ),
        (
          value: 'photos',
          icon: Icons.add_photo_alternate_outlined,
          title: 'Make one from photos',
          subtitle: 'Pick as many as you like',
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'pack') await _importWastickers();
    if (choice == 'files') await _importFiles();
    if (choice == 'photos') await _importPhotos();
  }

  Future<void> _showAddMenu(EfocStickerPack pack) async {
    final choice = await _sheetMenu(
      title: 'Add to "${pack.name}"',
      options: const [
        (
          value: 'photos',
          icon: Icons.add_photo_alternate_outlined,
          title: 'From photos',
          subtitle: 'Camera roll, squared to 512 px',
        ),
        (
          value: 'files',
          icon: Icons.image_outlined,
          title: 'From files',
          subtitle: 'Sticker files already on the phone',
        ),
      ],
    );
    if (choice == null || !mounted) return;
    await _addToPack(pack, choice);
  }

  Future<String?> _sheetMenu({
    required String title,
    required List<
            ({
              String value,
              IconData icon,
              String title,
              String subtitle,
            })>
        options,
  }) {
    return showModalBottomSheet<String>(
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
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final o in options)
              ListTile(
                leading: Icon(o.icon, color: Colors.white70),
                title: Text(
                  o.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  o.subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, o.value),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _busyOverlay() {
    return Container(
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
    );
  }
}

class _HelpLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HelpLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
