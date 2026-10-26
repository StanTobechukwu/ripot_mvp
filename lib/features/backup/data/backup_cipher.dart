import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class BackupCipher {
  static const maxClearBytes = 128 * 1024 * 1024;
  static const maxBytes = 180 * 1024 * 1024;
  static const iterations = 600000;
  static const header = 'Ripot Backup v1|AES-256-GCM|PBKDF2-HMAC-SHA256|600000';
  static List<int> random(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(256));
  }

  static Future<SecretKey> key(String pass, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);
  static Future<Uint8List> encrypt(Map<String, dynamic> data, String pass) =>
      compute(_encrypt, (jsonEncode(data), pass));
  static Future<Uint8List> _encrypt((String, String) args) async {
    if (args.$2.length < 12 || args.$2.length > 1024) {
      throw const FormatException('Use a passphrase of 12 to 1024 characters.');
    }
    final clear = utf8.encode(args.$1);
    if (clear.length > maxClearBytes) {
      throw const FormatException(
        'Backup exceeds the 128 MB content limit. Back up individual sections instead.',
      );
    }
    final salt = random(16), nonce = random(12);
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: await key(args.$2, salt),
      nonce: nonce,
      aad: utf8.encode(header),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'ripot-backup-encrypted',
          'version': 1,
          'algorithm': 'AES-256-GCM',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'mac': base64Encode(box.mac.bytes),
          'ciphertext': base64Encode(box.cipherText),
        }),
      ),
    );
  }

  static Future<Map<String, dynamic>> decrypt(
    Uint8List bytes,
    String pass,
  ) async {
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        pass.isEmpty ||
        pass.length > 1024) {
      throw const FormatException('Invalid backup size or passphrase.');
    }
    return jsonDecode(await compute(_decrypt, (bytes, pass)))
        as Map<String, dynamic>;
  }

  static Future<String> _decrypt((Uint8List, String) args) async {
    final j = jsonDecode(utf8.decode(args.$1)) as Map<String, dynamic>;
    if (j['format'] != 'ripot-backup-encrypted' ||
        j['version'] != 1 ||
        j['algorithm'] != 'AES-256-GCM' ||
        j['iterations'] != iterations) {
      throw const FormatException('Unsupported backup format.');
    }
    final salt = base64Decode(j['salt'] as String),
        nonce = base64Decode(j['nonce'] as String),
        mac = base64Decode(j['mac'] as String),
        bytes = base64Decode(j['ciphertext'] as String);
    if (salt.length != 16 ||
        nonce.length != 12 ||
        mac.length != 16 ||
        bytes.length > maxClearBytes) {
      throw const FormatException('Invalid encrypted backup.');
    }
    return utf8.decode(
      await AesGcm.with256bits().decrypt(
        SecretBox(bytes, nonce: nonce, mac: Mac(mac)),
        secretKey: await key(args.$2, salt),
        aad: utf8.encode(header),
      ),
    );
  }
}
