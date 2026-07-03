import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/image_converter.dart';
import 'services/document_converter.dart';
import 'services/pdf_converter.dart';
import 'services/docx_converter.dart';
import 'services/ipynb_converter.dart';

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

  // Image -> PDF settings, adjustable via the gear icon.
  double _marginCm = 1.0;
  int _quality = 90;
  PdfPageSize _pageSize = PdfPageSize.a4;
  double _customWidthCm = 21.0;
  double _customHeightCm = 29.7;
  PdfFitMode _fitMode = PdfFitMode.fitPage;
  double _dpi = 300;

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

  Future<void> _showPdfSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Image → PDF settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Margin: ${_marginCm.toStringAsFixed(1)} cm'),
                    Slider(
                      value: _marginCm,
                      min: 0,
                      max: 5,
                      divisions: 50,
                      label: '${_marginCm.toStringAsFixed(1)} cm',
                      onChanged: (v) => setDialogState(() => _marginCm = v),
                    ),
                    Text('Quality: $_quality%'),
                    Slider(
                      value: _quality.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 18,
                      label: '$_quality%',
                      onChanged: (v) =>
                          setDialogState(() => _quality = v.round()),
                    ),
                    const SizedBox(height: 8),
                    const Text('Page size'),
                    DropdownButton<PdfPageSize>(
                      value: _pageSize,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: PdfPageSize.a4,
                          child: Text('A4'),
                        ),
                        DropdownMenuItem(
                          value: PdfPageSize.letter,
                          child: Text('Letter'),
                        ),
                        DropdownMenuItem(
                          value: PdfPageSize.a5,
                          child: Text('A5'),
                        ),
                        DropdownMenuItem(
                          value: PdfPageSize.custom,
                          child: Text('Custom size (cm)'),
                        ),
                        DropdownMenuItem(
                          value: PdfPageSize.actualSizeFromDpi,
                          child: Text('Actual size (from DPI)'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => _pageSize = v!),
                    ),
                    if (_pageSize == PdfPageSize.custom) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Width (cm)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              controller: TextEditingController(
                                text: _customWidthCm.toString(),
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v);
                                if (parsed != null) {
                                  setDialogState(() => _customWidthCm = parsed);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Height (cm)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              controller: TextEditingController(
                                text: _customHeightCm.toString(),
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v);
                                if (parsed != null) {
                                  setDialogState(() => _customHeightCm = parsed);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text('Fit mode'),
                    DropdownButton<PdfFitMode>(
                      value: _fitMode,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: PdfFitMode.fitPage,
                          child: Text('Fit to page'),
                        ),
                        DropdownMenuItem(
                          value: PdfFitMode.actualSize,
                          child: Text('Actual size (from DPI)'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => _fitMode = v!),
                    ),
                    const SizedBox(height: 8),
                    Text('DPI: ${_dpi.round()}'),
                    Slider(
                      value: _dpi,
                      min: 72,
                      max: 600,
                      divisions: 22,
                      label: '${_dpi.round()} dpi',
                      onChanged: (v) => setDialogState(() => _dpi = v),
                    ),
                    const Text(
                      'DPI matters only for "Actual size" page/fit options - '
                      '300 is standard for scans/printing, 96 for screenshots.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    setState(() {}); // refresh main screen in case values changed
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
          outputs.add(await PdfConverter.imagesToPdf(
            _pickedFiles,
            marginCm: _marginCm,
            quality: _quality,
            pageSize: _pageSize,
            customWidthCm: _customWidthCm,
            customHeightCm: _customHeightCm,
            fitMode: _fitMode,
            dpi: _dpi,
          ));
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
            output = await PdfConverter.imagesToPdf(
              [file],
              marginCm: _marginCm,
              quality: _quality,
              pageSize: _pageSize,
              customWidthCm: _customWidthCm,
              customHeightCm: _customHeightCm,
              fitMode: _fitMode,
              dpi: _dpi,
            );
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
          case ConverterType.ipynbToPdf:
            output = await IpynbConverter.ipynbToPdf(file);
            break;
        }
        if (output != null) outputs.add(output);
      }

      if (outputs.isNotEmpty) {
        final sizes = await Future.wait(outputs.map((f) => f.length()));
        final totalBytes = sizes.fold<int>(0, (sum, s) => sum + s);
        setState(() => _status =
            'Done: ${outputs.length} file(s), ${_formatBytes(totalBytes)}');
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Shared runner for the newer dialog-based tools below: handles the
  /// busy/status state, computes total output size, and shares results.
  Future<void> _runConversion(Future<List<File>> Function() task) async {
    setState(() {
      _busy = true;
      _status = 'Converting...';
    });
    try {
      final outputs = await task();
      if (outputs.isNotEmpty) {
        final sizes = await Future.wait(outputs.map((f) => f.length()));
        final totalBytes = sizes.fold<int>(0, (sum, s) => sum + s);
        setState(() => _status =
            'Done: ${outputs.length} file(s), ${_formatBytes(totalBytes)}');
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

  Future<void> _mergePdfsAction() async {
    if (_pickedFiles.length < 2) {
      setState(() => _status = 'Pick 2 or more PDFs to merge.');
      return;
    }
    await _runConversion(() async => [await PdfConverter.mergePdfs(_pickedFiles)]);
  }

  Future<void> _splitPdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    final startController = TextEditingController(text: '1');
    final endController = TextEditingController(text: '1');
    bool splitAllPages = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Split PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: splitAllPages,
                title: const Text('Split into individual pages'),
                onChanged: (v) =>
                    setDialogState(() => splitAllPages = v ?? false),
              ),
              if (!splitAllPages) ...[
                TextField(
                  controller: startController,
                  decoration: const InputDecoration(labelText: 'Start page'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: endController,
                  decoration: const InputDecoration(labelText: 'End page'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Split'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final file = _pickedFiles.first;
    if (splitAllPages) {
      await _runConversion(() => PdfConverter.splitPdfIntoPages(file));
    } else {
      final start = int.tryParse(startController.text) ?? 1;
      final end = int.tryParse(endController.text) ?? 1;
      await _runConversion(
          () async => [await PdfConverter.splitPdfRange(file, start, end)]);
    }
  }

  Future<void> _rotatePdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    int angle = 90;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rotate PDF'),
          content: DropdownButton<int>(
            value: angle,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 90, child: Text('90°')),
              DropdownMenuItem(value: 180, child: Text('180°')),
              DropdownMenuItem(value: 270, child: Text('270°')),
            ],
            onChanged: (v) => setDialogState(() => angle = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rotate'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final file = _pickedFiles.first;
    await _runConversion(() async => [await PdfConverter.rotatePdf(file, angle)]);
  }

  Future<void> _protectPdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Password protect PDF'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Protect'),
          ),
        ],
      ),
    );
    if (confirmed != true || controller.text.isEmpty) return;

    final file = _pickedFiles.first;
    await _runConversion(
        () async => [await PdfConverter.protectPdf(file, controller.text)]);
  }

  Future<void> _unlockPdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock PDF (enter current password)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (confirmed != true || controller.text.isEmpty) return;

    final file = _pickedFiles.first;
    await _runConversion(
        () async => [await PdfConverter.unlockPdf(file, controller.text)]);
  }

  Future<void> _resizeImageDialog() async {
    if (_pickedFiles.isEmpty) return;
    final widthController = TextEditingController();
    final heightController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resize image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              decoration: const InputDecoration(labelText: 'Width (px)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: heightController,
              decoration: const InputDecoration(labelText: 'Height (px)'),
              keyboardType: TextInputType.number,
            ),
            const Text(
              'Leave one blank to keep aspect ratio.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resize'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final width = int.tryParse(widthController.text);
    final height = int.tryParse(heightController.text);
    if (width == null && height == null) return;

    await _runConversion(() async {
      final outs = <File>[];
      for (final f in _pickedFiles) {
        final out = await ImageConverter.resize(f, width: width, height: height);
        if (out != null) outs.add(out);
      }
      return outs;
    });
  }

  Future<void> _compressImageDialog() async {
    if (_pickedFiles.isEmpty) return;
    int localQuality = 70;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Compress image'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Quality: $localQuality%'),
              Slider(
                value: localQuality.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                label: '$localQuality%',
                onChanged: (v) =>
                    setDialogState(() => localQuality = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Compress'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await _runConversion(() async {
      final outs = <File>[];
      for (final f in _pickedFiles) {
        final out = await ImageConverter.compress(f, quality: localQuality);
        if (out != null) outs.add(out);
      }
      return outs;
    });
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
            const Text('Image Tools', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('Resize', _resizeImageDialog),
              _btn('Compress', _compressImageDialog),
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
            Row(
              children: [
                const Text('PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  tooltip: 'Image → PDF settings',
                  onPressed: _showPdfSettingsDialog,
                ),
              ],
            ),
            Wrap(spacing: 8, children: [
              _btn('Image → PDF', () => _convertTo('', ConverterType.imageToPdf)),
              _btn('PDF → Text', () => _convertTo('', ConverterType.pdfToText)),
              _btn('Text → PDF', () => _convertTo('', ConverterType.textToPdf)),
            ]),
            const SizedBox(height: 8),
            const Text('PDF Tools', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('Merge (2+ PDFs)', _mergePdfsAction),
              _btn('Split', _splitPdfDialog),
              _btn('Rotate', _rotatePdfDialog),
              _btn('Protect', _protectPdfDialog),
              _btn('Unlock', _unlockPdfDialog),
            ]),
            const SizedBox(height: 16),
            const Text('Notebook', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: [
              _btn('ipynb → PDF', () => _convertTo('', ConverterType.ipynbToPdf)),
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
  ipynbToPdf,
}
