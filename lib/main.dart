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

const String kSupportEmail = 'support@example.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConverterApp());
}

enum FileCategory {
  image,
  pdf,
  word,
  csv,
  json,
  xlsx,
  text,
  ipynb,
  unknown,
}

class ConverterApp extends StatelessWidget {
  const ConverterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConvertKaro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
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
  final List<File> _pickedFiles = [];
  List<File> _lastOutputs = [];
  String? _status;
  bool _isError = false;
  bool _busy = false;
  bool _showAllTools = false;

  // Image -> PDF settings
  double _marginCm = 1.0;
  int _quality = 90;
  PdfPageSize _pageSize = PdfPageSize.a4;
  double _customWidthCm = 21.0;
  double _customHeightCm = 29.7;
  PdfFitMode _fitMode = PdfFitMode.fitPage;
  double _dpi = 300;

  static const _imageExts = {'png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'tga'};

  String _extOf(File f) {
    final name = f.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  FileCategory _detectCategory() {
    if (_pickedFiles.isEmpty) return FileCategory.unknown;
    final ext = _extOf(_pickedFiles.first);
    if (_imageExts.contains(ext)) return FileCategory.image;
    if (ext == 'pdf') return FileCategory.pdf;
    if (ext == 'docx') return FileCategory.word;
    if (ext == 'csv') return FileCategory.csv;
    if (ext == 'json') return FileCategory.json;
    if (ext == 'xlsx') return FileCategory.xlsx;
    if (ext == 'txt' || ext == 'md' || ext == 'log') return FileCategory.text;
    if (ext == 'ipynb') return FileCategory.ipynb;
    return FileCategory.unknown;
  }

  Future<void> _pickFiles({bool append = false}) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      final newFiles = result.paths
          .where((p) => p != null)
          .map((p) => File(p!))
          .toList();
      setState(() {
        if (!append) _pickedFiles.clear();
        _pickedFiles.addAll(newFiles);
        _status = null;
        _isError = false;
        _lastOutputs = [];
      });
    }
  }

  void _removeFileAt(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
      if (_pickedFiles.isEmpty) {
        _status = null;
        _lastOutputs = [];
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _pickedFiles.clear();
      _lastOutputs = [];
      _status = null;
      _isError = false;
    });
  }

  Future<void> _openContactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=ConvertKaro Feedback',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found on this device.')),
        );
      }
    }
  }

  Future<void> _showPdfSettingsDialog() async {
    // Controllers created ONCE outside StatefulBuilder so typing decimals works!
    final widthCtrl = TextEditingController(text: _customWidthCm.toString());
    final heightCtrl = TextEditingController(text: _customHeightCm.toString());

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Image → PDF Settings'),
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
                              controller: widthCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Width (cm)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (v) {
                                final parsed = double.tryParse(v);
                                if (parsed != null && parsed > 0) {
                                  _customWidthCm = parsed;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: heightCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Height (cm)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (v) {
                                final parsed = double.tryParse(v);
                                if (parsed != null && parsed > 0) {
                                  _customHeightCm = parsed;
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
    widthCtrl.dispose();
    heightCtrl.dispose();
    setState(() {});
  }

  /// Unified conversion runner for all actions
  Future<void> _runConversion(Future<List<File>> Function() task) async {
    if (_pickedFiles.isEmpty) return;
    setState(() {
      _busy = true;
      _isError = false;
      _status = 'Converting... Please wait';
      _lastOutputs = [];
    });
    try {
      final outputs = await task();
      if (outputs.isNotEmpty) {
        final sizes = await Future.wait(outputs.map((f) => f.length()));
        final totalBytes = sizes.fold<int>(0, (sum, s) => sum + s);
        setState(() {
          _lastOutputs = outputs;
          _isError = false;
          _status =
              'Success! ${outputs.length} file(s) ready (${_formatBytes(totalBytes)})';
        });
        await Share.shareXFiles(outputs.map((f) => XFile(f.path)).toList());
      } else {
        setState(() {
          _isError = true;
          _status = 'Conversion failed: Could not process the selected file.';
        });
      }
    } catch (e) {
      setState(() {
        _isError = true;
        _status = 'Error: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _convertTo(String target, ConverterType type) async {
    await _runConversion(() async {
      final outputs = <File>[];
      final batchTypes = {ConverterType.image, ConverterType.imageToPdf};

      if (batchTypes.contains(type) && _pickedFiles.length > 1) {
        if (type == ConverterType.imageToPdf) {
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
          case ConverterType.xlsxToJson:
            output = await DocumentConverter.xlsxToJson(file);
            break;
          case ConverterType.jsonToXlsx:
            output = await DocumentConverter.jsonToXlsx(file);
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
          case ConverterType.ipynbToPy:
            output = await IpynbConverter.ipynbToPython(file);
            break;
        }
        if (output != null) outputs.add(output);
      }
      return outputs;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _mergePdfsAction() async {
    if (_pickedFiles.length < 2) {
      setState(() {
        _isError = true;
        _status = 'Please select at least 2 PDF files to merge (use "+ Add").';
      });
      return;
    }
    await _runConversion(
        () async => [await PdfConverter.mergePdfs(_pickedFiles)]);
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
                contentPadding: EdgeInsets.zero,
                value: splitAllPages,
                title: const Text('Split every page into separate PDF'),
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
            FilledButton(
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
              DropdownMenuItem(value: 90, child: Text('90° Clockwise')),
              DropdownMenuItem(value: 180, child: Text('180° Upside Down')),
              DropdownMenuItem(value: 270, child: Text('270° Counter-Clockwise')),
            ],
            onChanged: (v) => setDialogState(() => angle = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rotate'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final file = _pickedFiles.first;
    await _runConversion(
        () async => [await PdfConverter.rotatePdf(file, angle)]);
  }

  Future<void> _protectPdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Password Protect PDF'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Enter new password'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
        title: const Text('Unlock PDF'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Current PDF password'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
        title: const Text('Resize Image(s)'),
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
            const SizedBox(height: 8),
            const Text(
              'Tip: Leave one blank to automatically preserve aspect ratio.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
          title: const Text('Compress Image(s)'),
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
            FilledButton(
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
    final category = _detectCategory();
    final hasFiles = _pickedFiles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ConvertKaro'),
        actions: [
          if (hasFiles)
            Row(
              children: [
                const Text('All Tools', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _showAllTools,
                  onChanged: (v) => setState(() => _showAllTools = v),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: 'Contact / Feedback',
            onPressed: _openContactEmail,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilePickerCard(hasFiles),
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                _buildStatusBanner(),
              ],
              const SizedBox(height: 20),
              if (!hasFiles)
                _buildEmptyStateSupportedFormats()
              else
                ..._buildDynamicToolCards(category),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePickerCard(bool hasFiles) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pickFiles(append: false),
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      !hasFiles
                          ? 'Select File(s) to Convert'
                          : 'Replace (${_pickedFiles.length} selected)',
                    ),
                  ),
                ),
                if (hasFiles) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickFiles(append: true),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Clear all',
                    onPressed: _busy ? null : _clearSelection,
                  ),
                ],
              ],
            ),
            if (hasFiles) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(_pickedFiles.length, (i) {
                  final f = _pickedFiles[i];
                  return InputChip(
                    avatar: const Icon(Icons.insert_drive_file, size: 16),
                    label: Text(
                      f.uri.pathSegments.last,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: _busy ? null : () => _removeFileAt(i),
                    visualDensity: VisualDensity.compact,
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final bgColor = _isError
        ? Colors.red.withOpacity(0.1)
        : Colors.green.withOpacity(0.12);
    final fgColor = _isError ? Colors.red.shade800 : Colors.green.shade800;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fgColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _isError ? Icons.error_outline : Icons.check_circle_outline,
                color: fgColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status!,
                  style: TextStyle(color: fgColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_lastOutputs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Share.shareXFiles(
                  _lastOutputs.map((f) => XFile(f.path)).toList(),
                ),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share / Save Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyStateSupportedFormats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Smart Dynamic Converter',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick any file above — ConvertKaro will automatically detect its format and display the compatible conversion tools.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        _formatInfoTile(
          Icons.image_outlined,
          'Images (PNG, JPG, WEBP, BMP, GIF)',
          'Convert format, Resize, Compress, or combine into PDF',
        ),
        _formatInfoTile(
          Icons.picture_as_pdf_outlined,
          'PDF Documents (.pdf)',
          'PDF → Word, PDF → Text, Merge, Split, Rotate, Lock & Unlock',
        ),
        _formatInfoTile(
          Icons.description_outlined,
          'Word & Text (.docx, .txt)',
          'Word ↔ PDF, Word ↔ Text, Text → PDF',
        ),
        _formatInfoTile(
          Icons.table_chart_outlined,
          'Data & Spreadsheets (.csv, .json, .xlsx)',
          'Convert between CSV, JSON, and Excel (.xlsx)',
        ),
        _formatInfoTile(
          Icons.code_outlined,
          'Jupyter Notebooks (.ipynb)',
          'Export Notebook to PDF or Python (.py) script',
        ),
      ],
    );
  }

  Widget _formatInfoTile(IconData icon, String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
    );
  }

  List<Widget> _buildDynamicToolCards(FileCategory cat) {
    final showAll = _showAllTools || cat == FileCategory.unknown;
    final cards = <Widget>[];

    // 1. IMAGE TOOLS
    if (showAll || cat == FileCategory.image) {
      cards.add(_toolSectionCard(
        title: 'Image Conversions & Tools',
        icon: Icons.image,
        trailing: IconButton(
          icon: const Icon(Icons.settings, size: 20),
          tooltip: 'Image → PDF Settings',
          onPressed: _showPdfSettingsDialog,
        ),
        children: [
          _btn('→ PNG', () => _convertTo('png', ConverterType.image)),
          _btn('→ JPG', () => _convertTo('jpg', ConverterType.image)),
          _btn('→ BMP', () => _convertTo('bmp', ConverterType.image)),
          _btn('→ GIF', () => _convertTo('gif', ConverterType.image)),
          _btn('→ TGA', () => _convertTo('tga', ConverterType.image)),
          _btn('→ ICO', () => _convertTo('ico', ConverterType.image)),
          _btn('Image(s) → PDF', () => _convertTo('', ConverterType.imageToPdf)),
          _btn('Resize', _resizeImageDialog),
          _btn('Compress', _compressImageDialog),
        ],
      ));
    }

    // 2. PDF TOOLS
    if (showAll || cat == FileCategory.pdf) {
      cards.add(_toolSectionCard(
        title: 'PDF Conversions & Tools',
        icon: Icons.picture_as_pdf,
        children: [
          _btn('PDF → Word (.docx)', () => _convertTo('', ConverterType.pdfToWord)),
          _btn('PDF → Text (.txt)', () => _convertTo('', ConverterType.pdfToText)),
          _btn('Merge PDFs (2+)', _mergePdfsAction),
          _btn('Split PDF', _splitPdfDialog),
          _btn('Rotate PDF', _rotatePdfDialog),
          _btn('Protect (Lock)', _protectPdfDialog),
          _btn('Unlock PDF', _unlockPdfDialog),
        ],
      ));
    }

    // 3. WORD (.DOCX) TOOLS
    if (showAll || cat == FileCategory.word) {
      cards.add(_toolSectionCard(
        title: 'Word (.docx) Conversions',
        icon: Icons.article,
        children: [
          _btn('Word → PDF', () => _convertTo('', ConverterType.wordToPdf)),
          _btn('Word → Text (.txt)', () => _convertTo('', ConverterType.wordToText)),
        ],
      ));
    }

    // 4. TEXT (.TXT) TOOLS
    if (showAll || cat == FileCategory.text) {
      cards.add(_toolSectionCard(
        title: 'Text (.txt) Conversions',
        icon: Icons.notes,
        children: [
          _btn('Text → PDF', () => _convertTo('', ConverterType.textToPdf)),
          _btn('Text → Word (.docx)', () => _convertTo('', ConverterType.textToWord)),
        ],
      ));
    }

    // 5. CSV / JSON / XLSX SPREADSHEET TOOLS
    if (showAll ||
        cat == FileCategory.csv ||
        cat == FileCategory.json ||
        cat == FileCategory.xlsx) {
      cards.add(_toolSectionCard(
        title: 'Spreadsheet & Data Tools',
        icon: Icons.table_View,
        children: [
          if (showAll || cat == FileCategory.csv) ...[
            _btn('CSV → JSON', () => _convertTo('', ConverterType.csvToJson)),
            _btn('CSV → Excel (.xlsx)', () => _convertTo('', ConverterType.csvToXlsx)),
          ],
          if (showAll || cat == FileCategory.json) ...[
            _btn('JSON → CSV', () => _convertTo('', ConverterType.jsonToCsv)),
            _btn('JSON → Excel (.xlsx)', () => _convertTo('', ConverterType.jsonToXlsx)),
          ],
          if (showAll || cat == FileCategory.xlsx) ...[
            _btn('Excel (.xlsx) → CSV', () => _convertTo('', ConverterType.xlsxToCsv)),
            _btn('Excel (.xlsx) → JSON', () => _convertTo('', ConverterType.xlsxToJson)),
          ],
        ],
      ));
    }

    // 6. JUPYTER NOTEBOOK (.IPYNB)
    if (showAll || cat == FileCategory.ipynb) {
      cards.add(_toolSectionCard(
        title: 'Jupyter Notebook (.ipynb)',
        icon: Icons.terminal,
        children: [
          _btn('ipynb → PDF', () => _convertTo('', ConverterType.ipynbToPdf)),
          _btn('ipynb → Python (.py)', () => _convertTo('', ConverterType.ipynbToPy)),
        ],
      ));
    }

    return cards;
  }

  Widget _toolSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: children,
            ),
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
  xlsxToJson,
  jsonToXlsx,
  imageToPdf,
  pdfToText,
  textToPdf,
  wordToPdf,
  pdfToWord,
  wordToText,
  textToWord,
  ipynbToPdf,
  ipynbToPy,
}
