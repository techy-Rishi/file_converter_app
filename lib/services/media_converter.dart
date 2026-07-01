import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Converts audio/video files using FFmpeg.
/// Examples: mp4 -> mp3, mov -> mp4, wav -> mp3, etc.
class MediaConverter {
  static Future<File?> convert(File inputFile, String targetFormat) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${inputFile.uri.pathSegments.last.split('.').first}.$targetFormat';
    final outputPath = '${dir.path}/$fileName';

    final session = await FFmpegKit.execute(
      '-i "${inputFile.path}" "$outputPath"',
    );
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return File(outputPath);
    }
    return null; // conversion failed - check session logs for details
  }
}
