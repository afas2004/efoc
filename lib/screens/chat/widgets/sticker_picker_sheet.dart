import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/sticker.dart';
import '../../../services/file_pick.dart';
import '../../../services/save_file.dart';
import '../../../services/sticker_service.dart';
import '../../../theme/colors.dart';

/// The sticker tray behind the sticker button in the composer. Pops with the
/// sticker to send, or null if the sheet was dismissed.
Future<EfocSticker?> showStickerPickerSheet(
  BuildContext context, {
  String? focusPackId,
}) {
  return showModalBottomSheet<EfocSticker>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _StickerPickerSheet(focusPackId: focusPackId),
  );
}

class _StickerPickerSheet extends StatefulWidget {
  /// Open on this pack, when arriving from a share link.
  final String? focusPackId;

  const _StickerPickerSheet({this.focusPackId});

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  List<EfocStickerPack> _all = [];
  int _tab = 0;
  bool _loading = true;
  String? _error;

  /// Non-null while an import or export is running: "3 of 12".
  String? _busy;

  List<EfocStickerPack> get _tray => _all.where((p) => !p.archived).toList();
  List<EfocStickerPack> get _archived => _all.where((p) => p.archived).toList();

  EfocStickerPack? get _selected {
    final tray = _tray;
    if (tray.isEmpty) return null;
    return tray[_tab.clamp(0, tray.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? selectPackId}) async {
    try {
      final packs = await StickerService.instance.fetchTray();
      if (!mounted) return;
      setState(() {
        _all = packs;
        _loading = false;
        _error = null;
        final want = selectPackId ?? widget.focusPackId;
        if (want != null) {
          final tray = packs.where((p) => !p.archived).toList();
          final i = tray.indexWhere((p) => p.id == want);
          if (i >= 0) _tab = i;
        } else if (_tab >= _tray.length) {
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

  Future<void> _importWastickers() async {
    final picked = await _pick();
    if (picked.isEmpty || !mounted) return;

    final ImportedPack pack;
    try {
      pack = StickerService.parseWastickers(picked.first.bytes);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    }

    final name = await _askName(pack.name);
    if (name == null || !mounted) return;
    await _createPack(name: name, drafts: pack.stickers, tray: pack.tray);
  }

  Future<void> _importFiles() async {
    final picked = await _pick(multiple: true);
    if (picked.isEmpty || !mounted) return;

    final first = picked.first;
    if (picked.length == 1 && _looksLikePack(first.name)) {
      final ImportedPack pack;
      try {
        pack = StickerService.parseWastickers(first.bytes);
      } on FormatException catch (e) {
        _toast(e.message);
        return;
      }
      final name = await _askName(pack.name);
      if (name == null || !mounted) return;
      await _createPack(name: name, drafts: pack.stickers, tray: pack.tray);
      return;
    }

    final drafts = [
      for (final f in picked) StickerDraft.fromBytes(f.bytes, fileName: f.name),
    ];
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

  /// One place to open a chooser, so a platform failure comes back as a
  /// message instead of a tap that appears to do nothing.
  Future<List<PickedBytes>> _pick({
    bool multiple = false,
    String? accept,
  }) async {
    try {
      return await pickFiles(multiple: multiple, accept: accept);
    } catch (e) {
      _toast("Couldn't open the file picker: $e");
      return const [];
    }
  }

  Future<void> _createPack({
    required String name,
    required List<StickerDraft> drafts,
    StickerDraft? tray,
  }) async {
    setState(() => _busy = 'Uploading 0 of ${drafts.length}');
    try {
      final pack = await StickerService.instance.createPack(
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
      final picked = await _pick(multiple: true);
      for (final f in picked) {
        if (_looksLikePack(f.name)) continue;
        drafts.add(StickerDraft.fromBytes(f.bytes, fileName: f.name));
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
  // Sharing, removing
  // ------------------------------------------------------------

  /// Packs travel by link now. The owner copies it; anyone signed in can open
  /// it and add the pack to their own tray.
  Future<void> _share(EfocStickerPack pack) async {
    await Clipboard.setData(ClipboardData(text: pack.shareUrl));
    if (!mounted) return;
    _toast('Link copied — send it to whoever wants the pack');
  }

  Future<void> _uninstall(EfocStickerPack pack) async {
    final ok = await _confirm(
      title: 'Remove "${pack.name}"?',
      body: 'It leaves your sticker tray. The pack itself is untouched, and '
          'stickers already sent in chats stay where they are.',
      action: 'Remove',
    );
    if (ok != true) return;
    try {
      await StickerService.instance.uninstall(pack.id);
      if (mounted) await _load();
    } catch (e) {
      _toast('Could not remove: $e');
    }
  }

  Future<void> _deletePack(EfocStickerPack pack) async {
    final ok = await _confirm(
      title: 'Delete "${pack.name}" forever?',
      body: 'The pack and its stickers are deleted for everyone who installed '
          'it. Stickers already sent in chats stay where they are.',
      action: 'Delete',
      danger: true,
    );
    if (ok != true) return;
    try {
      await StickerService.instance.deletePack(pack);
      if (mounted) await _load();
    } catch (e) {
      _toast('Could not delete: $e');
    }
  }

  Future<void> _restore(EfocStickerPack pack) async {
    try {
      await StickerService.instance.install(pack.id);
      if (mounted) await _load(selectPackId: pack.id);
    } catch (e) {
      _toast('Could not restore: $e');
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EfocColors.sheetBg,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: TextStyle(
                color: danger ? const Color(0xFFFF6B6B) : null,
              ),
            ),
          ),
        ],
      ),
    );
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

  /// Where stickers come from, in plain words.
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
                'How stickers work here',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12),
              _HelpLine(
                icon: Icons.person_outline,
                title: 'Packs are yours',
                body:
                    'A pack belongs to the person who made it, not to a group. '
                    'It follows you into every chat, and only you can change '
                    'or delete it.',
              ),
              _HelpLine(
                icon: Icons.download_outlined,
                title: 'Sharing is a link',
                body:
                    'Copy a pack\'s link and send it to anyone. They open it '
                    'and tap "Add to my stickers" — no files, no importing.',
              ),
              _HelpLine(
                icon: Icons.file_download_outlined,
                title: 'A .wastickers file',
                body:
                    'WhatsApp has no export button, but sticker makers do. '
                    'Sticker Maker and Sticker.ly save a pack as a '
                    '.wastickers file — that is the one to import.',
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
                icon: Icons.inventory_2_outlined,
                title: 'Eight in the tray',
                body:
                    'Your tray shows eight packs. Add a ninth and the one you '
                    'used longest ago is archived — still installed, just out '
                    'of the way. Restore it any time.',
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

  /// Always visible, even with an empty tray.
  Widget _tabs() {
    final tray = _tray;
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < tray.length; i++) _trayTab(tray[i], i),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showAddMenu,
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
          if (_archived.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: IconButton(
                onPressed: _showArchived,
                tooltip: 'Archived packs',
                icon: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Colors.white38,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: IconButton(
              onPressed: _showHelp,
              tooltip: 'How stickers work here',
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

  Widget _trayTab(EfocStickerPack pack, int index) {
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

  Widget _packHeader(EfocStickerPack pack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  pack.isMine
                      ? 'Yours · ${pack.count} stickers'
                      : 'By someone else · ${pack.count} stickers',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (pack.isMine)
            IconButton(
              onPressed: () => _showPackMenu(pack),
              tooltip: 'Pack options',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.more_horiz,
                size: 20,
                color: Colors.white54,
              ),
            )
          else
            IconButton(
              onPressed: () => _uninstall(pack),
              tooltip: 'Remove from my tray',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: Colors.white38,
              ),
            ),
          IconButton(
            onPressed: () => _share(pack),
            tooltip: 'Copy share link',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.link, size: 19, color: Colors.white54),
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
      itemCount: pack.stickers.length + (pack.isMine ? 1 : 0),
      itemBuilder: (context, i) {
        if (pack.isMine && i == pack.stickers.length) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAddMenu(forPack: pack),
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
            'Make one from photos, import a .wastickers file, or open a link '
            'a friend sends you.',
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
                icon: Icons.add_photo_alternate_outlined,
                label: 'Use photos',
                onTap: _importPhotos,
              ),
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
            ],
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _showHelp,
            child: const Text(
              'How do stickers work here?',
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

  /// The "+" in the tray: a new pack, from a file or from photos.
  Future<void> _showAddMenu({EfocStickerPack? forPack}) async {
    final choice = await _sheetMenu(
      title: forPack == null ? 'New sticker pack' : 'Add to "${forPack.name}"',
      options: forPack == null
          ? const [
              (
                value: 'photos',
                icon: Icons.add_photo_alternate_outlined,
                title: 'From photos',
                subtitle: 'Camera roll, squared to 512 px',
              ),
              (
                value: 'pack',
                icon: Icons.file_download_outlined,
                title: 'Import a .wastickers file',
                subtitle: 'The pack file a sticker maker produces',
              ),
              (
                value: 'files',
                icon: Icons.image_outlined,
                title: 'Pick sticker files',
                subtitle: 'The .webp files copied out of WhatsApp',
              ),
            ]
          : const [
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
    if (!mounted || choice == null) return;

    if (forPack != null) {
      await _addToPack(forPack, choice);
      return;
    }
    if (choice == 'pack') await _importWastickers();
    if (choice == 'files') await _importFiles();
    if (choice == 'photos') await _importPhotos();
  }

  Future<void> _showPackMenu(EfocStickerPack pack) async {
    final choice = await _sheetMenu(
      title: pack.name,
      options: const [
        (
          value: 'add',
          icon: Icons.add_photo_alternate_outlined,
          title: 'Add stickers',
          subtitle: 'From photos or files',
        ),
        (
          value: 'export',
          icon: Icons.ios_share,
          title: 'Save as .wastickers',
          subtitle: 'To use it in WhatsApp or another app',
        ),
        (
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          title: 'Delete pack',
          subtitle: 'For everyone who has it',
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'add') await _showAddMenu(forPack: pack);
    if (choice == 'export') await _exportPack(pack);
    if (choice == 'delete') await _deletePack(pack);
  }

  /// Repacks the pack as a `.wastickers` file, for leaving efoc. Sharing with
  /// someone in the app is the link, not this.
  Future<void> _exportPack(EfocStickerPack pack) async {
    setState(() => _busy = 'Packing ${pack.name}…');
    try {
      final bytes = await StickerService.instance.exportWastickers(pack);
      if (!mounted) return;
      setState(() => _busy = null);
      await saveFile(
        bytes,
        '${pack.slug}.wastickers',
        // octet-stream, not application/zip: Chrome on Android otherwise
        // saves it as <name>.wastickers.zip, and Sticker Maker only takes
        // a file ending in .wastickers.
        mimeType: 'application/octet-stream',
      );
      _toast('Saved — send the file to whoever wants it');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast("Couldn't build that pack: $e");
    }
  }

  void _showArchived() {
    final archived = _archived;
    showModalBottomSheet<void>(
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
            const Text(
              'Archived packs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Out of the tray, still yours.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final pack in archived)
              ListTile(
                leading: SizedBox(
                  width: 32,
                  height: 32,
                  child: pack.iconUrl == null
                      ? const Icon(Icons.auto_awesome, color: Colors.white38)
                      : Image.network(
                          pack.iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.auto_awesome,
                            color: Colors.white38,
                          ),
                        ),
                ),
                title: Text(
                  pack.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  '${pack.count} stickers',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _restore(pack);
                  },
                  child: const Text('Restore'),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
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
