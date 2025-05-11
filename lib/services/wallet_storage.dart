import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/bitcoin_wallet.dart';

/// Serviço para armazenamento seguro de carteiras Bitcoin
class WalletStorage {
  static const String _walletIdsKey = 'wallet_ids';
  static const String _walletPrefix = 'wallet_';
  static const String _encryptionKeyKey = 'encryption_key';
  static const String _primaryWalletKey = 'primary_wallet_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  /// Gera uma chave de criptografia exclusiva para o dispositivo
  Future<String> _getOrCreateEncryptionKey() async {
    // Tenta recuperar a chave existente
    String? encryptionKey = await _secureStorage.read(key: _encryptionKeyKey);

    // Se não existir uma chave, cria uma nova
    if (encryptionKey == null) {
      // Gera uma chave aleatória de 32 bytes (256 bits)
      final key = encrypt.Key.fromSecureRandom(32);
      encryptionKey = base64Encode(key.bytes);

      // Armazena a chave no armazenamento seguro
      await _secureStorage.write(key: _encryptionKeyKey, value: encryptionKey);
    }

    return encryptionKey;
  }

  /// Criptografa os dados da carteira
  Future<String> _encryptData(String data) async {
    final encryptionKey = await _getOrCreateEncryptionKey();
    final key = encrypt.Key.fromBase64(encryptionKey);
    final iv = encrypt.IV.fromSecureRandom(16); // 16 bytes para AES

    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(data, iv: iv);

    // Combina o IV e os dados criptografados em um único string
    return json.encode({'iv': iv.base64, 'data': encrypted.base64});
  }

  /// Descriptografa os dados da carteira
  Future<String> _decryptData(String encryptedData) async {
    final encryptionKey = await _getOrCreateEncryptionKey();
    final key = encrypt.Key.fromBase64(encryptionKey);

    final data = json.decode(encryptedData);
    final iv = encrypt.IV.fromBase64(data['iv']);
    final encrypted = encrypt.Encrypted.fromBase64(data['data']);

    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// Salva uma carteira Bitcoin no armazenamento seguro
  Future<String> saveWallet(BitcoinWallet wallet) async {
    // Gera um ID único para a carteira
    final walletId = wallet.id ?? _uuid.v4();

    // Cria uma cópia da carteira com o ID atualizado
    final walletWithId = wallet.copyWith(id: walletId);

    // Serializa e criptografa os dados da carteira
    final serializedWallet = walletWithId.serialize();
    final encryptedWallet = await _encryptData(serializedWallet);

    // Salva a carteira criptografada no armazenamento seguro
    await _secureStorage.write(key: '$_walletPrefix$walletId', value: encryptedWallet);

    // Recupera a lista de IDs de carteiras existentes
    final prefs = await SharedPreferences.getInstance();
    final walletIds = prefs.getStringList(_walletIdsKey) ?? [];

    // Adiciona o novo ID à lista se ele ainda não existir
    if (!walletIds.contains(walletId)) {
      walletIds.add(walletId);
      await prefs.setStringList(_walletIdsKey, walletIds);
    }

    return walletId;
  }

  /// Carrega uma carteira específica pelo ID
  Future<BitcoinWallet?> loadWallet(String walletId) async {
    // Recupera os dados criptografados do armazenamento seguro
    final encryptedWallet = await _secureStorage.read(key: '$_walletPrefix$walletId');

    if (encryptedWallet == null) {
      return null;
    }

    // Descriptografa os dados da carteira
    final serializedWallet = await _decryptData(encryptedWallet);

    // Desserializa os dados em um objeto BitcoinWallet
    return BitcoinWallet.deserialize(serializedWallet);
  }

  /// Carrega todas as carteiras salvas
  Future<List<BitcoinWallet>> loadAllWallets() async {
    final prefs = await SharedPreferences.getInstance();
    final walletIds = prefs.getStringList(_walletIdsKey) ?? [];

    final wallets = <BitcoinWallet>[];

    for (final id in walletIds) {
      final wallet = await loadWallet(id);
      if (wallet != null) {
        wallets.add(wallet);
      }
    }

    return wallets;
  }

  /// Exclui uma carteira especifica
  Future<bool> deleteWallet(String walletId) async {
    // Recupera a lista de IDs de carteiras existentes
    final prefs = await SharedPreferences.getInstance();
    final walletIds = prefs.getStringList(_walletIdsKey) ?? [];

    // Remove o ID da lista
    if (!walletIds.contains(walletId)) {
      return false;
    }

    walletIds.remove(walletId);
    await prefs.setStringList(_walletIdsKey, walletIds);

    // Remove a carteira do armazenamento seguro
    await _secureStorage.delete(key: '$_walletPrefix$walletId');

    return true;
  }

  /// Verifica se uma carteira com determinado ID existe
  Future<bool> walletExists(String walletId) async {
    final encryptedWallet = await _secureStorage.read(key: '$_walletPrefix$walletId');
    return encryptedWallet != null;
  }

  /// Define uma carteira como a carteira primária
  Future<void> setPrimaryWallet(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryWalletKey, walletId);
  }

  /// Obtém o ID da carteira primária
  Future<String?> getPrimaryWalletId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_primaryWalletKey);
  }

  /// Obtém a carteira primária
  Future<BitcoinWallet?> getPrimaryWallet() async {
    final primaryWalletId = await getPrimaryWalletId();
    if (primaryWalletId == null) return null;

    return loadWallet(primaryWalletId);
  }

  /// Define automaticamente a primeira carteira como primária se nenhuma estiver definida
  Future<void> setupDefaultPrimaryWallet() async {
    final primaryWalletId = await getPrimaryWalletId();

    // Se já existe uma carteira primária, verifica se ela ainda existe
    if (primaryWalletId != null) {
      final exists = await walletExists(primaryWalletId);
      if (exists) return; // A carteira primária já existe, não precisa fazer nada
    }

    // Obtém todas as carteiras e define a primeira como primária, se houver
    final prefs = await SharedPreferences.getInstance();
    final walletIds = prefs.getStringList(_walletIdsKey) ?? [];

    if (walletIds.isNotEmpty) {
      await setPrimaryWallet(walletIds.first);
    }
  }
}
