import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/nom_client.dart';
import 'package:PetsMatch/utils/forfait_garde.dart' show uniteForfaitGarde;

// ── Pet-sitter : « Tarifs & forfaits », page unique des prix (13/11/2026).
//   • Tarifs : grille standard (user_profiles.tarifs_garde), visite d'essai
//     (clés essai_* du même JSON, lib/utils/garde_essai.dart), prestations sur
//     mesure (tarifs_garde_extra), affichage sur la fiche (tarifs_garde_visibles).
//   • Forfaits : packs de visites ou de promenades (forfaits_garde).
//   • Par client : tarif propre à un client (tarifs_clients_garde).
// Les prix restent visibles à la réservation, même masqués sur la fiche.
// Miroir site : website/src/app/garde/tarifs-clients/page.tsx.

const prestationsGarde = [
  ('promenade_30min', 'Promenade (30 min)'),
  ('promenade_1h',    'Promenade (1h)'),
  ('promenade_2h',    'Promenade (2h)'),
  ('visite',          'Visite à domicile'),
  ('garde_journee',   'Garde à domicile (journée)'),
  ('animal_supplementaire', 'Animal supplémentaire (par passage)'),
  ('autre',           'Autre prestation'),
];

class TarifsClientsPage extends StatefulWidget {
  /// 0 Tarifs · 1 Forfaits · 2 Par client.
  final int initialTab;
  const TarifsClientsPage({super.key, this.initialTab = 0});

  @override
  State<TarifsClientsPage> createState() => _TarifsClientsPageState();
}

class _TarifsClientsPageState extends State<TarifsClientsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _vert = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);
  static const _txt = TextStyle(fontFamily: 'Galey');
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _modifie = false;
  // Grille complète (prix + réglages essai_*) : réécrite telle quelle.
  Map<String, int> _tarifsBase = {};
  List<Map<String, dynamic>> _tarifsExtra = []; // [{label, prix, description}]
  bool _visibles = true;
  List<Map<String, dynamic>> _forfaits = [];
  List<Map<String, dynamic>> _clients = [];
  Map<String, Map<String, num>> _overridesByProfile = {};
  int _cle = 0; // clés stables des lignes « sur mesure »

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _pid => User_Info.activeProfileId;

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = _pid;
    if (uid == null || pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final profileRowFuture = _supa.from('user_profiles_complet').select().eq('id', pid).maybeSingle();
      final rdvRowsFuture = _supa.from('rdv').select('client_uid, client_profile_id, animal_id')
          .eq('pro_uid', uid).eq('pro_profile_id', pid)
          .inFilter('statut', ['confirme', 'termine'])
          .not('client_profile_id', 'is', null);
      final overrideRowsFuture = _supa.from('tarifs_clients_garde').select().eq('pro_uid', uid).eq('pro_profile_id', pid);
      final forfaitsFuture = _supa.from('forfaits_garde').select()
          .eq('pro_uid', uid).eq('actif', true)
          .or('pro_profile_id.eq.$pid,pro_profile_id.is.null').order('created_at');

      final profileRow = await profileRowFuture;
      final rdvRowsRaw = await rdvRowsFuture;
      final overrideRowsRaw = await overrideRowsFuture;
      List<Map<String, dynamic>> forfaits = [];
      try {
        forfaits = List<Map<String, dynamic>>.from(await forfaitsFuture as List);
      } catch (_) {}

      final tarifsBase = <String, int>{};
      if (profileRow?['tarifs_garde'] is Map) {
        for (final e in (profileRow!['tarifs_garde'] as Map).entries) {
          tarifsBase[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
        }
      }
      final tarifsExtra = <Map<String, dynamic>>[
        if (profileRow?['tarifs_garde_extra'] is List)
          for (final e in (profileRow!['tarifs_garde_extra'] as List))
            if (e is Map)
              {
                '_k': ++_cle,
                'label': e['label']?.toString() ?? '',
                'prix': (e['prix'] as num?)?.toInt() ?? 0,
                'description': e['description']?.toString() ?? '',
              },
      ];

      final seenClients = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(rdvRowsRaw as List)) {
        final cpid = r['client_profile_id']?.toString();
        if (cpid == null || cpid.isEmpty) continue;
        seenClients[cpid] = {'client_profile_id': cpid, 'client_uid': r['client_uid'], 'animal_id': r['animal_id']};
      }

      final overridesByProfile = <String, Map<String, num>>{};
      for (final o in List<Map<String, dynamic>>.from(overrideRowsRaw as List)) {
        final cpid = o['owner_profile_id']?.toString();
        if (cpid == null) continue;
        overridesByProfile.putIfAbsent(cpid, () => {})[o['prestation_type'] as String] = (o['prix'] as num?) ?? 0;
      }

      final clientNames = <String, String>{};
      if (seenClients.isNotEmpty) {
        final profiles = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom, profile_type').inFilter('id', seenClients.keys.toList());
        for (final p in List<Map<String, dynamic>>.from(profiles as List)) {
          clientNames[p['id'] as String] = nomClientProfil(p, defaut: 'Client');
        }
      }
      final clients = seenClients.values.map((c) => {...c, 'client_nom': clientNames[c['client_profile_id']] ?? 'Client'}).toList()
        ..sort((a, b) => (a['client_nom'] as String).compareTo(b['client_nom'] as String));

      if (mounted) {
        setState(() {
          _tarifsBase = tarifsBase;
          _tarifsExtra = tarifsExtra;
          _visibles = profileRow?['tarifs_garde_visibles'] != false;
          _forfaits = forfaits;
          _clients = clients;
          _overridesByProfile = overridesByProfile;
          _modifie = false;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback f) => setState(() { f(); _modifie = true; });

  void _snack(String m, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: _txt), behavior: SnackBarBehavior.floating,
      backgroundColor: erreur ? Colors.red : null,
    ));
  }

  // ── Onglet Tarifs ─────────────────────────────────────────────────────────

  Future<void> _enregistrerTarifs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final grille = Map<String, int>.from(_tarifsBase);
    final extraOut = [
      for (final e in _tarifsExtra)
        if ((e['label']?.toString().trim() ?? '').isNotEmpty)
          {
            'label': e['label'].toString().trim(),
            'prix': (e['prix'] as num?)?.toInt() ?? 0,
            if ((e['description']?.toString().trim() ?? '').isNotEmpty) 'description': e['description'].toString().trim(),
          },
    ];
    final maj = {'tarifs_garde': grille, 'tarifs_garde_extra': extraOut};
    try {
      if (_pid.isNotEmpty) {
        try {
          await _supa.from('user_profiles').update({...maj, 'tarifs_garde_visibles': _visibles}).eq('id', _pid);
        } on PostgrestException {
          // migration_garde_tarifs_visibles.sql pas encore passée.
          await _supa.from('user_profiles').update(maj).eq('id', _pid);
        }
      } else {
        await _supa.from('user_profiles').update(maj).eq('uid', uid).eq('is_main', true);
        await _supa.from('users').update(maj).eq('uid', uid);
        await FirebaseFirestore.instance.collection('users').doc(uid)
            .set({'tarifsGarde': grille, 'tarifsGardeExtra': extraOut}, SetOptions(merge: true));
      }
      if (mounted) setState(() => _modifie = false);
      _snack('Tarifs enregistrés.');
    } catch (e) {
      _snack('Erreur : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco({String? label, String? suffix, String? hint}) => InputDecoration(
        isDense: true, labelText: label, suffixText: suffix, hintText: hint,
        filled: true, fillColor: Colors.white,
        labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _vert, width: 1.5)),
      );

  Widget _titre(String t, {String? sous}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1E2025))),
          if (sous != null) Text(sous, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ]),
      );

  Widget _carte(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _ongletTarifs() {
    final essai = _tarifsBase['essai_actif'] == 1;
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
        _carte([
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _visibles,
            activeThumbColor: _vert,
            onChanged: (v) => _set(() => _visibles = v),
            title: const Text('Afficher mes tarifs et forfaits sur ma fiche publique',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(_visibles
                ? 'Visibles sur votre fiche, sur le site et dans l\'appli.'
                : 'Votre fiche affiche « Tarifs sur demande ». Le client voit toujours le prix au moment de réserver.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          ),
        ]),
        _carte([
          _titre('Tarifs standard (€ TTC)', sous: 'Laissez à 0 les prestations que vous ne proposez pas.'),
          for (final t in prestationsGarde)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                SizedBox(width: 92, child: TextFormField(
                  key: ValueKey('t_${t.$1}'),
                  initialValue: (_tarifsBase[t.$1] ?? 0).toString(),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: _deco(suffix: '€'),
                  onChanged: (val) { final v = int.tryParse(val); if (v != null && v >= 0) _set(() => _tarifsBase[t.$1] = v); },
                )),
              ]),
            ),
        ]),
        _carte([
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: essai,
            activeThumbColor: _vert,
            onChanged: (v) => _set(() => _tarifsBase['essai_actif'] = v ? 1 : 0),
            title: const Text("Visite d'essai pour les nouveaux clients",
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text("Vous rencontrez l'animal avant la première garde, puis indiquez si l'essai est concluant.",
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          ),
          if (essai) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: (_tarifsBase['essai'] ?? 0).toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: _deco(label: "Prix de l'essai", suffix: '€'),
                onChanged: (val) { final v = int.tryParse(val); if (v != null && v >= 0) _set(() => _tarifsBase['essai'] = v); },
              )),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(
                initialValue: (_tarifsBase['essai_duree'] ?? 30).toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: _deco(label: 'Durée', suffix: 'min'),
                onChanged: (val) { final v = int.tryParse(val); if (v != null && v > 0) _set(() => _tarifsBase['essai_duree'] = v); },
              )),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _tarifsBase['essai_obligatoire'] == 1,
              activeColor: _vert,
              onChanged: (v) => _set(() => _tarifsBase['essai_obligatoire'] = v == true ? 1 : 0),
              title: const Text('Essai obligatoire avant une première garde', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
              subtitle: Text("Un nouveau client ne peut réserver que l'essai, puis ses gardes une fois l'essai concluant.",
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ),
          ],
        ]),
        _carte([
          _titre('Prestations sur mesure', sous: 'Ex : nuit à domicile, soins particuliers, transport…'),
          for (int i = 0; i < _tarifsExtra.length; i++)
            Container(
              key: ValueKey('x_${_tarifsExtra[i]['_k']}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextFormField(
                    initialValue: _tarifsExtra[i]['label']?.toString() ?? '',
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: _deco(label: 'Intitulé'),
                    onChanged: (v) => _set(() => _tarifsExtra[i]['label'] = v),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: TextFormField(
                    initialValue: (_tarifsExtra[i]['prix'] as num?)?.toString() ?? '0',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: _deco(label: 'Prix', suffix: '€'),
                    onChanged: (v) => _set(() => _tarifsExtra[i]['prix'] = int.tryParse(v) ?? 0),
                  )),
                  IconButton(
                    tooltip: 'Retirer',
                    onPressed: () => _set(() => _tarifsExtra.removeAt(i)),
                    icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                  ),
                ]),
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: _tarifsExtra[i]['description']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  decoration: _deco(label: 'Précision (facultatif)'),
                  onChanged: (v) => _set(() => _tarifsExtra[i]['description'] = v),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () => _set(() => _tarifsExtra.add({'_k': ++_cle, 'label': '', 'prix': 0, 'description': ''})),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une prestation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: _teal),
          ),
        ]),
      ])),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving || !_modifie ? null : _enregistrerTarifs,
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_modifie ? 'Enregistrer les tarifs' : 'Tarifs enregistrés',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        )),
      )),
    ]);
  }

  // ── Onglet Forfaits ───────────────────────────────────────────────────────

  Future<void> _editerForfait([Map<String, dynamic>? f]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? User_Info.uid;
    var type = f?['type_prestation']?.toString() ?? 'visite';
    var public = f?['affiche_public'] != false;
    String unite() => uniteForfaitGarde(type);
    final nomCtrl = TextEditingController(text: f?['nom']?.toString() ?? '');
    final nbCtrl = TextEditingController(text: (f?['nb_visites'] ?? 5).toString());
    final prixCtrl = TextEditingController(text: f == null ? '' : ((f['prix'] as num?)?.toStringAsFixed(0) ?? ''));
    final descCtrl = TextEditingController(text: f?['description']?.toString() ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f == null ? 'Nouveau forfait' : 'Modifier le forfait',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final t in const [('visite', 'Visites'), ('promenade', 'Promenades'), ('garde_journee', 'Jours de garde')])
              ChoiceChip(
                label: Text(t.$2, style: TextStyle(fontFamily: 'Galey', color: type == t.$1 ? Colors.white : const Color(0xFF1F2A2E))),
                selected: type == t.$1, showCheckmark: false, selectedColor: _teal,
                onSelected: (_) => setSheet(() => type = t.$1),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: nomCtrl, textCapitalization: TextCapitalization.sentences,
              decoration: _deco(label: 'Nom du forfait', hint: 'Ex : Pack 5 ${unite()}')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: nbCtrl, keyboardType: TextInputType.number, decoration: _deco(label: 'Nombre de ${unite()}'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: prixCtrl, keyboardType: TextInputType.number, decoration: _deco(label: 'Prix (€ TTC)', suffix: '€'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: descCtrl, maxLines: 2, decoration: _deco(label: 'Description (facultatif)')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: public, activeColor: _vert,
            onChanged: (v) => setSheet(() => public = v ?? true),
            title: const Text('Proposer sur ma fiche et à la réservation', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
            subtitle: Text('Décoché, le forfait reste disponible dans vos devis.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(f == null ? 'Créer le forfait' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ])),
      )),
    );
    if (ok != true || nomCtrl.text.trim().isEmpty) return;
    final ligne = {
      'nom': nomCtrl.text.trim(),
      'nb_visites': int.tryParse(nbCtrl.text.trim()) ?? 1,
      'prix': double.tryParse(prixCtrl.text.trim().replaceAll(',', '.')) ?? 0,
      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'type_prestation': type,
    };
    try {
      Future<void> ecrire(Map<String, dynamic> l) async {
        if (f == null) {
          await _supa.from('forfaits_garde').insert({
            ...l, 'pro_uid': uid, if (_pid.isNotEmpty) 'pro_profile_id': _pid,
          });
        } else {
          await _supa.from('forfaits_garde').update(l).eq('id', f['id'].toString());
        }
      }
      try {
        await ecrire({...ligne, 'affiche_public': public});
      } on PostgrestException {
        // migration_garde_tarifs_visibles.sql pas encore passée.
        await ecrire(ligne);
      }
      await _load();
    } catch (e) {
      _snack('Erreur : $e', erreur: true);
    }
  }

  Future<void> _supprimerForfait(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Supprimer ce forfait ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Text('« ${f['nom']} » ne sera plus proposé. Les gardes déjà réservées avec ce forfait ne changent pas.', style: _txt),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await _supa.from('forfaits_garde').update({'actif': false}).eq('id', f['id'].toString());
    await _load();
  }

  Future<void> _basculerPublic(Map<String, dynamic> f, bool v) async {
    setState(() => f['affiche_public'] = v);
    try {
      await _supa.from('forfaits_garde').update({'affiche_public': v}).eq('id', f['id'].toString());
    } catch (e) {
      _snack('Erreur : $e', erreur: true);
      await _load();
    }
  }

  Widget _ongletForfaits() => ListView(padding: const EdgeInsets.all(12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text("Packs de visites, de promenades ou de jours de garde, facturés à l'achat puis décomptés à chaque passage. Le client les choisit à la réservation.",
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
        ),
        if (_forfaits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text("Aucun forfait pour l'instant.", style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500))),
          ),
        for (final f in _forfaits)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: InkWell(
                    onTap: () => _editerForfait(f),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('${f['nb_visites']} ${uniteForfaitGarde(f['type_prestation']?.toString())} — ${(f['prix'] as num?)?.toStringAsFixed(0) ?? 0} €',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                      if ((f['description']?.toString() ?? '').isNotEmpty)
                        Text(f['description'].toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                  )),
                  IconButton(tooltip: 'Modifier', onPressed: () => _editerForfait(f), icon: const Icon(Icons.edit_outlined, size: 20, color: _teal)),
                  IconButton(tooltip: 'Supprimer', onPressed: () => _supprimerForfait(f), icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent)),
                ]),
                InkWell(
                  onTap: () => _basculerPublic(f, f['affiche_public'] == false),
                  child: Row(children: [
                    SizedBox(width: 34, height: 34, child: Checkbox(
                      value: f['affiche_public'] != false, activeColor: _vert,
                      onChanged: (v) => _basculerPublic(f, v ?? true),
                    )),
                    Text('Proposer sur ma fiche et à la réservation', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _editerForfait(),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un forfait', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ]);

  // ── Onglet Par client ─────────────────────────────────────────────────────

  Future<void> _editClientTarifs(Map<String, dynamic> client) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = _pid;
    if (uid == null || pid.isEmpty) return;
    final cpid = client['client_profile_id'] as String;
    final current = Map<String, num>.from(_overridesByProfile[cpid] ?? {});
    final ctrls = <String, TextEditingController>{
      for (final t in prestationsGarde)
        t.$1: TextEditingController(text: (current[t.$1] ?? _tarifsBase[t.$1] ?? 0).toString()),
    };
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tarifs — ${client['client_nom']}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Laissez le tarif standard si aucune remise particulière.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ...prestationsGarde.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Standard : ${_tarifsBase[t.$1] ?? 0} €', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                ])),
                const SizedBox(width: 12),
                SizedBox(width: 90, child: TextFormField(
                  controller: ctrls[t.$1],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: _deco(suffix: '€'),
                )),
              ]),
            )),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: saving ? null : () async {
                setSheetState(() => saving = true);
                await _saveOverrides(uid, pid, client, ctrls);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
              ),
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            )),
          ])),
        ),
      ),
    );
  }

  Future<void> _saveOverrides(String uid, String pid, Map<String, dynamic> client, Map<String, TextEditingController> ctrls) async {
    final cpid = client['client_profile_id'] as String;
    final cuid = client['client_uid']?.toString();
    try {
      for (final t in prestationsGarde) {
        final val = int.tryParse(ctrls[t.$1]!.text) ?? 0;
        final base = _tarifsBase[t.$1] ?? 0;
        if (val == base) {
          await _supa.from('tarifs_clients_garde').delete()
              .eq('pro_profile_id', pid).eq('owner_profile_id', cpid).eq('prestation_type', t.$1);
        } else {
          await _supa.from('tarifs_clients_garde').upsert({
            'pro_uid': uid, 'pro_profile_id': pid, 'owner_uid': cuid, 'owner_profile_id': cpid,
            'prestation_type': t.$1, 'prix': val,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'pro_profile_id,owner_profile_id,prestation_type');
        }
      }
      await _load();
    } catch (e) {
      _snack('Erreur : $e', erreur: true);
    }
  }

  Widget _ongletClients() => ListView(padding: const EdgeInsets.all(12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            _clients.isEmpty
                ? 'Tarifs par client : disponible dès votre premier rendez-vous confirmé.'
                : 'Un prix particulier pour un client remplace le tarif standard pour lui seul.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
        ),
        for (final c in _clients)
          Builder(builder: (_) {
            final nb = _overridesByProfile[c['client_profile_id']]?.length ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                onTap: () => _editClientTarifs(c),
                title: Text(c['client_nom']?.toString() ?? 'Client', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(nb > 0 ? '$nb tarif${nb > 1 ? 's' : ''} personnalisé${nb > 1 ? 's' : ''}' : 'Tarifs standard',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: nb > 0 ? _vert : Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            );
          }),
      ]);

  Future<bool> _quitter() async {
    if (!_modifie) return true;
    final r = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Tarifs non enregistrés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: const Text('Quitter sans enregistrer vos modifications ?', style: _txt),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
      ],
    ));
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _quitter() && context.mounted) Navigator.pop(context);
      },
      child: DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab.clamp(0, 2),
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            title: const Text('Tarifs & forfaits', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            elevation: 0,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
              tabs: [Tab(text: 'Tarifs'), Tab(text: 'Forfaits'), Tab(text: 'Par client')],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : TabBarView(children: [_ongletTarifs(), _ongletForfaits(), _ongletClients()]),
        ),
      ),
    );
  }
}
