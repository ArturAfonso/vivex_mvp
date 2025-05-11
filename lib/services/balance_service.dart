import '../models/bitcoin_wallet.dart';
import '../services/blockchain_service.dart';

class BalanceService {
  // Armazena o saldo para cada carteira (ID da carteira -> saldo em BTC)
  final Map<String?, double> _walletBalances = {};
  
  // Armazena a cotação BTC/BRL
  double _btcToBrlRate = 350000.0;
  
  // Dependência do BlockchainService
  final BlockchainService _blockchainService;
  
  // Construtor que recebe a dependência
  BalanceService(this._blockchainService);
  
  // Métodos getter para obter os valores armazenados
  double getBalance(String? walletId) {
    return _walletBalances[walletId] ?? 0.0;
  }
  
  double getBtcToBrlRate() {
    return _btcToBrlRate;
  }
  
  // Método para atualizar o saldo de uma carteira específica
  Future<double> updateWalletBalance(BitcoinWallet wallet) async {
    try {
      // Consulta o saldo usando a biblioteca BDK
      final balance = await _blockchainService.getWalletBalanceFromWallet(wallet);
      
      // Armazena o saldo no mapa
      _walletBalances[wallet.id] = balance;
      
      return balance;
    } catch (e) {
      print('Erro ao atualizar saldo no BalanceService: $e');
      // Retorna o saldo atual se houver erro
      return _walletBalances[wallet.id] ?? 0.0;
    }
  }
  
  // Método para atualizar a cotação BTC/BRL
  Future<double> updateExchangeRate() async {
    try {
      final rate = await _blockchainService.getBtcToBrlRate();
      if (rate > 0) {
        _btcToBrlRate = rate;
      }
      return _btcToBrlRate;
    } catch (e) {
      print('Erro ao atualizar cotação no BalanceService: $e');
      return _btcToBrlRate;
    }
  }
  
  // Método para atualizar tanto o saldo quanto a cotação
  Future<void> updateBalanceAndRate(BitcoinWallet wallet) async {
    await Future.wait([
      updateWalletBalance(wallet),
      updateExchangeRate(),
    ]);
  }
}