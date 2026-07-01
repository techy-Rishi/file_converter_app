import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// OPTIONAL high-fidelity converter using the CloudConvert API.
/// Use this instead of DocxConverter when you need to preserve fonts,
/// tables, images, and exact layout during PDF <-> Word conversion.
///
/// Requires a free CloudConvert API key: https://cloudconvert.com/api/v2
/// Free tier: 25 conversion minutes/day, enough for testing and light use.
class CloudConvertService {
  static const String _apiKey = 'YOUR_CLOUDCONVERT_API_KEY';
  static const String _baseUrl = 'https://api.cloudconvert.com/v2';

  static Future<File?> convert({
    required File inputFile,
    required String inputFormat, // e.g. 'pdf'
    required String outputFormat, // e.g. 'docx'
  }) async {
    // 1. Create a conversion job (import -> convert -> export)
    final jobRes = await http.post(
      Uri.parse('$_baseUrl/jobs'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'tasks': {
          'import-file': {'operation': 'import/upload'},
          'convert-file': {
            'operation': 'convert',
            'input': 'import-file',
            'input_format': inputFormat,
            'output_format': outputFormat,
          },
          'export-file': {
            'operation': 'export/url',
            'input': 'convert-file',
          },
        }
      }),
    );
    final job = jsonDecode(jobRes.body)['data'];

    // 2. Upload the file to the import task
    final importTask = (job['tasks'] as List)
        .firstWhere((t) => t['name'] == 'import-file');
    final uploadUrl = importTask['result']['form']['url'];
    final uploadParams = importTask['result']['form']['parameters'];

    final uploadReq = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    uploadParams.forEach((k, v) => uploadReq.fields[k] = v.toString());
    uploadReq.files.add(await http.MultipartFile.fromPath('file', inputFile.path));
    await uploadReq.send();

    // 3. Poll job status until export task finishes
    final jobId = job['id'];
    String? downloadUrl;
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final statusRes = await http.get(
        Uri.parse('$_baseUrl/jobs/$jobId'),
        headers: {'Authorization': 'Bearer $_apiKey'},
      );
      final statusJob = jsonDecode(statusRes.body)['data'];
      final exportTask = (statusJob['tasks'] as List)
          .firstWhere((t) => t['name'] == 'export-file');
      if (exportTask['status'] == 'finished') {
        downloadUrl = exportTask['result']['files'][0]['url'];
        break;
      }
    }
    if (downloadUrl == null) return null;

    // 4. Download the converted file
    final fileRes = await http.get(Uri.parse(downloadUrl));
    final dir = await getApplicationDocumentsDirectory();
    final outFile = File('${dir.path}/converted.$outputFormat');
    await outFile.writeAsBytes(fileRes.bodyBytes);
    return outFile;
  }
}
