/// Side 30% taps turn pages, center 40% returns zero for immersive UI toggle.
/// On horizontal pages the physical gesture follows the reading direction.
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
  if (vertical) return pointX < width * 0.3 ? -1 : 1;
  return pointX < width * 0.3
      ? (reverse ? -1 : 1)
      : (reverse ? 1 : -1);
}
