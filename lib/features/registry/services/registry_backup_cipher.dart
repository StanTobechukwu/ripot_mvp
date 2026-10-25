import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../logbook/domain/logbook_models.dart' show object, textValue;

class RegistryBackupCipher {
  static const maxBytes = 40 * 1024 * 1024;
  static const iterations = 600000;
  static const _header =
      'Ripot Registry Backup v1|AES-256-GCM|PBKDF2-HMAC-SHA256|600000';
  static List<int> _random(int count) {
    final r = Random.secure();
    return List.generate(count, (_) => r.nextInt(256));
  }

  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<Uint8List> encrypt(
    Map<String, dynamic> snapshot,
    String password,
  ) => compute(_encrypt, (jsonEncode(snapshot), password));
  static Future<Uint8List> _encrypt((String, String) input) async {
    if (input.$2.length < 12 || input.$2.length > 1024) {
      throw const FormatException('Use a passphrase of 12 to 1024 characters');
    }
    final clear = utf8.encode(input.$1);
    if (clear.length > 28 * 1024 * 1024) {
      throw const FormatException(
        'Registry exceeds the 28 MB backup content limit',
      );
    }
    final salt = _random(16);
    final nonce = _random(12);
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: await _key(input.$2, salt),
      nonce: nonce,
      aad: utf8.encode(_header),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'ripot-registry-encrypted',
          'version': 1,
          'algorithm': 'AES-256-GCM',
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
  }

  static Future<Map<String, dynamic>> decrypt(
    Uint8List bytes,
    String password,
  ) async {
    if (bytes.length > maxBytes || bytes.isEmpty) {
      throw const FormatException('Invalid backup size');
    }
    final raw = await compute(_decrypt, (bytes, password));
    return object(jsonDecode(raw));
  }

  static Future<String> _decrypt((Uint8List, String) input) async {
    if (input.$2.isEmpty || input.$2.length > 1024) {
      throw const FormatException('Invalid passphrase');
    }
    final j = object(jsonDecode(utf8.decode(input.$1)));
    if (j['format'] != 'ripot-registry-encrypted' ||
        j['version'] != 1 ||
        j['algorithm'] != 'AES-256-GCM' ||
        j['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        j['iterations'] != iterations) {
      throw const FormatException('Unsupported encrypted backup');
    }
    final salt = base64Decode(textValue(j, 'salt', max: 32));
    final nonce = base64Decode(textValue(j, 'nonce', max: 24));
    final mac = base64Decode(textValue(j, 'mac', max: 32));
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid encryption header');
    }
    final encrypted = base64Decode(textValue(j, 'ciphertext', max: maxBytes));
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(encrypted, nonce: nonce, mac: Mac(mac)),
      secretKey: await _key(input.$2, salt),
      aad: utf8.encode(_header),
    );
    return utf8.decode(clear);
  }
}
