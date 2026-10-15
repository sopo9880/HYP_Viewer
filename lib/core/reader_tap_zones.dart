/// Tapping a physical edge moves in that on-screen direction.
/// With PageView.reverse=false (left-to-right reading), left is previous.
/// With PageView.reverse=true (right-to-left reading), left is next. Vertical scrolling keeps backward/forward
/// zones because horizontal physical movement has no meaning there.
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
  final left = pointX < width * 0.3;
  if (vertical) return left ? -1 : 1;
  return left ? (reverse ? 1 : -1) : (reverse ? -1 : 1);
}
