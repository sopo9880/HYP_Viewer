/// Side taps navigate by page index, not by animation direction:
/// left = previous (-1), right = next (+1), center = chrome (0).
/// Reverse mode controls how PageView slides, not which page is selected.
int readerTapDelta({
  required double pointX,
  required double pointY,
  required double width,
  required double height,
  required bool vertical,
  required bool reverse,
}) {
  if (width <= 0 || height <= 0 || pointX < 0 || pointX > width ||
      pointY < 0 || pointY > height) return 0;
  if (pointX >= width * 0.3 && pointX <= width * 0.7) return 0;
  return pointX < width * 0.3 ? -1 : 1;
}
