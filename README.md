# Cashinator

Touch-first, offline point-of-sale for the pastry shop. Runs entirely on a
single Samsung Tab S9 — no network, no sync, no accounts beyond two PINs.

## Running it

```bash
flutter pub get
flutter test                       # unit + export tests
python tool/verify_export.py       # diffs a generated .xlsx against the legacy format
flutter build apk --release        # sideload to the Tab S9
```

The APK build needs the Android SDK and a JDK; `flutter test` does not.

## Architecture

```
lib/
  core/           formatting, date shapes, error types — no Flutter imports
  data/
    db/           schema.dart (SQL + seeds), app_database.dart (connection)
    models/       Product, PaymentMethod, Order, OrderLine, Expense
  repositories/   the only code that touches sqflite
  export/         export_format.dart (constants), export_data.dart (pure
                  layout logic), excel_exporter.dart (xlsio writer), and the
                  expense_export_* pair for the expenses workbook
  state/          CartController, CatalogController (ChangeNotifier)
  ui/             auth/, pos/, backoffice/, widgets/
```

Repositories translate every `DatabaseException` into a typed `AppException`
carrying a sentence that can be shown to a cashier. No widget imports sqflite.

The export is split deliberately: `export_data.dart` decides every value and is
testable in pure Dart; `excel_exporter.dart` only places and styles cells.

## Two things worth knowing

**Snapshots, not joins.** Order lines store `product_name` and `unit_price` as
they were at the moment of sale, and orders store `payment_method_name` the same
way. A price rise or a rename next month cannot rewrite last month's export.

**Voiding is a status, never a delete.** A voided order keeps its row, its
lines, a reason and a timestamp. It stays visible in the `Sales Lines` sheet and
drops out of the `Day Summary` totals. Expenses follow the same rule.

## Excel export

Reproduces the layout of the shop's existing ledger exports, because a
downstream automation script parses those sheets by column position.

`Sales Lines` — 13 columns, identical in all 22 sample files:

```
Line Id, Order Id, Order Label, Product Name, Qty, Payment Method,
Time, Date, Source Image, Total Price, Status, Confidence, Notes
```

Three columns are legacy OCR artifacts with no POS meaning, hardcoded per spec:
`Source Image` = `1`, `Confidence` = `medium`, `Low Confidence Lines` = `0`.

`Day Summary` — one row per exported day, `Source Image` being the sequential
day index, and a bold `TOTAL` row of `SUM()` formulas.

### Payment columns

`MoMo`, `Card` and `Cash` are always emitted in that order, so a shop using only
those three produces a byte-identical header to the legacy file. Any additional
method used in the range is appended **after** them and **before**
`Low Confidence Lines`:

```
Source Image, Orders, Lines, Total Sales (RWF), MoMo, Card, Cash, [extras…], Low Confidence Lines
```

Case variants fold onto the baseline spelling — a `Momo` order lands in the
`MoMo` column rather than creating a fourth. The database also has a
case-insensitive unique index on payment method names, so the `MoMo`/`Momo`
split visible in the legacy data (1543 vs 73 rows) cannot recur.

## Expenses

The back office records what the shop spends: a name, an amount, a date, a time
and a payment method. The form is the till's payment sheet with the money
running the other way — the same optional date and time rows defaulting to now,
the same one-button-per-method confirmation — because the same people use both.

Expenses live in their own `expenses` table (schema v3) and are voided, never
deleted, exactly like orders.

They export to a **separate workbook**, `pastry_expenses_YYYY-MM-DD.xlsx`,
triggered from the same date range on the Excel export screen:

```
Expenses    — Expense Id, Name, Amount (RWF), Payment Method, Time, Date, Status, Notes
Day Summary — Date, Expenses, Total Spend (RWF), MoMo, Card, Cash, [extras…] + TOTAL row
```

The separation is deliberate. The sales workbook's layout is fixed by the
downstream automation script that parses it by column position; adding sheets
to that file would put the script at risk for no gain. The expenses sheets keep
the sales workbook's styling, payment-column rules and `SUM()` TOTAL row, but
drop the OCR-era columns (`Source Image`, `Confidence`, `Low Confidence
Lines`), which never meant anything for an expense.

Both back-office roles may record and void expenses — an expense is the same
kind of record as a sale, and a supervisor who may void a sale may write down
the milk they bought.

## Deviations from the original spec

Each of these was a real disagreement between the spec and the 22 sample files.

| # | Spec said | What ships | Why |
|---|---|---|---|
| 1 | `Day Summary` has fixed `MoMo, Card, Cash` | Those three, plus a column per extra method used | Payment methods are CRUD-able; the legacy data already contains `CEVR`, `William`, `Kivuwatt`. Fixed columns would silently drop them from the breakdown. |
| 2 | `Order Id` and `Order Label` are the same number | `Order Id` is the global row id; `Order Label` is a per-day counter | They coincide in the samples only because each file covers one day starting at 1. Staff need a short number that restarts daily; the export needs a stable unique id. |
| 3 | Snapshot the product name and price | Also snapshots the payment method name | Same failure mode: renaming "MoMo" would otherwise rewrite historical exports. |
| 4 | — | `Sales Lines` freezes at `A2` | The reference file freezes at `A40`, which is incidental to that file. Freeze panes do not affect a parsing script. |

## Known risks

- **`Source Image` semantics.** In the legacy files this is a *ledger-page*
  index (1–6 within a single day) and it joins the two sheets. This app follows
  the spec literally: `Sales Lines` hardcodes `1`, `Day Summary` uses a day
  index. **The two sheets therefore do not join on `Source Image` in a
  multi-day export.** If the downstream script relies on that join, it needs the
  day index in both sheets instead — a one-line change in `export_data.dart`.
- **The samples don't reconcile with themselves.** In `pastry_sales_2026-06-18`
  and `-19`, the `Day Summary` figures do not match the `Sales Lines` rows in
  the same workbook under any voided-exclusion rule. The samples could not be
  used as a correctness oracle; the export math follows the spec instead.
- **Syncfusion licensing.** `syncfusion_flutter_xlsio` is not open-source. A
  free community licence covers small businesses, but it must be registered and
  a licence key added. Swapping to the `excel` package would avoid this at the
  cost of formula support in the `TOTAL` row.

## Default PINs

Front office `1234`, back office `4321`. **Change both before the tablet reaches
the counter** — the back office shows a warning banner until you do. PINs are
stored salted and SHA-256 hashed, never in clear text.

## Deliberately out of scope

Cloud sync, receipt printing, inventory deduction, analytics dashboards, user
accounts beyond the two PIN roles.
