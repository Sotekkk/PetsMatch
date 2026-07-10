part of 'creation_flow_page.dart';

/// Bottom sheet d'édition d'un point d'intérêt (titre, description, rayon, défi).
/// Retourne la Map du point mise à jour via Navigator.pop, ou null si annulé.
Future<Map<String, dynamic>?> showPointDefiSheet(BuildContext context, Map<String, dynamic> point) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PointDefiSheet(point: Map<String, dynamic>.from(point)),
  );
}

class _PointDefiSheet extends StatefulWidget {
  final Map<String, dynamic> point;
  const _PointDefiSheet({required this.point});

  @override
  State<_PointDefiSheet> createState() => _PointDefiSheetState();
}

class _PointDefiSheetState extends State<_PointDefiSheet> {
  late final _titreCtrl = TextEditingController(text: widget.point['titre'] ?? '');
  late final _descCtrl = TextEditingController(text: widget.point['description'] ?? '');
  late final _rayonCtrl = TextEditingController(text: (widget.point['rayon_validation_m'] ?? 30).toString());
  late final _questionCtrl = TextEditingController(text: widget.point['question_texte'] ?? '');
  late final _reponseCtrl = TextEditingController(text: widget.point['question_reponse'] ?? '');
  late final _consigneCtrl = TextEditingController(text: widget.point['consigne_texte'] ?? '');
  late final _qrCtrl = TextEditingController(text: widget.point['qr_code_value'] ?? _genererCodeQr());
  late final _indiceCtrl = TextEditingController(text: widget.point['indice'] ?? '');
  late String _typeDefi = widget.point['type_defi'] ?? 'photo';

  static String _genererCodeQr() {
    final r = DateTime.now().millisecondsSinceEpoch;
    return 'BL-$r';
  }

  void _save() {
    if (_titreCtrl.text.trim().isEmpty) return;
    final updated = Map<String, dynamic>.from(widget.point)
      ..['titre'] = _titreCtrl.text.trim()
      ..['description'] = _descCtrl.text.trim()
      ..['rayon_validation_m'] = int.tryParse(_rayonCtrl.text) ?? 30
      ..['type_defi'] = _typeDefi
      ..['question_texte'] = _typeDefi == 'question' ? _questionCtrl.text.trim() : null
      ..['question_reponse'] = _typeDefi == 'question' ? _reponseCtrl.text.trim() : null
      ..['consigne_texte'] = (_typeDefi == 'objet_nature' || _typeDefi == 'action_animal') ? _consigneCtrl.text.trim() : null
      ..['qr_code_value'] = _typeDefi == 'qr_code' ? _qrCtrl.text.trim() : null
      ..['indice'] = _indiceCtrl.text.trim().isEmpty ? null : _indiceCtrl.text.trim();
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(controller: scrollCtrl, padding: const EdgeInsets.all(20), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Point d\'intérêt', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          TextField(controller: _titreCtrl, style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(labelText: 'Titre de l\'étape', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(labelText: 'Description', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: _rayonCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(labelText: 'Rayon de validation GPS (m)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 16),
          const Text('Type de défi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: kBlTypesDefi.map((t) => GestureDetector(
            onTap: () => setState(() => _typeDefi = t.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _typeDefi == t.$1 ? kBlTeal : Colors.white,
                border: Border.all(color: _typeDefi == t.$1 ? kBlTeal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(t.$3, size: 14, color: _typeDefi == t.$1 ? Colors.white : kBlDark),
                const SizedBox(width: 5),
                Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _typeDefi == t.$1 ? Colors.white : kBlDark)),
              ]),
            ),
          )).toList()),
          const SizedBox(height: 16),
          if (_typeDefi == 'question') ...[
            TextField(controller: _questionCtrl, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(labelText: 'Question posée', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: _reponseCtrl, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(labelText: 'Réponse attendue', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ],
          if (_typeDefi == 'objet_nature' || _typeDefi == 'action_animal')
            TextField(controller: _consigneCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(
                  labelText: _typeDefi == 'objet_nature' ? 'Objet / élément à trouver' : 'Action à réaliser avec son animal',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                )),
          if (_typeDefi == 'qr_code') ...[
            TextField(controller: _qrCtrl, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(labelText: 'Code du QR (à imprimer sur le terrain)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 10),
            Center(child: QrImageView(data: _qrCtrl.text, size: 140)),
          ],
          if (_typeDefi == 'photo')
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Le joueur devra prendre une photo pour valider l\'étape.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))),
          if (_typeDefi == 'gps_seul')
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Validation automatique par proximité GPS uniquement.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 16),
          TextField(controller: _indiceCtrl, style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(labelText: 'Indice (optionnel)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(backgroundColor: kBlTeal, padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Enregistrer le point', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
