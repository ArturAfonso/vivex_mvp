// Importe a classe Network do seu arquivo blockchain_service.dart
import 'package:bdk_flutter/bdk_flutter.dart' show Network;
import 'package:shared_preferences/shared_preferences.dart';

// Classe para armazenar configurações globais do aplicativo
class AppConfig {
  // Exemplo de configurações que você pode querer disponibilizar globalmente
  final String environment; // 'development', 'production', etc.
  final bool enableLogging;
  final String apiBaseUrl;
  Network networkType; // Configuração específica da blockchain
  
  // Keys para armazenamento persistente
  static const String _networkTypeKey = 'network_type';
  
  // Você pode adicionar qualquer outra configuração que precise estar disponível globalmente

  AppConfig({
    this.environment = 'development',
    this.enableLogging = true,
    this.apiBaseUrl = 'https://api.example.com',
    this.networkType = Network.testnet,
  });
  
  // Método para carregar configurações salvas
  Future<void> loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Carregar o tipo de rede salvo (ou manter o padrão se não existir)
      final savedNetworkType = prefs.getString(_networkTypeKey);
      if (savedNetworkType != null) {
        // Converter a string salva para o enum Network
        if (savedNetworkType == 'bitcoin') {
          networkType = Network.bitcoin;
        } else {
          networkType = Network.testnet;
        }
        print('Configuração de rede carregada: $savedNetworkType');
      } else {
        print('Nenhuma configuração de rede salva, usando padrão: testnet');
      }
    } catch (e) {
      print('Erro ao carregar configurações: $e');
      // Em caso de erro, manter as configurações padrão
    }
  }
  
  // Método para salvar as configurações atuais
  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Salvar o tipo de rede atual
      await prefs.setString(_networkTypeKey, networkType.name);
      print('Configuração de rede salva: ${networkType.name}');
    } catch (e) {
      print('Erro ao salvar configurações: $e');
    }
  }
  
  // Método para alterar e salvar a configuração de rede
  Future<void> setNetwork(Network network) async {
    networkType = network;
    await saveSettings(); // Salvar a alteração imediatamente
  }
}

