/// Rwandan francs are stored and displayed as whole units — the currency has no
/// subdivision in practice, and the legacy Excel exports carry bare integers.
/// Every price, line total and summary figure in this app is an `int` of RWF;
/// there is deliberately no floating point anywhere in the money path.
library;

/// Formats [amount] with thin-space thousands separators, e.g. `12 500`.
///
/// No currency symbol — callers that need one append `RWF` themselves, matching
/// how the shop writes figures on paper.
String formatRwf(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' '); // plain space thousands separator (RWF convention)
    }
    buffer.write(digits[i]);
  }

  return negative ? '-$buffer' : buffer.toString();
}

/// Formats [amount] for display next to a currency label.
String formatRwfWithUnit(int amount) => '${formatRwf(amount)} RWF';
