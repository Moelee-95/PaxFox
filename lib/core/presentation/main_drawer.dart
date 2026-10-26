import 'package:flutter/material.dart';

enum MainMenuDestination {
  home('Home', Icons.home_outlined),
  transactions('All transactions', Icons.receipt_long_outlined),
  categories('Categories', Icons.category_outlined),
  accounts('Accounts', Icons.account_balance_wallet_outlined),
  settings('Settings', Icons.settings_outlined),
  csv('Import & export CSV', Icons.import_export),
  recurring('Recurring payments', Icons.event_repeat);

  const MainMenuDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MainDrawer extends StatelessWidget {
  const MainDrawer({
    super.key,
    required this.onSelected,
    this.showTransactions = false,
  });

  final ValueChanged<MainMenuDestination> onSelected;
  final bool showTransactions;

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Moneva', style: TextStyle(fontSize: 24)),
          ),
          for (final destination in MainMenuDestination.values)
            ListTile(
              leading: Icon(destination.icon),
              title: Text(destination.label),
              selected:
                  (showTransactions &&
                  destination == MainMenuDestination.transactions),
              onTap: () => onSelected(destination),
            ),
        ],
      ),
    ),
  );
}
