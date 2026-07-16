import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Prestations & tarifs (photographe animalier) — catalogue configuré par
// le pro, choisi par le client lors de la réservation (rdv_booking_page.dart,
// flag isPhotographe).

const kTypesPrestation = <String, String>{
  'shooting_individuel': 'Shooting individuel',
  'portee': 'Portée',
  'elevage': 'Élevage',
  'naissance': 'Naissance',
  'concours': 'Concours',
  'exposition': 'Exposition',
  'commercial': 'Photos commerciales',
};

class PhotographePrestationsPage extends StatefulWidget {
  const PhotographePrestationsPage({super.key});

  @override
  State<PhotographePrestationsPage> createState() => _PhotographePrestationsPageState();
}

class _PhotographePrestationsPageState extends State<PhotographePrestationsPage> {
  static const _teal = Color(0xFF90A4AE);
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
      final rows = await _supa.from('prestations_photographe').select()
          .eq('pro_uid', uid).eq('actif', true).order('created_at');
      if (mounted) setState(() { _prestations = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _supprimer(String id) async {
    await _supa.from('prestations_photographe').update({'actif': false}).eq('id', id);
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
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes prestations', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _teal,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _prestations.isEmpty
              ? const Center(child: Text('Aucune prestation configurée.\nAjoutez-en une avec le bouton +',
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prestations.length,
                  itemBuilder: (_, i) {
                    final p = _prestations[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        onTap: () => _openForm(existing: p),
                        title: Text(p['nom']?.toString() ?? '',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(
                            '${kTypesPrestation[p['type']] ?? p['type']} · ${((p['prix'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} € · ${p['duree_minutes']} min',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
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
}

class _PrestationForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PrestationForm({this.existing});

  @override
  State<_PrestationForm> createState() => _PrestationFormState();
}

class _PrestationFormState extends State<_PrestationForm> {
  static const _teal = Color(0xFF90A4AE);
  final _supa = Supabase.instance.client;

  late String _type;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _dureeCtrl;
  late final TextEditingController _nbPhotosCtrl;
  late final TextEditingController _delaiCtrl;
  late final TextEditingController _kmInclusCtrl;
  late final TextEditingController _prixKmCtrl;
  late final TextEditingController _acompteCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = (e?['type'] as String?) ?? 'shooting_individuel';
    _nomCtrl = TextEditingController(text: e?['nom']?.toString() ?? '');
    _prixCtrl = TextEditingController(text: (e?['prix'] as num?)?.toString() ?? '');
    _dureeCtrl = TextEditingController(text: (e?['duree_minutes'] as num?)?.toString() ?? '60');
    _nbPhotosCtrl = TextEditingController(text: (e?['nb_photos'] as num?)?.toString() ?? '');
    _delaiCtrl = TextEditingController(text: (e?['delai_livraison_jours'] as num?)?.toString() ?? '7');
    _kmInclusCtrl = TextEditingController(text: (e?['deplacement_inclus_km'] as num?)?.toString() ?? '0');
    _prixKmCtrl = TextEditingController(text: (e?['prix_km_supp'] as num?)?.toString() ?? '0');
    _acompteCtrl = TextEditingController(text: (e?['acompte_pourcentage'] as num?)?.toString() ?? '30');
    _descCtrl = TextEditingController(text: e?['description']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _prixCtrl, _dureeCtrl, _nbPhotosCtrl, _delaiCtrl, _kmInclusCtrl, _prixKmCtrl, _acompteCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nomCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _saving = false); return; }
    try {
      final data = {
        'pro_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
        'type': _type,
        'nom': _nomCtrl.text.trim(),
        'prix': double.tryParse(_prixCtrl.text.trim()) ?? 0,
        'duree_minutes': int.tryParse(_dureeCtrl.text.trim()) ?? 60,
        if (_nbPhotosCtrl.text.trim().isNotEmpty) 'nb_photos': int.tryParse(_nbPhotosCtrl.text.trim()),
        'delai_livraison_jours': int.tryParse(_delaiCtrl.text.trim()) ?? 7,
        'deplacement_inclus_km': int.tryParse(_kmInclusCtrl.text.trim()) ?? 0,
        'prix_km_supp': double.tryParse(_prixKmCtrl.text.trim()) ?? 0,
        'acompte_pourcentage': int.tryParse(_acompteCtrl.text.trim()) ?? 30,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      };
      if (widget.existing != null) {
        await _supa.from('prestations_photographe').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('prestations_photographe').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
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
          Text(widget.existing != null ? 'Modifier la prestation' : 'Nouvelle prestation',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: kTypesPrestation.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          _field(_nomCtrl, 'Nom de la prestation'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_prixCtrl, 'Prix (€)', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_dureeCtrl, 'Durée (min)', type: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_nbPhotosCtrl, 'Nb de photos', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_delaiCtrl, 'Délai livraison (j)', type: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_kmInclusCtrl, 'Km inclus', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_prixKmCtrl, 'Prix/km suppl. (€)', type: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          const SizedBox(height: 12),
          _field(_acompteCtrl, 'Acompte (%)', type: TextInputType.number),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Description (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(widget.existing != null ? 'Enregistrer' : 'Créer la prestation',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
  }
}
