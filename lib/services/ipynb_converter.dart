import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

/// Converts a Jupyter Notebook (.ipynb) file into PDF or Python/Text script.
class IpynbConverter {
  static String _baseName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static String _joinSource(dynamic source) {
    if (source is List) return source.map((e) => e.toString()).join();
    if (source is String) return source;
    return '';
  }

  static Future<File> ipynbToPdf(File ipynbFile) async {
    final content = await ipynbFile.readAsString();
    final notebook = jsonDecode(content) as Map<String, dynamic>;
    final cells = (notebook['cells'] as List?) ?? [];

    final doc = pw.Document();
    final codeFont = pw.Font.courier();

    String extractOutputText(Map<String, dynamic> output) {
      final buffer = StringBuffer();
      final type = output['output_type'];
      if (type == 'stream') {
        buffer.write(_joinSource(output['text']));
      } else if (type == 'execute_result' || type == 'display_data') {
        final data = output['data'] as Map<String, dynamic>?;
        if (data != null && data['text/plain'] != null) {
          buffer.write(_joinSource(data['text/plain']));
        }
      } else if (type == 'error') {
        final traceback = output['traceback'];
        if (traceback is List) {
          buffer.write(traceback.map((e) => e.toString()).join('\n'));
        }
      }
      return buffer.toString();
    }

    final widgets = <pw.Widget>[];
    int execCount = 1;

    for (final cell in cells) {
      final cellType = cell['cell_type'];
      final source = _joinSource(cell['source']);
      if (source.trim().isEmpty) continue;

      if (cellType == 'markdown') {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Text(source, style: const pw.TextStyle(fontSize: 11)),
          ),
        );
      } else if (cellType == 'code') {
        widgets.add(
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#f5f5f5'),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'In [${execCount++}]:\n$source',
              style: pw.TextStyle(font: codeFont, fontSize: 9),
            ),
          ),
        );

        final outputs = (cell['outputs'] as List?) ?? [];
        for (final output in outputs) {
          final text = extractOutputText(output as Map<String, dynamic>);
          if (text.trim().isEmpty) continue;
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 2, bottom: 4),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#ffffff'),
                border: pw.Border.all(color: PdfColor.fromHex('#dddddd')),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                text,
                style: pw.TextStyle(font: codeFont, fontSize: 9),
              ),
            ),
          );
        }
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) =>
            widgets.isEmpty ? [pw.Text('Empty notebook')] : widgets,
      ),
    );

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(ipynbFile)}.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// Jupyter Notebook (.ipynb) -> Python script (.py)
  static Future<File> ipynbToPython(File ipynbFile) async {
    final content = await ipynbFile.readAsString();
    final notebook = jsonDecode(content) as Map<String, dynamic>;
    final cells = (notebook['cells'] as List?) ?? [];

    final buffer = StringBuffer();
    int cellNum = 1;
    for (final cell in cells) {
      final cellType = cell['cell_type'];
      final source = _joinSource(cell['source']).trim();
      if (source.isEmpty) continue;

      if (cellType == 'markdown') {
        for (final line in source.split('\n')) {
          buffer.writeln('# $line');
        }
        buffer.writeln();
      } else if (cellType == 'code') {
        buffer.writeln('# %% [Cell ${cellNum++}]');
        buffer.writeln(source);
        buffer.writeln();
      }
    }

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(ipynbFile)}.py');
    await outFile.writeAsString(buffer.toString());
    return outFile;
  }
}
