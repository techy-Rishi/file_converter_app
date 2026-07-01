import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';

/// Handles all PDF-related conversions.
class PdfConverter {
  /// One or more images -> single PDF
  static Future<File> imagesToPdf(List<File> imageFiles) async {
    final doc = pw.Document();

    for (final file in imageFiles) {
      final bytes = await file.readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          build: (context) => pw.Center(child: pw.Image(image)),
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// PDF -> plain text (extracts all readable text from the PDF)
  static Future<File> pdfToText(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final buffer = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document).extractText(startPageIndex: i);
      buffer.writeln(text);
      buffer.writeln('--- Page ${i + 1} end ---');
    }
    document.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/extracted.txt');
    await outFile.writeAsString(buffer.toString());
    return outFile;
  }

  /// Merge multiple PDFs into one
  static Future<File> mergePdfs(List<File> pdfFiles) async {
    final PdfDocument finalDoc = PdfDocument();

    for (final file in pdfFiles) {
      final bytes = await file.readAsBytes();
      final srcDoc = PdfDocument(inputBytes: bytes);
      for (int i = 0; i < srcDoc.pages.count; i++) {
        final template = srcDoc.pages[i].createTemplate();
        finalDoc.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
      }
      srcDoc.dispose();
    }

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/merged.pdf');
    await outFile.writeAsBytes(await finalDoc.save());
    finalDoc.dispose();
    return outFile;
  }

  /// Plain text -> PDF
  static Future<File> textToPdf(File txtFile) async {
    final content = await txtFile.readAsString();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [pw.Text(content)],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }
}
