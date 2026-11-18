import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/forfait_toilettage.dart' show resumeForfaitToilettage;

// ── Prestations & tarifs (toiletteur) — catalogue configuré par le pro,
// choisi par le client lors de la réservation (rdv_booking_page.dart,
// flag isToilettage). Le prix varie selon espèce/poids de l'animal via
// grille_prix (tranches), résolu par prixPourAnimal().

const kTypesPrestationToilettage = <String, String>{
  'bain': 'Bain',
  'coupe': 'Coupe',
  'tonte': 'Tonte',
  'demelage': 'Démêlage',
  'griffes': 'Griffes',
  'oreilles': 'Oreilles',
  'hygiene': 'Hygiène',
  'spa': 'SPA',
};

const kEspecesToilettage = ['chien', 'chat', 'nac'];

/// Résout le prix d'une prestation pour un animal donné : cherche la
/// première tranche de `grille_prix` dont l'espèce correspond et dont
/// `poids_max_kg` est ≥ au poids de l'animal (tranches triées croissant).
/// Fallback sur `prix_base` si aucune tranche ne correspond (espèce absente
/// de la grille, poids non renseigné, ou grille vide).
double prixPourAnimal(Map<String, dynamic> prestation, String espece, double? poidsKg) {
  final grille = (prestation['grille_prix'] as List?) ?? [];
  if (grille.isEmpty || poidsKg == null) {
    return (prestation['prix_base'] as num?)?.toDouble() ?? 0;
  }
  final especeLower = espece.toLowerCase();
  final tranches = grille
      .cast<Map<String, dynamic>>()
      .where((t) => (t['espece']?.toString().toLowerCase() ?? '') == especeLower)
      .toList()
    ..sort((a, b) => ((a['poids_max_kg'] as num?) ?? 0).compareTo((b['poids_max_kg'] as num?) ?? 0));
  for (final t in tranches) {
    final maxKg = (t['poids_max_kg'] as num?)?.toDouble();
    if (maxKg != null && poidsKg <= maxKg) {
      return (t['prix'] as num?)?.toDouble() ?? ((prestation['prix_base'] as num?)?.toDouble() ?? 0);
    }
  }
  // Poids au-delà de toutes les tranches : prix de la plus haute tranche.
  if (tranches.isNotEmpty) {
    return (tranches.last['prix'] as num?)?.toDouble() ?? ((prestation['prix_base'] as num?)?.toDouble() ?? 0);
  }
  return (prestation['prix_base'] as num?)?.toDouble() ?? 0;
}

class ToilettagePrestationsPage extends StatefulWidget {
  const ToilettagePrestationsPage({super.key});

  @override
  State<ToilettagePrestationsPage> createState() => _ToilettagePrestationsPageState();
}

class _ToilettagePrestationsPageState extends State<ToilettagePrestationsPage> {
  static const _orange = Color(0xFFFFB74D);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _prestations = [];
  // Cartes de séances (forfaits_toilettage, profil actif).
  List<Map<String, dynamic>> _forfaits = [];

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
      final rows = await _supa.from('prestations_toilettage').select()
          .eq('pro_uid', uid).eq('actif', true).order('created_at');
      if (mounted) setState(() { _prestations = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    try {
      final f = await _supa.from('forfaits_toilettage').select().eq('pro_profile_id', pid).eq('actif', true).order('created_at');
      if (mounted) setState(() => _forfaits = List<Map<String, dynamic>>.from(f as List));
    } catch (_) {
      // Migration des forfaits pas encore passée.
    }
  }

  Future<void> _openForfait({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ForfaitToilettageForm(existing: existing, prestations: _prestations),
    );
    if (result == true) await _load();
  }

  Future<void> _retirerForfait(String id) async {
    // Désactivée : les cartes déjà vendues restent décomptées normalement.
    await _supa.from('forfaits_toilettage').update({'actif': false}).eq('id', id);
    await _load();
  }

  String _nomPrestation(Object? id) =>
      _prestations.firstWhere((p) => p['id'].toString() == id?.toString(), orElse: () => const {})['nom']?.toString() ?? '';

  Widget _sectionForfaits() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 14),
        const Text('Cartes de séances', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Text('Ex. « 5 toilettages complets » payés d\'avance : chaque rendez-vous du client est décompté de sa carte, sans facture à la séance.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        for (final f in _forfaits)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              onTap: () => _openForfait(existing: f),
              title: Text(f['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(resumeForfaitToilettage(f, prestationNom: _nomPrestation(f['prestation_id'])),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _retirerForfait(f['id'].toString())),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _openForfait(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nouvelle carte de séances', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE08E1B), side: const BorderSide(color: _orange),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        ),
        const SizedBox(height: 70),
      ]);

  Future<void> _supprimer(String id) async {
    await _supa.from('prestations_toilettage').update({'actif': false}).eq('id', id);
    await _load();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PrestationToilettageForm(existing: existing),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: const Text('Mes prestations', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _orange,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _prestations.isEmpty
              ? const Center(child: Text('Aucune prestation configurée.\nAjoutez-en une avec le bouton +',
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prestations.length + 1,
                  itemBuilder: (_, i) {
                    if (i == _prestations.length) return _sectionForfaits();
                    final p = _prestations[i];
                    final grille = (p['grille_prix'] as List?) ?? [];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        onTap: () => _openForm(existing: p),
                        title: Text(p['nom']?.toString() ?? '',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(
                            '${kTypesPrestationToilettage[p['type']] ?? p['type']} · '
                            '${grille.isNotEmpty ? "${grille.length} tranche${grille.length > 1 ? 's' : ''} de prix" : "à partir de ${((p['prix_base'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} €"}'
                            ' · ${p['duree_minutes']} min',
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

/// Carte de séances : nom, prestation couverte (toutes par défaut), nombre de
/// séances, prix, validité éventuelle.
class _ForfaitToilettageForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> prestations;
  const _ForfaitToilettageForm({this.existing, required this.prestations});

  @override
  State<_ForfaitToilettageForm> createState() => _ForfaitToilettageFormState();
}

class _ForfaitToilettageFormState extends State<_ForfaitToilettageForm> {
  final _supa = Supabase.instance.client;
  late final TextEditingController _nom, _nb, _prix, _validite, _desc;
  String? _prestationId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nom = TextEditingController(text: e?['nom']?.toString() ?? '');
    _nb = TextEditingController(text: (e?['nb_seances'] as num?)?.toString() ?? '5');
    _prix = TextEditingController(text: (e?['prix'] as num?)?.toString() ?? '');
    _validite = TextEditingController(text: (e?['validite_mois'] as num?)?.toString() ?? '');
    _desc = TextEditingController(text: e?['description']?.toString() ?? '');
    _prestationId = e?['prestation_id']?.toString();
    if (_prestationId != null && !widget.prestations.any((p) => p['id'].toString() == _prestationId)) _prestationId = null;
  }

  @override
  void dispose() {
    for (final c in [_nom, _nb, _prix, _validite, _desc]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final nb = int.tryParse(_nb.text.trim()) ?? 0;
    final prix = double.tryParse(_prix.text.trim().replaceAll(',', '.')) ?? 0;
    if (_nom.text.trim().isEmpty || nb < 1 || prix <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nom, nombre de séances et prix sont obligatoires')));
      return;
    }
    setState(() => _saving = true);
    final v = int.tryParse(_validite.text.trim());
    final data = {
      'pro_uid': FirebaseAuth.instance.currentUser?.uid,
      'pro_profile_id': User_Info.activeProfileId,
      'nom': _nom.text.trim(),
      'prestation_id': _prestationId,
      'nb_seances': nb,
      'prix': prix,
      'validite_mois': v != null && v > 0 ? v : null,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
    };
    try {
      if (widget.existing != null) {
        await _supa.from('forfaits_toilettage').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('forfaits_toilettage').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  InputDecoration _deco(String l, {String? suffix}) => InputDecoration(labelText: l, suffixText: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.existing == null ? 'Nouvelle carte de séances' : 'Modifier la carte',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 14),
        TextField(controller: _nom, decoration: _deco('Nom (ex. Carte 5 toilettages)')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: _prestationId,
          isExpanded: true,
          decoration: _deco('Prestation couverte'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Toutes les prestations')),
            for (final p in widget.prestations)
              DropdownMenuItem<String?>(value: p['id'].toString(), child: Text(p['nom']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _prestationId = v),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _nb, keyboardType: TextInputType.number, decoration: _deco('Nombre de séances'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _prix, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco('Prix de la carte', suffix: '€ TTC'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _validite, keyboardType: TextInputType.number,
            decoration: _deco('Validité (facultatif)', suffix: 'mois')),
        const SizedBox(height: 10),
        TextField(controller: _desc, maxLines: 2, decoration: _deco('Description (facultatif)')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB74D), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(_saving ? 'Enregistrement…' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        )),
      ])),
    );
  }
}

class _PrestationToilettageForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PrestationToilettageForm({this.existing});

  @override
  State<_PrestationToilettageForm> createState() => _PrestationToilettageFormState();
}

class _PrestationToilettageFormState extends State<_PrestationToilettageForm> {
  static const _orange = Color(0xFFFFB74D);
  final _supa = Supabase.instance.client;

  late String _type;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _prixBaseCtrl;
  late final TextEditingController _dureeCtrl;
  late final TextEditingController _descCtrl;
  late final Set<String> _especes;
  late List<Map<String, dynamic>> _grille;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = (e?['type'] as String?) ?? 'bain';
    _nomCtrl = TextEditingController(text: e?['nom']?.toString() ?? '');
    _prixBaseCtrl = TextEditingController(text: (e?['prix_base'] as num?)?.toString() ?? '');
    _dureeCtrl = TextEditingController(text: (e?['duree_minutes'] as num?)?.toString() ?? '60');
    _descCtrl = TextEditingController(text: e?['description']?.toString() ?? '');
    _especes = ((e?['especes'] as List?)?.cast<String>().toSet()) ?? {'chien'};
    _grille = ((e?['grille_prix'] as List?)?.cast<Map<String, dynamic>>().map((m) => Map<String, dynamic>.from(m)).toList()) ?? [];
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _prixBaseCtrl, _dureeCtrl, _descCtrl]) { c.dispose(); }
    super.dispose();
  }

  void _addTranche() {
    setState(() => _grille.add({'espece': _especes.isNotEmpty ? _especes.first : 'chien', 'poids_max_kg': 10, 'prix': 0}));
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
        'especes': _especes.toList(),
        'prix_base': double.tryParse(_prixBaseCtrl.text.trim()) ?? 0,
        'duree_minutes': int.tryParse(_dureeCtrl.text.trim()) ?? 60,
        'grille_prix': _grille,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      };
      if (widget.existing != null) {
        await _supa.from('prestations_toilettage').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('prestations_toilettage').insert(data);
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
            items: kTypesPrestationToilettage.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          _field(_nomCtrl, 'Nom de la prestation'),
          const SizedBox(height: 12),
          Text('Espèces concernées', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: kEspecesToilettage.map((e) {
            final selected = _especes.contains(e);
            return FilterChip(
              label: Text(e, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              selected: selected,
              selectedColor: _orange.withValues(alpha: 0.2),
              onSelected: (v) => setState(() => v ? _especes.add(e) : _especes.remove(e)),
            );
          }).toList()),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_prixBaseCtrl, 'Prix de base (€ TTC)', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_dureeCtrl, 'Durée (min)', type: TextInputType.number)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Text('Grille de prix par poids (optionnel)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
            const Spacer(),
            TextButton.icon(onPressed: _addTranche, icon: const Icon(Icons.add, size: 16), label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
          ]),
          ..._grille.asMap().entries.map((entry) {
            final i = entry.key;
            final t = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 2, child: DropdownButtonFormField<String>(
                  initialValue: t['espece'] as String? ?? 'chien',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Espèce', isDense: true, border: OutlineInputBorder()),
                  items: kEspecesToilettage.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => _grille[i]['espece'] = v),
                )),
                const SizedBox(width: 6),
                Expanded(child: TextFormField(
                  initialValue: t['poids_max_kg']?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Poids max (kg)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => _grille[i]['poids_max_kg'] = int.tryParse(v) ?? 0,
                )),
                const SizedBox(width: 6),
                Expanded(child: TextFormField(
                  initialValue: t['prix']?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix (€ TTC)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => _grille[i]['prix'] = double.tryParse(v) ?? 0,
                )),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _grille.removeAt(i)),
                ),
              ]),
            );
          }),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Description (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _orange, padding: const EdgeInsets.symmetric(vertical: 14)),
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
