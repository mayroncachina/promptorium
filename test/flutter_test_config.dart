import 'dart:async';

import 'package:promptorium/ui/theme/motion.dart';

/// Animations are off in the suite (SPEC-034): a test of another subject
/// should not depend on how long a transition takes. Tests of motion set
/// [AppMotion.enabled] back to true.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppMotion.enabled = false;
  await testMain();
}
