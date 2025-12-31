import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/bitcoin_wallet.dart';

class ReceiveBitcoinScreen extends StatefulWidget {
  final BitcoinWallet wallet;

  const ReceiveBitcoinScreen({super.key, required this.wallet});

  @override
  State<ReceiveBitcoinScreen> createState() => _ReceiveBitcoinScreenState();
}

class _ReceiveBitcoinScreenState extends State<ReceiveBitcoinScreen> {
  String _selectedAddress = '';
  int _selectedAddressIndex = 0;
  bool _showCopiedMessage = false;

  @override
  void initState() {
    super.initState();
    // Seleciona o primeiro endereço por padrão, se disponível
    if (widget.wallet.addresses.isNotEmpty) {
      _selectedAddress = widget.wallet.addresses.first;
    }
  }

  void _copyToClipboard() {
    if (_selectedAddress.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _selectedAddress));
      setState(() {
        _showCopiedMessage = true;
      });

      // Oculta a mensagem de copiado após 2 segundos
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showCopiedMessage = false;
          });
        }
      });
    }
  }

  void _changeAddress(int index) {
    if (index >= 0 && index < widget.wallet.addresses.length) {
      setState(() {
        _selectedAddressIndex = index;
        _selectedAddress = widget.wallet.addresses[index];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receber Bitcoin'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: widget.wallet.addresses.isEmpty
          ? const Center(
              child: Text(
                'Esta carteira não possui endereços disponíveis.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Text(
                              widget.wallet.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.2),
                                    spreadRadius: 2,
                                    blurRadius: 5,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: _selectedAddress,
                                version: QrVersions.auto,
                                size: 220,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Seu endereço Bitcoin',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedAddress,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _showCopiedMessage ? Icons.check : Icons.copy,
                                      color: _showCopiedMessage ? Colors.green : Colors.blue.shade800,
                                    ),
                                    onPressed: _copyToClipboard,
                                    tooltip: 'Copiar endereço',
                                  ),
                                ],
                              ),
                            ),
                            if (_showCopiedMessage)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Endereço copiado!',
                                  style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    if (widget.wallet.addresses.length > 1) ...[
                      const Text(
                        'Outros endereços disponíveis',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: widget.wallet.addresses.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final address = widget.wallet.addresses[index];
                            final isSelected = index == _selectedAddressIndex;
                            
                            return ListTile(
                              title: Text(
                                address,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Endereço ${index + 1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: isSelected,
                              selectedTileColor: Colors.blue.shade50,
                              trailing: isSelected 
                                ? Icon(Icons.check_circle, color: Colors.blue.shade800)
                                : null,
                              onTap: () => _changeAddress(index),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    const Card(
                      elevation: 0,
                      color: Color(0xFFF5F5F5),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 28,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Compartilhe este endereço com quem deseja lhe enviar bitcoins. '
                              'Cada endereço pode ser utilizado para receber múltiplos pagamentos.',
                              style: TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
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