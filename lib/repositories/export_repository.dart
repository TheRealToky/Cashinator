import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../export/excel_exporter.dart';
import '../export/export_data.dart';
import 'order_repository.dart';

/// The result of a successful export.
class ExportResult {
  const ExportResult({
    required this.file,
    required this.orderCount,
    required this.lineCount,
    required this.dayCount,
  });

  final File file;
  final int orderCount;
  final int lineCount;
  final int dayCount;

  String get fileName => p.basename(file.path);
}

/// Pulls orders for a date range, renders the workbook and writes it to disk.
class ExportRepository {
  ExportRepository(
    this._orders, {
    ExportDataBuilder builder = const ExportDataBuilder(),
    ExcelExporter exporter = const ExcelExporter(),
  })  : _builder = builder,
        _exporter = exporter;

  final OrderRepository _orders;
  final ExportDataBuilder _builder;
  final ExcelExporter _exporter;

  /// Exports [from]..[to] inclusive.
  ///
  /// Throws [NotFoundException] when the range holds no orders, so the UI can
  /// say "nothing to export" instead of handing over an empty file.
  Future<ExportResult> exportRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final orders = await _orders.ordersInRange(from: from, to: to);
    if (orders.isEmpty) {
      throw const NotFoundException(
        'There are no sales in that date range yet.',
      );
    }

    final data = _builder.build(orders: orders, from: from, to: to);
    final bytes = _exporter.buildWorkbookBytes(data);

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(p.join(directory.path, _fileNameFor(from, to)));

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return ExportResult(
      file: file,
      orderCount: orders.length,
      lineCount: data.salesLines.length,
      dayCount: data.daySummaries.length,
    );
  }

  /// Where exports land on the tablet.
  ///
  /// Uses the app's external files directory on Android, which is reachable
  /// over USB from a laptop without root — that is how the shop moves the file
  /// to whoever runs the downstream script.
  Future<Directory> _exportDirectory() async {
    try {
      Directory? base;
      if (Platform.isAndroid) {
        final candidates = await getExternalStorageDirectories();
        base = (candidates != null && candidates.isNotEmpty)
            ? candidates.first
            : null;
      }
      base ??= await getApplicationDocumentsDirectory();
      return Directory(p.join(base.path, 'exports'));
    } on Object catch (error) {
      throw StorageException(
        'Could not find a place to save the export.',
        cause: error,
      );
    }
  }

  /// Mirrors the legacy naming: `pastry_sales_YYYY-MM-DD.xlsx` for one day,
  /// `pastry_sales_YYYY-MM-DD_to_YYYY-MM-DD.xlsx` for a range.
  String _fileNameFor(DateTime from, DateTime to) {
    final fromIso = formatIsoDate(from);
    final toIso = formatIsoDate(to);
    return fromIso == toIso
        ? 'pastry_sales_$fromIso.xlsx'
        : 'pastry_sales_${fromIso}_to_$toIso.xlsx';
  }
}
