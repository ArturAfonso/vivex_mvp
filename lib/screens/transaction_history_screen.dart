import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bitcoin_wallet.dart';
import '../services/blockchain_service.dart';
import '../config/service_locator.dart';
import 'package:intl/intl.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final BitcoinWallet wallet;

  const TransactionHistoryScreen({
    super.key,
    required this.wallet,
  });

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final BlockchainService _blockchainService = BlockchainService();
  List<TransactionDetails> _transactions = [];
  bool _isLoading = true;
  String? _errorMessage;
  Wallet? _bdkWallet;
  double _btcToBrlRate = 0.0; // Taxa de conversão BTC para BRL

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  // Método para inicializar a carteira BDK a partir da BitcoinWallet
  Future<Wallet?> _initBdkWallet() async {
    try {
      if (widget.wallet.mnemonic.isEmpty) {
        throw Exception('Não é possível carregar transações sem a frase mnemônica da carteira');
      }

      // 1. Criar uma frase mnemônica a partir da string existente
      final mnemonic = await Mnemonic.fromString(widget.wallet.mnemonic);

      // 2. Criar chave secreta usando a mnemônica
      final descriptorSecretKey = await DescriptorSecretKey.create(
        network: appConfig.networkType,
        mnemonic: mnemonic,
        password: widget.wallet.hasPassphrase && widget.wallet.passphrase != null ? widget.wallet.passphrase : '',
      );

      // 3. Determinar o tipo de carteira e criar os descritores apropriados
      Descriptor descriptor;
      Descriptor changeDescriptor;

      switch (widget.wallet.walletType.toLowerCase()) {
        case 'native segwit':
          // BIP84 (Native SegWit)
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.internalChain,
          );
          break;

        case 'segwit':
          // BIP49 (SegWit)
          descriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip49(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.internalChain,
          );
          break;

        case 'legacy':
          // BIP44 (Legacy)
          descriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip44(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.internalChain,
          );
          break;

        default:
          // Por padrão, assumimos BIP84 (Native SegWit)
          descriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.externalChain,
          );
          changeDescriptor = await Descriptor.newBip84(
            secretKey: descriptorSecretKey,
            network: appConfig.networkType,
            keychain: KeychainKind.internalChain,
          );
      }

      // 4. Inicializar a carteira BDK
      final bdkWallet = await Wallet.create(
        descriptor: descriptor,
        changeDescriptor: changeDescriptor,
        network: appConfig.networkType,
        databaseConfig: const DatabaseConfig.memory(),
      );

      return bdkWallet;
    } catch (e) {
      print('Erro ao inicializar carteira BDK: $e');
      return null;
    }
  }

  // Método para carregar as transações da carteira
  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Carregar a taxa de conversão BTC para BRL
      try {
        _btcToBrlRate = await _blockchainService.getBtcToBrlRate();
      } catch (e) {
        print('Erro ao carregar taxa de conversão: $e');
        // Definindo um valor padrão caso falhe
        _btcToBrlRate = 350000.0;
      }

      // Inicializar a carteira BDK
      final bdkWallet = await _initBdkWallet();
      if (bdkWallet == null) {
        throw Exception('Não foi possível inicializar a carteira');
      }

      // Salvar a referência da carteira
      _bdkWallet = bdkWallet;

      // Configurar a conexão com a blockchain
      final blockchain = await Blockchain.create(
        config: BlockchainConfig.electrum(
          config: ElectrumConfig(
            stopGap: BigInt.from(10),
            timeout: 5,
            retry: 5,
            url: appConfig.networkType == Network.testnet 
                ? 'ssl://electrum.blockstream.info:60002'  // Servidor para testnet
                : 'ssl://electrum.blockstream.info:50002', // Servidor para mainnet
            validateDomain: false,
          ),
        ),
      );

      // Sincronizar a carteira com a blockchain
      await bdkWallet.sync(blockchain: blockchain);

      // Obter as transações
      final transactions = bdkWallet.listTransactions(includeRaw: true);
      
      // Ordenar as transações por data (timestamp) com as mais recentes primeiro
      transactions.sort((a, b) {
        // Pegar os timestamps de confirmação ou usar 0 para transações não confirmadas
        final timestampA = a.confirmationTime != null ? a.confirmationTime!.timestamp.toInt() : 0;
        final timestampB = b.confirmationTime != null ? b.confirmationTime!.timestamp.toInt() : 0;
        
        // Ordenar em ordem decrescente (mais recentes primeiro)
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erro ao carregar transações: $e';
      });
      print('Erro ao carregar transações: $e');
    }
  }

  // Método para formatar o valor de BTC
  String _formatBtcAmount(BigInt satoshis) {
    final btcAmount = satoshis.toDouble() / 100000000;
    return btcAmount.toStringAsFixed(8);
  }

  // Método para formatar a data
  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'Não confirmada';
    
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    return formatter.format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico - ${widget.wallet.name}'),
        backgroundColor: Colors.blue.shade800,
        actions: [
          // Botão de atualizar
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
            tooltip: 'Atualizar transações',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : _transactions.isEmpty
                  ? _buildEmptyView()
                  : _buildTransactionsList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Erro ao carregar transações',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Ocorreu um erro desconhecido',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadTransactions,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
            ),
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma transação encontrada',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Esta carteira ainda não possui transações',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadTransactions,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
            ),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isReceived = tx.received > BigInt.zero;
        final amount = isReceived ? tx.received : tx.sent;
        final confirmationTime = tx.confirmationTime;
        final isConfirmed = confirmationTime != null;
        
        // Calcular o valor em moeda fiat (BRL) usando a taxa atual
        final btcAmount = amount.toDouble() / 100000000;
        final fiatAmount = btcAmount * _btcToBrlRate;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TransactionDetailScreen(
                    tx: tx,
                    wallet: widget.wallet,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Ícone da transação
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isReceived 
                              ? Colors.green.shade100 
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isReceived
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: isReceived 
                              ? Colors.green.shade700 
                              : Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Detalhes da transação
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isReceived ? 'Recebido' : 'Enviado',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isConfirmed 
                                  ? _formatDate(confirmationTime.timestamp.toInt())
                                  : 'Pendente - Não confirmada',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Valor da transação (agora em BTC e fiat)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isReceived ? "+" : "-"}${_formatBtcAmount(amount)} BTC',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isReceived 
                                  ? Colors.green.shade700 
                                  : Colors.orange.shade700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Valor em moeda fiat em vez de confirmações
                          Text(
                            'R\$ ${fiatAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Tela de detalhes da transação
class TransactionDetailScreen extends StatefulWidget {
  final TransactionDetails tx;
  final BitcoinWallet wallet;

  const TransactionDetailScreen({
    super.key,
    required this.tx,
    required this.wallet,
  });

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

// Enum para controlar a unidade de exibição do saldo (igual ao da tela principal)
enum BalanceUnit { btc, sats, brl }

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  // Unidade atual do saldo
  BalanceUnit _currentUnit = BalanceUnit.btc;
  
  // Taxa de conversão BTC para BRL
  double _btcToBrlRate = 350000.0; // Valor padrão
  
  @override
  void initState() {
    super.initState();
    _loadExchangeRate();
  }
  
  // Método para carregar a taxa de conversão
  Future<void> _loadExchangeRate() async {
    try {
      final blockchainService = BlockchainService();
      final rate = await blockchainService.getBtcToBrlRate();
      if (mounted) {
        setState(() {
          _btcToBrlRate = rate;
        });
      }
    } catch (e) {
      print('Erro ao carregar taxa de conversão: $e');
      // Mantém o valor padrão em caso de erro
    }
  }

  // Método para alternar entre as unidades ao clicar
  void _toggleBalanceUnit() {
    setState(() {
      switch (_currentUnit) {
        case BalanceUnit.btc:
          _currentUnit = BalanceUnit.sats;
          break;
        case BalanceUnit.sats:
          _currentUnit = BalanceUnit.brl;
          break;
        case BalanceUnit.brl:
          _currentUnit = BalanceUnit.btc;
          break;
      }
    });
  }

  // Método para formatar o valor de acordo com a unidade atual
  String _getFormattedAmount(BigInt satoshis) {
    final btcAmount = satoshis.toDouble() / 100000000;
    
    switch (_currentUnit) {
      case BalanceUnit.btc:
        return btcAmount.toStringAsFixed(8);
      case BalanceUnit.sats:
        return satoshis.toString();
      case BalanceUnit.brl:
        final brlAmount = btcAmount * _btcToBrlRate;
        return brlAmount.toStringAsFixed(2);
    }
  }

  // Método para obter o símbolo da unidade atual
  String _getUnitSymbol() {
    switch (_currentUnit) {
      case BalanceUnit.btc:
        return 'BTC';
      case BalanceUnit.sats:
        return 'sats';
      case BalanceUnit.brl:
        return 'R\$';
    }
  }

  // Método para obter a cor do texto de acordo com a unidade
  Color _getUnitColor() {
    switch (_currentUnit) {
      case BalanceUnit.btc:
        return Colors.orange.shade800;
      case BalanceUnit.sats:
        return Colors.orange.shade700;
      case BalanceUnit.brl:
        return Colors.green.shade700;
    }
  }

  // Método para formatar o valor de BTC para exibição sem alternância (usado em outros campos)
  String _formatBtcAmount(BigInt satoshis) {
    final btcAmount = satoshis.toDouble() / 100000000;
    return btcAmount.toStringAsFixed(8);
  }

  // Método para formatar a taxa de acordo com a unidade atual
  String _formatFee(BigInt? fee) {
    if (fee == null) return "0";
    
    final btcAmount = fee.toDouble() / 100000000;
    
    switch (_currentUnit) {
      case BalanceUnit.btc:
        return '${btcAmount.toStringAsFixed(8)} BTC';
      case BalanceUnit.sats:
        return '${fee.toString()} sats';
      case BalanceUnit.brl:
        final brlAmount = btcAmount * _btcToBrlRate;
        return 'R\$ ${brlAmount.toStringAsFixed(2)}';
    }
  }
  
  // Método para copiar texto para a área de transferência
  void _copyToClipboard(BuildContext context, String text) {
    // Usa a API de clipboard para copiar o texto
    Clipboard.setData(ClipboardData(text: text));
    
    // Feedback para o usuário
    /* ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Valor copiado para a área de transferência'),
        duration: Duration(seconds: 2),
      ),
    ); */
  }

  // Método para formatar a data
  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'Não confirmada';
    
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final formatter = DateFormat('dd/MM/yyyy HH:mm:ss');
    return formatter.format(date);
  }

  // Método para abrir o explorador de blocos
  Future<void> _openInBlockExplorer(BuildContext context) async {
    final network = appConfig.networkType;
    final baseUrl = network == Network.testnet
        ? 'https://blockstream.info/testnet/tx/'
        : 'https://blockstream.info/tx/';
    
    final url = '$baseUrl${widget.tx.txid}';
    final uri = Uri.parse(url);
    
    // Primeiro copiar o ID para a área de transferência
    _copyToClipboard(context, widget.tx.txid);
    
   
    
    // Tentar abrir o URL no navegador
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Em caso de erro ao abrir o navegador
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o navegador: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = widget.tx.received > BigInt.zero;
    final confirmationTime = widget.tx.confirmationTime;
    final isConfirmed = confirmationTime != null;
    final amount = isReceived ? widget.tx.received : widget.tx.sent;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Transação'),
        backgroundColor: Colors.blue.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card principal com informações da transação
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isReceived ? Colors.green.shade700 : Colors.orange.shade700,
                      isReceived ? Colors.green.shade900 : Colors.orange.shade900,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isReceived ? 'Bitcoin Recebido' : 'Bitcoin Enviado',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Valor',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _toggleBalanceUnit,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${isReceived ? "+" : "-"}${_getFormattedAmount(amount)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getUnitColor(),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getUnitSymbol(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Clique no valor para mudar a unidade',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Status',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isConfirmed ? 'Confirmada' : 'Não confirmada',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Data',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isConfirmed 
                                  ? _formatDate(confirmationTime.timestamp.toInt())
                                  : 'Pendente',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Detalhes da transação
            const Text(
              'Detalhes da Transação',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // ID da transação
            _buildDetailItem(
              context,
              'ID da Transação',
              widget.tx.txid,
              isSelectable: true,
              onTap: () => _openInBlockExplorer(context),
            ),
            
            // Confirmações
            if (isConfirmed)
              _buildDetailItem(
                context,
                'Confirmações',
                confirmationTime.height.toString(),
              ),
            
            // Taxa da transação (se disponível)
            if (widget.tx.fee != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Taxa',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          // Valor da taxa com funcionalidade de clique para alternar unidades
                          Expanded(
                            child: GestureDetector(
                              onTap: _toggleBalanceUnit,
                              child: Text(
                                _formatFee(widget.tx.fee),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _getUnitColor(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botão para copiar para a área de transferência
                          InkWell(
                            onTap: () {
                              final valueText = _formatFee(widget.tx.fee);
                              _copyToClipboard(context, valueText);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            // Data da confirmação (se confirmada)
            if (isConfirmed)
              _buildDetailItem(
                context,
                'Data de confirmação',
                _formatDate(confirmationTime.timestamp.toInt()),
              ),
            
            // Nome da carteira
            _buildDetailItem(
              context,
              'Carteira',
              widget.wallet.name,
            ),
            
            const SizedBox(height: 24),
            
            // Botão para ver no explorador de blocos
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openInBlockExplorer(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white, // Cor do texto e ícone em branco
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text(
                  'Ver no Explorador de Blocos',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, // Deixa o texto em negrito
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context,
    String label,
    String value, {
    bool isSelectable = false,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: GestureDetector(
              onTap: onTap,
              child: isSelectable
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: onTap != null
                                  ? Colors.blue.shade700
                                  : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.open_in_new,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                      ],
                    )
                  : Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}