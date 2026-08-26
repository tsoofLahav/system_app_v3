import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [Listenable] that never fires while the widget tree is locked.
///
/// Registries are told what changed from `dispose`, which Flutter runs while it
/// unmounts the old tree and forbids `markNeedsBuild`. A listener rebuilding
/// then throws *setState() called when widget tree was locked* — once per
/// listener, so a single closing pane can bury the console.
///
/// Notifying straight away is right whenever the tree is not locked, and
/// waiting for the end of the frame is right when it is. Waiting is only safe
/// mid-frame: post-frame callbacks do not schedule a frame of their own, so a
/// bump made while idle has to be delivered now or it may never arrive.
class FrameSafeNotifier extends ChangeNotifier {
  bool _pending = false;
  var _disposed = false;

  bool get isDisposed => _disposed;

  void notify() {
    if (_disposed) return;
    switch (SchedulerBinding.instance.schedulerPhase) {
      case SchedulerPhase.idle:
      case SchedulerPhase.postFrameCallbacks:
        notifyListeners();
      case SchedulerPhase.transientCallbacks:
      case SchedulerPhase.midFrameMicrotasks:
      case SchedulerPhase.persistentCallbacks:
        if (_pending) return;
        _pending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pending = false;
          if (_disposed) return;
          notifyListeners();
        });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
