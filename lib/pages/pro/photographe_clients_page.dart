// Photographe — « Mes clients » : les clients sont les PROPRIÉTAIRES (pas
// les animaux). Deux onglets :
//  • À traiter : le travail en cours, séance par séance, regroupé par tâche
//    (galerie à créer / à partager, sélection reçue à retoucher, à livrer,
//    à facturer, facture impayée, contrat / devis à envoyer ou en attente) ;
//  • Clients : un client = ses séances, galeries, devis, factures.
// Chaque séance ouvre le dossier de la séance (photographe_dossier_seance).
// Miroir site : /photographe/clients. Scopé au profil actif (pro_profile_id).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/contact_canaux.dart';
import 'package:PetsMatch/pages/pro/photographe_dossier_seance.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _muted = Color(0xFF6B7280);
const _ambre = Color(0xFFD97706);
const _violet = Color(0xFF7B5EA7);
const _rouge = Color(0xFFB3261E);

/// Tâches, dans l'ordre du travail.
const List<(String, String, Color)> kTachesPhoto = [
  ('selection', 'Sélection reçue — photos à retoucher', _ambre),
  ('livrer', 'En retouche — à livrer', _violet),
  ('galerie_creer', 'Galerie à créer', _teal),
  ('galerie_partager', 'Galerie à compléter et partager', _teal),
  ('facturer', 'À facturer', _ambre),
  ('impayee', 'Facture émise, non payée', _rouge),
  ('contrat', 'Contrat à envoyer ou en attente de signature', _muted),
  ('devis', 'Devis en attente de réponse', _muted),
];

class PhotographeClientsPage extends StatefulWidget {
  final int initialTab;
  const PhotographeClientsPage({super.key, this.initialTab = 0});

  @override
  State<PhotographeClientsPage> createState() => _PhotographeClientsPageState();
}

class _PhotographeClientsPageState extends State<PhotographeClientsPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tabs;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  final Map<String, Map<String, dynamic>> _galeries = {};   // rdv_id → galerie
  final Map<String, int> _nbPhotos = {}, _nbChoisies = {};  // album_id
  final Map<String, Map<String, dynamic>> _devis = {};      // rdv_id
  final Map<String, Map<String, dynamic>> _contrats = {};   // rdv_id
  final Map<String, Map<String, dynamic>> _factures = {};   // rdv_id
  final Map<String, Map<String, dynamic>> _profils = {};
  final Map<String, String> _prestations = {};
  String _recherche = '';

  String get _pid => User_Info.activeProfileId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _charger();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _l(dynamic r) => List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    if (_pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      _rdvs = _l(await _supa.from('rdv').select().eq('pro_profile_id', _pid)
          .inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', DateTime.now().subtract(const Duration(days: 540)).toUtc().toIso8601String())
          .order('date_heure', ascending: false).limit(400));
    } catch (_) {}
    final ids = _rdvs.map((r) => r['id'].toString()).toList();
    _galeries.clear(); _devis.clear(); _contrats.clear(); _factures.clear(); _nbPhotos.clear(); _nbChoisies.clear();
    if (ids.isNotEmpty) {
      try {
        for (final g in await _supa.from('albums_photo').select().inFilter('rdv_id', ids)) {
          _galeries[g['rdv_id'].toString()] = Map<String, dynamic>.from(g);
        }
      } catch (_) {}
      if (_galeries.isNotEmpty) {
        try {
          for (final p in await _supa.from('album_photos').select('album_id, selectionnee').inFilter('album_id', _galeries.values.map((g) => g['id']).toList())) {
            final k = p['album_id'].toString();
            _nbPhotos[k] = (_nbPhotos[k] ?? 0) + 1;
            if (p['selectionnee'] == true) _nbChoisies[k] = (_nbChoisies[k] ?? 0) + 1;
          }
        } catch (_) {}
      }
      try {
        for (final d in await _supa.from('devis').select('id, rdv_id, statut, total_ttc').inFilter('rdv_id', ids)) {
          _devis[d['rdv_id'].toString()] = Map<String, dynamic>.from(d);
        }
      } catch (_) {}
      try {
        for (final c in await _supa.from('documents_animaux').select('rdv_id, statut').eq('type', 'contrat_prestation_photo').inFilter('rdv_id', ids)) {
          _contrats[c['rdv_id'].toString()] = Map<String, dynamic>.from(c);
        }
      } catch (_) {}
      try {
        for (final f in await _supa.from('factures').select('source_rdv_id, statut, total_ttc').inFilter('source_rdv_id', ids).neq('statut', 'annulee')) {
          _factures[f['source_rdv_id'].toString()] = Map<String, dynamic>.from(f);
        }
      } catch (_) {}
    }
    final pids = {for (final r in _rdvs) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    if (pids.isNotEmpty) {
      try {
        for (final p in await _supa.from('user_profiles_complet').select().inFilter('id', pids.toList())) {
          _profils[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      } catch (_) {}
    }
    final prs = {for (final r in _rdvs) if (r['prestation_id'] != null) r['prestation_id'].toString()};
    if (prs.isNotEmpty) {
      try {
        for (final p in await _supa.from('prestations_photographe').select('id, nom').inFilter('id', prs.toList())) {
          _prestations[p['id'].toString()] = p['nom']?.toString() ?? '';
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Helpers ──
  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  String _jour(DateTime d) => DateFormat('d MMM yyyy', 'fr_FR').format(d);
  String _cleClient(Map<String, dynamic> r) =>
      r['client_profile_id']?.toString() ?? r['client_uid']?.toString() ?? 'manuel:${(r['client_nom_manuel'] ?? '').toString().trim().toLowerCase()}';
  String _nomClient(Map<String, dynamic> r) {
    final p = _profils[r['client_profile_id']?.toString()];
    if (p != null) {
      final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
      final st = (p['nom']?.toString() ?? '').trim();
      final n = p['profile_type'] != 'particulier' && st.isNotEmpty ? st : (perso.isNotEmpty ? perso : st);
      if (n.isNotEmpty) return n;
    }
    final m = (r['client_nom_manuel']?.toString() ?? '').trim();
    return m.isNotEmpty ? m : 'Client';
  }
  String _prestation(Map<String, dynamic> r) =>
      _prestations[r['prestation_id']?.toString()] ?? ((r['motif']?.toString() ?? '').trim().isEmpty ? 'Séance photo' : r['motif'].toString().trim());
  String? _animal(Map<String, dynamic> r) => (r['animal_nom_manuel']?.toString() ?? '').trim().isEmpty ? null : r['animal_nom_manuel'].toString();

  /// Tâches en cours d'une séance (clés de kTachesPhoto).
  List<String> _taches(Map<String, dynamic> r) {
    final id = r['id'].toString();
    final passee = _debut(r).isBefore(DateTime.now());
    final g = _galeries[id];
    final f = _factures[id];
    final out = <String>[];
    if (passee) {
      if (g == null) {
        out.add('galerie_creer');
      } else {
        final st = g['statut']?.toString() ?? 'brouillon';
        if (st == 'selection_recue') out.add('selection');
        if (st == 'en_retouche') out.add('livrer');
        if (st == 'brouillon') out.add('galerie_partager');
      }
      if (f == null) out.add('facturer');
    }
    if (f != null && f['statut'] != 'payee') out.add('impayee');
    final c = _contrats[id];
    if (!passee && (c == null || (c['statut'] != 'signe'))) out.add('contrat');
    final d = _devis[id];
    if (d != null && d['statut'] == 'envoye') out.add('devis');
    return out;
  }

  Future<void> _ouvrir(Map<String, dynamic> r) =>
      showDossierSeance(context, r, nomClient: _nomClient(r), prestation: _prestation(r), animal: _animal(r), onChanged: _charger);

  Widget _ligneSeance(Map<String, dynamic> r, {String? sousTitre}) {
    final g = _galeries[r['id'].toString()];
    final choisies = g == null ? 0 : (_nbChoisies[g['id'].toString()] ?? 0);
    return InkWell(
      onTap: () => _ouvrir(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_nomClient(r)} — ${_prestation(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
            Text([
              'Séance du ${_jour(_debut(r))}',
              if (_animal(r) != null) _animal(r)!,
              if (choisies > 0) '$choisies photo${choisies > 1 ? 's' : ''} choisie${choisies > 1 ? 's' : ''}',
              if (sousTitre != null && sousTitre.isNotEmpty) sousTitre,
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
          ])),
          const Icon(Icons.chevron_right, color: _muted),
        ]),
      ),
    );
  }

  Widget _aTraiter() {
    final parTache = <String, List<Map<String, dynamic>>>{};
    for (final r in _rdvs) {
      for (final t in _taches(r)) { parTache.putIfAbsent(t, () => []).add(r); }
    }
    final total = parTache.values.fold<int>(0, (n, l) => n + l.length);
    if (total == 0) {
      return const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('Rien à traiter : tout est à jour.', style: TextStyle(fontFamily: 'Galey', color: _muted))));
    }
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        for (final t in kTachesPhoto)
          if ((parTache[t.$1] ?? []).isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6E8E6))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: t.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
                  Text('${parTache[t.$1]!.length}', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: t.$3)),
                ]),
                const SizedBox(height: 4),
                for (final r in parTache[t.$1]!) _ligneSeance(r),
              ]),
            ),
      ]),
    );
  }

  Widget _clients() {
    final groupes = <String, List<Map<String, dynamic>>>{};
    for (final r in _rdvs) { groupes.putIfAbsent(_cleClient(r), () => []).add(r); }
    final q = _recherche.trim().toLowerCase();
    final cles = groupes.keys.where((k) => q.isEmpty || _nomClient(groupes[k]!.first).toLowerCase().contains(q)).toList()
      ..sort((a, b) => _nomClient(groupes[a]!.first).toLowerCase().compareTo(_nomClient(groupes[b]!.first).toLowerCase()));
    final now = DateTime.now();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => _recherche = v),
          decoration: const InputDecoration(hintText: 'Rechercher un client', prefixIcon: Icon(Icons.search), isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
        ),
      ),
      Expanded(child: cles.isEmpty
          ? const Center(child: Text('Aucun client pour le moment.', style: TextStyle(fontFamily: 'Galey', color: _muted)))
          : RefreshIndicator(
              onRefresh: _charger, color: _teal,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
                itemCount: cles.length,
                itemBuilder: (_, i) {
                  final seances = groupes[cles[i]]!;
                  final r0 = seances.first;
                  final prochaine = seances.where((r) => _debut(r).isAfter(now)).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));
                  final nbTaches = seances.fold<int>(0, (n, r) => n + _taches(r).length);
                  return Card(
                    elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE6E8E6))),
                    child: ListTile(
                      title: Text(_nomClient(r0), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                      subtitle: Text([
                        '${seances.length} séance${seances.length > 1 ? 's' : ''}',
                        if (prochaine.isNotEmpty) 'prochaine le ${_jour(_debut(prochaine.first))}',
                      ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      trailing: nbTaches > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(20)),
                              child: Text('$nbTaches à traiter', style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w700, color: _ambre)))
                          : const Icon(Icons.chevron_right),
                      onTap: () => _ficheClient(seances),
                    ),
                  );
                },
              ),
            )),
    ]);
  }

  Future<void> _ficheClient(List<Map<String, dynamic>> seances) async {
    final r0 = seances.first;
    final p = _profils[r0['client_profile_id']?.toString()];
    final tel = (p?['phone_number'] ?? p?['phone'] ?? r0['client_telephone_manuel'])?.toString() ?? '';
    final mail = (p?['email_contact'] ?? r0['client_email_manuel'])?.toString() ?? '';
    final clientUid = r0['client_uid']?.toString() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.7, maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
          Text(_nomClient(r0), style: const TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
          if (tel.isNotEmpty || mail.isNotEmpty)
            Text([tel, mail].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
          const SizedBox(height: 8),
          ContactCanaux(clientUid: clientUid, tel: tel, email: mail, monProfilId: _pid),
          const SizedBox(height: 8),
          const Text('Séances', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
          for (final r in seances)
            Builder(builder: (_) {
              final t = _taches(r);
              final f = _factures[r['id'].toString()];
              final g = _galeries[r['id'].toString()];
              return _ligneSeance(r, sousTitre: [
                if (g != null) 'galerie : ${g['statut'] == 'livree' ? 'livrée' : g['statut'] == 'selection_recue' ? 'sélection reçue' : g['statut'] == 'en_retouche' ? 'en retouche' : g['statut'] == 'partagee' ? 'partagée' : 'brouillon'}',
                if (f != null) f['statut'] == 'payee' ? 'facture payée' : 'facture non payée',
                if (t.isNotEmpty) '${t.length} à traiter',
              ].join(' · '));
            }),
        ]),
      ),
    );
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mes clients', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'À traiter'), Tab(text: 'Clients')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : TabBarView(controller: _tabs, children: [_aTraiter(), _clients()]),
    );
  }
}

