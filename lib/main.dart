import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'services/image_converter.dart';
import 'services/document_converter.dart';
import 'services/pdf_converter.dart';
import 'services/docx_converter.dart';

void main() => runApp(const ConverterApp());

class ConverterApp extends StatelessWidget {
  const ConverterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Converter',
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
  File? _pickedFile;
  String? _status;
  bool _busy = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        _status = null;
      });
    }
  }

  Future<void> _convertTo(String target, ConverterType type) async {
    if (_pickedFile == null) return;
    setState(() {
      _busy = true;
      _status = 'Converting...';
    });

    try {
      File? output;
      switch (type) {
        case ConverterType.image:
          output = await ImageConverter.convert(_pickedFile!, target);
          break;
        case ConverterType.csvToJson:
          output = await DocumentConverter.csvToJson(_pickedFile!);
          break;
        case ConverterType.jsonToCsv:
          output = await DocumentConverter.jsonToCsv(_pickedFile!);
          break;
        case ConverterType.csvToXlsx:
          output = await DocumentConverter.csvToXlsx(_pickedFile!);
          break;
        case ConverterType.xlsxToCsv:
          output = await DocumentConverter.xlsxToCsv(_pickedFile!);
          break;
        case ConverterType.imageToPdf:
          output = await PdfConverter.imagesToPdf([_pickedFile!]);
          break;
        case ConverterType.pdfToText:
          output = await PdfConverter.pdfToText(_pickedFile!);
          break;
        case ConverterType.textToPdf:
          output = await PdfConverter.textToPdf(_pickedFile!);
          break;
        case ConverterType.wordToPdf:
          output = await DocxConverter.wordToPdf(_pickedFile!);
          break;
        case ConverterType.pdfToWord:
          output = await DocxConverter.pdfToWord(_pickedFile!);
          break;
        case ConverterType.wordToText:
          output = await DocxConverter.wordToText(_pickedFile!);
          break;
        case ConverterType.textToWord:
          output = await DocxConverter.textToWord(_pickedFile!);
          break;
      }

      if (output != null) {
        setState(() => _status = 'Done: ${output!.path}');
        await Share.shareXFiles([XFile(output.path)]);
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
      appBar: AppBar(title: const Text('File Converter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(_pickedFile == null
                  ? 'Pick a file'
                  : 'Selected: ${_pickedFile!.uri.pathSegments.last}'),
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
      onPressed: _pickedFile == null || _busy ? null : onPressed,
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
