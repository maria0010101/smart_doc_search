import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';

/// Utility class for API key encryption, masking, and security management.
/// Prevents plain-text storage of sensitive API credentials across Android and Desktop.
///
/// Two cipher formats are supported:
///  * `enc:v2:` — HMAC-SHA256 key-stream cipher with a random per-value nonce
///                 (current format).
///  * `enc:v1:` — legacy XOR key-stream, still readable for backward
///                 compatibility with values written by older builds.
class SecurityUtil {
  // Current encryption signature prefix (HMAC-SHA256 key stream + nonce)
  static const String _encPrefixV2 = 'enc:v2:';
  // Legacy encryption signature prefix (XOR key stream)
  static const String _encPrefixV1 = 'enc:v1:';

  // Constant key derivation seed for local encryption
  static const String _secretSeed = 'SmartDoc-Security-2026-AI-KeyStore-v2';

  // Legacy v1 cipher key (read-only compatibility)
  static const List<int> _cipherKeyV1 = [
    0x53, 0x6d, 0x61, 0x72, 0x74, 0x44, 0x6f, 0x63, // SmartDoc
    0x53, 0x65, 0x63, 0x75, 0x72, 0x69, 0x74, 0x79, // Security
    0x32, 0x30, 0x32, 0x36, 0x5f, 0x41, 0x49, 0x5f, // 2026_AI_
    0x4b, 0x65, 0x79, 0x53, 0x74, 0x6f, 0x72, 0x65  // KeyStore
  ];

  /// Masks an API key for safe display in UI and prevents leakage in logs.
  static String maskKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '未設定';
    if (trimmed.length <= 8) return '********';

    final prefixLen = trimmed.length > 12 ? 6 : 3;
    final suffixLen = trimmed.length > 12 ? 4 : 3;
    final prefix = trimmed.substring(0, prefixLen);
    final suffix = trimmed.substring(trimmed.length - suffixLen);
    return '$prefix...$suffix';
  }

  static List<int> _randomNonce(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Deterministic key stream derived from the seed and the per-value nonce.
  static List<int> _keyStream(List<int> nonce, int length) {
    final out = <int>[];
    final hmac = Hmac(sha256, utf8.encode(_secretSeed));
    var counter = 0;
    while (out.length < length) {
      out.addAll(hmac.convert(<int>[...nonce, ...utf8.encode(':$counter')]).bytes);
      counter++;
    }
    return out;
  }

  /// Encrypts a plain-text API key using an HMAC-SHA256 key stream and a random
  /// nonce, then Base64-encodes the payload.
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final plainBytes = utf8.encode(plainText);
    final nonce = _randomNonce(12);
    final stream = _keyStream(nonce, plainBytes.length);
    final cipherBytes = List<int>.generate(
      plainBytes.length,
      (i) => plainBytes[i] ^ stream[i],
    );
    return '$_encPrefixV2${base64.encode(nonce)}:${base64.encode(cipherBytes)}';
  }

  /// Decrypts a cipher-text string back to plain-text.
  /// Supports both the current v2 format and legacy v1 / unencrypted values.
  static String decrypt(String cipherText) {
    final trimmed = cipherText.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith(_encPrefixV2)) {
      try {
        final parts = trimmed.substring(_encPrefixV2.length).split(':');
        if (parts.length != 2) return '';
        final nonce = base64.decode(parts[0]);
        final cipherBytes = base64.decode(parts[1]);
        final stream = _keyStream(nonce, cipherBytes.length);
        final plainBytes = List<int>.generate(
          cipherBytes.length,
          (i) => cipherBytes[i] ^ stream[i],
        );
        return utf8.decode(plainBytes);
      } catch (_) {
        return '';
      }
    }

    if (trimmed.startsWith(_encPrefixV1)) {
      try {
        final base64Data = trimmed.substring(_encPrefixV1.length);
        final encryptedBytes = base64.decode(base64Data);
        final plainBytes = List<int>.generate(
          encryptedBytes.length,
          (i) => encryptedBytes[i] ^ _cipherKeyV1[i % _cipherKeyV1.length],
        );
        return utf8.decode(plainBytes);
      } catch (_) {
        return '';
      }
    }

    // Legacy unencrypted plain text
    return trimmed;
  }

  /// Saves an API key in encrypted form to SharedPreferences.
  static Future<void> saveEncryptedKey(
    SharedPreferences prefs,
    String prefKey,
    String plainTextKey,
  ) async {
    final encrypted = encrypt(plainTextKey.trim());
    await prefs.setString(prefKey, encrypted);
  }

  /// Reads and decrypts an API key from SharedPreferences.
  static String getDecryptedKey(SharedPreferences prefs, String prefKey) {
    final raw = prefs.getString(prefKey) ?? '';
    return decrypt(raw);
  }

  /// One-click clear all stored API keys for all providers.
  static Future<void> clearAllApiKeys(SharedPreferences prefs) async {
    for (final key in AppConstants.allApiKeyPrefKeys) {
      await prefs.remove(key);
    }
  }
}
