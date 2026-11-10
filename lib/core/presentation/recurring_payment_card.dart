import 'package:flutter/material.dart';

import '../domain/category.dart';
import '../domain/ledger.dart';
import '../domain/recurring.dart';
import 'category_icons.dart';

/// Presentation only: the switch uses the store's existing pause/resume path.
class RecurringPaymentCard extends StatelessWidget {
  const RecurringPaymentCard({
    super.key,
    required this.rule,
    required this.currency,
    required this.accountName,
    required this.onEdit,
    required this.onDelete,
    required this.onActiveChanged,
    this.categoryIcon = CategoryIcon.general,
    this.categoryColor,
    this.pendingDate,
    this.today,
    this.activeValue,
  });
  final RecurringRule rule;
  final Currency currency;
  final String accountName;
  final CategoryIcon categoryIcon;
  final int? categoryColor;
  final DateTime? pendingDate, today;
  final bool? activeValue;
  final VoidCallback? onEdit, onDelete;
  final ValueChanged<bool>? onActiveChanged;

  String get schedule {
    final interval = rule.interval;
    return switch (rule.frequency) {
      RecurrenceFrequency.day =>
        interval == 1 ? 'Daily' : 'Every $interval days',
      RecurrenceFrequency.week =>
        '${interval == 1 ? 'Weekly' : 'Every $interval weeks'} · ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][(rule.day - 1).clamp(0, 6)]}',
      RecurrenceFrequency.month =>
        '${interval == 1 ? 'Monthly' : 'Every $interval months'} · Day ${rule.day}',
      RecurrenceFrequency.year =>
        '${interval == 1 ? 'Yearly' : 'Every $interval years'} · ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][(rule.month - 1).clamp(0, 11)]} ${rule.day}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = activeValue ?? rule.active;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final income = rule.type == EntryType.income;
    final current = dateOnly(today ?? DateTime.now());
    final due = dateOnly(pendingDate ?? rule.nextDate);
    final ended =
        pendingDate == null &&
        rule.endDate != null &&
        rule.nextDate.isAfter(rule.endDate!);
    final isToday = due == current;
    final tomorrow =
        due == DateTime(current.year, current.month, current.day + 1);
    final overdue = due.isBefore(current);
    final accent = !active || ended
        ? colors.onSurfaceVariant
        : income
        ? (dark ? const Color(0xff75cc94) : const Color(0xff439b55))
        : (dark ? const Color(0xffff9290) : const Color(0xffdf4146));
    final amountColor = income
        ? (dark ? const Color(0xff75cc94) : const Color(0xff279449))
        : (dark ? const Color(0xffff9290) : const Color(0xffdf4146));
    final badge = !active
        ? 'PAUSED'
        : ended
        ? 'ENDED'
        : overdue
        ? 'OVERDUE'
        : isToday
        ? 'TODAY'
        : tomorrow
        ? 'TOMORROW'
        : null;
    final status = !active
        ? 'Paused · scheduled ${dayKey(rule.nextDate)}'
        : ended
        ? 'Schedule ended'
        : overdue
        ? 'Overdue · ${dayKey(due)}'
        : isToday
        ? 'Due today!'
        : tomorrow
        ? 'Due tomorrow'
        : 'Next: ${dayKey(due)}';
    final iconColor = categoryColor == null
        ? income
              ? const Color(0xff65b9ab)
              : const Color(0xffe786af)
        : Color(categoryColor!);
    final foreground =
        ThemeData.estimateBrightnessForColor(iconColor) == Brightness.dark
        ? Colors.white
        : const Color(0xff25313a);
    // Keep the original tap area while reducing only the visible switch size.
    final controls = GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: onActiveChanged == null ? () {} : () => onActiveChanged!(!active),
      child: Tooltip(
        message: active ? 'Pause' : 'Resume',
        child: Transform.scale(
          scale: .8,
          child: Switch(
            key: ValueKey('recurring-active-${rule.id}'),
            value: active,
            onChanged: onActiveChanged,
            activeTrackColor: const Color(0xff2fc35b),
            activeThumbColor: Colors.white,
            inactiveTrackColor: colors.surfaceContainerHighest,
            inactiveThumbColor: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
    final deleteButton = IconButton(
      tooltip: 'Delete recurring rule',
      onPressed: onDelete,
      icon: const Icon(Icons.delete_outline, size: 26),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      color: colors.onSurfaceVariant,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [controls, deleteButton],
    );
    final price = Text(
      currency.display(rule.amount),
      style: theme.textTheme.titleLarge?.copyWith(
        color: amountColor,
        fontWeight: FontWeight.w800,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rule.description,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          schedule,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$accountName · ${rule.automatic ? 'Automatic' : 'Manual · ${TimeOfDay(hour: rule.reminderMinutes ~/ 60, minute: rule.reminderMinutes % 60).format(context)}'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    final icon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: iconColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: categoryGlyph(
          categoryIconData(categoryIcon),
          size: 23,
          color: foreground,
        ),
      ),
    );
    return Card(
      key: ValueKey('recurring-card-${rule.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Color.alphaBlend(
        accent.withValues(alpha: dark ? .085 : .065),
        colors.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: accent.withValues(alpha: dark ? .7 : .85),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badge != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          ThemeData.estimateBrightnessForColor(accent) ==
                              Brightness.dark
                          ? Colors.white
                          : const Color(0xff15241a),
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: 10),
                      Expanded(child: details),
                    ],
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: price),
                            const SizedBox(width: 12),
                            actions,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .42,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [price, const SizedBox(height: 3), actions],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            ColoredBox(
              color: accent.withValues(alpha: dark ? .14 : .11),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
