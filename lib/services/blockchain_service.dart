import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bdk_flutter/bdk_flutter.dart';
import '../models/bitcoin_wallet.dart';
import '../config/service_locator.dart';
import '../config/app_config.dart';

class BlockchainService {
  // URLs da API para cotação (ainda precisamos disso para conversão BTC->BRL)
  final String _btcToBrlApiUrl = 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=brl';

  // Configuração da blockchain Bitcoin
  Network get _network => appConfig.networkType; // Agora obtemos da configuração global
  
  // Usamos um getter para o blockchainConfig para que ele use o _network atualizado
  BlockchainConfig get _blockchainConfig => BlockchainConfig.electrum(
    config: ElectrumConfig(
      stopGap: BigInt.from(10),
      timeout: 5,
      retry: 5,
      url: _network == Network.testnet 
          ? 'ssl://electrum.blockstream.info:60002'  // Servidor para testnet
          : 'ssl://electrum.blockstream.info:50002', // Servidor para mainnet
      validateDomain: false,
    ),
  );

  // Método para obter o saldo de uma carteira a partir de seus endereços
  // Esta versão aceita apenas lista de endereços para manter compatibilidade
  Future<double> getWalletBalance(List<String> addresses) async {
    if (addresses.isEmpty) {
      return 0.0;
    }

    try {
      // Usa o novo método robusto de múltiplas APIs
      return await _getBalanceFromMultipleApis(addresses);
    } catch (e) {
      print('Erro ao consultar saldo via API: $e');
      return 0.0;
    }
  }

  // Método para obter saldo usando o objeto BitcoinWallet completo
  // Este método usa a abordagem recomendada pelos fóruns do BDK
  Future<double> getWalletBalanceFromWallet(BitcoinWallet wallet) async {
  // Obtem saldo usando o objeto BitcoinWallet completo
 
    try {
      // Se não temos a frase mnemônica, tentamos usar APIs como fallback
      if (wallet.mnemonic.isEmpty) {
        print('Frase mnemônica não encontrada, usando APIs como fallback');
        return await _getBalanceFromMultipleApis(wallet.addresses);
      }

      print('Tentando obter saldo com mnemônica diretamente');

      try {
        // 1. Criar uma frase mnemônica a partir da string existente
        final mnemonic = await Mnemonic.fromString(wallet.mnemonic);

        // 2. Criar chave secreta usando a mnemônica
        final descriptorSecretKey = await DescriptorSecretKey.create(
          network: _network,
          mnemonic: mnemonic,
          password: wallet.hasPassphrase && wallet.passphrase != null ? wallet.passphrase : '',
        );

        // 3. Determinar o tipo de carteira e criar os descritores apropriados
        Descriptor descriptor;
        Descriptor changeDescriptor;
        print('walletType: ${wallet.walletType.toString()}');

        switch (wallet.walletType.toLowerCase()) {
          case 'native segwit':
            // BIP84 (Native SegWit)
            descriptor = await Descriptor.newBip84(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.externalChain,
            );
            changeDescriptor = await Descriptor.newBip84(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.internalChain,
            );
            break;

          case 'segwit':
            // BIP49 (SegWit)
            descriptor = await Descriptor.newBip49(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.externalChain,
            );
            changeDescriptor = await Descriptor.newBip49(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.internalChain,
            );
            break;

          case 'legacy':
            // BIP44 (Legacy)
            descriptor = await Descriptor.newBip44(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.externalChain,
            );
            changeDescriptor = await Descriptor.newBip44(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.internalChain,
            );
            break;

          default:
            // Por padrão, assumimos BIP84 (Native SegWit)
            descriptor = await Descriptor.newBip84(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.externalChain,
            );
            changeDescriptor = await Descriptor.newBip84(
              secretKey: descriptorSecretKey,
              network: _network,
              keychain: KeychainKind.internalChain,
            );
        }

        // 4. Inicializar a carteira BDK
        print('Criando objeto de carteira BDK');
        final bdkWallet = await Wallet.create(
          descriptor: descriptor,
          changeDescriptor: changeDescriptor,
          network: _network,
          databaseConfig: const DatabaseConfig.memory(),
        );

        // 5. Configurar a conexão com um nó blockchain (Esplora)
        print('Criando conexão com blockchain');
        final blockchain = await Blockchain.create(
          config: BlockchainConfig.esplora(
            config: EsploraConfig(
              baseUrl: _network == Network.testnet ? 'https://mempool.space/testnet/api' : 'https://mempool.space/api',
              stopGap: BigInt.from(10),
            ),
          ),
        );

        // 6. Sincronizar a carteira com a blockchain
        print('Sincronizando carteira com a blockchain');
        await bdkWallet.sync(blockchain: blockchain);

        // 7. Obter o saldo
        print('Consultando saldo');
        final balance = bdkWallet.getBalance();

        // 8. Converter de satoshis para BTC
        final btcBalance = balance.total / BigInt.from(100000000);

        print('Saldo obtido via BDK: $btcBalance BTC');
        return btcBalance.toDouble();
      } catch (bdkError) {
        print('Erro ao usar a abordagem BDK com mnemônica: $bdkError');
        // Se falhar na criação da carteira via BDK, tenta o método alternativo
        return await _getBalanceFromMultipleApis(wallet.addresses);
      }
    } catch (e) {
      print('Erro ao consultar saldo via BDK: $e');
      // Se falhar usando BDK, tenta o método de API como backup
      return await _getBalanceFromMultipleApis(wallet.addresses);
    }
  }

  // Método de backup que usa APIs externas caso o BDK falhe
  Future<double> _getBalanceFromApiBackup(List<String> addresses) async {
    try {
      // Constrói a URL com todos os endereços concatenados
      final String addressesString = addresses.join('|');
      final response = await http.get(Uri.parse('https://blockchain.info/balance?active=$addressesString'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Soma o saldo de todos os endereços
        double totalBalanceSatoshi = 0;
        for (var address in addresses) {
          if (data.containsKey(address)) {
            // O saldo é retornado em satoshis
            totalBalanceSatoshi += (data[address]['final_balance'] as num).toDouble();
          }
        }

        // Converte de satoshis para BTC
        return totalBalanceSatoshi / 100000000;
      } else {
        throw Exception('Falha ao consultar saldo: ${response.statusCode}');
      }
    } catch (e) {
      print('Erro ao consultar saldo via API de backup: $e');
      throw Exception('Não foi possível obter o saldo. Verifique sua conexão.');
    }
  }

  // Método de backup aprimorado que tenta várias APIs para maior confiabilidade
  // Temporariamente comentado para forçar o uso apenas da API bdk_flutter
  Future<double> _getBalanceFromMultipleApis(List<String> addresses) async {
    // MÉTODO DESATIVADO PARA TESTES DE PERFORMANCE DA API BDK_FLUTTER
    // Retorna zero para forçar o fallback para o método BDK quando possível
    return 0.0;

    /*
    if (addresses.isEmpty) {
      return 0.0;
    }

    List<String> errors = [];

    // Tentativa 1: Blockchain.info
    try {
      final String addressesString = addresses.join('|');
      final response = await http.get(Uri.parse('https://blockchain.info/balance?active=$addressesString'),
          headers: {'User-Agent': 'VivexWallet/1.0'});

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        double totalBalanceSatoshi = 0;
        for (var address in addresses) {
          if (data.containsKey(address)) {
            totalBalanceSatoshi += (data[address]['final_balance'] as num).toDouble();
          }
        }

        return totalBalanceSatoshi / 100000000;
      } else {
        errors.add('Blockchain.info API falhou: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Erro ao consultar Blockchain.info: $e');
    }

    // Tentativa 2: BlockCypher
    try {
      double totalBalance = 0.0;
      final String network = _network == Network.bitcoin ? 'main' : 'test3';

      for (var address in addresses) {
        final response = await http.get(Uri.parse('https://api.blockcypher.com/v1/btc/$network/addrs/$address/balance'),
            headers: {'User-Agent': 'VivexWallet/1.0'});

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data.containsKey('balance')) {
            totalBalance += (data['balance'] as num).toDouble() / 100000000;
          }
        }
      }

      if (totalBalance > 0 || addresses.length == 1) {
        return totalBalance;
      } else {
        errors.add('BlockCypher retornou saldo zero para múltiplos endereços');
      }
    } catch (e) {
      errors.add('Erro ao consultar BlockCypher: $e');
    }

    // Tentativa 3: Mempool.space
    try {
      double totalBalance = 0.0;
      final String baseUrl =
          _network == Network.bitcoin ? 'https://mempool.space/api' : 'https://mempool.space/testnet/api';

      for (var address in addresses) {
        final response =
            await http.get(Uri.parse('$baseUrl/address/$address'), headers: {'User-Agent': 'VivexWallet/1.0'});

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data.containsKey('chain_stats') && data['chain_stats'].containsKey('funded_txo_sum')) {
            final funded = (data['chain_stats']['funded_txo_sum'] as num).toDouble();
            final spent = (data['chain_stats']['spent_txo_sum'] as num).toDouble();
            totalBalance += (funded - spent) / 100000000;
          }
        }
      }

      if (totalBalance > 0 || addresses.length == 1) {
        return totalBalance;
      } else {
        errors.add('Mempool.space retornou saldo zero para múltiplos endereços');
      }
    } catch (e) {
      errors.add('Erro ao consultar Mempool.space: $e');
    }

    // Se chegarmos aqui, todas as tentativas falharam
    print('Todas as APIs falharam ao consultar saldo. Erros: ${errors.join(', ')}');

    // Última alternativa: verificar cada endereço individualmente usando qualquer API que funcione
    try {
      double totalBalance = 0.0;
      for (var address in addresses) {
        try {
          // Tenta o BlockCypher para cada endereço individual
          final String network = _network == Network.bitcoin ? 'main' : 'test3';
          final response = await http.get(
              Uri.parse('https://api.blockcypher.com/v1/btc/$network/addrs/$address/balance'),
              headers: {'User-Agent': 'VivexWallet/1.0'});

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data.containsKey('balance')) {
              totalBalance += (data['balance'] as num).toDouble() / 100000000;
              continue; // Se conseguiu, passa para o próximo endereço
            }
          }
        } catch (_) {
          // Ignora e tenta próxima API
        }

        try {
          // Se BlockCypher falhou, tenta Mempool.space
          final String baseUrl =
              _network == Network.bitcoin ? 'https://mempool.space/api' : 'https://mempool.space/testnet/api';
          final response =
              await http.get(Uri.parse('$baseUrl/address/$address'), headers: {'User-Agent': 'VivexWallet/1.0'});

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data.containsKey('chain_stats')) {
              final funded = (data['chain_stats']['funded_txo_sum'] as num).toDouble();
              final spent = (data['chain_stats']['spent_txo_sum'] as num).toDouble();
              totalBalance += (funded - spent) / 100000000;
            }
          }
        } catch (_) {
          // Ignora e continua para o próximo endereço
        }
      }

      return totalBalance;
    } catch (e) {
      // Se tudo falhar, retorna zero
      print('Falha final ao tentar consultar saldo: $e');
      return 0.0;
    }
    */
  }

  // Método para enviar bitcoins usando a BDK
  Future<String> sendBitcoin({
    required BitcoinWallet sourceWallet,
    required String destinationAddress,
    required double amountInBtc,
    String? description,
    double feeRate = 1.0, // satoshis por vbyte
  }) async {
    try {
      if (sourceWallet.mnemonic.isEmpty) {
        throw Exception('Não é possível enviar sem a frase mnemônica da carteira');
      }

      print('Iniciando envio de $amountInBtc BTC para $destinationAddress');
      if (description != null && description.isNotEmpty) {
        print('Descrição da transação: $description');
      }

      // 1. Criar uma frase mnemônica a partir da string existente
      final mnemonic = await Mnemonic.fromString(sourceWallet.mnemonic);

      // 2. Criar chave secreta usando a mnemônica
      final descriptorSecretKey = await DescriptorSecretKey.create(
        network: _network,
        mnemonic: mnemonic,
        password: sourceWallet.hasPassphrase && sourceWallet.passphrase != null ? sourceWallet.passphrase : '',
      );

      // 3. Determinar o tipo de carteira e criar os descritores apropriados
      Descriptor descriptor;
      Descriptor changeDescriptor;

      switch (sourceWallet.walletType.toLowerCase()) {
        case 'native segwit':
          // BIP84 (Native SegWit)
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;

        case 'segwit':
          // BIP49 (SegWit)
          descriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;

        case 'legacy':
          // BIP44 (Legacy)
          descriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;

        default:
          // Por padrão, assumimos BIP84 (Native SegWit)
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
      }

      // 4. Inicializar a carteira BDK
      print('Criando objeto de carteira BDK para transação');
      final bdkWallet = await Wallet.create(
        descriptor: descriptor,
        changeDescriptor: changeDescriptor,
        network: _network,
        databaseConfig: const DatabaseConfig.memory(),
      );

      // 5. Configurar a conexão com a blockchain
      print('Configurando conexão com blockchain');
      final blockchain = await Blockchain.create(
        config: _blockchainConfig,
      );

      // 6. Sincronizar a carteira com a blockchain
      print('Sincronizando carteira com a blockchain');
      await bdkWallet.sync(blockchain: blockchain);

      // 7. Verificar o saldo
      print('Verificando saldo da carteira');
      final balance = bdkWallet.getBalance();
      final amountInSatoshi = BigInt.from(amountInBtc * 100000000); // Converter BTC para satoshis

      if (balance.total < amountInSatoshi) {
        throw Exception(
            'Saldo insuficiente: ${balance.total} satoshis disponíveis, necessário: $amountInSatoshi satoshis');
      }

      // 8. Criar uma transação
      print('Criando transação');
      final txBuilder = TxBuilder();

      // Adicionar o destinatário
      final address = await Address.fromString(s: destinationAddress, network: _network);
      txBuilder.addRecipient(address.scriptPubkey(), amountInSatoshi);

      // Adicionar descrição como um output OP_RETURN se fornecida
      if (description != null && description.isNotEmpty) {
        try {
          final opReturnBytes = utf8.encode(description);
          if (opReturnBytes.length <= 80) { // Limite de 80 bytes para OP_RETURN
            // Usar addData em vez de addOutput para adicionar OP_RETURN
            txBuilder.addData(data: opReturnBytes);
          } else {
            print('Descrição muito longa para OP_RETURN, será ignorada');
          }
        } catch (e) {
          print('Erro ao adicionar descrição como OP_RETURN: $e');
        }
      }

      // Definir a taxa de transação
      txBuilder.feeRate(feeRate);

      // Finalizar a construção da transação
      final psbtResult = await txBuilder.finish(bdkWallet);

      // 9. Assinar a transação
      print('Assinando transação');
      final psbt = psbtResult.$1;
      final signSuccess = await bdkWallet.sign(psbt: psbt);
      if (!signSuccess) {
        throw Exception('Falha ao assinar a transação');
      }

      // 10. Transmitir a transação para a rede
      // A forma correta é usar o método broadcast da classe Blockchain, não da Wallet
      print('Transmitindo transação para a rede');
      final extractedTx = psbt.extractTx(); // Use the PSBT object after signing
      final txid = await blockchain.broadcast(transaction: extractedTx);

      print('Transação enviada com sucesso! ID da transação: $txid');
      return txid;
    } catch (e) {
      print('Erro ao enviar bitcoins: $e');
      throw Exception('Falha ao enviar bitcoins: $e');
    }
  }

  // Método para enviar os bitcoins de volta para um endereço de testes
  Future<String> sendTestnetBitcoinBack({
    required BitcoinWallet sourceWallet,
    required String faucetAddress,
    required double amountInBtc,
  }) async {
    try {
      return await sendBitcoin(
        sourceWallet: sourceWallet,
        destinationAddress: faucetAddress,
        amountInBtc: amountInBtc,
        description: 'Devolução para faucet', // Corrigido de 'memo' para 'description'
        feeRate: 1.0, // Taxa padrão para testnet
      );
    } catch (e) {
      print('Erro ao enviar bitcoins de volta para o faucet: $e');
      throw Exception('Falha ao devolver bitcoins para o faucet: $e');
    }
  }

  // Método para obter a cotação atual de BTC para BRL (mantido como estava)
  Future<double> getBtcToBrlRate() async {
    try {
      final response = await http.get(Uri.parse(_btcToBrlApiUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Extrai a taxa BTC/BRL dos dados
        if (data.containsKey('bitcoin') && data['bitcoin'].containsKey('brl')) {
          return (data['bitcoin']['brl'] as num).toDouble();
        } else {
          throw Exception('Formato de resposta inválido');
        }
      } else {
        throw Exception('Falha ao consultar cotação: ${response.statusCode}');
      }
    } catch (e) {
      // Se falhar, usa uma API alternativa
      return await _getRateFromBackupProvider();
    }
  }

  // Método de backup para consultar a cotação caso a primeira API falhe (mantido como estava)
  Future<double> _getRateFromBackupProvider() async {
    try {
      // API alternativa para consultar a cotação
      final response = await http.get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.containsKey('price')) {
          return double.parse(data['price']);
        }
      }

      // Se ainda falhar, tenta uma terceira API
      final mercadoBitcoinResponse = await http.get(Uri.parse('https://www.mercadobitcoin.net/api/BTC/ticker/'));
      if (mercadoBitcoinResponse.statusCode == 200) {
        final data = json.decode(mercadoBitcoinResponse.body);
        if (data.containsKey('ticker') && data['ticker'].containsKey('last')) {
          return double.parse(data['ticker']['last']);
        }
      }

      // Se todas as tentativas falharem, retorna uma taxa padrão
      return 350000.0; // Taxa fixa caso todas as APIs falhem
    } catch (e) {
      print('Erro ao consultar cotação via API de backup: $e');
      return 350000.0; // Taxa fixa caso todas as APIs falhem
    }
  }

  // Método para obter a taxa de câmbio específica para uma moeda fiat
  Future<double> getExchangeRate(String fiatCurrency) async {
    if (fiatCurrency.toUpperCase() == 'BRL') {
      return await getBtcToBrlRate();
    } else {
      // Para outras moedas, implementar chamadas a APIs que suportem essas moedas
      throw Exception('Moeda $fiatCurrency não suportada');
    }
  }

  // Método para obter o saldo disponível de uma carteira
  Future<double> getAvailableBalance(BitcoinWallet wallet) async {
    try {
      return await getWalletBalanceFromWallet(wallet);
    } catch (e) {
      print('Erro ao obter saldo disponível: $e');
      return 0.0;
    }
  }

  // Método para estimar a taxa de transação
  Future<double> estimateTransactionFee({
    required BitcoinWallet sourceWallet,
    required String destinationAddress,
    required double amountInBtc,
  }) async {
    try {
      // Se a carteira não tem mnemônica, retornamos uma estimativa fixa
      if (sourceWallet.mnemonic.isEmpty) {
        return 0.0001; // Taxa fixa estimada de 0.0001 BTC (10000 satoshis)
      }

      // 1. Criar uma frase mnemônica a partir da string existente
      final mnemonic = await Mnemonic.fromString(sourceWallet.mnemonic);

      // 2. Criar chave secreta usando a mnemônica
      final descriptorSecretKey = await DescriptorSecretKey.create(
        network: _network,
        mnemonic: mnemonic,
        password: sourceWallet.hasPassphrase && sourceWallet.passphrase != null ? sourceWallet.passphrase : '',
      );

      // 3. Determinar o tipo de carteira e criar os descritores apropriados
      Descriptor descriptor;
      Descriptor changeDescriptor;

      switch (sourceWallet.walletType.toLowerCase()) {
        case 'native segwit':
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey, 
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;
        case 'segwit':
          descriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;
        case 'legacy':
          descriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
          break;
        default:
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: _network,
            keychain: KeychainKind.internalChain,
          );
      }

      // 4. Inicializar a carteira BDK
      final bdkWallet = await Wallet.create(
        descriptor: descriptor,
        changeDescriptor: changeDescriptor,
        network: _network,
        databaseConfig: const DatabaseConfig.memory(),
      );

      // 5. Configurar a conexão com a blockchain
      final blockchain = await Blockchain.create(
        config: _blockchainConfig,
      );

      // 6. Sincronizar a carteira com a blockchain
      await bdkWallet.sync(blockchain: blockchain);

      // 7. Criar uma transação de teste para estimar taxas
      final txBuilder = TxBuilder();
      
      // Adicionar o destinatário
      final address = await Address.fromString(s: destinationAddress, network: _network);
      final amountInSatoshi = BigInt.from(amountInBtc * 100000000);
      txBuilder.addRecipient(address.scriptPubkey(), amountInSatoshi);

      // Definir a taxa de transação padrão para estimativa
      txBuilder.feeRate(1.0);

      // 8. Tentar finalizar a transação para obter uma estimativa
      try {
        final psbtResult = await txBuilder.finish(bdkWallet);
        final psbt = psbtResult.$1;
        final fee = psbtResult.$2;

        // Converter a taxa de satoshis para BTC
        final feeInBtc = double.parse(fee.toString()) / 100000000;
        return feeInBtc;
      } catch (e) {
        print('Erro ao estimar taxa: $e');
        return 0.0001; // Taxa fixa estimada de 0.0001 BTC (10000 satoshis)
      }
    } catch (e) {
      print('Erro ao estimar taxa de transação: $e');
      return 0.0001; // Taxa fixa estimada de 0.0001 BTC (10000 satoshis)
    }
  }
}
