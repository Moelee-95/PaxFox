import 'package:flutter/widgets.dart';

/// Lazily mounts a pager destination once, preserving its scroll/controllers.
class RetainedPage extends StatefulWidget {
  const RetainedPage({super.key, required this.child});
  final Widget child;

  @override
  State<RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
