import 'package:flutter/material.dart';

class InfoButton extends StatelessWidget {
  const InfoButton({
    super.key,
    required this.title,
    required this.message,
    this.details,
  });

  final String title;
  final String message;
  final Widget? details;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: message,
    icon: Icon(Icons.info_outline, semanticLabel: title),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(message), ?details],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
