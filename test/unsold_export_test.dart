import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/models/unsold_log.dart';
import 'package:cashinator/export/excel_exporter.dart';
import 'package:cashinator/export/unsold_export_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = UnsoldExportBuilder();
  const exporter = ExcelExporter();

  UnsoldLog makeLog({
    required int id,
    required String productName,
    required int qty,
    required int unitPrice,
    required String date,
    int hour = 18,
    int minute = 30,
  }) {
    final day = parseIsoDate(date)!;
    return UnsoldLog(
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

  List<UnsoldLog> sampleLogs() => [
        makeLog(
          id: 1,
          productName: 'Croissant',
          qty: 5,
          unitPrice: 1500,
          date: '2026-08-20',
          hour: 18,
          minute: 0,
        ),
        makeLog(
          id: 2,
          productName: 'Baguette',
          qty: 10,
          unitPrice: 1000,
          date: '2026-08-20',
          hour: 18,
          minute: 30,
        ),
        makeLog(
          id: 3,
          productName: 'Pain au chocolat',
          qty: 4,
          unitPrice: 2000,
          date: '2026-08-21',
          hour: 19,
          minute: 0,
        ),
      ];

  group('UnsoldExportBuilder', () {
    test('build aggregates lines and day summaries correctly', () {
      final logs = sampleLogs();
      final data = builder.build(
        logs: logs,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 21),
      );

      expect(data.lines, hasLength(3));
      expect(data.daySummaries, hasLength(2));

      // Day 1: 5 + 10 = 15 qty, 5*1500 + 10*1000 = 17500 totalValue
      expect(data.daySummaries[0].date, '2026-08-20');
      expect(data.daySummaries[0].productsRecorded, 2);
      expect(data.daySummaries[0].totalQty, 15);
      expect(data.daySummaries[0].totalValue, 17500);

      // Day 2: 4 qty, 4*2000 = 8000 totalValue
      expect(data.daySummaries[1].date, '2026-08-21');
      expect(data.daySummaries[1].productsRecorded, 1);
      expect(data.daySummaries[1].totalQty, 4);
      expect(data.daySummaries[1].totalValue, 8000);
    });

    test('buildUnsoldWorkbookBytes produces a valid readable .xlsx archive', () async {
      final logs = sampleLogs();
      final data = builder.build(
        logs: logs,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 21),
      );

      final bytes = exporter.buildUnsoldWorkbookBytes(data);
      expect(bytes, isNotEmpty);

      // Verify that bytes form a valid zip/xlsx archive
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);

      // Write to temp file to check file writing
      final tempFile = File('${Directory.systemTemp.path}/test_unsold_export.xlsx');
      await tempFile.writeAsBytes(bytes);
      expect(await tempFile.exists(), isTrue);
      await tempFile.delete();
    });
  });
}
