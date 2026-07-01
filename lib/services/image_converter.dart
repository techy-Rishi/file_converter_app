import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Converts an image file to another image format.
/// Supported target formats: 'png', 'jpg', 'bmp', 'gif'
class ImageConverter {
  static Future<File?> convert(File inputFile, String targetFormat) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    List<int> outputBytes;
    switch (targetFormat.toLowerCase()) {
      case 'png':
        outputBytes = img.encodePng(image);
        break;
      case 'jpg':
      case 'jpeg':
        outputBytes = img.encodeJpg(image, quality: 92);
        break;
      case 'bmp':
        outputBytes = img.encodeBmp(image);
        break;
      case 'gif':
        outputBytes = img.encodeGif(image);
        break;
      default:
        throw UnsupportedError('Format $targetFormat not supported');
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${inputFile.uri.pathSegments.last.split('.').first}.$targetFormat';
    final outFile = File('${dir.path}/$fileName');
    await outFile.writeAsBytes(outputBytes);
    return outFile;
  }
}
