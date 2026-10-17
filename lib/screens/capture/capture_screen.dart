import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/clip_service.dart';
import '../../services/video_remux_service.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../../widgets/caption.dart';
import '../../widgets/clip_video.dart';
import 'capture_phase.dart';
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
  // Recorded with the phone sideways (top to the left) while the app stays
  // portrait: the camera's 2:3 portrait frames hold a 3:2 landscape scene.
  // Stored as a label only (clips.aspect_ratio). The column's check
  // constraint allows 9:16, 1:1 and 16:9, so landscape is filed as 16:9;
  // playback uses the video's real 3:2 size.
  static const String _ratio = '16x9';
  static const int _sidewaysRotation = 90;

  static const _clipLength = Duration(seconds: 3);
  static const _readyLength = Duration(seconds: 1);

  // ---------- capture state ----------
  CapturePhase _phase = CapturePhase.setup;

  // text
  String _text = '';
  String _fontKey = 'classic';
  String _highlight = kDefaultHighlight;
  Color _textColor = Colors.white;
  Offset _textAlign = Offset(kDefaultCaptionAlignment.x, kDefaultCaptionAlignment.y);

  // groups
  late Set<String> _selectedGroups;

  // "Ready?" ring
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
      duration: _readyLength,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _phase == CapturePhase.counting) {
          _beginRecording();
        }
      });

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
      if (!kIsWeb) {
        // Same as the web: frames stay portrait, the clip is turned
        // upright on playback (rotation = 90), not by the phone.
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }
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
    setState(() => _phase = CapturePhase.counting);
    _ringController.forward(from: 0);
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

    _recordTimer = Timer(_clipLength, () async {
      try {
        final file = await _cameraController!.stopVideoRecording();
        await _cameraController!.pausePreview();

        final fixedUrl = await VideoRemuxService.fixForLooping(
          file.path,
          _clipLength.inMilliseconds,
        );

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
        // Preview was paused for the compose step; bring it back so the
        // error isn't sitting on a frozen frame.
        await _cameraController?.resumePreview().catchError((_) {});
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
          mimeType: _recordedFile!.mimeType,
          textX: _textAlign.dx,
          textY: _textAlign.dy,
          rotation: _sidewaysRotation,
          textBg: _highlight,
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

  /// Live camera, filling [the landscape canvas]. The canvas is drawn
  /// rotated for a phone held sideways, so the feed is turned back
  /// (UprightClip) to stay as the camera sees it.
  Widget _buildLivePreview() {
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

    final controller = _cameraController;
    if (!_cameraReady || controller == null) {
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

    // previewSize is reported landscape (sensor); the feed itself is
    // portrait because the app is locked to portrait.
    final ps = controller.value.previewSize ?? const Size(720, 480);
    final w = ps.shortestSide, h = ps.longestSide;
    final preview = CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: UprightClip(
          rotation: _sidewaysRotation,
          child: SizedBox(width: w, height: h, child: preview),
        ),
      ),
    );
  }

  /// Insets of the physical screen, mapped onto the rotated canvas
  /// (canvas left = screen top, canvas top = screen right, ...).
  EdgeInsets _canvasInsets(BuildContext context) {
    final p = MediaQuery.of(context).padding;
    return EdgeInsets.fromLTRB(
      p.top + 12,
      p.right + 12,
      p.bottom + 12,
      p.left + 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final isSetup = phase == CapturePhase.setup;
    final isCompose = phase == CapturePhase.compose;
    final isCounting = phase == CapturePhase.counting;
    final isRecording = phase == CapturePhase.recording;
    final pad = _canvasInsets(context);

    // After recording the phone goes back upright: a normal portrait page.
    if (isCompose) return _buildCompose();

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: RotatedBox(
        // Drawn for a phone turned counter-clockwise (top to the left).
        quarterTurns: 1,
        child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildLivePreview(),
                  if (isCounting) BigCountdown(progress: _ringController),
                  if (isRecording) const RecPip(),

                  // Top bar: close · hour · flip
                  Positioned(
                    left: pad.left,
                    right: pad.right,
                    top: pad.top,
                    child: Row(
                      children: [
                        _CircleBtn(
                          icon: Icons.close,
                          onTap: isCounting || isRecording
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _formatHour(widget.hour),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black54),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '3 seconds · one shot · no retakes',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black54),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSetup)
                          _CircleBtn(
                            icon: Icons.flip_camera_android_rounded,
                            onTap: _flipCamera,
                          )
                        else
                          const SizedBox(width: 38),
                      ],
                    ),
                  ),

                  if (isSetup) const _RotateHint(),

                  // Start / Ready? / Recording…
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: pad.bottom,
                    child: Center(
                      child: SizedBox(
                        width: 280,
                        child: CaptureActions(
                          phase: phase,
                          selectedCount: _selectedGroups.length,
                          showFlip: false,
                          onFlip: _flipCamera,
                          onStart: _startCapture,
                          onSend: _sendClip,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// After recording, phone upright again: the clip as a wide landscape
  /// box at the top, the text and Log tools below it.
  Widget _buildCompose() {
    final vc = _videoController;
    final ready = vc != null && vc.value.isInitialized;

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
                      const SizedBox(width: 38),
                    ],
                  ),
                ),
                const Text(
                  'Add text, drag it into place, pick Logs, then send',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: AspectRatio(
                        aspectRatio: ready
                            ? uprightAspect(vc, _sidewaysRotation)
                            : 3 / 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (ready)
                                UprightVideoCover(
                                  controller: vc,
                                  rotation: _sidewaysRotation,
                                )
                              else
                                const ColoredBox(
                                  color: Color(0xFF0A0A0A),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white24,
                                      ),
                                    ),
                                  ),
                                ),
                              DraggableTextOverlay(
                                text: _text,
                                fontKey: _fontKey,
                                color: _textColor,
                                highlight: _highlight,
                                alignment: _textAlign,
                                onAlignmentChanged: (a) =>
                                    setState(() => _textAlign = a),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextToolbar(
                  text: _text,
                  fontKey: _fontKey,
                  color: _textColor,
                  highlight: _highlight,
                  onTextChanged: (v) => setState(() => _text = v),
                  onFontChanged: (v) => setState(() => _fontKey = v),
                  onColorChanged: (v) => setState(() => _textColor = v),
                  onHighlightChanged: (v) => setState(() => _highlight = v),
                ),
                const SizedBox(height: 10),
                GroupChips(
                  selected: _selectedGroups,
                  onToggle: _toggleGroup,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                  child: _uploading
                      ? const _UploadingBar()
                      : CaptureActions(
                          phase: CapturePhase.compose,
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
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Turn your phone" nudge on the setup screen.
class _RotateHint extends StatelessWidget {
  const _RotateHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Turn your phone sideways',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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