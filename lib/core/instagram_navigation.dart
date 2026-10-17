/// A narrow URL policy for the user-controlled Instagram inspector.
/// Allow Instagram content and the two Facebook HTTPS login hosts only;
/// block custom schemes, suspicious userinfo and non-standard ports.
/// A user-initiated popup may first open 'about:blank' before the target loads.
abstract final class InstagramNavigation {
  static bool isAllowed(Uri? uri, {bool popup = false}) {
    if (uri == null) return false;
    if (popup && uri.scheme == 'about' && uri.path == 'blank') return true;
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasPort || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'instagram.com' ||
        host.endsWith('.instagram.com') ||
        host == 'facebook.com' ||
        host == 'www.facebook.com' ||
        host == 'm.facebook.com';
  }

  static bool isInstagram(Uri? uri) {
    if (uri == null || !isAllowed(uri)) return false;
    final host = uri.host.toLowerCase();
    return host == 'instagram.com' || host.endsWith('.instagram.com');
  }
}
