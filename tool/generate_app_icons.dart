import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

/// Run from the repository root: dart run tool/generate_app_icons.dart.
void main() {
  final source = img.decodePng(
    File('assets/branding/app_icon_source.png').readAsBytesSync(),
  )!;
  if (source.width != source.height) {
    throw StateError('The launcher artwork must be square.');
  }

  // The supplied artwork has black outside its rounded navy tile. Replace
  // only corner-connected black pixels, preserving dark details in the fox.
  final pending = <int>[
    0,
    source.width - 1,
    (source.height - 1) * source.width,
    source.width * source.height - 1,
  ];
  while (pending.isNotEmpty) {
    final index = pending.removeLast();
    final x = index % source.width;
    final y = index ~/ source.width;
    final pixel = source.getPixel(x, y);
    if (pixel.r > 8 || pixel.g > 8 || pixel.b > 8) continue;
    source.setPixelRgb(x, y, 15, 35, 76);
    if (x > 0) pending.add(index - 1);
    if (x + 1 < source.width) pending.add(index + 1);
    if (y > 0) pending.add(index - source.width);
    if (y + 1 < source.height) pending.add(index + source.width);
  }

  void save(String path, img.Image image) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
  }

  img.Image resize(int size) => img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );

  const densities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };
  const res = 'android/app/src/main/res';
  for (final entry in densities.entries) {
    save(
      '$res/mipmap-${entry.key}/ic_launcher.png',
      resize((48 * entry.value).round()),
    );
    // Adaptive layers are 108dp; the artwork occupies the central 66dp safe
    // area so circular and other launcher masks retain the complete fox.
    final size = (108 * entry.value).round();
    final artworkSize = (66 * entry.value).round();
    final layer = img.Image(width: size, height: size, numChannels: 3);
    img.fill(layer, color: img.ColorRgb8(15, 35, 76));
    img.compositeImage(
      layer,
      resize(artworkSize),
      dstX: (size - artworkSize) ~/ 2,
      dstY: (size - artworkSize) ~/ 2,
    );
    save('$res/drawable-${entry.key}/ic_launcher_foreground.png', layer);
  }

  const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final catalog = jsonDecode(
    File('$ios/Contents.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final written = <String>{};
  for (final entry in catalog['images'] as List<dynamic>) {
    final filename = entry['filename'] as String;
    if (!written.add(filename)) continue;
    final points = double.parse((entry['size'] as String).split('x').first);
    final scale = double.parse((entry['scale'] as String).replaceAll('x', ''));
    save('$ios/$filename', resize((points * scale).round()));
  }
  stdout.writeln('Generated Android legacy/adaptive and iOS launcher icons.');
}
