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
  /// One or more images -> single PDF, with full control over layout.
  ///
  /// - [marginCm]: page margin on all sides, in centimeters.
  /// - [quality]: JPEG re-encode quality 1-100 (lower = smaller file size).
  /// - [pageSize]: A4 / Letter / A5 / custom (uses [customWidthCm] and
  ///   [customHeightCm]), or actualSizeFromDpi to make the PDF page
  ///   exactly match the image's physical print size at [dpi].
  /// - [customWidthCm] / [customHeightCm]: page dimensions in centimeters,
  ///   only used when pageSize is PdfPageSize.custom.
  /// - [fitMode]: fitPage scales the image to fill the page (minus
  ///   margins) preserving aspect ratio; actualSize places the image at
  ///   its true physical size (pixels / dpi), useful for scans that need
  ///   to print at exact scale.
  /// - [dpi]: only used when pageSize is actualSizeFromDpi or fitMode is
  ///   actualSize. Standard scan/print DPI is 300; screenshots are ~96.
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

      // Re-encode as JPEG at the chosen quality - this is what actually
      // controls output file size, same as "quality" sliders in most
      // official PDF/image converter apps.
      final jpegBytes = img.encodeJpg(decoded, quality: quality.clamp(1, 100));
      final pdfImage = pw.MemoryImage(jpegBytes);

      // Physical size of the image at the given DPI, in points.
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

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// PDF -> plain text (extracts all readable text from the PDF)
  static Future<File> pdfToText(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    final buffer = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final text = sf.PdfTextExtractor(document).extractText(startPageIndex: i);
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
    final sf.PdfDocument finalDoc = sf.PdfDocument();

    for (final file in pdfFiles) {
      final bytes = await file.readAsBytes();
      final srcDoc = sf.PdfDocument(inputBytes: bytes);
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

  /// Extracts a page range (1-indexed, inclusive) into a new PDF.
  static Future<File> splitPdfRange(
    File pdfFile,
    int startPage,
    int endPage,
  ) async {
    final bytes = await pdfFile.readAsBytes();
    final srcDoc = sf.PdfDocument(inputBytes: bytes);
    final newDoc = sf.PdfDocument();

    final start = startPage.clamp(1, srcDoc.pages.count);
    final end = endPage.clamp(1, srcDoc.pages.count);

    for (int i = start - 1; i <= end - 1; i++) {
      final template = srcDoc.pages[i].createTemplate();
      newDoc.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
    }
    srcDoc.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/split_${start}_$end.pdf');
    await outFile.writeAsBytes(await newDoc.save());
    newDoc.dispose();
    return outFile;
  }

  /// Splits every page of a PDF into its own separate single-page PDF file.
  static Future<List<File>> splitPdfIntoPages(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final srcDoc = sf.PdfDocument(inputBytes: bytes);
    final dir = await getApplicationDocumentsDirectory();
    final results = <File>[];

    for (int i = 0; i < srcDoc.pages.count; i++) {
      final newDoc = sf.PdfDocument();
      final template = srcDoc.pages[i].createTemplate();
      newDoc.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
      final outFile = File('${dir.path}/page_${i + 1}.pdf');
      await outFile.writeAsBytes(await newDoc.save());
      newDoc.dispose();
      results.add(outFile);
    }
    srcDoc.dispose();
    return results;
  }

  /// Rotates every page in the PDF by the given angle (must be 90, 180,
  /// or 270 degrees).
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

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/rotated.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
    return outFile;
  }

  /// Adds password protection to a PDF. The same password is used to
  /// both open (user password) and edit (owner password) the file.
  static Future<File> protectPdf(File pdfFile, String password) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes);

    document.security.userPassword = password;
    document.security.ownerPassword = password;

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/protected.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
    return outFile;
  }

  /// Removes password protection from a PDF (you must supply the
  /// current password to open it).
  static Future<File> unlockPdf(File pdfFile, String password) async {
    final bytes = await pdfFile.readAsBytes();
    final document = sf.PdfDocument(inputBytes: bytes, password: password);

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/unlocked.pdf');
    await outFile.writeAsBytes(await document.save());
    document.dispose();
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
