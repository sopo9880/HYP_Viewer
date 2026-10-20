import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/web_search_ad_block.dart';
import 'package:hyp_viewer/core/web_search_ad_rule_store.dart';

void main() {
  test('Built-in and updated host lists block ads but not gallery images', () {
    expect(WebSearchAdBlock.modes, ['off', 'standard', 'strong']);
    for (final uri in [
      Uri.parse('https://ads.exoclick.com/api/ad.js'),
      Uri.parse('https://popads.net/show.js'),
      Uri.parse('https://www.doubleclick.net/resource'),
      Uri.parse('https://a.trafficjunky.net/banner.js'),
      Uri.parse('https://onclicka.com/display'),
    ]) {
      expect(WebSearchAdBlock.shouldBlock(uri, 'standard'), isTrue,
          reason: uri.toString());
      expect(WebSearchAdBlock.shouldBlock(uri, 'off'), isFalse);
    }
    for (final safe in [
      Uri.parse('https://hitomi.la/search.html?q=test'),
      Uri.parse('https://ltn.gold-usergeneratedcontent.net/123.webp'),
      Uri.parse('https://w1.gold-usergeneratedcontent.net/img.jpg'),
      Uri.parse('https://example.com/gallery/123'),
    ]) {
      expect(WebSearchAdBlock.shouldBlock(safe, 'strong'), isFalse,
          reason: safe.toString());
    }
    expect(WebSearchAdBlock.shouldBlock(
      Uri.parse('https://ads.exoclick.com/t.js'), 'strong',
      isMainFrame: true), isFalse);
    expect(WebSearchAdBlock.shouldBlock(
      Uri.parse('https://cdn.example.com/banner/track.js'), 'standard'),
      isFalse);
    expect(WebSearchAdBlock.shouldBlock(
      Uri.parse('https://cdn.example.com/banner/ad.js'), 'strong'),
      isTrue);
  });

  test('Subscription parser accepts safe EasyList host rules only', () {
    const source = '''
! public comments
||ads.example.org^
||track.example.net^\$third-party
@@||allowed.example.org^
||notads.example.org^\$script
||evil*.example.org^
##.banner
/^badregex/
||sub.ads.example.co.uk^
''';
    final domains = WebSearchAdRuleStore.parseDomains(source);
    expect(domains, containsAll(['ads.example.org',
      'track.example.net', 'sub.ads.example.co.uk']));
    expect(domains, isNot(contains('allowed.example.org')));
    expect(domains, isNot(contains('notads.example.org')));
    expect(domains, isNot(contains('evil*.example.org')));
    expect(WebSearchAdRuleStore.matchesHost(
      'sub.ads.example.org', domains), isTrue);
    expect(WebSearchAdBlock.shouldBlock(
      Uri.parse('https://sub.ads.example.org/ad.js'), 'standard',
      additionalDomains: domains), isTrue);
    expect(WebSearchAdBlock.shouldBlock(
      Uri.parse('https://sub.ads.example.org/ad.js'), 'off',
      additionalDomains: domains), isFalse);
  });

  test('WebResourceRequest interception prevents real ad fetches', () {
    int blocked = 0;
    final request = WebResourceRequest(
      url: WebUri('https://adsterra.com/banners/pop.js'),
      isForMainFrame: false,
    );
    final response = WebSearchAdBlock.intercept(request, 'standard',
        onBlocked: () => blocked++);
    expect(response, isNotNull);
    expect(response!.statusCode, 200);
    expect(response.data, isEmpty);
    expect(blocked, 1);
    expect(WebSearchAdBlock.intercept(request, 'off'), isNull);
    expect(WebSearchAdBlock.intercept(
      WebResourceRequest(
        url: WebUri('https://hitomi.la/search.html?q=hello'),
        isForMainFrame: true,
      ), 'strong'), isNull);
    expect(WebSearchAdBlock.contentBlockers('standard').length,
        greaterThan(50));
    expect(WebSearchAdBlock.contentBlockers('off'), isEmpty);
  });

  test('Manual and automatic WebViews wire Windows/Android interception', () {
    final manual = File('lib/ui/hitomi_web_search_page.dart').readAsStringSync();
    final automatic = File('lib/ui/auto_hitomi_web_search.dart').readAsStringSync();
    for (final webview in [manual, automatic]) {
      expect(webview, contains('useShouldInterceptRequest: true'));
      expect(webview, contains('shouldInterceptRequest:'));
      expect(webview, contains('WebSearchAdBlock.intercept('));
      expect(webview, contains('onCreateWindow:'));
      expect(webview, contains('AT_DOCUMENT_START'));
      expect(webview, contains('WebSearchAdRuleStore.instance.ensureStarted()'));
    }
    expect(manual, contains('webAdBlockBlockedLabel'));
    expect(manual, contains("ValueKey('hitomi-ad-block-"));
    expect(WebSearchAdBlock.cleanPageJavaScript, contains('MutationObserver'));
    expect(WebSearchAdBlock.cleanPageJavaScript, contains('window.open'));
  });
}
