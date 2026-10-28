import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Converts between .docx (Word) and .pdf / .txt with full UTF-8 support.
class DocxConverter {
  static String _baseName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  /// Extracts plain text paragraphs from a .docx file properly using UTF-8
  static Future<List<String>> _readDocxParagraphs(File docxFile) async {
    final bytes = await docxFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final docXmlFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Not a valid .docx file'),
    );

    final contentBytes = docXmlFile.content as List<int>;
    final xmlString = utf8.decode(contentBytes, allowMalformed: true);
    final document = xml.XmlDocument.parse(xmlString);

    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final textRuns = p.findAllElements('w:t');
      final text = textRuns.map((t) => t.innerText).join();
      paragraphs.add(text);
    }
    return paragraphs;
  }

  /// Builds a valid UTF-8 .docx file from plain text lines
  static Future<File> _writeDocx(List<String> paragraphs, String outPath) async {
    final paragraphXml = paragraphs.map((line) {
      final escaped = line
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
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

    final ctBytes = utf8.encode(contentTypesXml);
    final relsBytes = utf8.encode(relsXml);
    final docBytes = utf8.encode(documentXml);

    final archive = Archive();
    archive.addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes));
    archive.addFile(ArchiveFile('_rels/.rels', relsBytes.length, relsBytes));
    archive.addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

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
                  child: pw.Text(p.isEmpty ? ' ' : p),
                ))
            .toList(),
      ),
    );

    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(docxFile)}.pdf');
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// PDF -> Word (.docx)
  static Future<File> pdfToWord(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    final paragraphs = <String>[];
    final extractor = PdfTextExtractor(document);
    for (int i = 0; i < document.pages.count; i++) {
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      paragraphs.addAll(text.split('\n'));
    }
    document.dispose();

    final dir = await getTemporaryDirectory();
    return _writeDocx(paragraphs, '${dir.path}/${_baseName(pdfFile)}.docx');
  }

  /// Word (.docx) -> plain .txt
  static Future<File> wordToText(File docxFile) async {
    final paragraphs = await _readDocxParagraphs(docxFile);
    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_baseName(docxFile)}.txt');
    await outFile.writeAsString(paragraphs.join('\n'));
    return outFile;
  }

  /// Plain .txt -> Word (.docx)
  static Future<File> textToWord(File txtFile) async {
    final content = await txtFile.readAsString();
    final paragraphs = content.replaceAll('\r\n', '\n').split('\n');
    final dir = await getTemporaryDirectory();
    return _writeDocx(paragraphs, '${dir.path}/${_baseName(txtFile)}.docx');
  }
}
