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

  /// Resizes an image. Supply [width] and/or [height]; if only one is
  /// given, the other is calculated to preserve aspect ratio.
  static Future<File?> resize(
    File inputFile, {
    int? width,
    int? height,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final resized = img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );

    final dir = await getApplicationDocumentsDirectory();
    final ext = inputFile.path.split('.').last;
    final baseName = inputFile.uri.pathSegments.last.split('.').first;
    final outFile = File('${dir.path}/${baseName}_resized.$ext');
    final outputBytes = ext.toLowerCase() == 'png'
        ? img.encodePng(resized)
        : img.encodeJpg(resized, quality: 92);
    await outFile.writeAsBytes(outputBytes);
    return outFile;
  }

  /// Re-compresses an image at the given JPEG quality (1-100) without
  /// changing its dimensions. Lower quality = smaller file size.
  static Future<File?> compress(File inputFile, {int quality = 70}) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final compressedBytes = img.encodeJpg(image, quality: quality.clamp(1, 100));

    final dir = await getApplicationDocumentsDirectory();
    final baseName = inputFile.uri.pathSegments.last.split('.').first;
    final outFile = File('${dir.path}/${baseName}_compressed.jpg');
    await outFile.writeAsBytes(compressedBytes);
    return outFile;
  }
}
