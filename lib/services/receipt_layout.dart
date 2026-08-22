import 'package:intl/intl.dart';

/// 58mm Font A is 32 characters wide on POSiFLOW / ESC-POS printers.
class ReceiptLayout {
  static const cols58 = 32;

  static String dash([int width = cols58]) => '-' * width;

  static String pair(
    String left,
    String right, {
    int width = cols58,
  }) {
    final r = right.trim();
    if (r.length >= width) {
      return r.substring(r.length - width);
    }
    final maxLeft = width - r.length;
    var l = left.trim();
    if (l.length > maxLeft - 1 && maxLeft > 1) {
      l = l.substring(0, maxLeft - 1);
    }
    final gap = width - l.length - r.length;
    if (gap <= 0) {
      return (l + r).substring(0, width);
    }
    return l + (' ' * gap) + r;
  }

  /// Matches the sample bill: "Item x Qty" on the left, amount on the right.
  static List<String> itemLines({
    required String name,
    required String qty,
    required String rate,
    int width = cols58,
  }) {
    final label = '$name x $qty';
    final r = rate.trim();
    final maxLeft = (width - r.length - 1).clamp(8, width);

    if (label.length <= maxLeft) {
      return [pair(label, r, width: width)];
    }

    final wrapped = _wrapWords(label, maxLeft);
    if (wrapped.isEmpty) {
      return [pair(label, r, width: width)];
    }

    return [
      pair(wrapped.first, r, width: width),
      ...wrapped.skip(1),
    ];
  }

  static List<String> _wrapWords(String text, int maxWidth) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final next = current.isEmpty ? word : '$current $word';
      if (next.length <= maxWidth) {
        current = next;
        continue;
      }
      if (current.isNotEmpty) {
        lines.add(current);
      }
      if (word.length <= maxWidth) {
        current = word;
      } else {
        lines.add(word.substring(0, maxWidth));
        current = word.substring(maxWidth);
      }
    }
    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines;
  }

  static String qtyText(double qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    return qty.toStringAsFixed(2);
  }

  static String money(double value, {bool forceDecimals = false}) {
    if (!forceDecimals && value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String taxLabel(double tax, double subtotal) {
    if (tax <= 0) return 'Tax';
    if (subtotal <= 0) return 'Tax';
    final percent = tax / subtotal * 100;
    final rounded = percent.roundToDouble();
    final text = (percent - rounded).abs() < 0.05
        ? rounded.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    return 'Tax($text%)';
  }

  static String billWhen(DateTime date) {
    return DateFormat('dd/MM/yyyy hh:mm a', 'en_US').format(date);
  }
}
