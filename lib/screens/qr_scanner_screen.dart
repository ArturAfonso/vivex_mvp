import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late MobileScannerController _controller;
  bool _isScanning = true;
  bool _hasFlash = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    // Verificar se o dispositivo tem flash
    if (mounted) {
      setState(() {
        _hasFlash = _controller.hasTorch;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR Code'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          if (_hasFlash)
            IconButton(
              icon: Icon(_isTorchOn ? Icons.flash_off : Icons.flash_on),
              onPressed: () {
                setState(() {
                  _isTorchOn = !_isTorchOn;
                  _controller.toggleTorch();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Scanner
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty && _isScanning) {
                      final barcode = barcodes.first;
                      final String? code = barcode.rawValue;
                      
                      if (code != null) {
                        setState(() {
                          _isScanning = false;
                        });
                        
                        // Retornar o valor escaneado para a tela anterior
                        Navigator.of(context).pop(code);
                      }
                    }
                  },
                ),
                
                // Moldura de escaneamento
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  width: 280,
                  height: 280,
                ),
                
                // Mensagem de orientação
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    color: Colors.blue.withOpacity(0.8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      child: Text(
                        'Posicione a câmera sobre o QR code do endereço Bitcoin',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Botão de cancelar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Cancelar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}