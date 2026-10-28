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

class ConverterApp extends StatefulWidget {
  const ConverterApp({super.key});

  @override
  State<ConverterApp> createState() => _ConverterAppState();
}

class _ConverterAppState extends State<ConverterApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConvertKaro',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const HomePage({super.key, required this.onToggleTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final List<File> _pickedFiles = [];
  List<File> _lastOutputs = [];
  int _lastInputBytes = 0;
  int _lastOutputBytes = 0;
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
  int? _imgToPdfTargetKb;

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
    final widthCtrl = TextEditingController(text: _customWidthCm.toString());
    final heightCtrl = TextEditingController(text: _customHeightCm.toString());
    final targetKbCtrl = TextEditingController(
      text: _imgToPdfTargetKb?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF4F46E5)),
                  SizedBox(width: 8),
                  Text('Image → PDF Settings'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: targetKbCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max PDF Size in KB (Optional)',
                        hintText: 'e.g. 200 (leave blank for default)',
                        prefixIcon: Icon(Icons.compress_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        _imgToPdfTargetKb =
                            (parsed != null && parsed > 0) ? parsed : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Text('Margin: ${_marginCm.toStringAsFixed(1)} cm'),
                    Slider(
                      value: _marginCm,
                      min: 0,
                      max: 5,
                      divisions: 50,
                      label: '${_marginCm.toStringAsFixed(1)} cm',
                      onChanged: (v) => setDialogState(() => _marginCm = v),
                    ),
                    Text('Image Quality: $_quality%'),
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
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Save Settings'),
                ),
              ],
            );
          },
        );
      },
    );
    widthCtrl.dispose();
    heightCtrl.dispose();
    targetKbCtrl.dispose();
    setState(() {});
  }

  /// Unified conversion runner for all actions
  Future<void> _runConversion(Future<List<File>> Function() task) async {
    if (_pickedFiles.isEmpty) return;

    final inputSizes = await Future.wait(
      _pickedFiles.map((f) async => await f.exists() ? await f.length() : 0),
    );
    final totalInBytes = inputSizes.fold<int>(0, (sum, s) => sum + s);

    setState(() {
      _busy = true;
      _isError = false;
      _status = 'Processing your file(s)... Please wait';
      _lastOutputs = [];
      _lastInputBytes = totalInBytes;
      _lastOutputBytes = 0;
    });
    try {
      final outputs = await task();
      if (outputs.isNotEmpty) {
        final sizes = await Future.wait(outputs.map((f) => f.length()));
        final totalOutBytes = sizes.fold<int>(0, (sum, s) => sum + s);
        setState(() {
          _lastOutputs = outputs;
          _lastOutputBytes = totalOutBytes;
          _isError = false;
          _status =
              'Success! ${outputs.length} file(s) ready (${_formatBytes(totalOutBytes)})';
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
            targetKb: _imgToPdfTargetKb,
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
              targetKb: _imgToPdfTargetKb,
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
              DropdownMenuItem(
                  value: 270, child: Text('270° Counter-Clockwise')),
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
          decoration: const InputDecoration(
            labelText: 'Enter new password',
            border: OutlineInputBorder(),
          ),
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
          decoration: const InputDecoration(
            labelText: 'Current PDF password',
            border: OutlineInputBorder(),
          ),
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
              decoration: const InputDecoration(
                labelText: 'Width (px)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: heightController,
              decoration: const InputDecoration(
                labelText: 'Height (px)',
                border: OutlineInputBorder(),
              ),
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
        final out =
            await ImageConverter.resize(f, width: width, height: height);
        if (out != null) outs.add(out);
      }
      return outs;
    });
  }

  /// Upgraded Image Compression Dialog: Target Size (KB) OR Quality Slider
  Future<void> _compressImageDialog() async {
    if (_pickedFiles.isEmpty) return;
    bool useTargetKb = true;
    int localQuality = 70;
    final kbController = TextEditingController(text: '100');
    final curSize = _pickedFiles.first.lengthSync();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.compress_rounded, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Expanded(child: Text('Compress Image(s)')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current file size: ${_formatBytes(curSize)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Target KB'),
                      icon: Icon(Icons.straighten_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('By Quality %'),
                      icon: Icon(Icons.tune_rounded, size: 18),
                    ),
                  ],
                  selected: {useTargetKb},
                  onSelectionChanged: (s) =>
                      setDialogState(() => useTargetKb = s.first),
                ),
                const SizedBox(height: 16),
                if (useTargetKb) ...[
                  TextField(
                    controller: kbController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Target Max Size (in KB)',
                      hintText: 'e.g. 50, 100, 200',
                      suffixText: 'KB',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Quick Presets:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [20, 50, 100, 200, 500].map((kb) {
                      return ActionChip(
                        label: Text('$kb KB'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setDialogState(() => kbController.text = '$kb'),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Text('JPEG Quality: $localQuality%'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Compress Now'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final targetKb = int.tryParse(kbController.text.trim());
    kbController.dispose();

    await _runConversion(() async {
      final outs = <File>[];
      for (final f in _pickedFiles) {
        File? out;
        if (useTargetKb && targetKb != null && targetKb > 0) {
          out = await ImageConverter.compressToTargetKb(f, targetKb: targetKb);
        } else {
          out = await ImageConverter.compress(f, quality: localQuality);
        }
        if (out != null) outs.add(out);
      }
      return outs;
    });
  }

  /// New PDF Compression Dialog: Target Size (KB) OR Compression Level
  Future<void> _compressPdfDialog() async {
    if (_pickedFiles.isEmpty) return;
    bool useTargetKb = true;
    int compressionPercent = 80;
    final kbController = TextEditingController(text: '200');
    final curSize = _pickedFiles.first.lengthSync();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5)),
              SizedBox(width: 8),
              Expanded(child: Text('Compress PDF')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current PDF size: ${_formatBytes(curSize)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Target KB'),
                      icon: Icon(Icons.straighten_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Level %'),
                      icon: Icon(Icons.speed_rounded, size: 18),
                    ),
                  ],
                  selected: {useTargetKb},
                  onSelectionChanged: (s) =>
                      setDialogState(() => useTargetKb = s.first),
                ),
                const SizedBox(height: 16),
                if (useTargetKb) ...[
                  TextField(
                    controller: kbController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Target Max Size (in KB)',
                      hintText: 'e.g. 100, 250, 500',
                      suffixText: 'KB',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Quick Presets:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [100, 200, 300, 500, 1024].map((kb) {
                      return ActionChip(
                        label: Text(kb == 1024 ? '1 MB' : '$kb KB'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setDialogState(() => kbController.text = '$kb'),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Text('Compression Strength: $compressionPercent%'),
                  Slider(
                    value: compressionPercent.toDouble(),
                    min: 20,
                    max: 100,
                    divisions: 8,
                    label: '$compressionPercent%',
                    onChanged: (v) =>
                        setDialogState(() => compressionPercent = v.round()),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.compress_rounded, size: 18),
              label: const Text('Compress PDF'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final targetKb = int.tryParse(kbController.text.trim());
    kbController.dispose();

    final file = _pickedFiles.first;
    await _runConversion(() async => [
          await PdfConverter.compressPdf(
            file,
            targetKb: (useTargetKb && targetKb != null && targetKb > 0)
                ? targetKb
                : null,
            compressionPercent: compressionPercent,
          ),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final category = _detectCategory();
    final hasFiles = _pickedFiles.isNotEmpty;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.tertiary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.autorenew_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'ConvertKaro',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ],
        ),
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
            icon: const Icon(Icons.brightness_6_rounded),
            tooltip: 'Toggle Theme',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded),
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
              _buildHeroFilePickerCard(hasFiles),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _busy
                    ? const Padding(
                        key: ValueKey('busy'),
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text(
                              'Processing on background isolate...',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(sizeFactor: anim, child: child),
                ),
                child: _status != null
                    ? Padding(
                        key: ValueKey(_status),
                        padding: const EdgeInsets.only(top: 12),
                        child: _buildStatusBanner(),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: !hasFiles
                    ? _buildEmptyStateSupportedFormats()
                    : Column(
                        key: ValueKey('${category.name}_$_showAllTools'),
                        children: _buildDynamicToolCards(category),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroFilePickerCard(bool hasFiles) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.65),
            cs.secondaryContainer.withValues(alpha: 0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasFiles) ...[
              Icon(
                Icons.cloud_upload_outlined,
                size: 42,
                color: cs.primary,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap below to pick images, PDFs, Word, Excel or Notebooks',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : () => _pickFiles(append: false),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                      !hasFiles
                          ? 'Select File(s) to Convert'
                          : 'Replace (${_pickedFiles.length} selected)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (hasFiles) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : () => _pickFiles(append: true),
                    icon: const Icon(Icons.add_rounded, size: 18),
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
                  final sizeStr =
                      f.existsSync() ? _formatBytes(f.lengthSync()) : '';
                  return InputChip(
                    avatar: const Icon(Icons.insert_drive_file_rounded, size: 16),
                    label: Text(
                      '${f.uri.pathSegments.last} ($sizeStr)',
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
        ? Colors.red.withValues(alpha: 0.12)
        : Colors.green.withValues(alpha: 0.12);
    final fgColor = _isError ? Colors.red.shade700 : Colors.green.shade700;

    String? savingsBadge;
    if (!_isError && _lastInputBytes > 0 && _lastOutputBytes > 0) {
      final diff = _lastInputBytes - _lastOutputBytes;
      if (diff > 0) {
        final pct = ((diff / _lastInputBytes) * 100).toStringAsFixed(0);
        savingsBadge =
            '${_formatBytes(_lastInputBytes)} → ${_formatBytes(_lastOutputBytes)} (Saved $pct%)';
      } else {
        savingsBadge =
            '${_formatBytes(_lastInputBytes)} → ${_formatBytes(_lastOutputBytes)}';
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fgColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: fgColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status!,
                  style: TextStyle(color: fgColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (savingsBadge != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: fgColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Size: $savingsBadge',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ),
          ],
          if (_lastOutputs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => Share.shareXFiles(
                  _lastOutputs.map((f) => XFile(f.path)).toList(),
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
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
      key: const ValueKey('empty_state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All-in-One Smart File Converter & Compressor',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Select any file above — ConvertKaro automatically shows compatible conversion & exact KB compression tools.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _formatInfoTile(
          Icons.image_outlined,
          'Images (PNG, JPG, WEBP, BMP, GIF)',
          'Compress to exact KB (50KB, 100KB), Resize, Convert, or Image → PDF',
          Colors.indigo,
        ),
        _formatInfoTile(
          Icons.picture_as_pdf_outlined,
          'PDF Documents (.pdf)',
          'Compress PDF to KB, PDF → Word, PDF → Text, Merge, Split, Rotate, Lock/Unlock',
          Colors.redAccent,
        ),
        _formatInfoTile(
          Icons.description_outlined,
          'Word & Text (.docx, .txt)',
          'Word ↔ PDF, Word ↔ Text, Text → PDF with full UTF-8 support',
          Colors.blue,
        ),
        _formatInfoTile(
          Icons.table_view_rounded,
          'Data & Spreadsheets (.csv, .json, .xlsx)',
          '2-way conversion between CSV, JSON, and Excel (.xlsx)',
          Colors.teal,
        ),
        _formatInfoTile(
          Icons.code_rounded,
          'Jupyter Notebooks (.ipynb)',
          'Export Notebook cells & output to PDF or Python (.py) script',
          Colors.deepOrange,
        ),
      ],
    );
  }

  Widget _formatInfoTile(
    IconData icon,
    String title,
    String subtitle,
    Color accent,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          foregroundColor: accent,
          child: Icon(icon, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  List<Widget> _buildDynamicToolCards(FileCategory cat) {
    final showAll = _showAllTools || cat == FileCategory.unknown;
    final cards = <Widget>[];

    // 1. IMAGE TOOLS
    if (showAll || cat == FileCategory.image) {
      cards.add(_toolSectionCard(
        index: 0,
        title: 'Image Conversions & KB Compressor',
        icon: Icons.image_rounded,
        trailing: IconButton(
          icon: const Icon(Icons.tune_rounded, size: 20),
          tooltip: 'Image → PDF Settings',
          onPressed: _showPdfSettingsDialog,
        ),
        children: [
          _btn(
            'Compress (Target KB)',
            _compressImageDialog,
            icon: Icons.compress_rounded,
            highlight: true,
          ),
          _btn('Resize (px)', _resizeImageDialog, icon: Icons.aspect_ratio_rounded),
          _btn(
            'Image(s) → PDF',
            () => _convertTo('', ConverterType.imageToPdf),
            icon: Icons.picture_as_pdf_rounded,
          ),
          _btn('→ PNG', () => _convertTo('png', ConverterType.image)),
          _btn('→ JPG', () => _convertTo('jpg', ConverterType.image)),
          _btn('→ BMP', () => _convertTo('bmp', ConverterType.image)),
          _btn('→ GIF', () => _convertTo('gif', ConverterType.image)),
          _btn('→ TGA', () => _convertTo('tga', ConverterType.image)),
          _btn('→ ICO', () => _convertTo('ico', ConverterType.image)),
        ],
      ));
    }

    // 2. PDF TOOLS
    if (showAll || cat == FileCategory.pdf) {
      cards.add(_toolSectionCard(
        index: 1,
        title: 'PDF Tools & KB Compressor',
        icon: Icons.picture_as_pdf_rounded,
        children: [
          _btn(
            'Compress PDF (KB)',
            _compressPdfDialog,
            icon: Icons.compress_rounded,
            highlight: true,
          ),
          _btn(
            'PDF → Word (.docx)',
            () => _convertTo('', ConverterType.pdfToWord),
            icon: Icons.description_rounded,
          ),
          _btn(
            'PDF → Text (.txt)',
            () => _convertTo('', ConverterType.pdfToText),
            icon: Icons.notes_rounded,
          ),
          _btn('Merge PDFs (2+)', _mergePdfsAction, icon: Icons.CallMerge_rounded),
          _btn('Split PDF', _splitPdfDialog, icon: Icons.call_split_rounded),
          _btn('Rotate PDF', _rotatePdfDialog, icon: Icons.rotate_right_rounded),
          _btn('Protect (Lock)', _protectPdfDialog, icon: Icons.lock_outline_rounded),
          _btn('Unlock PDF', _unlockPdfDialog, icon: Icons.lock_open_rounded),
        ],
      ));
    }

    // 3. WORD (.DOCX) TOOLS
    if (showAll || cat == FileCategory.word) {
      cards.add(_toolSectionCard(
        index: 2,
        title: 'Word (.docx) Conversions',
        icon: Icons.article_rounded,
        children: [
          _btn(
            'Word → PDF',
            () => _convertTo('', ConverterType.wordToPdf),
            icon: Icons.picture_as_pdf_rounded,
            highlight: true,
          ),
          _btn(
            'Word → Text (.txt)',
            () => _convertTo('', ConverterType.wordToText),
            icon: Icons.notes_rounded,
          ),
        ],
      ));
    }

    // 4. TEXT (.TXT) TOOLS
    if (showAll || cat == FileCategory.text) {
      cards.add(_toolSectionCard(
        index: 3,
        title: 'Text (.txt) Conversions',
        icon: Icons.notes_rounded,
        children: [
          _btn(
            'Text → PDF',
            () => _convertTo('', ConverterType.textToPdf),
            icon: Icons.picture_as_pdf_rounded,
            highlight: true,
          ),
          _btn(
            'Text → Word (.docx)',
            () => _convertTo('', ConverterType.textToWord),
            icon: Icons.description_rounded,
          ),
        ],
      ));
    }

    // 5. CSV / JSON / XLSX SPREADSHEET TOOLS
    if (showAll ||
        cat == FileCategory.csv ||
        cat == FileCategory.json ||
        cat == FileCategory.xlsx) {
      cards.add(_toolSectionCard(
        index: 4,
        title: 'Spreadsheet & Data Tools',
        icon: Icons.table_view_rounded,
        children: [
          if (showAll || cat == FileCategory.csv) ...[
            _btn('CSV → JSON', () => _convertTo('', ConverterType.csvToJson)),
            _btn('CSV → Excel (.xlsx)',
                () => _convertTo('', ConverterType.csvToXlsx)),
          ],
          if (showAll || cat == FileCategory.json) ...[
            _btn('JSON → CSV', () => _convertTo('', ConverterType.jsonToCsv)),
            _btn('JSON → Excel (.xlsx)',
                () => _convertTo('', ConverterType.jsonToXlsx)),
          ],
          if (showAll || cat == FileCategory.xlsx) ...[
            _btn('Excel (.xlsx) → CSV',
                () => _convertTo('', ConverterType.xlsxToCsv)),
            _btn('Excel (.xlsx) → JSON',
                () => _convertTo('', ConverterType.xlsxToJson)),
          ],
        ],
      ));
    }

    // 6. JUPYTER NOTEBOOK (.IPYNB)
    if (showAll || cat == FileCategory.ipynb) {
      cards.add(_toolSectionCard(
        index: 5,
        title: 'Jupyter Notebook (.ipynb)',
        icon: Icons.terminal_rounded,
        children: [
          _btn(
            'ipynb → PDF',
            () => _convertTo('', ConverterType.ipynbToPdf),
            highlight: true,
          ),
          _btn(
            'ipynb → Python (.py)',
            () => _convertTo('', ConverterType.ipynbToPy),
          ),
        ],
      ));
    }

    return cards;
  }

  Widget _toolSectionCard({
    required int index,
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 280 + (index * 70)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.primary,
                    child: Icon(icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: children,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(
    String label,
    VoidCallback onPressed, {
    IconData? icon,
    bool highlight = false,
  }) {
    final disabled = _pickedFiles.isEmpty || _busy;
    if (highlight) {
      return FilledButton.icon(
        onPressed: disabled ? null : onPressed,
        icon: Icon(icon ?? Icons.auto_awesome_rounded, size: 17),
        label: Text(label),
      );
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
        onPressed: disabled ? null : onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: disabled ? null : onPressed,
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
