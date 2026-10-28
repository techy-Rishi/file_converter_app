import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

/// Converts between CSV, JSON, and XLSX (full 2-way support between all three).
class DocumentConverter {
  static String _baseName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static List<List<dynamic>> _parseCsv(String rawContent) {
    final normalized =
        rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) {
      throw Exception('CSV file is empty.');
    }
    return const CsvToListConverter(eol: '\n').convert(normalized);
  }

  /// CSV -> JSON
  static Future<File> csvToJson(File csvFile) async {
    final content = await csvFile.readAsString();
    final rows = _parseCsv(content);
    if (rows.isEmpty) throw Exception('CSV file has no rows.');

    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final data = rows.skip(1).where((r) => r.isNotEmpty).map((row) {
      final map = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        final key = headers[i].isEmpty ? 'col_$i' : headers[i];
        map[key] = i < row.length ? row[i] : null;
      }
      return map;
    }).toList();

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(csvFile)}.json');
    await outFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    return outFile;
  }

  /// JSON -> CSV
  static Future<File> jsonToCsv(File jsonFile) async {
    final content = await jsonFile.readAsString();
    final decoded = jsonDecode(content);

    List<dynamic> data;
    if (decoded is List) {
      data = decoded;
    } else if (decoded is Map) {
      data = [decoded];
    } else {
      throw Exception('JSON must be an array of objects or a single object.');
    }

    if (data.isEmpty) throw Exception('JSON data is empty.');

    // Collect union of all keys across all objects
    final headerSet = <String>{};
    for (final item in data) {
      if (item is Map) {
        headerSet.addAll(item.keys.map((k) => k.toString()));
      }
    }
    final headers = headerSet.toList();

    final rows = <List<dynamic>>[headers];
    for (final item in data) {
      if (item is Map) {
        rows.add(headers.map((h) {
          final val = item[h];
          if (val == null) return '';
          if (val is Map || val is List) return jsonEncode(val);
          return val;
        }).toList());
      }
    }

    final csvString = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(jsonFile)}.csv');
    await outFile.writeAsString(csvString);
    return outFile;
  }

  /// CSV -> XLSX
  static Future<File> csvToXlsx(File csvFile) async {
    final content = await csvFile.readAsString();
    final rows = _parseCsv(content);

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    for (final row in rows) {
      sheet.appendRow(row.map((e) => TextCellValue(e.toString())).toList());
    }

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(csvFile)}.xlsx');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode XLSX file.');
    await outFile.writeAsBytes(bytes);
    return outFile;
  }

  /// XLSX -> CSV
  static Future<File> xlsxToCsv(File xlsxFile) async {
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) throw Exception('No sheets found in XLSX file.');

    final sheet = excel.tables[excel.tables.keys.first]!;
    final rows = sheet.rows
        .map((row) =>
            row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
    final csvString = const ListToCsvConverter().convert(rows);

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(xlsxFile)}.csv');
    await outFile.writeAsString(csvString);
    return outFile;
  }

  /// XLSX -> JSON (New!)
  static Future<File> xlsxToJson(File xlsxFile) async {
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) throw Exception('No sheets found in XLSX file.');

    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.rows.isEmpty) throw Exception('Spreadsheet is empty.');

    final headers = sheet.rows.first
        .map((cell) => cell?.value?.toString().trim() ?? '')
        .toList();

    final data = sheet.rows.skip(1).map((row) {
      final map = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        final key = headers[i].isEmpty ? 'col_$i' : headers[i];
        map[key] = i < row.length ? (row[i]?.value?.toString() ?? '') : '';
      }
      return map;
    }).toList();

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(xlsxFile)}.json');
    await outFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    return outFile;
  }

  /// JSON -> XLSX (New!)
  static Future<File> jsonToXlsx(File jsonFile) async {
    final csvTemp = await jsonToCsv(jsonFile);
    return csvToXlsx(csvTemp);
  }
}
