import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'web_search_ad_rule_store.dart';

/// Network-first ad blocking for HYP's isolated Hitomi search WebViews.
/// Both Android WebView and Windows WebView2 support shouldInterceptRequest.
/// First-party gallery pages, CDN media and main-frame navigations are safe.
class WebSearchAdBlock {
  static const modes = <String>['off', 'standard', 'strong'];

  // Built-in rules work offline and before an optional EasyList update.
  static const Set<String> _adHosts = {
    'doubleclick.net', 'googlesyndication.com',
    'googleadservices.com', 'adservice.google.com',
    'google-analytics.com', 'googletagmanager.com',
    'googletagservices.com', '2mdn.net', 'adnxs.com',
    'adsrvr.org', 'adform.net', 'adcolony.com',
    'adroll.com', 'adsterra.com', 'adsterra.net',
    'adtechus.com', 'advertising.com', 'amazon-adsystem.com',
    'a-ads.com', 'bidswitch.net', 'bidgear.com',
    'bidvertiser.com', 'casalemedia.com', 'contextweb.com',
    'crwdcntrl.net', 'exoclick.com', 'exosrv.com',
    'exoticads.com', 'exdynsrv.com', 'ero-advertising.com',
    'evoload.io', 'gamboladvertising.com', 'hilltopads.net',
    'infolinks.com', 'juicyads.com', 'jsmcr.net',
    'lijit.com', 'linksynergy.com', 'mobidea.com',
    'myclick-2.com', 'onclicka.com', 'onclickads.net',
    'onclasrv.com', 'oneclickads.net', 'popads.net',
    'popcash.net', 'popunder.net', 'popunderjs.com',
    'propellerads.com', 'propeller-tracking.com',
    'pushame.com', 'pushground.com', 'revcontent.com',
    'revenuehits.com', 'richpush.com', 'rtbhouse.com',
    'sape.ru', 'smartadserver.com', 'spotxchange.com',
    'tabunder.com', 'trafficjunky.net', 'trafficstars.com',
    'trafficforce.com', 'trafficfactory.biz', 'tradedoubler.com',
    'tsyndicate.com', 'tynt.com', 'unityads.unity3d.com',
    'viglink.com', 'yadro.ru', 'zedo.com',
  };

  static const Set<String> _strongHosts = {
    'taboola.com', 'outbrain.com', 'mgid.com',
    'scorecardresearch.com', 'criteo.com', 'criteo.net',
    'quantserve.com', 'rubiconproject.com', 'pubmatic.com',
    'openx.net', 'sharethrough.com', 'imrworldwide.com',
    'moatads.com', 'newrelic.com', 'hotjar.com',
    'yandex.ru', 'yieldmo.com', 'zergnet.com',
  };

  static final RegExp _strongPath = RegExp(
    r'/(?:ads?|adserver|advertis(?:e|ement|ing)|banner|popunder|'
    r'prebid|vast|sponsor(?:ed)?|tracking|analytics)'
    r'(?:[./_-]|$)', caseSensitive: false,
  );

  static bool isFirstParty(Uri? uri) {
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'hitomi.la' || host.endsWith('.hitomi.la');
  }

  static bool shouldBlock(Uri? uri, String mode, {
    bool isMainFrame = false,
    Set<String> additionalDomains = const {},
  }) {
    if (mode == 'off' || isMainFrame || uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        isFirstParty(uri)) return false;
    final host = uri.host.toLowerCase();
    if (WebSearchAdRuleStore.matchesHost(host, _adHosts) ||
        WebSearchAdRuleStore.matchesHost(host, additionalDomains)) {
      return true;
    }
    if (mode == 'strong') {
      if (WebSearchAdRuleStore.matchesHost(host, _strongHosts)) return true;
      // Hostnames starting with a dedicated ad/tracker label are suspicious
      // on third-party origins, but legitimate image/gallery hosts are not.
      final first = host.split('.').first;
      if (RegExp(r'^(?:ads?|adserver|advert|tracker|popunder)(?:[0-9_-].*)?$')
          .hasMatch(first)) return true;
      if (_strongPath.hasMatch(uri.path)) return true;
    }
    return false;
  }

  /// Return an empty resource *before* a blocked network request is issued.
  /// Returning null lets WebView load all legitimate scripts, search results,
  /// gallery covers and metadata normally.
  static WebResourceResponse? intercept(WebResourceRequest request,
      String mode, {void Function()? onBlocked}) {
    final uri = Uri.tryParse(request.url.toString());
    if (!shouldBlock(uri, mode,
        isMainFrame: request.isForMainFrame == true,
        additionalDomains: WebSearchAdRuleStore.instance.domains)) {
      return null;
    }
    onBlocked?.call();
    return WebResourceResponse(
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      statusCode: 200,
      reasonPhrase: 'OK',
      headers: const {'Access-Control-Allow-Origin': '*'},
      data: Uint8List(0),
    );
  }

  /// Android content blockers are defense in depth. Network interception
  /// above is used on both Windows and Android including downloaded rules.
  static List<ContentBlocker> contentBlockers(String mode) {
    if (mode == 'off') return const [];
    final domains = <String>{..._adHosts,
      if (mode == 'strong') ..._strongHosts};
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

  /// Inject at document start and again after load. The MutationObserver
  /// removes dynamic ad containers without removing gallery/search links.
  static const String cleanPageJavaScript = r'''(function () {
    if (!/^(?:[\w-]+\.)*hitomi\.la$/i.test(location.hostname)) return;
    if (window.__hypAdCleaning) return;
    window.__hypAdCleaning = true;
    var selectors = [
      'ins.adsbygoogle', '[data-ad-slot]', '[data-ad-client]',
      '.adsbygoogle', '.ad-banner', '.ad-container', '.ad-placement',
      '.ad-wrapper', '.advertisement', '.advertising', '.sponsor-banner',
      '.popunder', '.popup-ad', '.sticky-ad',
      'iframe[src*="doubleclick"]', 'iframe[src*="exoclick"]',
      'iframe[src*="popads"]', 'iframe[src*="exosrv"]',
      'iframe[src*="adsterra"]', 'iframe[src*="onclicka"]',
      'iframe[src*="propellerads"]'
    ];
    var css = selectors.join(',') +
      '{display:none!important;visibility:hidden!important;pointer-events:none!important;}';
    function clean() {
      var root = document.head || document.documentElement;
      if (!root) return;
      if (!document.getElementById('__hypAdCss')) {
        var style = document.createElement('style');
        style.id = '__hypAdCss';
        style.textContent = css;
        root.appendChild(style);
      }
      try {
        document.querySelectorAll(selectors.join(',')).forEach(function (node) {
          node.remove();
        });
      } catch (_) {}
    }
    var scheduled = false;
    var observer = new MutationObserver(function () {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(function () { scheduled = false; clean(); });
    });
    if (document.documentElement) {
      observer.observe(document.documentElement,
        {childList:true, subtree:true});
    }
    // Prevent script-created and unsolicited popup tabs in this embedded
    // search view. Top-level site navigation remains handled by native code.
    window.open = function () { return null; };
    document.addEventListener('click', function (event) {
      var target = event.target;
      var link = target && target.closest && target.closest('a[target="_blank"]');
      if (!link) return;
      try {
        if (new URL(link.href, location.href).hostname !== location.hostname) {
          event.preventDefault();
          event.stopPropagation();
        } else {
          link.target = '_self';
        }
      } catch (_) {}
    }, true);
    clean();
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', clean, {once: true});
    }
  })();''';
}
