import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/services/gamification_service.dart';

/// Formulaire minimal (Phase 1) pour enregistrer une balade et alimenter la
/// boucle flamme + XP/palier de l'animal. Ouvert depuis la fiche animal.
class EnregistrerBaladePage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final String espece;

  const EnregistrerBaladePage({
    super.key,
    required this.animalId,
    required this.animalNom,
    required this.espece,
  });

  @override
  State<EnregistrerBaladePage> createState() => _EnregistrerBaladePageState();
}

class _EnregistrerBaladePageState extends State<EnregistrerBaladePage> {
  static const _teal = Color(0xFF0C5C6C);

  final _distanceCtrl = TextEditingController();
  final _dureeCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _dureeCtrl.dispose();
    super.dispose();
  }

  double? get _distance => double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '.'));
  int? get _duree => int.tryParse(_dureeCtrl.text.trim());

  Future<void> _submit() async {
    final distance = _distance;
    final duree = _duree;
    if ((distance == null || distance <= 0) && (duree == null || duree <= 0)) {
      setState(() => _error = 'Indiquez une distance ou une durée.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final result = await GamificationService.instance.recordBalade(
        uid: User_Info.uid,
        profileId: User_Info.activeProfileId,
        animalId: widget.animalId,
        espece: widget.espece,
        distanceKm: (distance != null && distance > 0) ? distance : null,
        dureeMinutes: (duree != null && duree > 0) ? duree : null,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = "Impossible d'enregistrer la balade."; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Balade avec ${widget.animalNom}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🚶 Renseignez la distance ou la durée de la balade.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.black54)),
          const SizedBox(height: 20),
          TextField(
            controller: _distanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Distance (km)',
              labelStyle: const TextStyle(fontFamily: 'Galey'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _dureeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Durée (minutes)',
              labelStyle: const TextStyle(fontFamily: 'Galey'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontFamily: 'Galey', color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer la balade',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
