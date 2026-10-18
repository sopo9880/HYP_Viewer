/// Windows tray and close-policy state; intentionally free of native plugins.
///
/// In particular, an idle "X quits" window must NOT keep native close
/// prevention enabled. Only active downloads warrant an exit confirmation.
class WindowsTrayState {
  bool exitOnClose = false;
  int activeLeases = 0;
  bool installerActive = false;
  int queuedCount = 0;
  bool canPause = false;
  bool paused = false;
  String workId = '';
  String recentTitle = '';
  int pagesDone = 0;
  int pagesTotal = 0;
  int successfulDownloads = 0;
  double installerProgress = 0;

  bool get hasActiveTransfers => activeLeases > 0 || installerActive;

  bool get preventClose => !exitOnClose || hasActiveTransfers;

  bool get needsExitConfirmation => hasActiveTransfers;

  int? get galleryPercent => pagesTotal > 0
      ? (pagesDone * 100 ~/ pagesTotal).clamp(0, 100).toInt()
      : null;

  int get installerPercent =>
      (installerProgress * 100).round().clamp(0, 100).toInt();

  bool get showPause => canPause && activeLeases > 0 && !installerActive;

  bool get canCancel => activeLeases > 0 || queuedCount > 0;

  void setGalleryProgress(int done, int total, {
    required String currentWorkId,
    required int pendingCount,
    required bool isPaused,
  }) {
    pagesDone = done.clamp(0, total > 0 ? total : 0).toInt();
    pagesTotal = total > 0 ? total : 0;
    workId = currentWorkId;
    queuedCount = pendingCount < 0 ? 0 : pendingCount;
    paused = isPaused;
  }

  void resetGallery() {
    workId = '';
    pagesDone = 0;
    pagesTotal = 0;
    paused = false;
    canPause = false;
  }

  void resetInstaller() {
    installerActive = false;
    installerProgress = 0;
  }

  void recordCompletion() {
    successfulDownloads++;
  }

  int takeCompletions() {
    final completed = successfulDownloads;
    successfulDownloads = 0;
    return completed;
  }
}
