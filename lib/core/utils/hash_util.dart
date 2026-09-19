import 'dart:io';
import 'package:crypto/crypto.dart';

class HashUtil {
  /// Computes the SHA-256 checksum of a file.
  static Future<String> calculateFileSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Computes the SHA-256 of raw bytes.
  static String calculateBytesSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
