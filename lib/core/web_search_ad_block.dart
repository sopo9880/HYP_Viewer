import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Conservative, offline ad-domain rules for HYP's Hitomi search WebViews.
/// Never blocks the main document, gallery images or first-party resources.
/// These are intentionally bounded instead of accepting remote executable lists.
class WebSearchAdBlock {
  static const modes = <String>['off', 'standard', 'strong'];
  static const _advertisingDomains = <String>[
    'doubleclick.net', 'googlesyndication.com',
    'googleadservices.com', 'adservice.google.com',
    'exoclick.com', 'exosrv.com', 'popads.net',
    'propellerads.com', 'onclicka.com',
    'trafficjunky.net', 'juicyads.com',
    'adsterra.com', 'adsrvr.org', 'adnxs.com',
  ];
  static const _strongOnlyDomains = <String>[
    'taboola.com', 'outbrain.com', 'mgid.com',
    'scorecardresearch.com', 'criteo.com',
  ];

  static bool isFirstParty(Uri? uri) {
    if (uri == null) return false;
    return uri.host == 'hitomi.la' || uri.host.endsWith('.hitomi.la');
  }

  static bool shouldBlock(Uri? uri, String mode, {bool isMainFrame = false}) {
    if (mode == 'off' || isMainFrame || uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        isFirstParty(uri)) return false;
    final host = uri.host.toLowerCase();
    final domains = [
      ..._advertisingDomains,
      if (mode == 'strong') ..._strongOnlyDomains,
    ];
    return domains.any((domain) => host == domain || host.endsWith('.' + domain));
  }

  static List<ContentBlocker> contentBlockers(String mode) {
    if (mode == 'off') return const [];
    final domains = [
      ..._advertisingDomains,
      if (mode == 'strong') ..._strongOnlyDomains,
    ];
    return [
      for (final domain in domains)
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: r'^https?://([a-z0-9-]+\.)*' +
                domain.replaceAll('.', r'\.') + r'([/:?#]|$)',
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
    ];
  }

  /// On Windows this additionally removes empty ad containers; it is safe on
  /// Android too. No gallery card/title/image or site navigation is touched.
  static const String cleanPageJavaScript = r'''(function () {
    if (window.__hypAdStyleInstalled) return;
    window.__hypAdStyleInstalled = true;
    var style = document.createElement('style');
    style.textContent = [
      'ins.adsbygoogle',
      '.ad-banner',
      '.advertisement',
      '.ad-container',
      '.adsbygoogle',
      'iframe[src*="doubleclick.net"]',
      'iframe[src*="exoclick.com"]',
      'iframe[src*="popads.net"]'
    ].join(',') + '{display:none!important;visibility:hidden!important;}';
    (document.head || document.documentElement).appendChild(style);
  })();''';
}
