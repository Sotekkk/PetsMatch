import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../balades_ludiques_shared.dart';

class DefiQrWidget extends StatefulWidget {
  final String qrCodeValeurAttendue;
  final Future<void> Function(String valeurScannee) onValidated;

  const DefiQrWidget({super.key, required this.qrCodeValeurAttendue, required this.onValidated});

  @override
  State<DefiQrWidget> createState() => _DefiQrWidgetState();
}

class _DefiQrWidgetState extends State<DefiQrWidget> {
  bool _erreur = false;
  bool _busy = false;

  Future<void> _scanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (result == null) return;
    if (result.trim() != widget.qrCodeValeurAttendue.trim()) {
      setState(() => _erreur = true);
      return;
    }
    setState(() { _erreur = false; _busy = true; });
    await widget.onValidated(result.trim());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Scannez le QR code présent sur le terrain pour valider cette étape.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.4)),
      if (_erreur) const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Ce QR code ne correspond pas à cette étape.', style: TextStyle(fontFamily: 'Galey', color: Colors.red, fontSize: 12)),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _scanner,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.qr_code_scanner, color: Colors.white),
          label: const Text('Scanner le QR code', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: kBlOrange, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
    ]);
  }
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner le QR code', style: TextStyle(fontFamily: 'Galey')),
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_handled) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final value = barcodes.first.rawValue;
          if (value == null) return;
          _handled = true;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}
