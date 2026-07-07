import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/config.dart';

const _kTeal = Color(0xFF0C5C6C);
const _kPurple = Color(0xFF7B5EA7);

const _kStatutLabels = {
  'brouillon': 'Brouillon', 'envoye': 'Envoyé',
  'accepte': 'Accepté', 'refuse': 'Refusé', 'expire': 'Expiré',
};
const _kStatutColors = {
  'brouillon': Colors.grey, 'envoye': Colors.blue,
  'accepte': Color(0xFF6E9E57), 'refuse': Colors.red, 'expire': Colors.orange,
};

// Le devis lié à un animal apparaît dans les documents de l'animal (visible par
// le propriétaire) — l'éducateur, lui, n'a pas accès à l'onglet Documents de la fiche.
Future<void> _syncDocumentAnimal(String devisId, String animalId, String statut,
    String token, double total, String? proProfileId) async {
  final supa = Supabase.instance.client;
  final docStatut = statut == 'accepte' ? 'signe' : statut == 'refuse' ? 'refuse' : statut == 'brouillon' ? 'brouillon' : 'en_attente';
  try {
    final existing = await supa.from('documents_animaux').select('id')
        .eq('animal_id', animalId).eq('type', 'devis').contains('metadata', {'devis_id': devisId}).maybeSingle();
    if (existing != null) {
      await supa.from('documents_animaux').update({'statut': docStatut}).eq('id', existing['id']);
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await supa.from('documents_animaux').insert({
        'animal_id': animalId,
        'uid_eleveur': uid,
        'pro_profile_id': proProfileId,
        'type': 'devis',
        'titre': 'Devis — ${total.toStringAsFixed(2)} €',
        'url': '$kSiteBaseUrl/devis/$token',
        'statut': docStatut,
        'metadata': {'devis_id': devisId, 'token': token},
      });
    }
  } catch (_) {}
}

class EducationDevisPage extends StatefulWidget {
  const EducationDevisPage({super.key});
  @override
  State<EducationDevisPage> createState() => _EducationDevisPageState();
}

class _EducationDevisPageState extends State<EducationDevisPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _devis = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final rows = await _supa.from('devis').select().eq('pro_uid', uid).order('created_at', ascending: false);
      if (mounted) setState(() { _devis = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DevisFormSheet(),
    );
    if (created == true) _load();
  }

  Future<void> _send(Map<String, dynamic> d) async {
    await _supa.from('devis').update({
      'statut': 'envoye', 'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', d['id']);
    final clientUid = d['client_uid'] as String?;
    if (clientUid != null) {
      await _supa.from('notifications').insert({
        'uid': clientUid, 'type': 'devis_recu',
        'title': 'Vous avez reçu un devis',
        'body': 'Un devis de ${(d['total_ttc'] as num).toStringAsFixed(2)} € vous a été envoyé.',
        'data': {'devis_id': d['id'], 'token': d['token_acceptation']},
        'read': false,
      });
    }
    final animalId = d['animal_id'] as String?;
    if (animalId != null) {
      await _syncDocumentAnimal(d['id'] as String, animalId, 'envoye',
          d['token_acceptation'] as String, (d['total_ttc'] as num).toDouble(), d['pro_profile_id'] as String?);
    }
    _load();
    if (mounted) _shareLink(d['token_acceptation'] as String);
  }

  void _shareLink(String token) {
    final url = '$kSiteBaseUrl/devis/$token';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce devis ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('devis').delete().eq('id', id).neq('statut', 'accepte');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _kTeal, foregroundColor: Colors.white,
        title: const Text('Devis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: _kTeal,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau devis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : _devis.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.request_quote_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text('Aucun devis', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _devis.length,
                  itemBuilder: (_, i) {
                    final d = _devis[i];
                    final statut = d['statut']?.toString() ?? 'brouillon';
                    final lignes = (d['lignes'] as List?) ?? [];
                    final total = (d['total_ttc'] as num?)?.toDouble() ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(
                              '${d['prenom_client'] ?? ''} ${d['nom_client'] ?? ''}'.trim(),
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_kStatutColors[statut] ?? Colors.grey).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_kStatutLabels[statut] ?? statut,
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                                    color: _kStatutColors[statut] ?? Colors.grey)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text('${lignes.length} ligne(s) — ${total.toStringAsFixed(2)} €',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          if (statut == 'brouillon')
                            TextButton.icon(
                              onPressed: () => _send(d),
                              icon: const Icon(Icons.send, size: 15),
                              label: const Text('Envoyer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: _kTeal),
                            )
                          else
                            TextButton.icon(
                              onPressed: () => _shareLink(d['token_acceptation'] as String),
                              icon: const Icon(Icons.link, size: 15),
                              label: const Text('Voir le lien', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: _kTeal),
                            ),
                          const Spacer(),
                          if (statut != 'accepte')
                            IconButton(
                              onPressed: () => _delete(d['id'] as String),
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                            ),
                        ]),
                      ]),
                    );
                  },
                ),
    );
  }
}

// ── Formulaire création ──────────────────────────────────────────────────────

class _Ligne {
  String description;
  int quantite;
  double prixUnitaire;
  final TextEditingController descCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController prixCtrl;
  _Ligne({this.description = '', this.quantite = 1, this.prixUnitaire = 0})
      : descCtrl = TextEditingController(text: description),
        qtyCtrl = TextEditingController(text: quantite.toString()),
        prixCtrl = TextEditingController(text: prixUnitaire == 0 ? '' : prixUnitaire.toString());
  double get total => quantite * prixUnitaire;
  Map<String, dynamic> toMap() => {
        'description': description, 'quantite': quantite,
        'prix_unitaire': prixUnitaire, 'total': total,
      };
  void dispose() { descCtrl.dispose(); qtyCtrl.dispose(); prixCtrl.dispose(); }
}

class _DevisFormSheet extends StatefulWidget {
  const _DevisFormSheet();
  @override
  State<_DevisFormSheet> createState() => _DevisFormSheetState();
}

class _DevisFormSheetState extends State<_DevisFormSheet> {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _clientUid;
  String? _clientProfileId;

  Map<String, dynamic> _tarifs = {};
  List<Map<String, dynamic>> _forfaits = [];
  List<Map<String, dynamic>> _animaux = [];
  String? _animalId;
  final List<_Ligne> _lignes = [_Ligne()];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTarifsForfaits();
    _loadAnimaux();
  }

  Future<void> _loadAnimaux() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    try {
      final access = await _supa.from('animal_access').select('animal_id')
          .eq('pro_profile_id', pid).inFilter('statut', ['active', 'active_write']);
      final ids = List<Map<String, dynamic>>.from(access)
          .map((a) => a['animal_id'] as String).toSet().toList();
      if (ids.isEmpty) return;
      final animaux = await _supa.from('animaux').select('id,nom,espece').inFilter('id', ids);
      if (mounted) setState(() => _animaux = List<Map<String, dynamic>>.from(animaux));
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose(); _nomCtrl.dispose(); _prenomCtrl.dispose();
    _emailCtrl.dispose(); _telCtrl.dispose(); _noteCtrl.dispose();
    for (final l in _lignes) { l.dispose(); }
    super.dispose();
  }

  Future<void> _loadTarifsForfaits() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    try {
      final tarifsRow = pid.isNotEmpty
          ? await _supa.from('user_profiles').select('tarifs_education').eq('id', pid).maybeSingle()
          : null;
      final forfaitsRows = await _supa.from('forfaits_education')
          .select('id,nom,prix').eq('pro_uid', uid).eq('actif', true);
      if (mounted) {
        setState(() {
          _tarifs = (tarifsRow?['tarifs_education'] as Map?)?.cast<String, dynamic>() ?? {};
          _forfaits = List<Map<String, dynamic>>.from(forfaitsRows);
        });
      }
    } catch (_) {}
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().length < 2) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final rows = await _supa.from('users')
          .select('uid,firstname,lastname,email,phone_number')
          .or('firstname.ilike.%$q%,lastname.ilike.%$q%,email.ilike.%$q%')
          .neq('uid', uid).limit(6);
      if (mounted) setState(() => _searchResults = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {} finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _prefillUser(Map<String, dynamic> u) async {
    _nomCtrl.text = u['lastname']?.toString() ?? '';
    _prenomCtrl.text = u['firstname']?.toString() ?? '';
    _emailCtrl.text = u['email']?.toString() ?? '';
    _telCtrl.text = u['phone_number']?.toString() ?? '';
    _clientUid = u['uid']?.toString();
    _searchCtrl.text = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
    setState(() => _searchResults = []);
    final profile = await _supa.from('user_profiles').select('id')
        .eq('uid', _clientUid!).eq('is_main', true).maybeSingle();
    _clientProfileId = profile?['id']?.toString();
  }

  void _addLigne(String description, num prix) {
    setState(() => _lignes.add(_Ligne(description: description, prixUnitaire: prix.toDouble())));
  }

  double get _total => _lignes.fold(0.0, (s, l) => s + l.total);

  Future<void> _save(bool envoyer) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final validLignes = _lignes.where((l) => l.description.trim().isNotEmpty).toList();
    if (_nomCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nom et email du client sont obligatoires.');
      return;
    }
    if (validLignes.isEmpty) {
      setState(() => _error = 'Ajoutez au moins une ligne de prestation.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
          UniqueKey().toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final pid = User_Info.activeProfileId;
      final row = {
        'pro_uid': uid,
        'pro_profile_id': pid.isNotEmpty ? pid : null,
        'date_devis': DateTime.now().toIso8601String().split('T').first,
        'client_uid': _clientUid,
        'client_profile_id': _clientProfileId,
        'animal_id': _animalId,
        'nom_client': _nomCtrl.text.trim(),
        'prenom_client': _prenomCtrl.text.trim(),
        'email_client': _emailCtrl.text.trim(),
        'telephone_client': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'lignes': validLignes.map((l) => l.toMap()).toList(),
        'total_ttc': _total,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'statut': envoyer ? 'envoye' : 'brouillon',
        'token_acceptation': token,
      };
      final inserted = await _supa.from('devis').insert(row).select().single();
      if (envoyer && _clientUid != null) {
        await _supa.from('notifications').insert({
          'uid': _clientUid, 'type': 'devis_recu',
          'title': 'Vous avez reçu un devis',
          'body': 'Un devis de ${_total.toStringAsFixed(2)} € vous a été envoyé.',
          'data': {'devis_id': inserted['id'], 'token': token},
          'read': false,
        });
      }
      if (_animalId != null) {
        await _syncDocumentAnimal(inserted['id'] as String, _animalId!,
            row['statut'] as String, token, _total, pid.isNotEmpty ? pid : null);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F8F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(controller: scrollCtrl, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Nouveau devis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 16),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(fontFamily: 'Galey', color: Colors.red, fontSize: 12)),
            ),

          const Text('Client', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _searchCtrl,
            onChanged: _searchUsers,
            decoration: InputDecoration(
              hintText: 'Rechercher un utilisateur PetsMatch (optionnel)…',
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          if (_searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Column(children: _searchResults.map((u) => ListTile(
                dense: true,
                title: Text('${u['firstname'] ?? ''} ${u['lastname'] ?? ''}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                subtitle: Text(u['email']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                onTap: () => _prefillUser(u),
              )).toList()),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _nomCtrl,
                decoration: const InputDecoration(labelText: 'Nom *', filled: true, fillColor: Colors.white, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _prenomCtrl,
                decoration: const InputDecoration(labelText: 'Prénom', filled: true, fillColor: Colors.white, border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email *', filled: true, fillColor: Colors.white, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _telCtrl,
              decoration: const InputDecoration(labelText: 'Téléphone', filled: true, fillColor: Colors.white, border: OutlineInputBorder())),

          const SizedBox(height: 20),
          const Text('Prestations', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (_tarifs['cours_individuel'] != null)
              _quickAddChip('Cours individuel', _tarifs['cours_individuel'] as num),
            if (_tarifs['cours_collectif'] != null)
              _quickAddChip('Cours collectif', _tarifs['cours_collectif'] as num),
            if (_tarifs['evaluation'] != null)
              _quickAddChip('Évaluation', _tarifs['evaluation'] as num),
            for (final f in _forfaits)
              _quickAddChip(f['nom']?.toString() ?? '', (f['prix'] as num?) ?? 0, purple: true),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < _lignes.length; i++) _ligneRow(i),
          TextButton.icon(
            onPressed: () => setState(() => _lignes.add(_Ligne())),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ajouter une ligne', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: _kTeal),
          ),
          const Divider(height: 24),
          Align(alignment: Alignment.centerRight,
              child: Text('Total : ${_total.toStringAsFixed(2)} €',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),

          if (_animaux.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _animalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Animal concerné (optionnel)',
                  filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('—', style: TextStyle(fontFamily: 'Galey'))),
                for (final a in _animaux)
                  DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text('${a['nom']}${a['espece'] != null ? ' (${a['espece']})' : ''}',
                        style: const TextStyle(fontFamily: 'Galey')),
                  ),
              ],
              onChanged: (v) => setState(() => _animalId = v),
            ),
          ],

          const SizedBox(height: 16),
          TextField(controller: _noteCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes internes', filled: true, fillColor: Colors.white, border: OutlineInputBorder())),

          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _saving ? null : () => _save(false),
              style: OutlinedButton.styleFrom(foregroundColor: _kTeal, side: const BorderSide(color: _kTeal),
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: const Text('Brouillon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: _saving ? null : () => _save(true),
              style: ElevatedButton.styleFrom(backgroundColor: _kTeal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text(_saving ? '…' : 'Créer et envoyer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _quickAddChip(String label, num prix, {bool purple = false}) {
    final color = purple ? _kPurple : _kTeal;
    return GestureDetector(
      onTap: () => _addLigne(label, prix),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('+ $label ($prix €)', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _ligneRow(int i) {
    final l = _lignes[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(flex: 3, child: TextField(
          controller: l.descCtrl,
          onChanged: (v) => l.description = v,
          decoration: const InputDecoration(hintText: 'Description', isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
        )),
        const SizedBox(width: 6),
        Expanded(child: TextField(
          controller: l.qtyCtrl,
          keyboardType: TextInputType.number,
          onChanged: (v) => setState(() => l.quantite = int.tryParse(v) ?? 1),
          decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
        )),
        const SizedBox(width: 6),
        Expanded(child: TextField(
          controller: l.prixCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() => l.prixUnitaire = double.tryParse(v.replaceAll(',', '.')) ?? 0),
          decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
        )),
        IconButton(
          onPressed: () => setState(() { l.dispose(); _lignes.removeAt(i); }),
          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
        ),
      ]),
    );
  }
}
