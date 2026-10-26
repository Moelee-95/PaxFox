import 'package:flutter/services.dart';

import '../domain/number_format.dart';

/// Groups money as it is edited, preserving fractional digits and caret position.
class GroupedAmountFormatter extends TextInputFormatter {
  const GroupedAmountFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var text = newValue.text;
    var decimalComma = -1;
    final replacingAll =
        oldValue.selection.start == 0 &&
        oldValue.selection.end == oldValue.text.length;
    final editingGrouped = oldValue.text.contains(',') && !replacingAll;
    if (editingGrouped) {
      // A newly typed comma is a decimal key; existing commas are grouping.
      final offset = oldValue.selection.start;
      if (oldValue.selection.isCollapsed &&
          offset >= 0 &&
          text.length == oldValue.text.length + 1 &&
          text[offset] == ',' &&
          text.replaceRange(offset, offset + 1, '') == oldValue.text) {
        decimalComma = offset;
      }
      text = String.fromCharCodes([
        for (var i = 0; i < text.length; i++)
          if (text[i] != ',') text.codeUnitAt(i) else if (i == decimalComma) 46,
      ]);
    } else {
      final normalized = normalizeAmountInput(text);
      if (text.contains(',') &&
          normalized.contains('.') &&
          !text.contains('.')) {
        decimalComma = text.indexOf(',');
      }
      text = normalized;
    }
    // Validation belongs to the form; do not silently strip arbitrary characters.
    if (!RegExp(r'^-?\d*(?:\.\d*)?$').hasMatch(text)) return newValue;
    final parts = text.split('.');
    final grouped =
        '${groupDigits(parts.first)}${parts.length == 2 ? '.${parts.last}' : ''}';
    int caret(int offset) {
      if (offset < 0) return grouped.length;
      var logical = 0;
      for (var i = 0; i < offset && i < newValue.text.length; i++) {
        if (newValue.text[i] != ',' || i == decimalComma) logical++;
      }
      if (logical == 0) return 0;
      var seen = 0;
      for (var i = 0; i < grouped.length; i++) {
        if (grouped[i] != ',' && ++seen == logical) return i + 1;
      }
      return grouped.length;
    }

    // Forward-delete over a grouping comma should move past it, otherwise
    // the comma is reinserted at the same caret and Delete appears stuck.
    final oldOffset = oldValue.selection.baseOffset;
    final skippedComma =
        oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldOffset >= 0 &&
        oldOffset < oldValue.text.length &&
        oldValue.text[oldOffset] == ',' &&
        newValue.selection.baseOffset == oldOffset &&
        oldValue.text.replaceRange(oldOffset, oldOffset + 1, '') ==
            newValue.text;
    int adjustedCaret(int offset) {
      final mapped = caret(offset);
      return skippedComma && mapped < grouped.length && grouped[mapped] == ','
          ? mapped + 1
          : mapped;
    }

    return TextEditingValue(
      text: grouped,
      selection: TextSelection(
        baseOffset: adjustedCaret(newValue.selection.baseOffset),
        extentOffset: adjustedCaret(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
    );
  }
}
