import 'package:flutter/material.dart';

import 'fox_head_icon.dart';

/// Soft capsule navigation. Only the pill and destination styles animate;
/// the shell retains ownership of its cached pages and page controller.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xffb69aff) : const Color(0xff7c4dff);
    final muted = dark ? const Color(0xffaaa8b1) : const Color(0xff85858b);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(44),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0xff303039), Color(0xff222229)]
                  : const [Color(0xfffdfefe), Color(0xffeff1f2)],
            ),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .10)
                  : Colors.white.withValues(alpha: .95),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .16 : .045),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 4;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Stack(
                        children: [
                          AnimatedPositionedDirectional(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            start: selectedIndex * width,
                            top: 0,
                            bottom: 0,
                            width: width,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(40),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: dark
                                      ? const [
                                          Color(0xff41414c),
                                          Color(0xff30303a),
                                        ]
                                      : const [Colors.white, Color(0xfff7f8f8)],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: dark ? .15 : .95,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: dark ? .18 : .065,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: NavigationBarTheme(
                      data: NavigationBarThemeData(
                        labelTextStyle: WidgetStateProperty.resolveWith(
                          (states) => TextStyle(
                            fontSize: 12,
                            fontWeight: states.contains(WidgetState.selected)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: states.contains(WidgetState.selected)
                                ? accent
                                : muted,
                          ),
                        ),
                        iconTheme: WidgetStateProperty.resolveWith(
                          (states) => IconThemeData(
                            size: 25,
                            color: states.contains(WidgetState.selected)
                                ? accent
                                : muted,
                          ),
                        ),
                      ),
                      child: NavigationBar(
                        height: 76,
                        animationDuration: duration,
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        indicatorColor: Colors.transparent,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onSelected,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            selectedIcon: Icon(Icons.dashboard),
                            label: 'Overview',
                          ),
                          NavigationDestination(
                            icon: FoxHeadIcon(),
                            label: 'Cashflow',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.more_horiz),
                            label: 'More',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
