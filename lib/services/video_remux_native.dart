Future<String> fixForLooping(String inputPath) async {
  // Android's CameraX already writes MP4 with proper seek metadata.
  // No remux needed — this was a WebM-only problem.
  return inputPath;
}