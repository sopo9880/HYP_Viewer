import 'package:flutter/material.dart';

/// Built-in cover art palettes: no font/image files or third-party assets.
class CoverPalettes {
  static const colors = <List<Color>>[
    [Color(0xFF3E247B), Color(0xFF0B1428), Color(0xFF8D5CF6)],
    [Color(0xFF13505B), Color(0xFF071F29), Color(0xFF4EC6C0)],
    [Color(0xFF9B3C64), Color(0xFF26102E), Color(0xFFF4A07A)],
    [Color(0xFF735321), Color(0xFF201B18), Color(0xFFE6B96C)],
    [Color(0xFF415AA8), Color(0xFF101B44), Color(0xFFB5D7FF)],
    [Color(0xFF4A785E), Color(0xFF12271A), Color(0xFFB1DDB7)],
  ];
  static const names = <String>[
    '바이올렛', '오션', '로즈', '앰버', '블루', '포레스트',
  ];
  static const symbols = <IconData>[
    Icons.auto_stories_rounded,
    Icons.water_rounded,
    Icons.favorite_rounded,
    Icons.star_rounded,
    Icons.nights_stay_rounded,
    Icons.forest_rounded,
  ];
}
