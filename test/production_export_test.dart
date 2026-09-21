import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/models/production_log.dart';
import 'package:cashinator/export/excel_exporter.dart';
import 'package:cashinator/export/production_export_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = ProductionExportBuilder();
  const exporter = ExcelExporter();

  ProductionLog makeLog({
    required int id,
    required String productName,
    required int qty,
    required int unitPrice,
    required String date,
    int hour = 6,
    int minute = 30,
  }) {
    final day = parseIsoDate(date)!;
    return ProductionLog(
      id: id,
      productId: 10 + id,
      productName: productName,
      category: 'Pastry',
      unitPrice: unitPrice,
      qty: qty,
      businessDate: date,
      recordedAt: combineDateAndTime(day, hour, minute),
    );
  }

  List<ProductionLog> sampleLogs() => [
        makeLog(
          id: 1,
          productName: 'Croissant',
          qty: 30,
          unitPrice: 1500,
          date: '2026-08-20',
          hour: 6,
          minute: 0,
        ),
        makeLog(
          id: 2,
          productName: 'Baguette',
          qty: 50,
          unitPrice: 1000,
          date: '2026-08-20',
          hour: 6,
          minute: 30,
        ),
        makeLog(
          id: 3,
          productName: 'Pain au chocolat',
          qty: 25,
          unitPrice: 2000,
          date: '2026-08-21',
          hour: 7,
          minute: 0,
        ),
      ];

  group('ProductionExportBuilder', () {
    test('build aggregates lines and day summaries correctly', () {
      final logs = sampleLogs();
      final data = builder.build(
        logs: logs,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 21),
      );

      expect(data.lines, hasLength(3));
      expect(data.daySummaries, hasLength(2));

      // Day 1: 30 + 50 = 80 qty, 30*1500 + 50*1000 = 95000 totalValue
      expect(data.daySummaries[0].date, '2026-08-20');
      expect(data.daySummaries[0].productsRecorded, 2);
      expect(data.daySummaries[0].totalQty, 80);
      expect(data.daySummaries[0].totalValue, 95000);

      // Day 2: 25 qty, 25*2000 = 50000 totalValue
      expect(data.daySummaries[1].date, '2026-08-21');
      expect(data.daySummaries[1].productsRecorded, 1);
      expect(data.daySummaries[1].totalQty, 25);
      expect(data.daySummaries[1].totalValue, 50000);
    });

    test('buildProductionWorkbookBytes produces a valid readable .xlsx archive', () async {
      final logs = sampleLogs();
      final data = builder.build(
        logs: logs,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 21),
      );

      final bytes = exporter.buildProductionWorkbookBytes(data);
      expect(bytes, isNotEmpty);

      // Verify that bytes form a valid zip/xlsx archive
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);

      // Write to temp file to check file writing
      final tempFile = File('${Directory.systemTemp.path}/test_production_export.xlsx');
      await tempFile.writeAsBytes(bytes);
      expect(await tempFile.exists(), isTrue);
      await tempFile.delete();
    });
  });
}
