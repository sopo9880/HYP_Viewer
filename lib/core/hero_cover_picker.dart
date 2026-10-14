import 'dart:math';

/// Choose a cover from existing library-image keys. Preset placeholders are
/// not real cached images and are intentionally excluded from random artwork.
String? pickRandomLibraryCover(Iterable<String> availableKeys, {
  String? previous,
  Random? random,
}) {
  final keys = availableKeys.toSet().toList()..sort();
  if (keys.isEmpty) return null;
  final options = keys.length > 1 && keys.contains(previous)
      ? keys.where((key) => key != previous).toList()
      : keys;
  return options[(random ?? Random()).nextInt(options.length)];
}
