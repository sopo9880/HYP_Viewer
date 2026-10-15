import 'package:flutter/widgets.dart';

/// Reader navigation should not restore focus to an underlying search field:
/// on Android that reopens the IME as soon as the route is popped.
///
/// Give keyboard focus to the dashboard's non-text shortcut scope BEFORE
/// pushing the reader and AGAIN after its pop transition is complete.
/// Search text remains intact and the field can be tapped normally later.
abstract final class ReaderNavigationFocus {
  static Future<void> show({
    required FocusNode returnFocus,
    required Future<void> Function() openReader,
    required bool Function() isMounted,
  }) async {
    if (isMounted() && returnFocus.canRequestFocus) {
      returnFocus.requestFocus();
    }
    try {
      await openReader();
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
}
