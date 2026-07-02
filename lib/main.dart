import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/image_converter.dart';
import 'services/document_converter.dart';
import 'services/pdf_converter.dart';
import 'services/docx_converter.dart';

// TODO: Replace with your real support email.
const String kSupportEmail = 'support@example.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConverterApp());
}

class ConverterApp extends StatelessWidget {
  const ConverterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConvertKaro',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> _pickedFiles = [];
  String? _status;
  bool _busy = false;

  Future<void> _pickFile() async {
    // allowMultiple lets you select several files at once for batch
    // conversion (mainly useful for images).
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFiles = result.paths
            .where((p) => p != null)
            .map((p) => File(p!))
            .toList();
        _status = null;
      });
    }
  }

  Future<void> _openContactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=ConvertKaro Feedback',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _convertTo(String target, ConverterType type) async {
    if (_pickedFiles.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Converting...';
    });

    try {
      final outputs = <File>[];

      // Batch-friendly types loop over every picked file. Others
      // (docs/pdf/word) just use the first picked file.
      final batchTypes = {ConverterType.image, ConverterType.imageToPdf};

      if (batchTypes.contains(type) && _pickedFiles.length > 1) {
        if (type == ConverterType.imageToPdf) {
          // Combine all picked images into a single PDF.
          outputs.add(await PdfConverter.imagesToPdf(_pickedFiles));
        } else {
          for (final f in _pickedFiles) {
            final out = await ImageConverter.convert(f, target);
            if (out != null) outputs.add(out);
          }
        }
      } else {
        final file = _pickedFiles.first;
        File? output;
        switch (type) {
          case ConverterType.image:
            output = await ImageConverter.convert(file, target);
            break;
          case ConverterType.csvToJson:
            output = await DocumentConverter.csvToJson(file);
            break;
          case ConverterType.jsonToCsv:
            output = await DocumentConverter.jsonToCsv(file);
            break;
          case ConverterType.csvToXlsx:
            output = await DocumentConverter.csvToXlsx(file);
            break;
          case ConverterType.xlsxToCsv:
            output = await DocumentConverter.xlsxToCsv(file);
            break;
          case ConverterType.imageToPdf:
            output = await PdfConverter.imagesToPdf([file]);
            break;
          case ConverterType.pdfToText:
            output = await PdfConverter.pdfToText(file);
            break;
          case ConverterType.textToPdf:
            output = await PdfConverter.textToPdf(file);
            break;
          case ConverterType.wordToPdf:
            output = await DocxConverter.wordToPdf(file);
            break;
          case ConverterType.pdfToWord:
            output = await DocxConverter.pdfToWord(file);
            break;
          case ConverterType.wordToText:
            output = await DocxConverter.wordToText(file);
            break;
          case ConverterType.textToWord:
            output = await DocxConverter.textToWord(file);
            break;
        }
        if (output != null) outputs.add(output);
      }

      if (outputs.isNotEmpty) {
        setState(() => _status = 'Done: ${outputs.length} file(s)');
        await Share.shareXFiles(outputs.map((f) => XFile(f.path)).toList());
      } else {
        setState(() => _status = 'Conversion failed.');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ConvertKaro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: 'Contact / Feedback',
            onPressed: _openContactEmail,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(_pickedFiles.isEmpty
                  ? 'Pick file(s)'
                  : '${_pickedFiles.length} file(s) selected'),
            ),
            const SizedBox(height: 20),
            const Text('Images', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('PNG', () => _convertTo('png', ConverterType.image)),
              _btn('JPG', () => _convertTo('jpg', ConverterType.image)),
              _btn('BMP', () => _convertTo('bmp', ConverterType.image)),
              _btn('GIF', () => _convertTo('gif', ConverterType.image)),
            ]),
            const SizedBox(height: 16),
            const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('CSV → JSON', () => _convertTo('', ConverterType.csvToJson)),
              _btn('JSON → CSV', () => _convertTo('', ConverterType.jsonToCsv)),
              _btn('CSV → XLSX', () => _convertTo('', ConverterType.csvToXlsx)),
              _btn('XLSX → CSV', () => _convertTo('', ConverterType.xlsxToCsv)),
            ]),
            const SizedBox(height: 16),
            const Text('PDF', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('Image → PDF', () => _convertTo('', ConverterType.imageToPdf)),
              _btn('PDF → Text', () => _convertTo('', ConverterType.pdfToText)),
              _btn('Text → PDF', () => _convertTo('', ConverterType.textToPdf)),
            ]),
            const SizedBox(height: 16),
            const Text('Word', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('Word → PDF', () => _convertTo('', ConverterType.wordToPdf)),
              _btn('PDF → Word', () => _convertTo('', ConverterType.pdfToWord)),
              _btn('Word → Text', () => _convertTo('', ConverterType.wordToText)),
              _btn('Text → Word', () => _convertTo('', ConverterType.textToWord)),
            ]),
            const SizedBox(height: 24),
            if (_busy) const CircularProgressIndicator(),
            if (_status != null) Text(_status!),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _pickedFiles.isEmpty || _busy ? null : onPressed,
      child: Text(label),
    );
  }
}

enum ConverterType {
  image,
  csvToJson,
  jsonToCsv,
  csvToXlsx,
  xlsxToCsv,
  imageToPdf,
  pdfToText,
  textToPdf,
  wordToPdf,
  pdfToWord,
  wordToText,
  textToWord,
}
