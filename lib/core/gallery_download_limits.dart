/// User-configurable soft limits for authorized gallery downloads.
///
/// Explicit retry of a failed size-limit download may bypass the soft limits
/// for ONE work, but never the absolute hard safety limits, provider rights,
/// HTTPS origin rules or file type checks.
class GalleryDownloadLimits {
  static const int mib = 1024 * 1024;

  static const int defaultImageMiB = 35;
  static const int defaultTotalMiB = 165;
  static const int defaultArchiveMiB = 180;

  /// Deliberate hard caps: avoid unlimited responses or zip bombs.
  static const int hardImageMiB = 128;
  static const int hardTotalMiB = 1024;
  static const int hardArchiveMiB = 1024;
  static const int hardUncompressedMiB = 1536;

  final int imageMiB;
  final int totalMiB;
  final int archiveMiB;

  const GalleryDownloadLimits({
    this.imageMiB = defaultImageMiB,
    this.totalMiB = defaultTotalMiB,
    this.archiveMiB = defaultArchiveMiB,
  });

  const GalleryDownloadLimits.maximum()
      : imageMiB = hardImageMiB,
        totalMiB = hardTotalMiB,
        archiveMiB = hardArchiveMiB;

  int get imageBytes => imageMiB * mib;
  int get totalBytes => totalMiB * mib;
  int get archiveBytes => archiveMiB * mib;

  static int sanitizeMiB(Object? value, int fallback, int hardMaximum) {
    if (value is! int || value < 1 || value > hardMaximum) return fallback;
    return value;
  }

  GalleryDownloadLimits get validated => GalleryDownloadLimits(
        imageMiB: sanitizeMiB(imageMiB, defaultImageMiB, hardImageMiB),
        totalMiB: sanitizeMiB(totalMiB, defaultTotalMiB, hardTotalMiB),
        archiveMiB: sanitizeMiB(archiveMiB, defaultArchiveMiB, hardArchiveMiB),
      );

  GalleryDownloadLimits effective({bool allowSizeOverride = false}) =>
      allowSizeOverride ? const GalleryDownloadLimits.maximum() : validated;
}

/// Explicit size failures can be persisted without raw URLs or error bodies.
/// The code is stable and permits a one-work size-limit retry.
class GallerySizeLimitException extends FormatException {
  final String code;
  final int? measuredBytes;
  final int limitBytes;

  GallerySizeLimitException._(this.code, this.measuredBytes, this.limitBytes,
      String description) : super(description);

  static GallerySizeLimitException image(int? size, int limitBytes) =>
      GallerySizeLimitException._(
        'DOWNLOAD_IMAGE_SIZE_LIMIT', size, limitBytes,
        '이미지 한 장 용량이 설정 한도 ' + _describe(limitBytes) + '를 초과했어.',
      );

  static GallerySizeLimitException total(int size, int limitBytes) =>
      GallerySizeLimitException._(
        'DOWNLOAD_TOTAL_SIZE_LIMIT', size, limitBytes,
        '작품 이미지 총용량이 설정 한도 ' + _describe(limitBytes) + '를 초과했어.',
      );

  static GallerySizeLimitException archive(int size, int limitBytes) =>
      GallerySizeLimitException._(
        'DOWNLOAD_ARCHIVE_SIZE_LIMIT', size, limitBytes,
        '완성된 CBZ 용량이 설정 한도 ' + _describe(limitBytes) + '를 초과했어.',
      );

  static String _describe(int bytes) =>
      (bytes / mib).toStringAsFixed(0) + 'MiB';

  /// Legacy 0.4.22 records used DOWNLOAD_FAILED for several FormatExceptions.
  /// Manual user retries may opt in for that code; automatic ones never do.
  static bool allowsExplicitRetry(String code) => const {
    'DOWNLOAD_IMAGE_SIZE_LIMIT',
    'DOWNLOAD_TOTAL_SIZE_LIMIT',
    'DOWNLOAD_ARCHIVE_SIZE_LIMIT',
    'IMAGE_SIZE_LIMIT',
    'DOWNLOAD_FAILED',
  }.contains(code);
}
