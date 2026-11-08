import 'package:flutter/material.dart';

/// Vector silhouette inherits the navigation icon theme without raster assets.
class FoxHeadIcon extends StatelessWidget {
  const FoxHeadIcon({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return CustomPaint(
      size: Size.square(theme.size ?? 25),
      painter: _FoxHeadPainter(
        theme.color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _FoxHeadPainter extends CustomPainter {
  const _FoxHeadPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 30, size.height / 30);
    final face = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(3, 2)
      ..lineTo(11, 7)
      ..quadraticBezierTo(15, 5, 19, 7)
      ..lineTo(27, 2)
      ..lineTo(25, 17)
      ..lineTo(28, 18)
      ..lineTo(21, 23)
      ..lineTo(15, 28)
      ..lineTo(9, 23)
      ..lineTo(2, 18)
      ..lineTo(5, 17)
      ..close()
      ..moveTo(6, 11)
      ..quadraticBezierTo(11, 12, 14, 18)
      ..lineTo(14, 24)
      ..lineTo(8, 19)
      ..close()
      ..moveTo(24, 11)
      ..quadraticBezierTo(19, 12, 16, 18)
      ..lineTo(16, 24)
      ..lineTo(22, 19)
      ..close();
    canvas.drawPath(face, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoxHeadPainter oldDelegate) => color != oldDelegate.color;
}
