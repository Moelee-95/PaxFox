import 'package:flutter/material.dart';

/// Shared pill indicator follows TabController taps and finger-driven swipes.
class OutlinedTabs extends StatelessWidget {
  const OutlinedTabs({
    super.key,
    required this.controller,
    required this.colors,
    required this.tabs,
    this.isScrollable = false,
    this.padding,
    this.labelPadding,
  }) : assert(colors.length == tabs.length);

  static const expense = Color(0xffdf373f);
  static const income = Color(0xff249b6a);
  static const overview = Color(0xff1976d2);

  final TabController controller;
  final List<Color> colors;
  final List<Widget> tabs;
  final bool isScrollable;
  final EdgeInsetsGeometry? padding, labelPadding;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.animation!,
    builder: (context, _) {
      final position = controller.animation!.value.clamp(
        0.0,
        colors.length - 1.0,
      );
      final lower = position.floor();
      final upper = position.ceil();
      final color = Color.lerp(colors[lower], colors[upper], position - lower)!;
      return TabBar(
        controller: controller,
        isScrollable: isScrollable,
        tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
        physics: isScrollable ? const NeverScrollableScrollPhysics() : null,
        padding: padding,
        labelPadding: labelPadding,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: color,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        splashBorderRadius: BorderRadius.circular(32),
        indicator: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color, width: 2),
        ),
        tabs: tabs,
      );
    },
  );
}
