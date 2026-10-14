/// Builds fixed web reader links. These are web pages, NOT image manifest URLs.
/// The browser owns page navigation; the app can only remember pages chosen here.
/// Observed website fragment: page 1 is #1- (with trailing dash), pages >=2
/// are #2-3, #3-4 etc. This scheme is unrelated to downloader image URLs.
class HitomiReaderLink {
  static Uri forWork(String workId, {int page = 1}) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호는 숫자 1~12자리여야 해.');
    }
    if (page < 1 || page > 1000000) {
      throw const FormatException('페이지는 1~1000000 사이여야 해.');
    }
    final fragment = page == 1 ? '1-' : '$page-${page + 1}';
    return Uri.parse('https://hitomi.la/reader/$workId.html#$fragment');
  }
}
