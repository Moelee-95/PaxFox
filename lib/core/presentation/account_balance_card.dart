import 'package:flutter/material.dart';

import '../domain/ledger.dart';

class AccountBalanceCard extends StatelessWidget {
  const AccountBalanceCard({
    super.key,
    required this.account,
    required this.balance,
  });

  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 184,
    child: Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                account.currency.display(balance),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: balance < 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
            Text(
              !account.available
                  ? 'Blocked'
                  : account.kind == AccountKind.cash
                  ? 'Cash'
                  : 'Bank',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
