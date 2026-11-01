import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/presentation/profile_editor.dart';

enum MoreDestination {
  transactions(
    'All transactions',
    'Search and manage your transactions',
    Icons.receipt_long_outlined,
    Colors.teal,
  ),
  categories(
    'Categories',
    'Organize your income and spending',
    Icons.category_outlined,
    Colors.orange,
  ),
  accounts(
    'Accounts',
    'Manage your accounts and outstanding debts',
    Icons.account_balance_wallet_outlined,
    Colors.green,
  ),
  recurring(
    'Recurring payments',
    'Manage your scheduled income and expenses',
    Icons.event_repeat,
    Colors.purple,
  ),
  csv(
    'Import & export CSV',
    'Bring in transactions or export your records',
    Icons.import_export,
    Colors.cyan,
  ),
  settings(
    'Settings',
    'Manage your invoice extraction preferences',
    Icons.settings_outlined,
    Colors.indigo,
  );

  const MoreDestination(this.label, this.subtitle, this.icon, this.color);
  final String label;
  final String subtitle;
  final IconData icon;
  final MaterialColor color;
}

const _supportOptions = [
  (
    title: 'Help & FAQ',
    subtitle: 'Frequently asked questions',
    icon: Icons.help_outline,
    color: Colors.blue,
  ),
  (
    title: 'Rate App',
    subtitle: 'Share your experience with us',
    icon: Icons.star_outline,
    color: Colors.amber,
  ),
  (
    title: 'Changelog',
    subtitle: "What's new and updates",
    icon: Icons.history,
    color: Colors.purple,
  ),
  (
    title: 'Privacy Policy',
    subtitle: 'Data protection and privacy',
    icon: Icons.privacy_tip_outlined,
    color: Colors.pink,
  ),
  (
    title: 'Terms and Conditions',
    subtitle: 'Service and usage terms',
    icon: Icons.description_outlined,
    color: Colors.cyan,
  ),
  (
    title: 'About',
    subtitle: 'About PaxFox',
    icon: Icons.info_outline,
    color: Colors.blueGrey,
  ),
];

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, required this.store, required this.onSelected});
  final LedgerStore store;
  final ValueChanged<MoreDestination> onSelected;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String title, String subtitle) =>
      '$title $subtitle'.toLowerCase().contains(_query);

  Future<void> _editProfile() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProfileEditor(store: widget.store),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final destinations = MoreDestination.values
        .where((item) => _matches(item.label, item.subtitle))
        .toList();
    final support = _supportOptions
        .where((item) => _matches(item.title, item.subtitle))
        .toList();
    // Keep off-screen cards out of the build/layout work when opening More.
    final rows = <WidgetBuilder>[
      (_) => _ProfileCard(store: widget.store, onEdit: _editProfile),
      (_) => const SizedBox(height: 24),
      (_) => TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search options...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: colors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                ),
        ),
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
      ),
      if (destinations.isNotEmpty) ...[
        (_) => const _SectionTitle('Manage'),
        for (final item in destinations)
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              color: colors.surfaceContainerLowest,
              clipBehavior: Clip.antiAlias,
              child: _OptionTile(
                title: item.label,
                subtitle: item.subtitle,
                icon: item.icon,
                color: item.color,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  widget.onSelected(item);
                },
              ),
            ),
          ),
      ],
      if (support.isNotEmpty) ...[
        (_) => const _SectionTitle('Support'),
        (_) => Card(
          margin: EdgeInsets.zero,
          color: colors.surfaceContainerLowest,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < support.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 80),
                _OptionTile(
                  title: support[i].title,
                  subtitle: support[i].subtitle,
                  icon: support[i].icon,
                  color: support[i].color,
                ),
              ],
            ],
          ),
        ),
        (_) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            'Support options are coming soon.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
      if (destinations.isEmpty && support.isEmpty)
        (_) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text('No matching options.', textAlign: TextAlign.center),
        ),
      (_) => const SizedBox(height: 32),
      (_) => Text(
        'PaxFox',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      (_) => const SizedBox(height: 4),
      (_) => Text(
        'Your money, in view.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 712),
        child: ListView.builder(
          key: const PageStorageKey('more-options'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index](context),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.store, required this.onEdit});
  final LedgerStore store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final avatar = CircleAvatar(
      radius: 30,
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      child: const Icon(Icons.person, size: 34),
    );
    final edit = IconButton.filledTonal(
      tooltip: 'Edit profile',
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          store.profileName.isEmpty ? 'Your profile' : store.profileName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          store.profileEmail.isEmpty
              ? 'Personalize your local profile'
              : store.profileEmail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Card(
      key: const ValueKey('more-profile-card'),
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 22;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [avatar, const Spacer(), edit]),
                      const SizedBox(height: 16),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      avatar,
                      const SizedBox(width: 16),
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      edit,
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final MaterialColor color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color.withValues(alpha: dark ? 0.18 : 0.09),
        foregroundColor: dark ? color.shade200 : color.shade700,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
