import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Clips recorded with the phone sideways are stored as the camera sees
/// them (scene lying on its side): rotation = 90 for the back camera (turn
/// counter-clockwise to show upright), 270 for the front camera (turn
/// clockwise). These helpers turn them upright wherever a clip is shown.

int clipRotationOf(Map<String, dynamic>? clip) =>
    (clip?['rotation'] as num?)?.toInt() ?? 0;

/// Turns [child] upright: 90 → counter-clockwise, 270 → clockwise.
class UprightClip extends StatelessWidget {
  final int rotation;
  final Widget child;

  const UprightClip({super.key, required this.rotation, required this.child});

  @override
  Widget build(BuildContext context) =>
      switch (rotation) {
        90 => RotatedBox(quarterTurns: 3, child: child),
        270 => RotatedBox(quarterTurns: 1, child: child),
        _ => child,
      };
}

/// Width / height of the clip as it should be shown.
double uprightAspect(VideoPlayerController c, int rotation) {
  final a = c.value.aspectRatio;
  return rotation == 90 || rotation == 270 ? 1 / a : a;
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
