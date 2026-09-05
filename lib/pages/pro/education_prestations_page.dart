import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';

// ── Catalogue de cours (éducateur/comportementaliste) — remplace la liste
// fixe (cours individuel/évaluation/autre) : le pro définit ses propres
// types de cours (nom + durée), choisis par la famille dans le calendrier de
// réservation (education_reservation_page.dart). Même modèle que
// photographe_prestations_page.dart / toilettage_prestations_page.dart.

class EducationPrestationsPage extends StatefulWidget {
  const EducationPrestationsPage({super.key});

  @override
  State<EducationPrestationsPage> createState() => _EducationPrestationsPageState();
}

class _EducationPrestationsPageState extends State<EducationPrestationsPage> {
  static const _purple = Color(0xFF7B5EA7);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _prestations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      var q = _supa.from('prestations_education').select().eq('pro_uid', uid).eq('actif', true);
      if (User_Info.activeProfileId.isNotEmpty) q = q.eq('pro_profile_id', User_Info.activeProfileId);
      final rows = await q.order('ordre').order('created_at');
      if (mounted) setState(() { _prestations = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _supprimer(String id) async {
    await _supa.from('prestations_education').update({'actif': false}).eq('id', id);
    await _load();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PrestationForm(existing: existing),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: const Text('Mes cours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _purple,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : _prestations.isEmpty
              ? const Center(child: Text('Aucun cours configuré.\nAjoutez-en un avec le bouton +\n(ex : "Rappel chiot", "Cours avancé"…)',
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prestations.length,
                  itemBuilder: (_, i) {
                    final p = _prestations[i];
                    final prix = (p['prix'] as num?)?.toDouble();
                    final bilan = p['bilan_requis'] == true;
                    final domicile = p['domicile_ok'] != false;
                    final collectif = p['type'] == 'collectif';
                    final capacite = (p['capacite_max'] as num?)?.toInt();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        onTap: () => _openForm(existing: p),
                        title: Row(children: [
                          Icon(collectif ? Icons.groups_outlined : Icons.school_outlined, size: 16, color: _purple),
                          const SizedBox(width: 6),
                          Expanded(child: Text(p['nom']?.toString() ?? '',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                        ]),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${collectif ? 'Collectif (max ${capacite ?? 6})' : 'Individuel'} · ${p['duree_minutes']} min'
                                  '${prix != null ? ' · ${prix.toStringAsFixed(0)} €' : ''}',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            _tag(bilan ? 'Bilan requis' : 'Sans bilan', bilan),
                            _tag(domicile ? 'À domicile possible' : 'Chez le pro uniquement', domicile),
                          ]),
                        ]),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _supprimer(p['id'].toString()),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _tag(String label, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: active ? _purple.withValues(alpha: 0.1) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
        color: active ? _purple : Colors.grey.shade500)),
  );
}

class _PrestationForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PrestationForm({this.existing});

  @override
  State<_PrestationForm> createState() => _PrestationFormState();
}

class _PrestationFormState extends State<_PrestationForm> {
  static const _purple = Color(0xFF7B5EA7);
  final _supa = Supabase.instance.client;

  late final TextEditingController _nomCtrl;
  late final TextEditingController _dureeCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _capaciteCtrl;
  late final TextEditingController _lieuCtrl;
  double? _lieuLat, _lieuLng;
  late bool _bilanRequis;
  late bool _domicileOk;
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nomCtrl = TextEditingController(text: e?['nom']?.toString() ?? '');
    _dureeCtrl = TextEditingController(text: (e?['duree_minutes'] as num?)?.toString() ?? '60');
    _prixCtrl = TextEditingController(text: (e?['prix'] as num?)?.toString() ?? '');
    _descCtrl = TextEditingController(text: e?['description']?.toString() ?? '');
    _capaciteCtrl = TextEditingController(text: (e?['capacite_max'] as num?)?.toString() ?? '6');
    _lieuCtrl = TextEditingController(text: e?['lieu_adresse']?.toString() ?? '');
    _lieuLat = (e?['lieu_lat'] as num?)?.toDouble();
    _lieuLng = (e?['lieu_lng'] as num?)?.toDouble();
    _bilanRequis = e?['bilan_requis'] == true;
    _domicileOk = e?['domicile_ok'] != false;
    _type = e?['type']?.toString() ?? 'individuel';
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _dureeCtrl, _prixCtrl, _descCtrl, _capaciteCtrl, _lieuCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Donnez un nom à ce cours.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _saving = false); return; }
    try {
      // Géocode l'adresse du cours si elle a changé.
      final lieu = _lieuCtrl.text.trim();
      if (lieu.isEmpty) {
        _lieuLat = null; _lieuLng = null;
      } else if (lieu != (widget.existing?['lieu_adresse']?.toString() ?? '') || _lieuLat == null) {
        final geo = await GeocodingHelper.geocode(lieu);
        _lieuLat = geo?.lat;
        _lieuLng = geo?.lng;
      }
      final data = {
        'pro_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
        'nom': _nomCtrl.text.trim(),
        'type': _type,
        'duree_minutes': int.tryParse(_dureeCtrl.text.trim()) ?? 60,
        'prix': double.tryParse(_prixCtrl.text.trim()),
        'bilan_requis': _bilanRequis,
        'domicile_ok': _domicileOk,
        if (_type == 'collectif') 'capacite_max': int.tryParse(_capaciteCtrl.text.trim()) ?? 6,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        'lieu_adresse': lieu.isEmpty ? null : lieu,
        'lieu_lat': _lieuLat,
        'lieu_lng': _lieuLng,
      };
      if (widget.existing != null) {
        await _supa.from('prestations_education').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('prestations_education').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  // Interrupteur toujours visible (fond + bordure colorés à l'état actif) —
  // un Switch seul se voit mal sur fond blanc quand il est désactivé.
  Widget _toggleCard({required bool value, required ValueChanged<bool> onChanged, required String label, required String hint}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? _purple.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? _purple : Colors.grey.shade300),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
              color: value ? _purple : Colors.black87)),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ])),
        const SizedBox(width: 8),
        Switch(value: value, activeThumbColor: _purple, onChanged: onChanged),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? type}) => TextField(
    controller: ctrl,
    keyboardType: type,
    style: const TextStyle(fontFamily: 'Galey'),
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing != null ? 'Modifier le cours' : 'Nouveau cours',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Row(children: [
            for (final t in [('individuel', '🎓 Individuel'), ('collectif', '👥 Collectif')])
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: t.$1 == 'individuel' ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _type = t.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _type == t.$1 ? _purple.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _type == t.$1 ? _purple : Colors.grey.shade300, width: _type == t.$1 ? 2 : 1),
                    ),
                    child: Center(child: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        color: _type == t.$1 ? _purple : Colors.grey.shade600))),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 12),
          _field(_nomCtrl, 'Nom du cours', ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_dureeCtrl, 'Durée (min)', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_prixCtrl, 'Prix (€, optionnel)', type: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          if (_type == 'collectif') ...[
            const SizedBox(height: 12),
            _field(_capaciteCtrl, 'Capacité max', type: TextInputType.number),
          ],
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Description (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _lieuCtrl, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(
                labelText: 'Lieu du cours (adresse, optionnel)',
                helperText: 'Ex. « Parc de la Tête d\'Or, Lyon ». Laissez vide = à votre cabinet.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              )),
          const SizedBox(height: 10),
          _toggleCard(
            value: _bilanRequis,
            onChanged: (v) => setState(() => _bilanRequis = v),
            label: 'Nécessite un bilan préalable',
            hint: 'Proposé en priorité aux nouvelles familles si l\'option "Bilan obligatoire" est activée',
          ),
          const SizedBox(height: 8),
          _toggleCard(
            value: _domicileOk,
            onChanged: (v) => setState(() => _domicileOk = v),
            label: 'Peut être proposé à domicile',
            hint: 'La famille pourra le demander à domicile sur les créneaux que vous autorisez',
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _purple, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(widget.existing != null ? 'Enregistrer' : 'Créer le cours',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
  }
}
