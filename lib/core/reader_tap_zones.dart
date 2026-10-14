/// Physical tap zones for the paged reader.
///
/// Tapping the left edge acts like swiping LEFT; the right edge like swiping
/// RIGHT. RTL books reverse the reading direction. Vertical readers use the
/// top/bottom halves instead. Webtoon scrolling disables discrete tap turns.
int readerTapDelta({
  required double pointX,
  required double pointY,
  required double width,
  required double height,
  required bool vertical,
  required bool reverse,
}) {
  if (width <= 0 || height <= 0) return 0;
  final topOrLeft = vertical ? pointY < height / 2 : pointX < width / 2;
  if (vertical) return topOrLeft ? (reverse ? 1 : -1)
                                : (reverse ? -1 : 1);
  return topOrLeft ? (reverse ? -1 : 1) : (reverse ? 1 : -1);
}
