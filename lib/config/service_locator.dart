import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:get_it/get_it.dart';
import 'app_config.dart';
import '../services/blockchain_service.dart';
import '../services/balance_service.dart';

// Instância global do GetIt
final GetIt locator = GetIt.instance;

// Função para configurar a injeção de dependências
void setupLocator() {
  // Registrar AppConfig como singleton
  locator.registerSingleton<AppConfig>(AppConfig(
    environment: 'development',
    enableLogging: true,
    networkType: Network.testnet,
  ));
  
  // Registrar o BlockchainService
  locator.registerLazySingleton<BlockchainService>(() => BlockchainService());
  
  // Registrar o BalanceService, que depende do BlockchainService
  locator.registerLazySingleton<BalanceService>(
    () => BalanceService(locator<BlockchainService>())
  );
}

// Carregar configurações salvas após a inicialização do service locator
Future<void> loadSavedConfigurations() async {
  // Carregar configurações salvas como configuração de rede
  await appConfig.loadSavedSettings();
}

// Função de utilidade para acessar o AppConfig facilmente
AppConfig get appConfig => locator<AppConfig>();

// Função de utilidade para acessar o BlockchainService facilmente
BlockchainService get blockchainService => locator<BlockchainService>();

// Função de utilidade para acessar o BalanceService facilmente
BalanceService get balanceService => locator<BalanceService>();