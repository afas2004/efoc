import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/export_service.dart';
import '../../../services/vlog_service.dart';
import '../../../state/app_state.dart';
import '../../../theme/colors.dart';

/// ⬇ → "Make a vlog": pick Logs and hours from today, get one video,
/// saved straight to the phone. Yesterday only has the full stitched vlog
/// (raw clips are cleared after the midnight stitch), so that tab offers
/// those to save.
Future<void> showMakeVlogSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _MakeVlogSheet(),
  );
}

enum _Phase { pick, working, saved, failed }

class _MakeVlogSheet extends StatefulWidget {
  const _MakeVlogSheet();

  @override
  State<_MakeVlogSheet> createState() => _MakeVlogSheetState();
}

class _MakeVlogSheetState extends State<_MakeVlogSheet> {
  bool _today = true;
  late Set<String> _groups;
  final Set<int> _hours = {}; // empty = every hour
  Map<int, int> _byHour = {};
  bool _loadingHours = true;

  _Phase _phase = _Phase.pick;
  String _status = '';
  String? _error;
  StreamSubscription<EfocExport>? _watch;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _groups = {if (state.hasGroups) state.currentGroup.id};
    _loadHours();
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _loadHours() async {
    setState(() => _loadingHours = true);
    try {
      final byHour =
          await ExportService.instance.todaysClipsByHour(_groups.toList());
      if (!mounted) return;
      setState(() {
        _byHour = byHour;
        _hours.removeWhere((h) => !byHour.containsKey(h));
        _loadingHours = false;
      });
    } catch (e) {
      debugPrint('Load hours error: $e');
      if (mounted) setState(() => _loadingHours = false);
    }
  }

  int get _clipCount => _hours.isEmpty
      ? _byHour.values.fold(0, (a, b) => a + b)
      : _hours.fold(0, (a, h) => a + (_byHour[h] ?? 0));

  String _fileName() {
    final d = DateTime.now();
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final hrs = _hours.isEmpty
        ? 'all'
        : (_hours.toList()..sort()).map((h) => h.toString().padLeft(2, '0')).join('_');
    return 'efoc-$date-$hrs.mp4';
  }

  Future<void> _make() async {
    final fileName = _fileName();
    setState(() {
      _phase = _Phase.working;
      _status = 'Starting…';
      _error = null;
    });
    try {
      final id = await ExportService.instance.start(
        day: DateTime.now(),
        groupIds: _groups.toList(),
        hours: _hours.isEmpty ? null : (_hours.toList()..sort()),
      );
      if (!mounted) return;
      setState(() => _status = 'Stitching… usually 1–2 minutes');
      _watch = ExportService.instance.watch(id).listen((e) async {
        if (!mounted) return;
        if (e.status == 'running') {
          setState(() => _status = 'Stitching your clips…');
        } else if (e.isFailed) {
          setState(() {
            _phase = _Phase.failed;
            _error = e.error ?? 'Something went wrong.';
          });
        } else if (e.isDone) {
          setState(() => _status = 'Downloading…');
          try {
            await ExportService.instance.save(e, fileName: fileName);
            if (mounted) setState(() => _phase = _Phase.saved);
          } catch (err) {
            if (mounted) {
              setState(() {
                _phase = _Phase.failed;
                _error = "It's ready but the download failed. Try ⬇ again.";
              });
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Make vlog error: $e');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = "Couldn't start. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Make a vlog',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            if (_phase == _Phase.pick) ...[
              _DayToggle(
                today: _today,
                onChanged: (v) => setState(() => _today = v),
              ),
              const SizedBox(height: 16),
              if (_today) ..._buildToday() else const _YesterdayList(),
            ] else
              _buildProgress(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildToday() {
    final state = context.watch<AppState>();
    final hours = _byHour.keys.toList()..sort();
    return [
      const _Label('LOGS'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in state.groups)
            _Chip(
              label: g.name,
              on: _groups.contains(g.id),
              onTap: () {
                setState(() {
                  if (_groups.contains(g.id)) {
                    if (_groups.length > 1) _groups.remove(g.id);
                  } else {
                    _groups.add(g.id);
                  }
                });
                _loadHours();
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      const _Label('HOURS'),
      if (_loadingHours)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (hours.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No clips today in these Logs yet.',
            style: TextStyle(color: EfocColors.textMuted, fontSize: 13),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              label: 'All hours',
              on: _hours.isEmpty,
              onTap: () => setState(_hours.clear),
            ),
            for (final h in hours)
              _Chip(
                label: '${_hourLabel(h)} · ${_byHour[h]}',
                on: _hours.contains(h),
                onTap: () => setState(() {
                  if (!_hours.remove(h)) _hours.add(h);
                }),
              ),
          ],
        ),
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: EfocColors.accent,
            disabledBackgroundColor: EfocColors.accent.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          onPressed: _clipCount == 0 ? null : _make,
          child: Text(
            _clipCount == 0
                ? 'Make vlog'
                : 'Make vlog · $_clipCount clip${_clipCount == 1 ? '' : 's'} · ~${_clipCount * 3}s',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Stitched like the midnight vlog, then saved to your phone.',
        textAlign: TextAlign.center,
        style: TextStyle(color: EfocColors.textMuted, fontSize: 11),
      ),
    ];
  }

  Widget _buildProgress() {
    final failed = _phase == _Phase.failed;
    final saved = _phase == _Phase.saved;
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: Center(
            child: saved
                ? const Icon(Icons.check_circle_rounded,
                    color: EfocColors.success, size: 40)
                : failed
                    ? const Icon(Icons.error_outline_rounded,
                        color: EfocColors.danger, size: 40)
                    : SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: EfocColors.accentBright,
                        ),
                      ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          saved
              ? 'Saved to your phone ✓'
              : failed
                  ? (_error ?? 'Something went wrong.')
                  : _status,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_phase == _Phase.working) ...[
          const SizedBox(height: 6),
          const Text(
            "You can close this. We'll send a notification when it's ready, "
            'and it waits under ⬇ for a day.',
            textAlign: TextAlign.center,
            style: TextStyle(color: EfocColors.textMuted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            if (failed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _phase = _Phase.pick),
                  child: const Text('Back'),
                ),
              ),
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  saved ? 'Done' : 'Close',
                  style: TextStyle(color: EfocColors.accentBright),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _hourLabel(int h) =>
      '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';
}

/// Yesterday: the full stitched vlog of each Log, to save as-is.
class _YesterdayList extends StatefulWidget {
  const _YesterdayList();

  @override
  State<_YesterdayList> createState() => _YesterdayListState();
}

class _YesterdayListState extends State<_YesterdayList> {
  String? _saving;
  final Set<String> _saved = {};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final withVlog = state.groups
        .where((g) => state.yesterdayVlog(g.id) != null)
        .toList();

    if (withVlog.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No stitched vlogs from yesterday.',
          textAlign: TextAlign.center,
          style: TextStyle(color: EfocColors.textMuted, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in withVlog)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: EfocColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saving != null
                    ? null
                    : () async {
                        final vlog = state.yesterdayVlog(g.id)!;
                        setState(() => _saving = g.id);
                        state.markVlogViewed(vlog);
                        try {
                          await VlogService.instance
                              .shareVlog(vlog, groupName: g.name);
                          _saved.add(g.id);
                        } catch (e) {
                          debugPrint('Save yesterday error: $e');
                        }
                        if (mounted) setState(() => _saving = null);
                      },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Text('🎬', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${g.name} · ${state.yesterdayVlog(g.id)!.clipCount} clips',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_saving == g.id)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _saved.contains(g.id)
                              ? Icons.check_rounded
                              : Icons.download_rounded,
                          color: _saved.contains(g.id)
                              ? EfocColors.success
                              : EfocColors.textMuted,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          "Yesterday's raw clips are cleared after the midnight stitch, so "
          'only the full vlog can be saved.',
          textAlign: TextAlign.center,
          style: TextStyle(color: EfocColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  final bool today;
  final ValueChanged<bool> onChanged;

  const _DayToggle({required this.today, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool on, bool value) => Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? EfocColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: on ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EfocColors.surface,
        borderRadius: BorderRadius.circular(23),
      ),
      child: Row(
        children: [
          tab('Today · pick hours', today, true),
          tab('Yesterday · full', !today, false),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: EfocColors.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? EfocColors.accent.withValues(alpha: 0.15) : EfocColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? EfocColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? EfocColors.accentBright : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
