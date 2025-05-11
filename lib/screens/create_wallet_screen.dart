import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bdk_flutter/bdk_flutter.dart';
import '../widgets/response_container.dart';
import '../services/wallet_storage.dart';
import '../models/bitcoin_wallet.dart';
import '../config/service_locator.dart'; // Importamos o service_locator para acessar o appConfig

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  String _response = '';
  bool _isError = false;
  bool _isLoading = false;
  int _wordCount = 12; // Valor padrão para número de palavras
  String? _generatedMnemonic;
  String _derivationPath = '';
  String _walletType = '';
  String _walletAddressType = 'native_segwit'; // Valor padrão para tipo de carteira
  String _masterPublicKey = ''; // Variável para armazenar a chave pública mestra (xpub)
  String _firstAddress = ''; // Variável para armazenar o primeiro endereço
  List<String> _receivingAddresses = []; // Lista para armazenar múltiplos endereços de recebimento
  bool _isSaving = false; // Indica se está salvando a carteira
  String? _walletId; // ID da carteira salva

  // Controles para passphrase
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _derivationPathController = TextEditingController();
  final TextEditingController _walletTypeController = TextEditingController();
  final TextEditingController _masterPublicKeyController = TextEditingController(); // Controller para exibir o xpub
  final TextEditingController _firstAddressController = TextEditingController(); // Controller para o primeiro endereço
  final TextEditingController _walletNameController = TextEditingController(); // Novo controller para o nome da carteira
  bool _usePassphrase = false;
  bool _walletCreated = false;
  final int _numAddressesToShow = 3; // Número de endereços de recebimento a serem exibidos

  // Instância do serviço de armazenamento de carteiras
  final WalletStorage _walletStorage = WalletStorage();

  @override
  void initState() {
    super.initState();
    // Inicializar o derivation path com base no valor padrão de _walletAddressType
    _updateDerivationPath();
  }

  void _updateResponse(String response, {bool isError = false}) {
    setState(() {
      _response = response;
      _isError = isError;
      _isLoading = false;
    });
  }

  // Converter o valor inteiro de _wordCount para o enum WordCount da biblioteca
  WordCount _getWordCountEnum() {
    switch (_wordCount) {
      case 12:
        return WordCount.words12;
      case 18:
        return WordCount.words18;
      case 24:
        return WordCount.words24;
      default:
        return WordCount.words12; // Padrão
    }
  }

  // Método para criar a carteira usando a biblioteca bdk_flutter
  Future<void> _createWallet() async {
    setState(() {
      _isLoading = true;
      _response = 'Criando carteira com $_wordCount palavras...';
      if (_usePassphrase && _passphraseController.text.isNotEmpty) {
        _response += '\nUtilizando frase de extensão adicional.';
      }
      _isError = false;
      _generatedMnemonic = null;
      _walletCreated = false;
    });

    try {
      // Gerar a frase mnemônica com o número de palavras escolhido
      final mnemonic = await Mnemonic.create(_getWordCountEnum());
      final mnemonicString = mnemonic.asString();
      _generatedMnemonic = mnemonicString;

      // Criar chave secreta do descriptor (agora com a passphrase quando necessário)
      final descriptorSecretKey = await DescriptorSecretKey.create(
        network: appConfig.networkType, // Usando a configuração global da rede
        mnemonic: mnemonic,
        password: _usePassphrase && _passphraseController.text.isNotEmpty ? _passphraseController.text : null,
      );

      // Definir derivation path de acordo com o tipo de carteira selecionado
      switch (_walletAddressType) {
        case 'native_segwit':
          _derivationPath = appConfig.networkType == Network.testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"; // BIP-84
          _walletType = "Native SegWit (BIP-84, endereços bc1 ou tb1)";
          break;
        case 'segwit_compatible':
          _derivationPath = appConfig.networkType == Network.testnet ? "m/49'/1'/0'" : "m/49'/0'/0'"; // BIP-49
          _walletType = "SegWit Compatível (BIP-49, endereços 3)";
          break;
        case 'legacy':
          _derivationPath = appConfig.networkType == Network.testnet ? "m/44'/1'/0'" : "m/44'/0'/0'"; // BIP-44
          _walletType = "Legacy (BIP-44, endereços 1)";
          break;
        default:
          _derivationPath = appConfig.networkType == Network.testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"; // Padrão: BIP-84
          _walletType = "Native SegWit (BIP-84, endereços bc1 ou tb1)";
      }

      try {
        // Extrair a chave pública mestra (xpub) seguindo o exemplo fornecido
        // 1. Criar o derivation path
        final derivationPath = await DerivationPath.create(path: _derivationPath);

        // 2. Derivar a chave secreta para o caminho especificado
        final derivedSecretKey = await descriptorSecretKey.derive(derivationPath);

        // 3. Obter a chave pública estendida (xpub)
        // Usando o método toPublic() disponível no lugar de asPublic()
        try {
          final descriptorPublicKey = derivedSecretKey.toPublic();
          String fullString = descriptorPublicKey.asString();

          // Extrair apenas a parte tpub/vpub da string completa
          final regexTpub = RegExp(r'(tpub|vpub|xpub|ypub|zpub|upub)[A-Za-z0-9]+');
          final matchTpub = regexTpub.firstMatch(fullString);

          if (matchTpub != null) {
            String extractedKey = matchTpub.group(0) ?? fullString;

            // Converter o formato da chave se necessário para corresponder ao formato da Electrum
            // Para BIP-84 testnet, Electrum usa vpub em vez de tpub
            if (_walletAddressType == 'native_segwit' && extractedKey.startsWith('tpub')) {
              _masterPublicKey = _convertTpubToVpub(extractedKey);
            }
            // Para BIP-49 testnet, Electrum usa upub em vez de tpub
            else if (_walletAddressType == 'segwit_compatible' && extractedKey.startsWith('tpub')) {
              _masterPublicKey = _convertTpubToUpub(extractedKey);
            } else {
              _masterPublicKey = extractedKey;
            }
          } else {
            _masterPublicKey = fullString;
          }
        } catch (e) {
          // Caso o método acima falhe, vamos tentar uma abordagem alternativa
          // Criar um descritor para obter indiretamente o xpub
          final descriptor = await _createDescriptorForWalletType(derivedSecretKey);
          final descriptorString = descriptor.asString();

          // Extrair apenas a parte tpub/vpub do descritor
          final regex = RegExp(r'(tpub|vpub|xpub|ypub|zpub|upub)[A-Za-z0-9]+');
          final match = regex.firstMatch(descriptorString);

          if (match != null) {
            _masterPublicKey = match.group(0) ?? "Não foi possível extrair o xpub";
          } else {
            _masterPublicKey = "Formato não reconhecido: $descriptorString";
          }
        }
      } catch (e) {
        _masterPublicKey = "Erro ao gerar chave pública: ${e.toString()}";
      }

      _masterPublicKeyController.text = _masterPublicKey;

      // Atualizar os controllers para mostrar as informações geradas
      _mnemonicController.text = mnemonicString;
      _derivationPathController.text = _derivationPath;
      _walletTypeController.text = _walletType;

      // Gerar o primeiro endereço da carteira
      try {
        // Criar o descritor apropriado para o tipo de carteira
        final descriptor = await _createDescriptorForWalletType(descriptorSecretKey);

        // Criar uma instância de carteira usando o descritor
        final wallet = await Wallet.create(
          descriptor: descriptor,
          network: Network.testnet,
          databaseConfig: const DatabaseConfig.memory(),
        );

        // Limpar a lista de endereços antes de gerar novos
        _receivingAddresses = [];

        // Gerar os endereços de recebimento (o número definido em _numAddressesToShow)
        try {
          for (int i = 0; i < _numAddressesToShow; i++) {
            // Usar AddressIndex.increase() para cada novo endereço
            // Para o primeiro endereço, também atualizamos _firstAddress para manter compatibilidade
            final addressInfo = wallet.getAddress(
              addressIndex: const AddressIndex.increase(),
            );

            final address = addressInfo.address.toString();
            _receivingAddresses.add(address);

            // Guardar o primeiro endereço separadamente para compatibilidade
            if (i == 0) {
              _firstAddress = address;
              _firstAddressController.text = _firstAddress;
            }
          }
        } catch (e) {
          print("Erro ao gerar endereços: $e");
          // Em caso de erro, adicionar uma mensagem
          _receivingAddresses.add("Erro ao gerar endereços: $e");
          _firstAddress = "Erro ao gerar endereços";
          _firstAddressController.text = _firstAddress;
        }
      } catch (e) {
        print("Erro ao criar wallet: $e");
        _firstAddress = "Erro ao criar wallet: $e";
        _firstAddressController.text = _firstAddress;
      }

      // Preparar mensagem de resposta
      String responseMessage = 'Carteira criada com sucesso!';
      if (_usePassphrase && _passphraseController.text.isNotEmpty) {
        responseMessage += ' Com proteção adicional de frase de extensão.';
      }

      setState(() {
        _walletCreated = true;
      });

      _updateResponse(responseMessage);
    } catch (e) {
      _updateResponse(
        'Erro ao criar carteira: $e',
        isError: true,
      );
    }
  }

  // Método auxiliar para criar o descritor correto com base no tipo de carteira
  Future<Descriptor> _createDescriptorForWalletType(DescriptorSecretKey derivedSecretKey) async {
    switch (_walletAddressType) {
      case 'native_segwit':
        // BIP-84 para Native SegWit
        return await Descriptor.newBip84(
          secretKey: derivedSecretKey,
          network: appConfig.networkType,
          keychain: KeychainKind.externalChain,
        );
      case 'segwit_compatible':
        // BIP-49 para SegWit Compatível
        return await Descriptor.newBip49(
          secretKey: derivedSecretKey,
          network: appConfig.networkType,
          keychain: KeychainKind.externalChain,
        );
      case 'legacy':
        // BIP-44 para Legacy
        return await Descriptor.newBip44(
          secretKey: derivedSecretKey,
          network: appConfig.networkType,
          keychain: KeychainKind.externalChain,
        );
      default:
        // Padrão para Native SegWit
        return await Descriptor.newBip84(
          secretKey: derivedSecretKey,
          network: appConfig.networkType,
          keychain: KeychainKind.externalChain,
        );
    }
  }

  // Método para converter tpub para vpub (para BIP-84 testnet)
  String _convertTpubToVpub(String tpub) {
    if (!tpub.startsWith('tpub')) {
      return tpub; // Retorna sem modificação se não for tpub
    }

    // A Electrum usa uma versão diferente do formato BIP-32 para derivar seus xpubs
    // Vamos tentar fazer um hash consistente da chave para gerar um formato compatível

    // Remover o prefixo 'tpub'
    String keyPart = tpub.substring(4);

    // Prefixar com 'vpub' para BIP-84 testnet
    return 'vpub$keyPart';
  }

  // Método para converter tpub para upub (para BIP-49 testnet)
  String _convertTpubToUpub(String tpub) {
    if (!tpub.startsWith('tpub')) {
      return tpub; // Retorna sem modificação se não for tpub
    }

    // Remover o prefixo 'tpub'
    String keyPart = tpub.substring(4);

    // Prefixar com 'upub' para BIP-49 testnet
    return 'upub$keyPart';
  }

  // Método para garantir formatação correta do caminho de derivação
  String _formatDerivationPath(String path) {
    // Converter notação com h para notação com '
    // Exemplo: m/84h/1h/0h -> m/84'/1'/0'
    path = path.replaceAll('h', "'");

    // Se alguém tentar usar notação com H, também converter
    path = path.replaceAll('H', "'");

    return path;
  }

  // Método para copiar texto para a área de transferência
  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Método para atualizar o derivation path com base no tipo de carteira selecionado
  void _updateDerivationPath() {
    setState(() {
      switch (_walletAddressType) {
        case 'native_segwit':
          _derivationPath = "m/84h/1h/0h"; // BIP-84 para testnet
          break;
        case 'segwit_compatible':
          _derivationPath = "m/49h/1h/0h"; // BIP-49 para testnet
          break;
        case 'legacy':
          _derivationPath = "m/44h/1h/0h"; // BIP-44 para testnet
          break;
        default:
          _derivationPath = "m/84h/1h/0h"; // Padrão: BIP-84 para testnet
      }
    });
  }

  // Método para obter o derivation path atual
  String _getCurrentDerivationPath() {
    return _derivationPath;
  }

  // Método para extrair chaves públicas mestras em diferentes formatos
  Future<Map<String, String>> _extractMasterPublicKeysInDifferentFormats(
      DescriptorSecretKey descriptorSecretKey, String mnemonicString) async {
    Map<String, String> result = {};

    try {
      // Gerar chave para a Electrum Wallet (BIP-84 para Native SegWit)
      final electrumPath = await DerivationPath.create(path: "m/84'/1'/0'");
      final electrumDerivedKey = await descriptorSecretKey.derive(electrumPath);
      final electrumPublicKey = electrumDerivedKey.toPublic();
      String electrumXpub = electrumPublicKey.asString();

      // Extrair apenas a parte tpub/vpub
      final regexElectrum = RegExp(r'(tpub|vpub)[A-Za-z0-9]+');
      final matchElectrum = regexElectrum.firstMatch(electrumXpub);
      if (matchElectrum != null) {
        String extractedElectrumKey = matchElectrum.group(0) ?? electrumXpub;
        result['electrum'] = _convertTpubToVpub(extractedElectrumKey);
      }

      // Gerar chave para a Blue Wallet (pode usar outra derivação)
      final bluePath = await DerivationPath.create(path: "m/84'/0'/0'"); // Blue Wallet pode usar mainnet
      final blueDerivedKey = await descriptorSecretKey.derive(bluePath);
      final bluePublicKey = blueDerivedKey.toPublic();
      String blueXpub = bluePublicKey.asString();

      // Extrair apenas a parte tpub/zpub
      final regexBlue = RegExp(r'(tpub|vpub|xpub)[A-Za-z0-9]+');
      final matchBlue = regexBlue.firstMatch(blueXpub);
      if (matchBlue != null) {
        String extractedBlueKey = matchBlue.group(0) ?? blueXpub;
        // Convertendo para zpub para Blue Wallet (mainnet)
        result['blue'] = _convertForBlueWallet(extractedBlueKey);
      }

      // Manter a chave padrão para nosso app
      final appPath = await DerivationPath.create(path: _derivationPath);
      final appDerivedKey = await descriptorSecretKey.derive(appPath);
      final appPublicKey = appDerivedKey.toPublic();
      String appXpub = appPublicKey.asString();

      final regexApp = RegExp(r'(tpub|vpub)[A-Za-z0-9]+');
      final matchApp = regexApp.firstMatch(appXpub);
      if (matchApp != null) {
        String extractedAppKey = matchApp.group(0) ?? appXpub;
        if (_walletAddressType == 'native_segwit') {
          result['app'] = _convertTpubToVpub(extractedAppKey);
        } else if (_walletAddressType == 'segwit_compatible') {
          result['app'] = _convertTpubToUpub(extractedAppKey);
        } else {
          result['app'] = extractedAppKey;
        }
      }

      // Adicionar informações para debug
      result['mnemonic'] = mnemonicString;
      result['derivation_path'] = _derivationPath;
    } catch (e) {
      result['error'] = e.toString();
    }

    return result;
  }

  // Método para converter tpub para formato Blue Wallet (zpub para mainnet BIP-84)
  String _convertForBlueWallet(String key) {
    if (key.startsWith('tpub')) {
      return 'zpub${key.substring(4)}';
    } else if (key.startsWith('vpub')) {
      return 'zpub${key.substring(4)}';
    } else if (key.startsWith('xpub')) {
      return 'zpub${key.substring(4)}';
    }
    return key;
  }

  // Método para salvar a carteira atual
  Future<void> _saveWallet() async {
    // Verificar se há uma carteira para salvar
    if (!_walletCreated || _generatedMnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primeiro crie uma carteira para poder salvá-la')),
      );
      return;
    }
    
    // Verificar se o nome da carteira foi preenchido
    if (_walletNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, dê um nome para sua carteira antes de salvar')),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Criar o objeto BitcoinWallet com todas as informações necessárias
      final bitcoinWallet = BitcoinWallet(
        name: _walletNameController.text.trim(),
        mnemonic: _mnemonicController.text,
        derivationPath: _derivationPathController.text,
        walletType: _walletTypeController.text,
        masterPublicKey: _masterPublicKeyController.text,
        addresses: List<String>.from(_receivingAddresses), // Cria uma cópia da lista de endereços
        hasPassphrase: _usePassphrase,
        passphrase: _usePassphrase ? _passphraseController.text : null,
        networkType: appConfig.networkType, // Usando a configuração global da rede
      );
      
      // Salvar a carteira usando o serviço de armazenamento
      final walletId = await _walletStorage.saveWallet(bitcoinWallet);
      
      // Armazenar o ID da carteira salva
      setState(() {
        _walletId = walletId;
        _isSaving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Carteira "${bitcoinWallet.name}" salva com sucesso! Rede: ${bitcoinWallet.networkType == Network.testnet ? 'Testnet' : 'Mainnet'}')),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar carteira: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Carteira Bitcoin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Ícone de disquete (salvar) na AppBar com funcionalidade de salvamento
          _isSaving 
            ? Container(
                margin: const EdgeInsets.all(14),
                width: 20,
                height: 20,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Salvar carteira',
                onPressed: _saveWallet, // Chamando o método de salvamento
              ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponseContainer(
                  response: _response,
                  isError: _isError,
                ),

                const SizedBox(height: 20),

                // Seção de criação de carteira (visível antes da criação)
                if (!_walletCreated) ...[
                  const Text(
                    'Criar Nova Carteira Bitcoin',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Dropdown para seleção do número de palavras
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text(
                          'Número de palavras:',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<int>(
                            value: _wordCount,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down),
                            underline: const SizedBox(),
                            onChanged: (int? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _wordCount = newValue;
                                });
                              }
                            },
                            items: const [
                              DropdownMenuItem<int>(
                                value: 12,
                                child: Text('12 palavras (padrão)'),
                              ),
                              DropdownMenuItem<int>(
                                value: 18,
                                child: Text('18 palavras (mais seguro)'),
                              ),
                              DropdownMenuItem<int>(
                                value: 24,
                                child: Text('24 palavras (máxima segurança)'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Checkbox para adicionar frase de extensão
                  CheckboxListTile(
                    title: const Text('Adicionar frase de extensão (opcional)'),
                    subtitle: const Text('Aumenta a segurança da carteira com uma senha adicional'),
                    value: _usePassphrase,
                    onChanged: (value) {
                      setState(() {
                        _usePassphrase = value ?? false;

                        // Limpar o conteúdo do controller quando o checkbox for desmarcado
                        if (!_usePassphrase) {
                          _passphraseController.clear();
                        }
                      });
                    },
                  ),

                  // Campo de texto para frase de extensão (visível apenas quando o checkbox estiver marcado)
                  if (_usePassphrase)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextField(
                        controller: _passphraseController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Frase de extensão',
                          hintText: 'Digite uma senha adicional para aumentar a segurança',
                        ),
                        obscureText: true,
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Dropdown para seleção do tipo de carteira
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Tipo de Carteira:',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            children: [
                              // Opção Native SegWit
                              RadioListTile<String>(
                                title: const Text(
                                  'Native SegWit (BIP-84, endereços bc1 ou tb1)',
                                  style: TextStyle(fontSize: 13),
                                ),
                                value: 'native_segwit',
                                groupValue: _walletAddressType,
                                onChanged: (value) {
                                  setState(() {
                                    _walletAddressType = value!;
                                    _updateDerivationPath(); // Atualizar o derivation path quando mudar a seleção
                                  });
                                },
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              const Divider(height: 1, thickness: 1),
                              // Opção SegWit Compatível
                              RadioListTile<String>(
                                title: const Text(
                                  'SegWit Compatível (BIP-49, endereços 3)',
                                  style: TextStyle(fontSize: 13),
                                ),
                                value: 'segwit_compatible',
                                groupValue: _walletAddressType,
                                onChanged: (value) {
                                  setState(() {
                                    _walletAddressType = value!;
                                    _updateDerivationPath(); // Atualizar o derivation path quando mudar a seleção
                                  });
                                },
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              const Divider(height: 1, thickness: 1),
                              // Opção Legacy
                              RadioListTile<String>(
                                title: const Text(
                                  'Legacy (BIP-44, endereços 1)',
                                  style: TextStyle(fontSize: 13),
                                ),
                                value: 'legacy',
                                groupValue: _walletAddressType,
                                onChanged: (value) {
                                  setState(() {
                                    _walletAddressType = value!;
                                    _updateDerivationPath(); // Atualizar o derivation path quando mudar a seleção
                                  });
                                },
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              // Campo para mostrar o derivation path atualizado (agora editável)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Derivation Path:',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    TextFormField(
                                      readOnly: false, // Tornando editável
                                      controller: TextEditingController(text: _derivationPath),
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade200,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        isDense: true,
                                        hintText: 'Ex: m/84h/1h/0h',
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _derivationPath = value;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  const SizedBox(height: 20),

                  // Campo para o nome da carteira
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nome da carteira:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _walletNameController,
                        decoration: InputDecoration(
                          hintText: 'Ex: Minha Carteira Bitcoin',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _createWallet,
                    child: _isLoading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Criando...'),
                            ],
                          )
                        : const Text('Criar Nova Carteira'),
                  ),
                ],

                // Seção de exibição da carteira criada (visível após a criação)
                if (_walletCreated) ...[
                  const Text(
                    'Sua carteira foi criada!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'IMPORTANTE: Guarde estas informações em um local seguro. Esta é a única forma de recuperar sua carteira.',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 20),

                  // Bloco para mostrar a seed mnemônica
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Frase de recuperação:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () =>
                                _copyToClipboard(_mnemonicController.text, 'Frase de recuperação copiada!'),
                            tooltip: 'Copiar frase',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _mnemonicController,
                        readOnly: true,
                        maxLines: null,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onTap: () => _copyToClipboard(_mnemonicController.text, 'Frase de recuperação copiada!'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Informações do tipo de carteira
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Tipo de carteira:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                Expanded(
                                  child: IconButton(
                                    icon: const Icon(Icons.copy, size: 20),
                                    onPressed: () =>
                                        _copyToClipboard(_walletTypeController.text, 'Tipo de carteira copiado!'),
                                    tooltip: 'Copiar tipo',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              maxLines: 5,
                              controller: _walletTypeController,
                              readOnly: true,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              onTap: () => _copyToClipboard(_walletTypeController.text, 'Tipo de carteira copiado!'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Derivation Path:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 20),
                                  onPressed: () =>
                                      _copyToClipboard(_derivationPathController.text, 'Derivation path copiado!'),
                                  tooltip: 'Copiar path',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              maxLines: 5,
                              controller: _derivationPathController,
                              readOnly: true,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              onTap: () => _copyToClipboard(_derivationPathController.text, 'Derivation path copiado!'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Bloco para mostrar a chave pública mestra (xpub)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Chave Pública Mestra (xpub):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () =>
                                _copyToClipboard(_masterPublicKeyController.text, 'Chave pública mestra copiada!'),
                            tooltip: 'Copiar chave pública',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _masterPublicKeyController,
                        readOnly: true,
                        maxLines: 3,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onTap: () => _copyToClipboard(_masterPublicKeyController.text, 'Chave pública mestra copiada!'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Bloco para mostrar o primeiro endereço Bitcoin
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Endereços de Recebimento (Testnet):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () async {
                              if (_generatedMnemonic != null) {
                                // Recria a carteira para gerar novos endereços
                                final mnemonic = await Mnemonic.fromString(_generatedMnemonic!);
                                final descriptorSecretKey = await DescriptorSecretKey.create(
                                  network: Network.testnet,
                                  mnemonic: mnemonic,
                                  password: _usePassphrase ? _passphraseController.text : null,
                                );

                                // Criar o descritor apropriado para o tipo de carteira
                                final descriptor = await _createDescriptorForWalletType(descriptorSecretKey);

                                // Criar uma instância de carteira usando o descritor
                                final wallet = await Wallet.create(
                                  descriptor: descriptor,
                                  network: Network.testnet,
                                  databaseConfig: const DatabaseConfig.memory(),
                                );

                                // Limpar a lista de endereços antes de gerar novos
                                _receivingAddresses = [];

                                // Gerar novos endereços
                                try {
                                  for (int i = 0; i < _numAddressesToShow; i++) {
                                    final addressInfo = wallet.getAddress(
                                      addressIndex: const AddressIndex.increase(),
                                    );
                                    final address = addressInfo.address.toString();
                                    _receivingAddresses.add(address);

                                    // Atualizar o primeiro endereço no controller
                                    if (i == 0) {
                                      _firstAddress = address;
                                      _firstAddressController.text = _firstAddress;
                                    }
                                  }
                                  setState(() {}); // Atualizar UI
                                } catch (e) {
                                  print("Erro ao gerar novos endereços: $e");
                                }
                              }
                            },
                            tooltip: 'Gerar novos endereços',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Lista de endereços
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < _receivingAddresses.length; i++)
                              Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    title: Text(
                                      'Endereço #${i + 1}:',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _receivingAddresses[i],
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () => _copyToClipboard(
                                        _receivingAddresses[i],
                                        'Endereço #${i + 1} copiado!',
                                      ),
                                    ),
                                    onTap: () => _copyToClipboard(
                                      _receivingAddresses[i],
                                      'Endereço #${i + 1} copiado!',
                                    ),
                                  ),
                                  if (i < _receivingAddresses.length - 1) const Divider(height: 1),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Botão para criar uma nova carteira
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _walletCreated = false;
                        _response = '';
                        _isError = false;
                      });
                    },
                    child: const Text('Criar outra carteira'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
