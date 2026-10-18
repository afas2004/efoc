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

/// Where a working vlog is, for the step row and the bar.
enum _Step { waiting, stitching, downloading }

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

  _Step _step = _Step.waiting;
  DateTime _startedAt = DateTime.now();
  DateTime _stepAt = DateTime.now();
  double? _download; // 0–1 once the size is known
  int _stitchClips = 0;
  bool _reused = false;
  Timer? _tick;

  /// Fresh stitches left in the rolling 24 hours, once loaded.
  int? _left;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _groups = {if (state.hasGroups) state.currentGroup.id};
    _loadHours();
    _loadLeft();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadLeft() async {
    try {
      final used = await ExportService.instance.usedToday();
      if (mounted) {
        setState(() => _left = (ExportService.dailyLimit - used).clamp(0, 99));
      }
    } catch (e) {
      debugPrint('Export quota error: $e');
    }
  }

  void _setStep(_Step step) {
    if (_step == step) return;
    setState(() {
      _step = step;
      _stepAt = DateTime.now();
    });
  }

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
  }

  /// A rough bar: GitHub takes ~20s to start a runner, then about 3s a
  /// clip plus ~20s to join and upload. Never claims done before it is.
  double get _progress {
    final inStep =
        DateTime.now().difference(_stepAt).inMilliseconds / 1000.0;
    switch (_step) {
      case _Step.waiting:
        return 0.15 * (inStep / 25).clamp(0.0, 1.0);
      case _Step.stitching:
        final expected = _stitchClips * 3 + 20;
        return 0.15 + 0.7 * (inStep / expected).clamp(0.0, 0.95);
      case _Step.downloading:
        return 0.85 + 0.15 * (_download ?? 0);
    }
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
    final groupIds = _groups.toList();
    final hours = _hours.isEmpty ? null : (_hours.toList()..sort());
    final clips = _clipCount;
    setState(() {
      _phase = _Phase.working;
      _status = 'Checking…';
      _error = null;
      _download = null;
      _reused = false;
      _stitchClips = clips;
      _step = _Step.waiting;
      _startedAt = DateTime.now();
      _stepAt = DateTime.now();
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Same vlog as last time and nothing new since: just save it again.
    try {
      final again = await ExportService.instance.findReusable(
        day: DateTime.now(),
        groupIds: groupIds,
        hours: hours,
        clipCount: clips,
      );
      if (again != null && mounted) {
        _reused = true;
        if (await _save(again, fileName)) return;
        // The file's gone (nightly cleanup): stitch a fresh one.
        _reused = false;
      }
    } catch (e) {
      debugPrint('Reuse check error: $e');
    }
    if (!mounted) return;

    if (_left != null && _left! <= 0) {
      _fail("You've made ${ExportService.dailyLimit} vlogs in the last "
          '24 hours. Try again later.');
      return;
    }

    _setStep(_Step.waiting);
    setState(() => _status = 'Waiting for a stitcher…');
    try {
      final id = await ExportService.instance.start(
        day: DateTime.now(),
        groupIds: groupIds,
        hours: hours,
      );
      if (!mounted) return;
      setState(() => _left = _left == null ? null : _left! - 1);
      _watch = ExportService.instance.watch(id).listen((e) async {
        if (!mounted) return;
        if (e.status == 'running') {
          _setStep(_Step.stitching);
          setState(() => _status =
              'Stitching $clips clip${clips == 1 ? '' : 's'}…');
        } else if (e.isFailed) {
          _fail(e.error ?? 'Something went wrong.');
        } else if (e.isDone) {
          if (!await _save(e, fileName) && mounted) {
            _fail("It's ready but the download failed. Try ⬇ again.");
          }
        }
      });
    } catch (e) {
      debugPrint('Make vlog error: $e');
      if (!mounted) return;
      // Most likely the daily cap (RLS) or no connection.
      _loadLeft();
      _fail(_left != null && _left! <= 0
          ? "You've made ${ExportService.dailyLimit} vlogs in the last "
              '24 hours. Try again later.'
          : "Couldn't start. Check your connection and try again.");
    }
  }

  /// Downloads [e] to the phone. False if the download failed.
  Future<bool> _save(EfocExport e, String fileName) async {
    _setStep(_Step.downloading);
    setState(() => _status = _reused
        ? 'No new clips since your last one. Saving it again…'
        : 'Downloading…');
    try {
      await ExportService.instance.save(
        e,
        fileName: fileName,
        onProgress: (p) {
          if (mounted) setState(() => _download = p);
        },
      );
      _stopTicking();
      if (mounted) setState(() => _phase = _Phase.saved);
      return true;
    } catch (err) {
      debugPrint('Save vlog error: $err');
      return false;
    }
  }

  void _fail(String message) {
    _stopTicking();
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
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
      Text(
        [
          'Stitched like the midnight vlog, then saved to your phone.',
          if (_left != null)
            '$_left of ${ExportService.dailyLimit} left today. '
                'Making the same one again is free.',
        ].join('\n'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: EfocColors.textMuted, fontSize: 11),
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
                    : _StepRow(step: _step, reused: _reused),
          ),
        ),
        if (_phase == _Phase.working) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: EfocColors.surface,
              color: EfocColors.accentBright,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _reused
                ? _elapsed()
                : '${_elapsed()} · usually 1–2 minutes',
            textAlign: TextAlign.center,
            style: const TextStyle(color: EfocColors.textMuted, fontSize: 11),
          ),
        ],
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

  String _elapsed() {
    final d = DateTime.now().difference(_startedAt);
    final m = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  static String _hourLabel(int h) =>
      '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';
}

/// Waiting → Stitching → Saving, with the current step lit.
class _StepRow extends StatelessWidget {
  final _Step step;
  final bool reused;

  const _StepRow({required this.step, required this.reused});

  @override
  Widget build(BuildContext context) {
    final steps = reused
        ? const [(_Step.downloading, 'Saving')]
        : const [
            (_Step.waiting, 'Starting'),
            (_Step.stitching, 'Stitching'),
            (_Step.downloading, 'Saving'),
          ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Container(
              width: 18,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: EfocColors.textMuted,
            ),
          _StepDot(
            label: steps[i].$2,
            done: steps[i].$1.index < step.index,
            current: steps[i].$1 == step,
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;

  const _StepDot({
    required this.label,
    required this.done,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final color = done || current ? EfocColors.accentBright : EfocColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        else
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 13,
            color: color,
          ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
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
