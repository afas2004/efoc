import 'package:flutter/material.dart';

import '../../models/sticker.dart';
import '../../services/sticker_service.dart';
import '../../theme/colors.dart';

/// A pack opened from a share link: `efoc.party/?pack=<slug>`
///
/// Shows the pack to anyone signed in, whether or not they have it, with one
/// button that puts it in their tray.
class StickerPackScreen extends StatefulWidget {
  final String slug;

  const StickerPackScreen({super.key, required this.slug});

  @override
  State<StickerPackScreen> createState() => _StickerPackScreenState();
}

class _StickerPackScreenState extends State<StickerPackScreen> {
  EfocStickerPack? _pack;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pack = await StickerService.instance.fetchBySlug(widget.slug);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
        _error = pack == null ? 'That pack link no longer works.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    final pack = _pack;
    if (pack == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (pack.installed && !pack.archived) {
        await StickerService.instance.uninstall(pack.id);
      } else {
        await StickerService.instance.install(pack.id);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pack.installed && !pack.archived
                ? 'Removed from your stickers'
                : 'Added to your stickers',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That did not work: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EfocColors.bg,
      appBar: AppBar(
        backgroundColor: EfocColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Sticker pack',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _body(),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final pack = _pack!;
    final inTray = pack.installed && !pack.archived;

    return Column(
      children: [
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 84,
            height: 84,
            child: pack.iconUrl == null
                ? const ColoredBox(color: EfocColors.surface)
                : Image.network(
                    pack.iconUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: EfocColors.surface),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          pack.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${pack.count} stickers',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: pack.stickers.length,
            itemBuilder: (context, i) => Image.network(
              pack.stickers[i].url,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white24,
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      inTray ? EfocColors.surface : EfocColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _busy ? null : _toggle,
                icon: Icon(
                  inTray ? Icons.check : Icons.add,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  _busy
                      ? 'Working…'
                      : inTray
                          ? 'In your stickers'
                          : 'Add to my stickers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
