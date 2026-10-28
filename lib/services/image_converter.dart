import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Converts, resizes, and compresses images on a background Isolate
/// so the UI never freezes.
class ImageConverter {
  static String _baseName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static Future<File?> convert(
    File inputFile,
    String targetFormat, {
    int quality = 92,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final fmt = targetFormat.toLowerCase();

    final outputBytes = await Isolate.run<List<int>?>(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      switch (fmt) {
        case 'png':
          return img.encodePng(image);
        case 'jpg':
        case 'jpeg':
          return img.encodeJpg(image, quality: quality.clamp(1, 100));
        case 'bmp':
          return img.encodeBmp(image);
        case 'gif':
          return img.encodeGif(image);
        case 'tga':
          return img.encodeTga(image);
        case 'ico':
          final icoImg = (image.width > 256 || image.height > 256)
              ? img.copyResize(
                  image,
                  width: image.width >= image.height ? 256 : null,
                  height: image.height > image.width ? 256 : null,
                )
              : image;
          return img.encodeIco(icoImg);
        default:
          throw UnsupportedError('Format $targetFormat not supported');
      }
    });

    if (outputBytes == null) return null;

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File('${dir.path}/${_baseName(inputFile)}_$timestamp.$fmt');
    await outFile.writeAsBytes(outputBytes);
    return outFile;
  }

  /// Resizes an image. If only width or height is given, aspect ratio is preserved.
  static Future<File?> resize(
    File inputFile, {
    int? width,
    int? height,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final ext = inputFile.path.split('.').last.toLowerCase();

    final outputBytes = await Isolate.run<List<int>?>(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final resized = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );

      switch (ext) {
        case 'png':
          return img.encodePng(resized);
        case 'bmp':
          return img.encodeBmp(resized);
        case 'gif':
          return img.encodeGif(resized);
        default:
          return img.encodeJpg(resized, quality: 92);
      }
    });

    if (outputBytes == null) return null;

    final dir = await getTemporaryDirectory();
    final outExt = ['png', 'bmp', 'gif'].contains(ext) ? ext : 'jpg';
    final outFile = File(
      '${dir.path}/${_baseName(inputFile)}_resized_${width ?? 'auto'}x${height ?? 'auto'}.$outExt',
    );
    await outFile.writeAsBytes(outputBytes);
    return outFile;
  }

  /// Re-compresses an image at the given JPEG quality (1-100).
  static Future<File?> compress(File inputFile, {int quality = 70}) async {
    final bytes = await inputFile.readAsBytes();

    final compressedBytes = await Isolate.run<List<int>?>(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return img.encodeJpg(image, quality: quality.clamp(1, 100));
    });

    if (compressedBytes == null) return null;

    final dir = await getTemporaryDirectory();
    final outFile = File(
      '${dir.path}/${_baseName(inputFile)}_q$quality.jpg',
    );
    await outFile.writeAsBytes(compressedBytes);
    return outFile;
  }
}
