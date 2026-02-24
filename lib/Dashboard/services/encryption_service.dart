import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Provides AES encryption and decryption utilities for secure text storage.
///
/// Uses:
/// • AES encryption algorithm
/// • CBC mode
/// • PKCS7 padding
/// • Base64 encoding for transport and storage
///
/// Notes:
/// • A fixed 32-byte key is used for encryption and decryption.
/// • Initialization Vector (IV) is generated with fixed length (16 bytes).
/// • Encrypted output contains IV + encrypted data encoded in Base64.
class EncryptionService {

  /// Secret key used for AES encryption.
  ///
  /// Must be 32 bytes for AES-256 encryption.
  /// In production, store keys securely using secure storage or environment variables.
  static const _keyString = "my32lengthsupersecretnooneknows!";

  /// Encrypts plain text using AES encryption.
  ///
  /// Process:
  /// • Generates AES key from predefined secret string
  /// • Creates initialization vector (IV)
  /// • Encrypts text using AES CBC mode with PKCS7 padding
  /// • Prepends IV to encrypted bytes
  /// • Returns Base64 encoded encrypted string
  ///
  /// [text] Plain text string to encrypt.
  ///
  /// Returns:
  /// • Base64 encoded encrypted string containing IV + encrypted data.
  String encryptText(String text) {
    final key = encrypt.Key.fromUtf8(_keyString);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );
    final encrypted = encrypter.encrypt(text, iv: iv);
    return base64.encode(iv.bytes + encrypted.bytes);
  }

  /// Decrypts Base64 encoded encrypted text back to plain text.
  ///
  /// Process:
  /// • Decodes Base64 input
  /// • Extracts IV from first 16 bytes
  /// • Extracts encrypted payload
  /// • Decrypts using AES CBC mode with PKCS7 padding
  ///
  /// [base64Text] Base64 encoded string containing IV + encrypted data.
  ///
  /// Returns:
  /// • Decrypted plain text string.
  String decryptText(String base64Text) {
    final fullBytes = base64.decode(base64Text);
    final ivBytes = fullBytes.sublist(0, 16);
    final encryptedBytes = fullBytes.sublist(16);
    final key = encrypt.Key.fromUtf8(_keyString);
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );
    return encrypter.decrypt(encrypt.Encrypted(encryptedBytes), iv: iv);
  }
}