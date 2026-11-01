import 'package:flutter/material.dart';

import '../domain/category.dart';

const categoryColors = <(String, int)>[
  ('Turquoise', 0xff39bbcc),
  ('Indigo', 0xff4956cc),
  ('Slate', 0xff7c90a7),
  ('Coral', 0xffe6676b),
  ('Mint', 0xff55c7a3),
  ('Teal', 0xff6ab8ad),
  ('Gray', 0xff737373),
  ('Periwinkle', 0xff7b89e8),
  ('Violet', 0xff8174a7),
  ('Leaf', 0xff80af61),
  ('Sky', 0xff87c5d9),
  ('Sage', 0xffafcfb8),
  ('Olive', 0xffbdc683),
  ('Mauve', 0xffcb96bc),
  ('Lilac', 0xffd19ee1),
  ('Rose', 0xffdbbbcb),
  ('Orange', 0xffef9167),
  ('Pink', 0xffee8cb4),
  ('Salmon', 0xffefa3a5),
  ('Blush', 0xfff7a9c8),
  ('Peach', 0xfff9c18f),
];

int defaultCategoryColor(CategoryKind kind) =>
    kind == CategoryKind.income ? 0xff39bbcc : 0xff55c7a3;

Color categoryForeground(Color background) =>
    background.computeLuminance() > 0.42
    ? const Color(0xff17212b)
    : Colors.white;
