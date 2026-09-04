/// Session ops vs last-session cache for Home visit membership.
///
/// Server GET is the base. This-session add/remove replay on top. Yesterday's
/// prefs never PUT just because the server list is empty.
enum HomeVisitOpKind { add, remove }

class HomeVisitOp {
  const HomeVisitOp.add(this.fileId) : kind = HomeVisitOpKind.add;
  const HomeVisitOp.remove(this.fileId) : kind = HomeVisitOpKind.remove;

  final HomeVisitOpKind kind;
  final int fileId;
}

/// Drop ops the server already reflects.
List<HomeVisitOp> ackHomeVisitOps(List<int> serverIds, List<HomeVisitOp> ops) {
  return [
    for (final op in ops)
      if (op.kind == HomeVisitOpKind.add
          ? !serverIds.contains(op.fileId)
          : serverIds.contains(op.fileId))
        op,
  ];
}

/// Apply un-ACK'd session ops onto the server list (adds go to the front).
List<int> applyHomeVisitOps(List<int> serverIds, List<HomeVisitOp> ops) {
  final out = List<int>.from(serverIds);
  for (final op in ops) {
    out.remove(op.fileId);
    if (op.kind == HomeVisitOpKind.add) {
      out.insert(0, op.fileId);
    }
  }
  return out;
}

/// GET result + leftover session ops. [null] server means the fetch failed —
/// keep [fallback] (paint / offline), do not treat empty prefs as authority.
List<int> mergeHomeVisitIds({
  required List<int>? serverIds,
  required List<HomeVisitOp> pendingOps,
  List<int> fallback = const [],
}) {
  if (serverIds == null) return List<int>.from(fallback);
  final pending = ackHomeVisitOps(serverIds, pendingOps);
  return applyHomeVisitOps(serverIds, pending);
}
