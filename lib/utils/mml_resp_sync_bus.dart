import 'dart:async';

/// Notifies Helper 1 when Helper 5 minimal monitoring is saved (5.2.A sync).
class MmlRespSavedEvent {
  final String enrollmentId;
  final String sheetYmd;

  const MmlRespSavedEvent({
    required this.enrollmentId,
    required this.sheetYmd,
  });
}

class MmlRespSyncBus {
  MmlRespSyncBus._();

  static final _controller = StreamController<MmlRespSavedEvent>.broadcast();

  static Stream<MmlRespSavedEvent> get stream => _controller.stream;

  static void notifySaved({
    required String enrollmentId,
    required String sheetYmd,
  }) {
    final eid = enrollmentId.trim();
    final ymd = sheetYmd.length >= 10 ? sheetYmd.substring(0, 10) : sheetYmd.trim();
    if (eid.isEmpty || ymd.isEmpty) return;
    _controller.add(MmlRespSavedEvent(enrollmentId: eid, sheetYmd: ymd));
  }
}
