enum CapturePhase {
  setup,      // before Start
  counting,   // 3..2..1
  recording,  // 2s recording
  compose,    // frozen frame + text + groups
}