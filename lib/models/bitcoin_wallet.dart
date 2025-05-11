import 'dart:convert';
import 'package:bdk_flutter/bdk_flutter.dart';

/// Modelo que representa uma carteira Bitcoin completa
class BitcoinWallet {
  final String? id; // ID único da carteira para armazenamento local
  final String name; // Nome personalizado da carteira
  final String mnemonic; // Frase mnemônica (palavras-semente)
  final String derivationPath; // Caminho de derivação (ex: m/84'/1'/0')
  final String walletType; // Tipo de carteira (ex: Native SegWit)
  final String masterPublicKey; // Chave pública mestra (xpub)
  final List<String> addresses; // Lista de endereços de recebimento
  final bool hasPassphrase; // Indica se a carteira usa uma frase de extensão
  final String? passphrase; // Frase de extensão (opcional)
  final DateTime createdAt; // Data de criação
  final Network networkType; // Indica se é testnet ou mainnet

  BitcoinWallet({
    this.id,
    required this.name,
    required this.mnemonic,
    required this.derivationPath,
    required this.walletType,
    required this.masterPublicKey,
    required this.addresses,
    this.hasPassphrase = false,
    this.passphrase,
    DateTime? createdAt,
    this.networkType = Network.testnet, // Valor padrão como testnet
  }) : createdAt = createdAt ?? DateTime.now();

  /// Converte a carteira para um Map (para serialização)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mnemonic': mnemonic,
      'derivationPath': derivationPath,
      'walletType': walletType,
      'masterPublicKey': masterPublicKey,
      'addresses': addresses,
      'hasPassphrase': hasPassphrase,
      'passphrase': passphrase,
      'createdAt': createdAt.toIso8601String(),
      'networkType': networkType.name, // Convertendo enum para string
    };
  }

  /// Cria uma carteira a partir de um Map (desserialização)
  factory BitcoinWallet.fromJson(Map<String, dynamic> json) {
    // Conversão segura do campo networkType
    Network network;
    try {
      network = json['networkType'] == 'bitcoin' 
          ? Network.bitcoin 
          : Network.testnet;
    } catch (_) {
      network = Network.testnet; // Default para testnet se não estiver presente
    }
    
    return BitcoinWallet(
      id: json['id'] as String?,
      name: json['name'] as String,
      mnemonic: json['mnemonic'] as String,
      derivationPath: json['derivationPath'] as String,
      walletType: json['walletType'] as String,
      masterPublicKey: json['masterPublicKey'] as String,
      addresses: List<String>.from(json['addresses']),
      hasPassphrase: json['hasPassphrase'] as bool,
      passphrase: json['passphrase'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      networkType: network,
    );
  }

  /// Serializa a carteira para uma string JSON
  String serialize() {
    return jsonEncode(toJson());
  }

  /// Desserializa uma string JSON para um objeto BitcoinWallet
  static BitcoinWallet deserialize(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return BitcoinWallet.fromJson(json);
  }

  /// Cria uma cópia da carteira com campos atualizados
  BitcoinWallet copyWith({
    String? id,
    String? name,
    String? mnemonic,
    String? derivationPath,
    String? walletType,
    String? masterPublicKey,
    List<String>? addresses,
    bool? hasPassphrase,
    String? passphrase,
    DateTime? createdAt,
    Network? networkType,
  }) {
    return BitcoinWallet(
      id: id ?? this.id,
      name: name ?? this.name,
      mnemonic: mnemonic ?? this.mnemonic,
      derivationPath: derivationPath ?? this.derivationPath,
      walletType: walletType ?? this.walletType,
      masterPublicKey: masterPublicKey ?? this.masterPublicKey,
      addresses: addresses ?? this.addresses,
      hasPassphrase: hasPassphrase ?? this.hasPassphrase,
      passphrase: passphrase ?? this.passphrase,
      createdAt: createdAt ?? this.createdAt,
      networkType: networkType ?? this.networkType,
    );
  }

  /// Implementação do operador de igualdade para comparar carteiras
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BitcoinWallet &&
        other.id == id &&
        other.name == name &&
        other.mnemonic == mnemonic &&
        other.derivationPath == derivationPath &&
        other.walletType == walletType &&
        other.networkType == networkType &&
        other.masterPublicKey == masterPublicKey;
  }

  /// Implementação do hashCode para complementar o operador de igualdade
  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        mnemonic.hashCode ^
        derivationPath.hashCode ^
        walletType.hashCode ^
        networkType.hashCode ^
        masterPublicKey.hashCode;
  }
}
