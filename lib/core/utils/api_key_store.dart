import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_doc_search/core/utils/security_util.dart';

/// Cross-platform encrypted storage for AI provider API keys.
///
/// SharedPreferences is still written as a best-effort mirror, but the
/// authoritative copy lives in a JSON file inside the application documents
/// directory (SmartDocSearch/secure/api_keys.json), which is the
/// same root the SQLite database uses.
///
/// This makes keys survive restarts on Windows 11 even when the platform
/// preference store is not writable for the running executable — the previous
/// cause of API keys having to be re-typed on every launch.
class ApiKeyStore {
  ApiKeyStore._();

  static final ApiKeyStore instance = ApiKeyStore._();

  static const String _dirName = 'SmartDocSearch';
  static const String _subDir = 'secure';
  static const String _fileName = 'api_keys.json';

  Map<String, String>? _cache;

  Future<File> _resolveFile() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _dirName, _subDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final data = <String, String>{};
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              if (value is String) data[key.toString()] = value;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('ApiKeyStore: failed to read keystore: $e');
    }
    _cache = data;
    return data;
  }

  Future<void> _persist(Map<String, String> data) async {
    final file = await _resolveFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(data), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
    _cache = Map<String, String>.from(data);
  }

  /// Reads and decrypts a stored API key. Falls back to the SharedPreferences
  /// copy (and migrates it into the keystore) for values written by older builds.
  Future<String> read(String prefKey) async {
    final data = await _load();
    final stored = data[prefKey];
    if (stored != null && stored.isNotEmpty) {
      final decrypted = SecurityUtil.decrypt(stored);
      if (decrypted.isNotEmpty) return decrypted;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = SecurityUtil.getDecryptedKey(prefs, prefKey);
      if (legacy.isNotEmpty) {
        await write(prefKey, legacy);
        return legacy;
      }
    } catch (e) {
      debugPrint('ApiKeyStore: preference fallback failed: $e');
    }
    return '';
  }

  /// Encrypts and stores an API key. Returns true when the encrypted keystore
  /// file was written successfully (SharedPreferences is best effort only).
  Future<bool> write(String prefKey, String plainTextKey) async {
    final trimmed = plainTextKey.trim();
    final data = Map<String, String>.from(await _load());
    if (trimmed.isEmpty) {
      data.remove(prefKey);
    } else {
      data[prefKey] = SecurityUtil.encrypt(trimmed);
    }

    var persisted = false;
    try {
      await _persist(data);
      persisted = true;
    } catch (e) {
      debugPrint('ApiKeyStore: failed to write keystore: $e');
      _cache = data;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(prefKey);
      } else {
        await SecurityUtil.saveEncryptedKey(prefs, prefKey, trimmed);
      }
    } catch (_) {}

    return persisted;
  }

  /// Removes the given API keys from both the keystore and SharedPreferences.
  Future<void> clearAll(List<String> prefKeys) async {
    final data = Map<String, String>.from(await _load());
    for (final key in prefKeys) {
      data.remove(key);
    }
    try {
      await _persist(data);
    } catch (e) {
      debugPrint('ApiKeyStore: failed to clear keystore: $e');
      _cache = data;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
