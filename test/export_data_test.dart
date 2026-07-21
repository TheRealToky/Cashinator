import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/models/order.dart';
import 'package:cashinator/data/models/order_line.dart';
import 'package:cashinator/export/export_data.dart';
import 'package:cashinator/export/export_format.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an order with the given lines, defaulting to a normal sale.
OrderWithLines makeOrder({
  required int id,
  required String date,
  required String paymentMethod,
  required List<(String name, int qty, int unitPrice)> lines,
  OrderStatus status = OrderStatus.normal,
  String? voidReason,
  int hour = 9,
  int minute = 30,
}) {
  final parsed = parseIsoDate(date)!;
  final createdAt = DateTime(parsed.year, parsed.month, parsed.day, hour, minute);

  final orderLines = <OrderLine>[];
  for (var i = 0; i < lines.length; i++) {
    final (name, qty, unitPrice) = lines[i];
    orderLines.add(OrderLine(
      id: id * 100 + i,
      orderId: id,
      productId: i + 1,
      productName: name,
      qty: qty,
      unitPrice: unitPrice,
      lineNo: i,
    ));
  }

  final total = orderLines.fold(0, (sum, line) => sum + line.lineTotal);

  return OrderWithLines(
    Order(
      id: id,
      orderLabel: '$id',
      businessDate: date,
      createdAt: createdAt,
      paymentMethodId: 1,
      paymentMethodName: paymentMethod,
      status: status,
      total: total,
      voidReason: voidReason,
      voidedAt: status == OrderStatus.voided ? createdAt : null,
    ),
    orderLines,
  );
}

void main() {
  const builder = ExportDataBuilder();
  final day = parseIsoDate('2026-07-20')!;

  group('Sales Lines', () {
    test('emits one row per line with a unique, sequential Line Id', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 2, 3000), ('Cappuccino', 1, 3500)],
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('Muffin', 1, 2000)],
            hour: 10,
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.salesLines, hasLength(3));
      expect(
        data.salesLines.map((row) => row.lineId),
        [1, 2, 3],
        reason: 'Line Id must be unique across the export',
      );
      expect(data.salesLines.map((row) => row.orderId), [1, 1, 2]);
    });

    test('Total Price is qty x snapshotted unit price', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 4, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.salesLines.single.totalPrice, 12000);
      expect(data.salesLines.single.qty, 4);
    });

    test('hardcodes the legacy OCR columns', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      final row = data.salesLines.single;
      expect(row.sourceImage, 1);
      expect(row.confidence, 'medium');
    });

    test('formats Time as HH:MM and Date as YYYY-MM-DD', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
            hour: 7,
            minute: 5,
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.salesLines.single.time, '07:05');
      expect(data.salesLines.single.date, '2026-07-20');
    });

    test('keeps voided lines and puts the reason in Notes', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
            status: OrderStatus.voided,
            voidReason: 'Rang up twice',
          ),
        ],
        from: day,
        to: day,
      );

      final row = data.salesLines.single;
      expect(row.status, 'voided');
      expect(row.notes, 'Rang up twice');
    });

    test('leaves Notes blank for normal orders', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.salesLines.single.notes, '');
    });

    test('column count matches the legacy header', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.salesLines.single.toCells(), hasLength(13));
      expect(kSalesLinesHeader, hasLength(13));
    });
  });

  group('Day Summary', () {
    test('excludes voided orders from every total', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 2, 3000)], // 6000, counted
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Muffin', 5, 2000)], // 10000, voided — must not count
            status: OrderStatus.voided,
            voidReason: 'Customer left',
          ),
        ],
        from: day,
        to: day,
      );

      final summary = data.daySummaries.single;
      expect(summary.orders, 1);
      expect(summary.lines, 1);
      expect(summary.totalSales, 6000);
      expect(summary.byPaymentMethod['MoMo'], 6000);

      // ...while both orders' lines remain visible for audit.
      expect(data.salesLines, hasLength(2));
    });

    test('numbers days sequentially in Source Image', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('Croissant', 1, 3000)],
          ),
          makeOrder(
            id: 2,
            date: '2026-07-21',
            paymentMethod: 'Cash',
            lines: [('Croissant', 1, 3000)],
          ),
          makeOrder(
            id: 3,
            date: '2026-07-22',
            paymentMethod: 'Cash',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: parseIsoDate('2026-07-22')!,
      );

      expect(data.daySummaries.map((row) => row.sourceImage), [1, 2, 3]);
      expect(
        data.daySummaries.map((row) => row.date),
        ['2026-07-20', '2026-07-21', '2026-07-22'],
      );
    });

    test('always carries the three legacy payment columns', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.paymentColumns, ['MoMo', 'Card', 'Cash']);
      expect(
        data.daySummaryHeader,
        [
          'Source Image',
          'Orders',
          'Lines',
          'Total Sales (RWF)',
          'MoMo',
          'Card',
          'Cash',
          'Low Confidence Lines',
        ],
        reason: 'a three-method shop must produce the untouched legacy header',
      );
    });

    test('adds a column for a method the shop invents later', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'CEVR',
            lines: [('Croissant', 1, 3000)],
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('Muffin', 1, 2000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(data.paymentColumns, ['MoMo', 'Card', 'Cash', 'CEVR']);
      expect(data.daySummaryHeader.last, 'Low Confidence Lines');

      final summary = data.daySummaries.single;
      expect(summary.byPaymentMethod['CEVR'], 3000);
      expect(summary.byPaymentMethod['Cash'], 2000);
      expect(summary.totalSales, 5000);
    });

    test('folds a case variant onto the baseline column', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'Momo', // lowercase second "m", as in the ledgers
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(
        data.paymentColumns,
        ['MoMo', 'Card', 'Cash'],
        reason: '"Momo" must not create a fourth column',
      );
      expect(data.daySummaries.single.byPaymentMethod['MoMo'], 3000);
    });

    test('day totals equal the sum of the payment columns', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 2, 3000)],
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('Muffin', 3, 2000)],
          ),
          makeOrder(
            id: 3,
            date: '2026-07-20',
            paymentMethod: 'Card',
            lines: [('Cappuccino', 1, 3500)],
          ),
        ],
        from: day,
        to: day,
      );

      final summary = data.daySummaries.single;
      final columnSum = data.paymentColumns
          .map((column) => summary.byPaymentMethod[column] ?? 0)
          .fold(0, (a, b) => a + b);

      expect(columnSum, summary.totalSales);
      expect(summary.totalSales, 6000 + 6000 + 3500);
    });

    test('a day of only voided orders still gets a zeroed row', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Croissant', 1, 3000)],
            status: OrderStatus.voided,
            voidReason: 'Mistake',
          ),
        ],
        from: day,
        to: day,
      );

      final summary = data.daySummaries.single;
      expect(summary.orders, 0);
      expect(summary.lines, 0);
      expect(summary.totalSales, 0);
      expect(data.salesLines, hasLength(1));
    });

    test('cell count matches the header width', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'CEVR',
            lines: [('Croissant', 1, 3000)],
          ),
        ],
        from: day,
        to: day,
      );

      expect(
        data.daySummaries.single.toCells(data.paymentColumns),
        hasLength(data.daySummaryHeader.length),
      );
    });
  });

  group('ordering', () {
    test('sorts by date then time regardless of input order', () {
      final data = builder.build(
        orders: [
          makeOrder(
            id: 3,
            date: '2026-07-21',
            paymentMethod: 'Cash',
            lines: [('C', 1, 100)],
            hour: 8,
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('B', 1, 100)],
            hour: 15,
          ),
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('A', 1, 100)],
            hour: 7,
          ),
        ],
        from: day,
        to: parseIsoDate('2026-07-21')!,
      );

      expect(data.salesLines.map((row) => row.productName), ['A', 'B', 'C']);
    });
  });
}
