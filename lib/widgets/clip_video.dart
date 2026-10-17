import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Clips recorded with the phone sideways are stored as the camera sees
/// them (scene lying on its side) with rotation = 90. These helpers turn
/// them upright wherever a clip is shown. See 20261017_landscape_clips.sql.

int clipRotationOf(Map<String, dynamic>? clip) =>
    (clip?['rotation'] as num?)?.toInt() ?? 0;

/// Turns [child] 90° counter-clockwise when [rotation] is 90.
class UprightClip extends StatelessWidget {
  final int rotation;
  final Widget child;

  const UprightClip({super.key, required this.rotation, required this.child});

  @override
  Widget build(BuildContext context) =>
      rotation == 90 ? RotatedBox(quarterTurns: 3, child: child) : child;
}

/// Width / height of the clip as it should be shown.
double uprightAspect(VideoPlayerController c, int rotation) {
  final a = c.value.aspectRatio;
  return rotation == 90 ? 1 / a : a;
}

/// A video filling its box (cropping the overflow), turned upright.
class UprightVideoCover extends StatelessWidget {
  final VideoPlayerController controller;
  final int rotation;
  final BoxFit fit;

  const UprightVideoCover({
    super.key,
    required this.controller,
    required this.rotation,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    return ClipRect(
      child: FittedBox(
        fit: fit,
        child: UprightClip(
          rotation: rotation,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
