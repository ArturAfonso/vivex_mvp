import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:vivex_mvp/config/app_config.dart';
import 'package:vivex_mvp/screens/receive_bitcoin_screen.dart';
import 'package:vivex_mvp/screens/wallet_details_screen.dart';
import 'package:vivex_mvp/services/blockchain_service.dart';
import 'widgets/response_container.dart';
import 'screens/create_wallet_screen.dart';
import 'screens/wallets_list_screen.dart';
import 'models/bitcoin_wallet.dart';
import 'services/wallet_storage.dart';
import 'screens/send_bitcoin_screen.dart';
import 'screens/transaction_history_screen.dart'; // Importação da tela de histórico
import 'config/service_locator.dart'; // Importação do service locator
import 'services/balance_service.dart';

void main() async {
  // Garante que os bindings do Flutter estejam inicializados
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa o GetIt antes de iniciar o app
  setupLocator();
  
  // Carrega as configurações salvas
  await loadSavedConfigurations();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Art BTC wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
final GetIt locator = GetIt.instance;
AppConfig appConfig = locator<AppConfig>();

// Enum para controlar a unidade de exibição do saldo
enum BalanceUnit { btc, sats, brl }

class _HomeScreenState extends State<HomeScreen> {
  final WalletStorage _walletStorage = WalletStorage();
  final BlockchainService _blockchainService = BlockchainService();

  List<BitcoinWallet> _wallets = [];
  bool _isLoading = false; // Variável para rastrear o estado de carregamento
  bool _isLoadingBalance = false; // Variável para rastrear o carregamento do saldo
  BitcoinWallet? _selectedWallet; // Carteira selecionada atualmente

  // Unidade atual do saldo
  BalanceUnit _currentUnit = BalanceUnit.btc;

  // Valores reais do saldo
  double _bitcoinAmount = 0.0;
  double _btcToBrlRate = 350000.0; // Taxa padrão caso falhe a consulta online

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

    // Mostrar um feedback visual da troca
    /* ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unidade alterada para ${_getUnitSymbol()}'),
        duration: const Duration(seconds: 1),
      ),
    ); */
  }

  // Método para obter o valor formatado de acordo com a unidade atual
  String _getFormattedBalance() {
    if (_isLoadingBalance) {
      return "...";
    }

    switch (_currentUnit) {
      case BalanceUnit.btc:
        return _bitcoinAmount.toStringAsFixed(8);
      case BalanceUnit.sats:
        // 1 BTC = 100,000,000 sats
        return ((_bitcoinAmount * 100000000).toInt()).toString();
      case BalanceUnit.brl:
        // Valor em reais com 2 casas decimais
        return (_bitcoinAmount * _btcToBrlRate).toStringAsFixed(2);
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

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  // Método para atualizar o saldo da carteira selecionada
  Future<void> _updateWalletBalance() async {
    if (_selectedWallet == null) {
      return;
    }

    setState(() {
      _isLoadingBalance = true;
    });

    try {
      // Usa o BalanceService para atualizar e obter o saldo
      await balanceService.updateBalanceAndRate(_selectedWallet!);

      // Obtém os valores atualizados do BalanceService
      final balance = balanceService.getBalance(_selectedWallet!.id);
      final rate = balanceService.getBtcToBrlRate();

      // Atualiza o estado com os valores obtidos
      setState(() {
        _bitcoinAmount = balance;
        _btcToBrlRate = rate;
        _isLoadingBalance = false;
      });
    } catch (e) {
      print('Erro ao atualizar saldo: $e');
      setState(() {
        _isLoadingBalance = false;
      });

      // Mostra erro apenas se estiver visível (ainda montado)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar saldo: ${e.toString()}'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // Método para atualizar o saldo de todas as carteiras em segundo plano
  Future<void> _updateAllWalletsBalance() async {
    if (_wallets.isEmpty) return;
    
    print('Iniciando atualização de saldo para todas as carteiras em segundo plano');
    
    // Pula a carteira principal que já foi atualizada
    final otherWallets = _wallets.where((wallet) => wallet.id != _selectedWallet?.id).toList();
    
    if (otherWallets.isEmpty) {
      print('Não há outras carteiras para atualizar');
      return;
    }
    
    // Atualiza as carteiras uma a uma sem bloqueio de UI
    for (final wallet in otherWallets) {
      try {
        print('Atualizando saldo da carteira: ${wallet.name}');
        await balanceService.updateWalletBalance(wallet);
        
        // Atualiza a UI se estiver visível
        if (mounted) {
          setState(() {}); // Força atualização da lista que exibe os saldos
        }
      } catch (e) {
        print('Erro ao atualizar saldo da carteira ${wallet.name}: $e');
        // Continua mesmo se houver erro em uma carteira específica
      }
    }
    
    print('Atualização de saldo em segundo plano concluída');
  }

  // Método para carregar as carteiras do armazenamento
  Future<void> _loadWallets() async {
    setState(() {
      _isLoading = true;
      _selectedWallet = null; // Resetar a carteira selecionada ao recarregar
    });

    try {
      final allWallets = await _walletStorage.loadAllWallets();
      
      // Filtrar carteiras pelo tipo de rede atual
      final filteredWallets = allWallets.where((wallet) => 
        wallet.networkType == appConfig.networkType
      ).toList();
      
      setState(() {
        _wallets = filteredWallets;
        _isLoading = false;

        // Se existir ao menos uma carteira compatível com a rede atual
        if (_wallets.isNotEmpty) {
          // Busca o ID da carteira primária
          String? primaryWalletId;
          
          // Método assíncrono mais confiável para obter o ID da carteira primária
          _walletStorage.getPrimaryWalletId().then((id) {
            if (id != null && mounted) {
              // Busca a carteira primária na lista de carteiras filtradas
              final primaryWallet = _wallets.firstWhere(
                (wallet) => wallet.id == id,
                orElse: () => _wallets.first
              );
              
              if (mounted) {
                setState(() {
                  _selectedWallet = primaryWallet;
                  _updateWalletBalance().then((_) {
                    // Após atualizar a carteira principal, atualiza as demais em segundo plano
                    _updateAllWalletsBalance();
                  });
                });
              }
            }
          });
          
          // Enquanto aguarda a busca assíncrona, seleciona a primeira carteira para exibição imediata
          _selectedWallet = _wallets.first;
          
          // Verifica se já existe um saldo armazenado no BalanceService para a carteira atual
          final cachedBalance = balanceService.getBalance(_selectedWallet!.id);
          final cachedRate = balanceService.getBtcToBrlRate();

          // Se já existir um saldo armazenado, usa-o imediatamente
          if (cachedBalance > 0) {
            _bitcoinAmount = cachedBalance;
            _btcToBrlRate = cachedRate;
          }

          // Inicia a atualização do saldo em background
          _updateWalletBalance();
        } else {
          // Resetar os valores de saldo se não houver carteiras selecionadas
          _bitcoinAmount = 0;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar carteiras: ${e.toString()}'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  Future<void> _setSelectedWallet(BitcoinWallet? wallet) async {
    if (wallet != null && wallet.id != null) {
      await _walletStorage.setPrimaryWallet(wallet.id!);
      setState(() {
        _selectedWallet = wallet;
      });

      // Atualiza o saldo da nova carteira selecionada
      _updateWalletBalance();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Carteira "${wallet.name}" selecionada como primária')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('MVP - Bitcoin Wallet'),
        backgroundColor: Colors.blue.shade800,
        actions: [
          Row(
            children: [
              Text(appConfig.networkType == Network.testnet ? 'Testnet' : 'Mainnet'),
              
              IconButton(
                icon: Icon(Icons.circle_rounded, color: appConfig.networkType == Network.testnet ? Colors.red : Colors.green),
                onPressed: () async {
                  // Inverter a rede atual
                  Network newNetwork = appConfig.networkType == Network.testnet 
                      ? Network.bitcoin 
                      : Network.testnet;
                  
                  // Atualizar a configuração global (isso salva automaticamente a configuração)
                  await appConfig.setNetwork(newNetwork);
                  
                  // Recarregar a lista de carteiras com base na nova rede selecionada
                  _loadWallets();
                  
                  // Mostrar feedback para o usuário
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rede alterada para ${newNetwork == Network.testnet ? 'Testnet' : 'Mainnet'}'),
                      backgroundColor: newNetwork == Network.testnet ? Colors.red.shade700 : Colors.green.shade700,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                tooltip: 'Alternar entre Testnet e Mainnet',
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _wallets.isEmpty
              ? _buildEmptyState()
              : _buildWalletDisplay(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateWalletScreen()),
          );

          if (result == true) {
            _loadWallets();
          }
        },
        backgroundColor: Colors.blue.shade800,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: appConfig.networkType == Network.testnet 
                ? Colors.red.shade200 
                : Colors.green.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            'Você não possui carteiras Bitcoin na rede ${appConfig.networkType == Network.testnet ? 'Testnet' : 'Mainnet'}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateWalletScreen()),
              );

              if (result == true) {
                _loadWallets();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: appConfig.networkType == Network.testnet 
                ? Colors.red.shade800 
                : Colors.green.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Criar Nova Carteira',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletDisplay() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cartão da carteira principal exibindo o saldo
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
                    Colors.blue.shade800,
                    Colors.blue.shade900,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedWallet?.name ?? 'Carteira Principal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Botão para atualizar o saldo
                      IconButton(
                        onPressed: _updateWalletBalance,
                        icon: _isLoadingBalance
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, color: Colors.white),
                        tooltip: 'Atualizar saldo',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Saldo',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
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
                          _getFormattedBalance(),
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        icon: Icons.send,
                        label: 'Enviar',
                        onTap: () {
                          // Verificar se existe uma carteira selecionada
                          if (_selectedWallet == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Selecione uma carteira primeiro!'),
                              ),
                            );
                            return;
                          }

                          // Navegar para a tela de envio de bitcoins
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SendBitcoinScreen(
                                wallet: _selectedWallet!,
                              ),
                            ),
                          ).then((_) {
                            // Atualizar o saldo quando voltar da tela de envio
                            _updateWalletBalance();
                          });
                        },
                      ),
                      _buildActionButton(
                        icon: Icons.qr_code,
                        label: 'Receber',
                        onTap: () {
                          // Verificar se existe uma carteira selecionada
                          if (_selectedWallet == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Selecione uma carteira primeiro!'),
                              ),
                            );
                            return;
                          }

                          // Navegar para a tela de recebimento de bitcoins
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReceiveBitcoinScreen(
                                wallet: _selectedWallet!,
                              ),
                            ),
                          );
                        },
                      ),
                      _buildActionButton(
                        icon: Icons.history,
                        label: 'Histórico',
                        onTap: () {
                          // Verificar se existe uma carteira selecionada
                          if (_selectedWallet == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Selecione uma carteira primeiro!'),
                              ),
                            );
                            return;
                          }

                          // Navegar para a tela de histórico de transações
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TransactionHistoryScreen(
                                wallet: _selectedWallet!,
                              ),
                            ),
                          );
                        },
                      ),
                      _buildActionButton(
                        icon: Icons.info_outline,
                        label: 'Detalhes',
                        onTap: () {
                          // Navegar para a tela de detalhes da carteira
                          if (_selectedWallet != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WalletDetailsScreen(
                                  wallet: _selectedWallet!,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Lista de carteiras
          const Text(
            'Suas Carteiras',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Lista de carteiras disponíveis
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _wallets.length,
            itemBuilder: (context, index) {
              final wallet = _wallets[index];
              final isSelected = _selectedWallet?.id == wallet.id;

              // Obtenha o saldo em BTC da carteira
              final walletBalance = balanceService.getBalance(wallet.id);
              // Calcule o valor em BRL usando a taxa de câmbio atual
              final walletBalanceBRL = (walletBalance * _btcToBrlRate).toStringAsFixed(2);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? Colors.blue.shade800 : Colors.transparent,
                    width: 2,
                  ),
                ),
                elevation: isSelected ? 4 : 1,
                child: ListTile(
                  onTap: () {
                    setState(() {
                      _selectedWallet = wallet;
                      _updateWalletBalance();
                    });
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  title: Text(
                    wallet.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Saldo: R\$ $walletBalanceBRL',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WalletDetailsScreen(wallet: wallet),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
