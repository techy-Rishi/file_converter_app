import 'dart:io';
import 'dart:ui';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

/// Page size presets, in points (1 cm = 28.3465 pt).
enum PdfPageSize { a4, letter, a5, custom, actualSizeFromDpi }

/// How the image should be placed on the page.
enum PdfFitMode { fitPage, actualSize }

/// Handles all PDF-related conversions.
class PdfConverter {
  static String _baseName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  /// Copies a page from [srcPage] into [targetDoc] while preserving exact
  /// dimensions, orientation, and zero extra margins.
  static void _copyPageExact(sf.PdfPage srcPage, sf.PdfDocument targetDoc) {
    final template = srcPage.createTemplate();
    final section = targetDoc.sections!.add();
    section.pageSettings.margins.all = 0;
    section.pageSettings.size = srcPage.size;
    section.pageSettings.orientation =
        srcPage.size.width > srcPage.size.height
            ? sf.PdfPageOrientation.landscape
            : sf.PdfPageOrientation.portrait;
    section.pages.add().graphics.drawPdfTemplate(template, Offset.zero);
  }

  /// One or more images -> single PDF, with full control over layout.
  static Future<File> imagesToPdf(
    List<File> imageFiles, {
    double marginCm = 1.0,
    int quality = 90,
    PdfPageSize pageSize = PdfPageSize.a4,
    double customWidthCm = 21.0,
    double customHeightCm = 29.7,
    PdfFitMode fitMode = PdfFitMode.fitPage,
    double dpi = 300,
  }) async {
    final doc = pw.Document();
    final marginPt = marginCm * PdfPageFormat.cm;

    for (final file in imageFiles) {
      final rawBytes = await file.readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) continue;

      final jpegBytes = img.encodeJpg(decoded, quality: quality.clamp(1, 100));
      final pdfImage = pw.MemoryImage(jpegBytes);

      final imgWidthPt = (decoded.width / dpi) * PdfPageFormat.inch;
      final imgHeightPt = (decoded.height / dpi) * PdfPageFormat.inch;

      PdfPageFormat format;
      if (pageSize == PdfPageSize.actualSizeFromDpi) {
        format = PdfPageFormat(
          imgWidthPt + marginPt * 2,
          imgHeightPt + marginPt * 2,
          marginAll: marginPt,
        );
      } else if (pageSize == PdfPageSize.custom) {
        format = PdfPageFormat(
          customWidthCm * PdfPageFormat.cm,
          customHeightCm * PdfPageFormat.cm,
          marginLeft: marginPt,
          marginRight: marginPt,
          marginTop: marginPt,
          marginBottom: marginPt,
        );
      } else {
        final base = switch (pageSize) {
          PdfPageSize.letter => PdfPageFormat.letter,
          PdfPageSize.a5 => PdfPageFormat.a5,
          _ => PdfPageFormat.a4,
        };
        format = base.copyWith(
          marginLeft: marginPt,
          marginRight: marginPt,
          marginTop: marginPt,
          marginBottom: marginPt,
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) {
            if (fitMode == PdfFitMode.actualSize ||
                pageSize == PdfPageSize.actualSizeFromDpi) {
              return pw.Center(
                child: pw.SizedBox(
                  width: imgWidthPt,
                  height: imgHeightPt,
                  child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
                ),
              );
            }
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final name = imageFiles.length == 1
        ? _baseName(imageFiles.first)
        : 'images_${imageFiles.length}';
    final outFile = File('${dir.path}/$name.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// PDF -> plain text (extracts all readable text from the PDF)
  static Future<File> pdfToText(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    final buffer = StringBuffer();
    final extractor = sf.PdfTextExtractor(document);
    for (int i = 0; i < document.pages.count; i++) {
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      buffer.writeln(text);
      buffer.writeln('--- Page ${i + 1} end ---');
    }
    document.dispose();

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(pdfFile)}.txt');
    await outFile.writeAsString(buffer.toString());
    return outFile;
  }

  /// Merge multiple PDFs into one (preserving exact page sizes)
  static Future<File> mergePdfs(List<File> pdfFiles) async {
    final sf.PdfDocument finalDoc = sf.PdfDocument();

    for (final file in pdfFiles) {
      final bytes = await file.readAsBytes();
      final srcDoc = sf.PdfDocument(inputBytes: bytes);
      for (int i = 0; i < srcDoc.pages.count; i++) {
        _copyPageExact(srcDoc.pages[i], finalDoc);
      }
      srcDoc.dispose();
    }

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/merged_${pdfFiles.length}_files.pdf');
    await outFile.writeAsBytes(await finalDoc.save());
    finalDoc.dispose();
    return outFile;
  }

  /// Extracts a page range (1-indexed, inclusive) into a new PDF.
  static Future<File> splitPdfRange(
    File pdfFile,
    int startPage,
    int endPage,
  ) async {
    final bytes = await pdfFile.readAsBytes();
    final srcDoc = sf.PdfDocument(inputBytes: bytes);
    final newDoc = sf.PdfDocument();

    final count = srcDoc.pages.count;
    final a = startPage.clamp(1, count);
    final b = endPage.clamp(1, count);
    final start = a <= b ? a : b;
    final end = a <= b ? b : a;

    for (int i = start - 1; i <= end - 1; i++) {
      _copyPageExact(srcDoc.pages[i], newDoc);
    }
    srcDoc.dispose();

    final dir = await getTemporaryDirectory();
    final outFile =
        File('${dir.path}/${_baseName(pdfFile)}_pages_${start}_to_$end.pdf');
    await outFile.writeAsBytes(await newDoc.save());
    newDoc.dispose();
    return outFile;
  }

  /// Splits every page of a PDF into its own separate single-page PDF file.
  static Future<List<File>> splitPdfIntoPages(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final srcDoc = sf.PdfDocument(inputBytes: bytes);
    final dir = await getTemporaryDirectory();
    final results = <File>[];
    final base = _baseName(pdfFile);

    for (int i = 0; i < srcDoc.pages.count; i++) {
      final newDoc = sf.PdfDocument();
      _copyPageExact(srcDoc.pages[i], newDoc);
      final outFile = File('${dir.path}/${base}_page_${i + 1}.pdf');
      await outFile.writeAsBytes(await newDoc.save());
      newDoc.dispose();
      results.add(outFile);
    }
    srcDoc.dispose();
    return results;
  }

  /// Rotates every page in the PDF by the given angle (90, 180, or 270).
  static Future<File> rotatePdf(File pdfFile, int degrees) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    final angle = switch (degrees % 360) {
      90 => sf.PdfPageRotateAngle.rotateAngle90,
      180 => sf.PdfPageRotateAngle.rotateAngle180,
      270 => sf.PdfPageRotateAngle.rotateAngle270,
      _ => sf.PdfPageRotateAngle.rotateAngle0,
    };

    for (int i = 0; i < document.pages.count; i++) {
      document.pages[i].rotation = angle;
    }

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(pdfFile)}_rotated.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
    return outFile;
  }

  /// Adds password protection to a PDF.
  static Future<File> protectPdf(File pdfFile, String password) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    document.security.userPassword = password;
    document.security.ownerPassword = password;

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(pdfFile)}_protected.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
    return outFile;
  }

  /// Removes password protection from a PDF.
  static Future<File> unlockPdf(File pdfFile, String password) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes, password: password);

    // Clear passwords so the saved PDF is actually unlocked!
    document.security.userPassword = '';
    document.security.ownerPassword = '';

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(pdfFile)}_unlocked.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
    return outFile;
  }

  /// Plain text -> PDF (handles multi-page text files without crashing)
  static Future<File> textToPdf(File txtFile) async {
    final content = await txtFile.readAsString();
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => lines
            .map((line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(line.isEmpty ? ' ' : line),
                ))
            .toList(),
      ),
    );

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(txtFile)}.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }
}
