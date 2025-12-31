import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bitcoin_wallet.dart';
import '../services/blockchain_service.dart';
import '../config/service_locator.dart';
import 'qr_scanner_screen.dart';

class SendBitcoinScreen extends StatefulWidget {
  final BitcoinWallet wallet;

  const SendBitcoinScreen({
    super.key,
    required this.wallet,
  });

  @override
  State<SendBitcoinScreen> createState() => _SendBitcoinScreenState();
}

class _SendBitcoinScreenState extends State<SendBitcoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _fiatAmountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _blockchainService = BlockchainService();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  double _exchangeRate = 0.0; // Taxa de câmbio BTC/BRL
  double _availableBalance = 0.0; // Saldo disponível em BTC
  bool _isLoadingBalance = true;

  @override
  void initState() {
    super.initState();
    _fetchExchangeRateAndBalance();
    // Sincronizar os campos de BTC e BRL
    _amountController.addListener(_updateFiatAmount);
    _fiatAmountController.addListener(_updateBtcAmount);
  }

  Future<void> _fetchExchangeRateAndBalance() async {
    try {
      if (!mounted) return; // Verificar se o widget ainda está montado
      
      setState(() {
        _isLoadingBalance = true;
      });
      
      // Usar o BalanceService para obter os valores
      // Primeiro, verificar se já temos um valor em cache
      double exchangeRate = balanceService.getBtcToBrlRate();
      double balance = balanceService.getBalance(widget.wallet.id);
      
      // Se não temos valores em cache ou queremos atualizar, buscamos novamente
      if (balance <= 0) {
        // Atualiza o saldo e a taxa de câmbio
        await balanceService.updateBalanceAndRate(widget.wallet);
        
        // Obtém os valores atualizados
        exchangeRate = balanceService.getBtcToBrlRate();
        balance = balanceService.getBalance(widget.wallet.id);
      }
      
      if (!mounted) return; // Verificar novamente após operações assíncronas
      
      setState(() {
        _exchangeRate = exchangeRate;
        _availableBalance = balance;
        _isLoadingBalance = false;
      });
    } catch (e) {
      if (!mounted) return; // Verificar se ainda está montado antes de atualizar o estado
      
      setState(() {
        _errorMessage = "Erro ao carregar dados: ${e.toString()}";
        _isLoadingBalance = false;
      });
    }
  }

  void _updateFiatAmount() {
    if (_amountController.text.isEmpty) {
      _fiatAmountController.text = '';
      return;
    }
    
    // Não disparar evento se estiver atualizando a partir do fiatAmount
    if (_amountController.text == _lastAmountValue) return;
    _lastAmountValue = _amountController.text;
    
    final btcText = _amountController.text.trim().replaceAll(',', '.');
    final btcAmount = double.tryParse(btcText) ?? 0.0;
    final fiatAmount = btcAmount * _exchangeRate;
    
    // Atualiza sem disparar listener
    _fiatAmountController.removeListener(_updateBtcAmount);
    _fiatAmountController.text = fiatAmount.toStringAsFixed(2);
    _fiatAmountController.addListener(_updateBtcAmount);
  }

  void _updateBtcAmount() {
    if (_fiatAmountController.text.isEmpty) {
      _amountController.text = '';
      return;
    }
    
    // Não disparar evento se estiver atualizando a partir do btcAmount
    if (_fiatAmountController.text == _lastFiatValue) return;
    _lastFiatValue = _fiatAmountController.text;
    
    final fiatText = _fiatAmountController.text.trim().replaceAll(',', '.');
    final fiatAmount = double.tryParse(fiatText) ?? 0.0;
    final btcAmount = fiatAmount / _exchangeRate;
    
    // Atualiza sem disparar listener
    _amountController.removeListener(_updateFiatAmount);
    _amountController.text = btcAmount.toStringAsFixed(8);
    _amountController.addListener(_updateFiatAmount);
  }

  String _lastAmountValue = '';
  String _lastFiatValue = '';

  Future<void> _setMaxAmount() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // Verificar se há um endereço de destino
      final destinationAddress = _addressController.text.trim();
      if (destinationAddress.isEmpty) {
        setState(() {
          _errorMessage = "Por favor, insira um endereço de destino primeiro";
          _isLoading = false;
        });
        return;
      }
      
      // Estimar a taxa de transação
      final estimatedFee = await _blockchainService.estimateTransactionFee(
        sourceWallet: widget.wallet,
        destinationAddress: destinationAddress,
        amountInBtc: _availableBalance,
      );
      
      final maxAmount = _availableBalance - estimatedFee;
      
      if (!mounted) return; // Verificar se ainda está montado após operação assíncrona
      
      if (maxAmount <= 0) {
        setState(() {
          _errorMessage = "Saldo insuficiente após taxas";
          _isLoading = false;
        });
        return;
      }
      
      setState(() {
        _isLoading = false;
        _amountController.removeListener(_updateFiatAmount);
        _amountController.text = maxAmount.toStringAsFixed(8);
        _amountController.addListener(_updateFiatAmount);
        _updateFiatAmount();
      });
    } catch (e) {
      if (!mounted) return; // Verificar se ainda está montado em caso de erro
      
      setState(() {
        _isLoading = false;
        _errorMessage = "Erro ao calcular valor máximo: ${e.toString()}";
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.removeListener(_updateFiatAmount);
    _amountController.dispose();
    _fiatAmountController.removeListener(_updateBtcAmount);
    _fiatAmountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _sendBitcoin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Ocultar o teclado
    FocusScope.of(context).unfocus();

    // Obter os valores dos campos
    final destinationAddress = _addressController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amountInBtc = double.tryParse(amountText) ?? 0.0;
    final description = _descriptionController.text.trim();

    if (amountInBtc <= 0) {
      setState(() {
        _errorMessage = "O valor deve ser maior que zero";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Chamar o método atualizado para enviar bitcoins
      final txid = await _blockchainService.sendBitcoin(
        sourceWallet: widget.wallet,
        destinationAddress: destinationAddress,
        amountInBtc: amountInBtc,
        description: description, // Passar a descrição para OP_RETURN
      );

      // Se chegou aqui, a transação foi enviada com sucesso
      if (!mounted) return; // Verificar se ainda está montado após operação assíncrona
      
      // Atualizar o saldo no BalanceService para manter a consistência
      await balanceService.updateWalletBalance(widget.wallet);
      
      setState(() {
        _isLoading = false;
        _successMessage = "Transação enviada com sucesso!\nID: $txid";
      });

      // Limpar os campos após o envio bem-sucedido
      _addressController.clear();
      _amountController.clear();
      _fiatAmountController.clear();
      _descriptionController.clear();
      
      // Atualizar a interface com o novo saldo
      _fetchExchangeRateAndBalance();
    } catch (e) {
      if (!mounted) return; // Verificar se ainda está montado em caso de erro
      
      setState(() {
        _isLoading = false;
        _errorMessage = "Erro ao enviar bitcoins: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enviar Bitcoin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Carteira de origem
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Carteira de Origem:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.wallet.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tipo: ${widget.wallet.walletType}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Endereço principal: ${widget.wallet.addresses.isNotEmpty ? widget.wallet.addresses.first : 'Nenhum endereço disponível'}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _isLoadingBalance
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Carregando saldo...'),
                                ],
                              ),
                            )
                          : Text(
                              'Saldo disponível: ${_availableBalance.toStringAsFixed(8)} BTC',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                      if (!_isLoadingBalance && _exchangeRate > 0)
                        Text(
                          'Valor aproximado: R\$ ${(_availableBalance * _exchangeRate).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Endereço de destino
              const Text(
                'Endereço de Destino:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  hintText: 'Ex: tb1q...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.blue,
                        size: 28,
                      ),
                      onPressed: () async {
                        // Navegar para a tela de escaneamento de QR code
                        final scannedAddress = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QrScannerScreen(),
                          ),
                        );

                        // Se um endereço foi escaneado com sucesso, preencher o campo
                        if (scannedAddress != null && mounted) {
                          setState(() {
                            _addressController.text = scannedAddress;
                          });
                        }
                      },
                      tooltip: 'Escanear QR Code',
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: () async {
                      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                      if (clipboardData?.text != null) {
                        setState(() {
                          _addressController.text = clipboardData!.text!;
                        });
                      }
                    },
                    tooltip: 'Colar',
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Por favor, insira o endereço de destino';
                  }
                  // Verificação básica de formato de endereço Bitcoin
                  if (!value.startsWith('tb1') &&
                      !value.startsWith('bc1') &&
                      !value.startsWith('2') &&
                      !value.startsWith('3') &&
                      !value.startsWith('m') &&
                      !value.startsWith('n') &&
                      !value.startsWith('1')) {
                    return 'Endereço Bitcoin inválido';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Descrição (novo campo)
              const Text(
                'Descrição (opcional):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: 'Ex: Pagamento de serviço',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLength: 80, // Limite para OP_RETURN
              ),

              const SizedBox(height: 16),

              // Valor em BTC com botão máximo
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Valor (BTC):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: 'Ex: 0.001',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixText: 'BTC',
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Por favor, insira o valor a enviar';
                            }
                            final amount = double.tryParse(value.replaceAll(',', '.'));
                            if (amount == null) {
                              return 'Valor inválido';
                            }
                            if (amount <= 0) {
                              return 'O valor deve ser maior que zero';
                            }
                            if (amount > _availableBalance) {
                              return 'Saldo insuficiente';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 32.0),
                    child: ElevatedButton(
                      onPressed: _isLoading || _isLoadingBalance ? null : _setMaxAmount,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Máximo'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Valor em BRL (novo campo)
              const Text(
                'Valor (BRL):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fiatAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'Ex: 600.00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixText: 'R\$ ',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),

              const SizedBox(height: 24),

              // Mensagens de erro ou sucesso
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),

              if (_successMessage != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card verde com mensagem de sucesso
                    GestureDetector(
                      onTap: () {
                        // Extrair apenas o ID da transação do texto completo
                        final idParts = _successMessage!.split('ID: ');
                        if (idParts.length > 1) {
                          final txId = idParts[1].trim();
                          Clipboard.setData(ClipboardData(text: txId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ID da transação copiado para a área de transferência'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: TextStyle(color: Colors.green.shade900),
                              ),
                            ),
                            Icon(
                              Icons.copy,
                              size: 20,
                              color: Colors.green.shade700,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Link para o explorador de blocos - agora como texto simples sublinhado
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        // Extrair o ID da transação
                        final idParts = _successMessage!.split('ID: ');
                        if (idParts.length > 1) {
                          final txId = idParts[1].trim();
                          return InkWell(
                            onTap: () async {
                              final url = 'https://blockstream.info/testnet/tx/$txId';
                              try {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Não foi possível abrir o explorador: $e'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'Ver no explorador de blocos',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                decoration: TextDecoration.underline,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              // Botão de enviar
              ElevatedButton(
                onPressed: _isLoading ? null : _sendBitcoin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Enviando...'),
                        ],
                      )
                    : const Text(
                        'ENVIAR BITCOINS',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 16),

              // Informações adicionais
              const Card(
                elevation: 0,
                color: Color(0xFFF5F5F5),
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Observações:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Confira sempre o endereço de destino antes de enviar',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '• Transações na blockchain são irreversíveis',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '• A taxa de transação é calculada automaticamente',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
