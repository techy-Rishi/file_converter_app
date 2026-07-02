import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

/// Converts a Jupyter Notebook (.ipynb) file into a readable PDF,
/// rendering markdown cells as text and code cells (with their outputs)
/// in a monospaced, shaded block - similar to Jupyter's own "Export as
/// PDF" or "Print Preview" output.
class IpynbConverter {
  static Future<File> ipynbToPdf(File ipynbFile) async {
    final content = await ipynbFile.readAsString();
    final notebook = jsonDecode(content) as Map<String, dynamic>;
    final cells = (notebook['cells'] as List?) ?? [];

    final doc = pw.Document();
    final codeFont = pw.Font.courier();

    String joinSource(dynamic source) {
      if (source is List) return source.map((e) => e.toString()).join();
      if (source is String) return source;
      return '';
    }

    String extractOutputText(Map<String, dynamic> output) {
      final buffer = StringBuffer();
      final type = output['output_type'];
      if (type == 'stream') {
        buffer.write(joinSource(output['text']));
      } else if (type == 'execute_result' || type == 'display_data') {
        final data = output['data'] as Map<String, dynamic>?;
        if (data != null && data['text/plain'] != null) {
          buffer.write(joinSource(data['text/plain']));
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
      final source = joinSource(cell['source']);
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
              'In [${execCount++}]: $source',
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
        build: (context) => widgets,
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/notebook.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }
}
