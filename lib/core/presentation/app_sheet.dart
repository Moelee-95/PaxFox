import 'package:flutter/material.dart';

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool editor = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: !editor,
    enableDrag: !editor,
    backgroundColor: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 650),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
  );
}

class SelectionSheet extends StatelessWidget {
  const SelectionSheet({
    super.key,
    required this.title,
    required this.child,
    this.toolbar,
    this.footer,
  });
  final String title;
  final Widget child;
  final Widget? toolbar, footer;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .68,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (toolbar != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: toolbar!,
            ),
          const Divider(height: 24),
          Expanded(child: child),
          ?footer,
        ],
      ),
    ),
  );
}
