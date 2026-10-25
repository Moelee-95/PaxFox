import 'package:flutter/material.dart';

import '../domain/category.dart';
import '../domain/ledger.dart';

IconData categoryIconData(CategoryIcon icon) => switch (icon) {
  CategoryIcon.general => Icons.category_outlined,
  CategoryIcon.groceries => Icons.local_grocery_store_outlined,
  CategoryIcon.dining => Icons.restaurant_outlined,
  CategoryIcon.transport => Icons.directions_bus_outlined,
  CategoryIcon.home => Icons.home_outlined,
  CategoryIcon.health => Icons.health_and_safety_outlined,
  CategoryIcon.shopping => Icons.shopping_bag_outlined,
  CategoryIcon.entertainment => Icons.movie_outlined,
  CategoryIcon.education => Icons.school_outlined,
  CategoryIcon.insurance => Icons.shield_outlined,
  CategoryIcon.subscriptions => Icons.subscriptions_outlined,
  CategoryIcon.travel => Icons.flight_outlined,
  CategoryIcon.salary => Icons.payments_outlined,
  CategoryIcon.freelance => Icons.work_outline,
  CategoryIcon.investments => Icons.trending_up,
  CategoryIcon.gifts => Icons.card_giftcard,
  CategoryIcon.pets => Icons.pets_outlined,
  CategoryIcon.savings => Icons.savings_outlined,
};

Color transactionColor(EntryType type) => switch (type) {
  EntryType.expense => Colors.red,
  EntryType.income => Colors.green,
  EntryType.refund => Colors.yellow.shade700,
  EntryType.transfer => Colors.blue,
};
