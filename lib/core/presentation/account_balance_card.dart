import 'package:flutter/material.dart';

import '../domain/ledger.dart';

class AccountBalanceCard extends StatelessWidget {
  const AccountBalanceCard({
    super.key,
    required this.account,
    required this.balance,
    required this.onEdit,
  });

  final Account account;
  final int balance;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                !account.available
                    ? Icons.lock_outline
                    : account.kind == AccountKind.cash
                    ? Icons.payments_outlined
                    : Icons.account_balance_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: account.name,
                  child: Text(
                    account.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit ${account.name}',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              account.reportingCurrency.display(account.toBase(balance)),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: balance < 0 ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
          if (account.currency != account.reportingCurrency)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                account.currency.display(balance),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
}
