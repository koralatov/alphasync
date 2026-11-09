// This file belongs only to the Apple Silicon app target. Shared behaviour stays in AlphaSyncUI.
#if !arch(arm64)
#error("The Apple Silicon edition must be compiled for arm64 only.")
#endif
#if !AS_SILICON_EDITION
#error("The Apple Silicon edition must use its dedicated target configuration.")
#endif

// Add genuine Apple Silicon-only integrations here when a feature needs one.
// Swift concurrency and the current USB file protocol are shared by both editions.
