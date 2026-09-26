import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/clip_service.dart';
import '../../services/video_remux_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import 'capture_phase.dart';
import 'capture_stage.dart';
import 'widgets/big_countdown.dart';
import 'widgets/capture_actions.dart';
import 'widgets/draggable_text_overlay.dart';
import 'widgets/group_chips.dart';
import 'widgets/rec_pip.dart';
import 'widgets/text_toolbar.dart';

class CaptureScreen extends StatefulWidget {
  final int hour;

  const CaptureScreen({super.key, required this.hour});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with TickerProviderStateMixin {
  // Fixed portrait. No picker, no forced screen rotation.
  static const String _ratio = '9x16';

  // ---------- capture state ----------
  CapturePhase _phase = CapturePhase.setup;

  // text
  String _text = 'Good morning!';
  String _fontKey = 'classic';
  Color _textColor = Colors.white;
  Offset _textAlign = const Offset(0, -0.3);

  // groups
  late Set<String> _selectedGroups;

  // countdown
  int _countValue = 3;
  late final AnimationController _ringController;

  // recording timer
  Timer? _recordTimer;

  // ---------- camera state ----------
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _cameraReady = false;
  String? _cameraError;

  // recorded file
  XFile? _recordedFile;

  // compose preview player
  VideoPlayerController? _videoController;

  // ---------- upload state ----------
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    final current = context.read<AppState>().currentGroup.id;
    _selectedGroups = {current};

    _initCamera();
  }

  @override
  void dispose() {
    _ringController.dispose();
    _recordTimer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ============================================================
  // CAMERA
  // ============================================================
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No camera detected');
        return;
      }
      final frontIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = frontIdx >= 0 ? frontIdx : 0;
      await _openCamera(_cameras[_cameraIndex]);
    } catch (e) {
      setState(() => _cameraError = 'Camera unavailable: $e');
    }
  }

  Future<void> _openCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraError = null;
      });
      Future.microtask(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      await controller.dispose();
      if (mounted) {
        setState(() => _cameraError = 'Camera init failed: $e');
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    await _cameraController?.dispose();
    setState(() {
      _cameraReady = false;
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    });
    await _openCamera(_cameras[_cameraIndex]);
  }

  // ============================================================
  // CAPTURE FLOW
  // ============================================================
  void _startCapture() {
    if (!_cameraReady || _cameraController == null) return;
    setState(() {
      _phase = CapturePhase.counting;
      _countValue = 3;
    });
    _ringController.forward(from: 0);
    _ringController.addListener(_onRingTick);
  }

  void _onRingTick() {
    final remaining = 3 - (_ringController.value * 3);
    final newCount = remaining.ceil().clamp(0, 3);
    if (newCount != _countValue) {
      setState(() => _countValue = newCount);
    }
    if (_ringController.isCompleted) {
      _ringController.removeListener(_onRingTick);
      _beginRecording();
    }
  }

  Future<void> _beginRecording() async {
    setState(() => _phase = CapturePhase.recording);
    try {
      await _cameraController!.startVideoRecording();
    } catch (e) {
      setState(() {
        _phase = CapturePhase.setup;
        _cameraError = 'Recording failed: $e';
      });
      return;
    }

    _recordTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final file = await _cameraController!.stopVideoRecording();
        await _cameraController!.pausePreview();

        final fixedUrl = await VideoRemuxService.fixForLooping(file.path);

        if (!mounted) return;

        final uri = kIsWeb ? Uri.parse(fixedUrl) : Uri.file(fixedUrl);
        final controller = VideoPlayerController.networkUrl(uri);
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();

        if (!mounted) {
          await controller.dispose();
          return;
        }

        setState(() {
          _recordedFile = file;
          _videoController = controller;
          _phase = CapturePhase.compose;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = CapturePhase.setup;
          _cameraError = 'Save failed: $e';
        });
      }
    });
  }

  // ============================================================
  // SEND / UPLOAD
  // ============================================================
  Future<void> _sendClip() async {
    if (_recordedFile == null) {
      _showError('No recording to send');
      return;
    }
    if (_selectedGroups.isEmpty) {
      _showError('Pick at least one Log');
      return;
    }

    setState(() => _uploading = true);

    final colorHex =
        '#${_textColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

    int successCount = 0;
    final errors = <String>[];

    for (final groupId in _selectedGroups) {
      try {
        await ClipService.instance.uploadClip(
          filePath: _recordedFile!.path,
          groupId: groupId,
          hour: widget.hour,
          text: _text,
          fontKey: _fontKey,
          textColorHex: colorHex,
          ratio: _ratio,
        );
        successCount++;
      } catch (e) {
        errors.add('$groupId: $e');
      }
    }

    if (!mounted) return;

    if (successCount > 0) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent to $successCount Log${successCount != 1 ? "s" : ""} ✓',
          ),
          duration: const Duration(milliseconds: 1400),
        ),
      );
    } else {
      setState(() => _uploading = false);
      _showError(errors.isNotEmpty ? errors.first : 'Upload failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: EfocColors.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_selectedGroups.contains(groupId)) {
        _selectedGroups.remove(groupId);
      } else {
        _selectedGroups.add(groupId);
      }
    });
  }

  // ============================================================
  // BUILD
  // ============================================================
  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  Widget? _buildPreview() {
    if (_phase == CapturePhase.compose) {
      final vc = _videoController;
      if (vc == null || !vc.value.isInitialized) {
        return Container(
          color: const Color(0xFF0A0A0A),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white24,
            ),
          ),
        );
      }
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: vc.value.size.width,
            height: vc.value.size.height,
            child: VideoPlayer(vc),
          ),
        ),
      );
    }

    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white24,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.hardEdge,
      child: SizedBox.expand(
        child: CameraPreview(_cameraController!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final isSetup = phase == CapturePhase.setup;
    final isCompose = phase == CapturePhase.compose;
    final isCounting = phase == CapturePhase.counting;
    final isRecording = phase == CapturePhase.recording;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      _CircleBtn(
                        icon: Icons.close,
                        onTap: _uploading
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _formatHour(widget.hour),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _CircleBtn(icon: Icons.more_horiz, onTap: () {}),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    isCompose
                        ? 'Add text, pick groups, then send'
                        : '2 seconds · one shot · no retakes',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: CaptureStage(
                      ratio: _ratio,
                      preview: _buildPreview(),
                      children: [
                        if (isCompose)
                          Container(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        if (isCounting)
                          BigCountdown(
                            value: _countValue,
                            progress: _ringController.value,
                          ),
                        if (isRecording) const RecPip(),
                        if (isCompose)
                          DraggableTextOverlay(
                            text: _text,
                            fontKey: _fontKey,
                            color: _textColor,
                            alignment: _textAlign,
                            onAlignmentChanged: (a) =>
                                setState(() => _textAlign = a),
                          ),
                      ],
                    ),
                  ),
                ),
                if (isCompose) ...[
                  TextToolbar(
                    text: _text,
                    fontKey: _fontKey,
                    color: _textColor,
                    onTextChanged: (v) => setState(() => _text = v),
                    onFontChanged: (v) => setState(() => _fontKey = v),
                    onColorChanged: (v) => setState(() => _textColor = v),
                  ),
                  const SizedBox(height: 10),
                  GroupChips(
                    selected: _selectedGroups,
                    onToggle: _toggleGroup,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                  child: _uploading
                      ? const _UploadingBar()
                      : CaptureActions(
                          phase: phase,
                          selectedCount: _selectedGroups.length,
                          onFlip: _flipCamera,
                          onStart: _startCapture,
                          onSend: _sendClip,
                        ),
                ),
              ],
            ),
            if (_uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: EfocColors.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _UploadingBar extends StatelessWidget {
  const _UploadingBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: EfocColors.accent.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(26),
      ),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Uploading…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}