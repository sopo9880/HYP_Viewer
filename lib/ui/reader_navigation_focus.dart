import 'package:flutter/widgets.dart';

/// Keep keyboard focus away from the underlying search TextField when opening
/// a reader, web search route, or an online search-result bottom sheet.
///
/// Give focus to the dashboard's non-text shortcut scope BEFORE navigation
/// and AGAIN after the route or modal is dismissed. Search text/results remain
/// intact; tapping the field manually can still request focus normally.
abstract final class ReaderNavigationFocus {
  static Future<T> showResult<T>({
    required FocusNode returnFocus,
    required Future<T> Function() openRoute,
    required bool Function() isMounted,
  }) async {
    if (isMounted() && returnFocus.canRequestFocus) {
      returnFocus.requestFocus();
    }
    try {
      return await openRoute();
    } finally {
      if (isMounted()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isMounted() && returnFocus.canRequestFocus) {
            returnFocus.requestFocus();
          }
        });
      }
    }
  }

  /// Existing reader API delegates to the same focus-safe navigation policy.
  static Future<void> show({
    required FocusNode returnFocus,
    required Future<void> Function() openReader,
    required bool Function() isMounted,
  }) => showResult<void>(
    returnFocus: returnFocus,
    openRoute: openReader,
    isMounted: isMounted,
  );
}
