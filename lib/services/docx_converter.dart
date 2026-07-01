import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Converts between .docx (Word) and .pdf / .txt.
///
/// NOTE: This is a TEXT-ONLY converter. It preserves paragraphs but not
/// fonts, images, tables, or complex layout. For pixel-perfect conversion
/// (keeping original formatting), see the CloudConvert option in
/// STEPS.md — this offline version is for when content matters more
/// than exact appearance, and needs no internet or paid API.
class DocxConverter {
  /// Extracts plain text paragraphs from a .docx file
  static Future<List<String>> _readDocxParagraphs(File docxFile) async {
    final bytes = await docxFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final docXmlFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Not a valid .docx file'),
    );
    final xmlString = String.fromCharCodes(docXmlFile.content);
    final document = xml.XmlDocument.parse(xmlString);

    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final textRuns = p.findAllElements('w:t');
      final text = textRuns.map((t) => t.innerText).join();
      paragraphs.add(text);
    }
    return paragraphs;
  }

  /// Builds a minimal valid .docx file from plain text lines
  static Future<File> _writeDocx(List<String> paragraphs, String outPath) async {
    final paragraphXml = paragraphs.map((line) {
      final escaped = line
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      return '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
    }).join();

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>$paragraphXml</w:body>
</w:document>''';

    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final archive = Archive();
    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length,
        contentTypesXml.codeUnits));
    archive.addFile(ArchiveFile(
        '_rels/.rels', relsXml.length, relsXml.codeUnits));
    archive.addFile(ArchiveFile(
        'word/document.xml', documentXml.length, documentXml.codeUnits));

    final zipBytes = ZipEncoder().encode(archive)!;
    final outFile = File(outPath);
    await outFile.writeAsBytes(zipBytes);
    return outFile;
  }

  /// Word (.docx) -> PDF
  static Future<File> wordToPdf(File docxFile) async {
    final paragraphs = await _readDocxParagraphs(docxFile);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => paragraphs
            .map((p) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(p),
                ))
            .toList(),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// PDF -> Word (.docx)
  static Future<File> pdfToWord(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final paragraphs = <String>[];
    for (int i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document).extractText(startPageIndex: i);
      paragraphs.addAll(text.split('\n'));
    }
    document.dispose();

    final dir = await getApplicationDocumentsDirectory();
    return _writeDocx(paragraphs, '${dir.path}/converted.docx');
  }

  /// Word (.docx) -> plain .txt
  static Future<File> wordToText(File docxFile) async {
    final paragraphs = await _readDocxParagraphs(docxFile);
    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.txt');
    await outFile.writeAsString(paragraphs.join('\n'));
    return outFile;
  }

  /// Plain .txt -> Word (.docx)
  static Future<File> textToWord(File txtFile) async {
    final content = await txtFile.readAsString();
    final paragraphs = content.split('\n');
    final dir = await getApplicationDocumentsDirectory();
    return _writeDocx(paragraphs, '${dir.path}/converted.docx');
  }
}
