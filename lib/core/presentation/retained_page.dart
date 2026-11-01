import 'package:flutter/widgets.dart';

/// Lazily mounts a pager destination once, preserving its scroll/controllers.
class RetainedPage extends StatefulWidget {
  const RetainedPage({super.key, required this.child, this.active = true});
  final Widget child;

  /// Hidden inner tabs can defer layout until a tap or swipe needs them.
  /// Main destinations keep the default so their data listeners remain live.
  final bool active;

  @override
  State<RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<RetainedPage>
    with AutomaticKeepAliveClientMixin {
  late Widget _child = widget.child;

  @override
  void didUpdateWidget(RetainedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _child = widget.child;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _child;
  }
}
