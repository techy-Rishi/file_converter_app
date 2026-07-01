import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

/// Converts between csv, json, xlsx, and plain txt.
class DocumentConverter {
  /// CSV -> JSON
  static Future<File> csvToJson(File csvFile) async {
    final content = await csvFile.readAsString();
    final rows = const CsvToListConverter().convert(content);
    final headers = rows.first.map((e) => e.toString()).toList();
    final data = rows.skip(1).map((row) {
      return Map.fromIterables(headers, row);
    }).toList();

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.json');
    await outFile.writeAsString(jsonEncode(data));
    return outFile;
  }

  /// JSON -> CSV (expects a JSON array of flat objects)
  static Future<File> jsonToCsv(File jsonFile) async {
    final content = await jsonFile.readAsString();
    final List<dynamic> data = jsonDecode(content);
    if (data.isEmpty) throw Exception('JSON array is empty');

    final headers = (data.first as Map).keys.toList();
    final rows = <List<dynamic>>[headers];
    for (final item in data) {
      rows.add(headers.map((h) => item[h]).toList());
    }
    final csvString = const ListToCsvConverter().convert(rows);

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.csv');
    await outFile.writeAsString(csvString);
    return outFile;
  }

  /// CSV -> XLSX
  static Future<File> csvToXlsx(File csvFile) async {
    final content = await csvFile.readAsString();
    final rows = const CsvToListConverter().convert(content);

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    for (final row in rows) {
      sheet.appendRow(row.map((e) => TextCellValue(e.toString())).toList());
    }

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.xlsx');
    final bytes = excel.encode();
    await outFile.writeAsBytes(bytes!);
    return outFile;
  }

  /// XLSX -> CSV
  static Future<File> xlsxToCsv(File xlsxFile) async {
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    final rows = sheet.rows
        .map((row) => row.map((cell) => cell?.value.toString() ?? '').toList())
        .toList();
    final csvString = const ListToCsvConverter().convert(rows);

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.csv');
    await outFile.writeAsString(csvString);
    return outFile;
  }
}
