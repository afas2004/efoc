import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/vlog.dart';
import '../../services/clip_service.dart';
import '../../services/vlog_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';

/// Opens a stitched vlog full-screen and marks it viewed everywhere.
Future<void> openStitchedVlog(
  BuildContext context,
  EfocVlog vlog, {
  required String dayLabel,
}) {
  final state = context.read<AppState>();
  final group = state.groups.where((g) => g.id == vlog.groupId).firstOrNull;
  state.markVlogViewed(vlog);
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VlogViewerScreen.stitched(
        vlog: vlog,
        title: '$dayLabel · ${group?.name ?? 'Log'}',
        groupName: group?.name ?? 'log',
      ),
    ),
  );
}

/// Plays today's clips in the current group back to back. The real stitched
/// file only exists after midnight, so this is a preview, not a download.
Future<void> openTodayPreview(BuildContext context) {
  final state = context.read<AppState>();
  final paths = state.todaysClipsInOrder
      .map((c) => c['storage_path'] as String)
      .toList();
  if (paths.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No clips yet today')),
    );
    return Future.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VlogViewerScreen.today(
        clipPaths: paths,
        title: 'Today · ${state.currentGroup.name}',
      ),
    ),
  );
}

class VlogViewerScreen extends StatefulWidget {
  final String title;

  /// Set for a stitched vlog.
  final EfocVlog? vlog;
  final String groupName;

  /// Set for the "today so far" playlist.
  final List<String> clipPaths;

  const VlogViewerScreen.stitched({
    super.key,
    required EfocVlog this.vlog,
    required this.title,
    required this.groupName,
  }) : clipPaths = const [];

  const VlogViewerScreen.today({
    super.key,
    required this.clipPaths,
    required this.title,
  })  : vlog = null,
        groupName = '';

  bool get isPlaylist => vlog == null;

  @override
  State<VlogViewerScreen> createState() => _VlogViewerScreenState();
}

class _VlogViewerScreenState extends State<VlogViewerScreen> {
  VideoPlayerController? _controller;

  /// Playlist mode: the next clip, initialised ahead of time so clips
  /// follow each other without a loading gap.
  VideoPlayerController? _next;
  int _index = 0;

  String? _error;
  bool _sharing = false;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _next?.dispose();
    super.dispose();
  }

  Future<VideoPlayerController> _load(String url) async {
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    return c;
  }

  Future<void> _start() async {
    try {
      if (widget.isPlaylist) {
        final c = await _load(
          await ClipService.instance.getSignedUrl(widget.clipPaths.first),
        );
        if (!mounted) return c.dispose();
        _controller = c..addListener(_onTick);
        await c.play();
        _preloadNext();
      } else {
        final c = await _load(
          await VlogService.instance.signedUrl(widget.vlog!.storagePath),
        );
        if (!mounted) return c.dispose();
        _controller = c..addListener(_onTick);
        await c.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load vlog');
      debugPrint('Vlog viewer load error: $e');
    }
  }

  Future<void> _preloadNext() async {
    final i = _index + 1;
    if (i >= widget.clipPaths.length) return;
    try {
      final c = await _load(
        await ClipService.instance.getSignedUrl(widget.clipPaths[i]),
      );
      if (!mounted || i != _index + 1) return c.dispose();
      _next = c;
    } catch (e) {
      debugPrint('Preload clip $i failed: $e');
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final ended = v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying;
    if (ended && widget.isPlaylist) {
      _advance();
    } else {
      setState(() {}); // scrubber + play state
    }
  }

  Future<void> _advance() async {
    if (_advancing) return;
    if (_index + 1 >= widget.clipPaths.length) {
      setState(() {});
      return;
    }
    _advancing = true;
    final old = _controller;
    old?.removeListener(_onTick);

    var next = _next;
    _next = null;
    _index++;
    try {
      next ??= await _load(
        await ClipService.instance.getSignedUrl(widget.clipPaths[_index]),
      );
    } catch (e) {
      debugPrint('Clip $_index failed, skipping: $e');
      _advancing = false;
      _controller = old;
      return _advance();
    }
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() => _controller = next!..addListener(_onTick));
    await next.play();
    old?.dispose();
    _advancing = false;
    _preloadNext();
  }

  Future<void> _replayPlaylist() async {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _next?.dispose();
    _controller = null;
    _next = null;
    _index = 0;
    setState(() {});
    await _start();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final atEnd = c.value.position >= c.value.duration;
    if (widget.isPlaylist && atEnd && _index == widget.clipPaths.length - 1) {
      _replayPlaylist();
    } else if (c.value.isPlaying) {
      c.pause();
    } else {
      if (atEnd) c.seekTo(Duration.zero);
      c.play();
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Downloading…')));
    try {
      await VlogService.instance
          .shareVlog(widget.vlog!, groupName: widget.groupName);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Download failed. Try again.')),
      );
      debugPrint('Share vlog error: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String get _subtitle {
    if (widget.isPlaylist) {
      final n = widget.clipPaths.length;
      return 'So far · clip ${_index + 1} of $n · full vlog stitches at midnight';
    }
    final n = widget.vlog!.clipCount;
    return 'Stitched at midnight · $n clip${n == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EfocColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _togglePlay,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: _error != null
                      ? Text(
                          _error!,
                          style: const TextStyle(color: Colors.white54),
                        )
                      : !ready
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: EfocColors.accent,
                              ),
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                AspectRatio(
                                  aspectRatio: c.value.aspectRatio,
                                  child: VideoPlayer(c),
                                ),
                                if (!c.value.isPlaying)
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 38,
                                    ),
                                  ),
                              ],
                            ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  if (widget.isPlaylist)
                    _PlaylistProgress(
                      count: widget.clipPaths.length,
                      index: _index,
                    )
                  else if (ready)
                    VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: VideoProgressColors(
                        playedColor: EfocColors.accent,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  if (!widget.isPlaylist) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: EfocColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: _sharing ? null : _share,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          _sharing ? 'Preparing…' : 'Download vlog',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistProgress extends StatelessWidget {
  final int count;
  final int index;

  const _PlaylistProgress({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i <= index ? EfocColors.accent : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
