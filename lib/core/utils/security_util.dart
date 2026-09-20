import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/constants/app_constants.dart';

/// Utility class for API key encryption, masking, and security management.
/// Prevents plain-text storage of sensitive API credentials across Android and Desktop.
class SecurityUtil {
  // Obfuscation / encryption signature prefix
  static const String _encPrefix = 'enc:v1:';

  // Constant key derivation seed for local encryption
  static const List<int> _cipherKey = [
    0x53, 0x6d, 0x61, 0x72, 0x74, 0x44, 0x6f, 0x63, // SmartDoc
    0x53, 0x65, 0x63, 0x75, 0x72, 0x69, 0x74, 0x79, // Security
    0x32, 0x30, 0x32, 0x36, 0x5f, 0x41, 0x49, 0x5f, // 2026_AI_
    0x4b, 0x65, 0x79, 0x53, 0x74, 0x6f, 0x72, 0x65  // KeyStore
  ];

  /// Masks an API key for safe display in UI and prevents leakage in logs.
  /// Example: "sk-proj-1234567890abcdef" -> "sk-proj-...cdef"
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

  /// Encrypts a plain-text API key using multi-byte XOR stream cipher and Base64 encoding.
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final plainBytes = utf8.encode(plainText);
    final encryptedBytes = List<int>.generate(plainBytes.length, (i) {
      return plainBytes[i] ^ _cipherKey[i % _cipherKey.length];
    });
    return '$_encPrefix${base64.encode(encryptedBytes)}';
  }

  /// Decrypts a cipher-text string back to plain-text.
  /// Supports backward compatibility with unencrypted legacy stored keys.
  static String decrypt(String cipherText) {
    final trimmed = cipherText.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith(_encPrefix)) {
      // Legacy unencrypted plain text
      return trimmed;
    }

    try {
      final base64Data = trimmed.substring(_encPrefix.length);
      final encryptedBytes = base64.decode(base64Data);
      final plainBytes = List<int>.generate(encryptedBytes.length, (i) {
        return encryptedBytes[i] ^ _cipherKey[i % _cipherKey.length];
      });
      return utf8.decode(plainBytes);
    } catch (_) {
      // Return empty if decryption fails (e.g. corrupted data)
      return '';
    }
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
    await prefs.remove(AppConstants.prefDeepSeekApiKey);
    await prefs.remove(AppConstants.prefOpenAiApiKey);
    await prefs.remove(AppConstants.prefClaudeApiKey);
    await prefs.remove(AppConstants.prefGoogleApiKey);
  }
}
