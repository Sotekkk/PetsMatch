// Mes galeries clients (photographe) : liste filtrable par statut et
// création (rattachée ou non à une séance, sans fiche animal obligatoire).
// Fonctionnalité Premium. Miroir site : /photographe/galeries.
// Scopé au profil actif (pro_profile_id).
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/galeries_api.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart' show DashBadge;
import 'package:PetsMatch/pages/pro/photographe_studio_dashboard.dart' show styleGalerie;
import 'package:PetsMatch/pages/pro/photographe_album_page.dart';
import 'package:PetsMatch/pages/pro/photographe_abonnement_page.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

class PhotographeGaleriesPage extends StatefulWidget {
  const PhotographeGaleriesPage({super.key});

  @override
  State<PhotographeGaleriesPage> createState() => _PhotographeGaleriesPageState();
}

class _PhotographeGaleriesPageState extends State<PhotographeGaleriesPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  bool _premium = false;
  String _filtre = 'en_cours';
  List<Map<String, dynamic>> _galeries = [];
  List<Map<String, dynamic>> _seances = [];
  final Map<String, int> _nb = {};
  final Map<String, String> _clients = {};

  String get _pid => User_Info.activeProfileId;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _pid.isEmpty) { setState(() => _loading = false); return; }
    // Galeries clients : formule Premium uniquement.
    _premium = PlanService.getPhotographeConfig(await PlanService.getPhotographePlanCode(uid)).hasGaleriesClients;
    try {
      _galeries = List<Map<String, dynamic>>.from(await _supa.from('albums_photo').select()
          .eq('pro_profile_id', _pid).order('updated_at', ascending: false));
    } catch (_) {
      try {
        _galeries = List<Map<String, dynamic>>.from(await _supa.from('albums_photo').select()
            .eq('pro_profile_id', _pid).order('created_at', ascending: false));
      } catch (_) { _galeries = []; }
    }
    try {
      _seances = List<Map<String, dynamic>>.from(await _supa.from('rdv')
          .select('id, date_heure, motif, client_uid, client_profile_id, client_nom_manuel')
          .eq('pro_profile_id', _pid).inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', DateTime.now().subtract(const Duration(days: 120)).toUtc().toIso8601String())
          .order('date_heure', ascending: false).limit(80));
    } catch (_) {}
    _nb.clear();
    if (_galeries.isNotEmpty) {
      try {
        for (final p in await _supa.from('album_photos').select('album_id').inFilter('album_id', _galeries.map((g) => g['id']).toList())) {
          _nb[p['album_id'].toString()] = (_nb[p['album_id'].toString()] ?? 0) + 1;
        }
      } catch (_) {}
    }
    final profils = {
      for (final r in [..._galeries, ..._seances]) if (r['client_profile_id'] != null) r['client_profile_id'].toString(),
    };
    if (profils.isNotEmpty) {
      try {
        for (final p in await _supa.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList())) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final st = (p['nom']?.toString() ?? '').trim();
          _clients[p['id'].toString()] = p['profile_type'] != 'particulier' && st.isNotEmpty ? st : (perso.isNotEmpty ? perso : st);
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }

  Future<void> _creer() async {
    final titreCtrl = TextEditingController();
    String? rdvId;
    DateTime? date;
    final avecGalerie = _galeries.map((g) => g['rdv_id']?.toString()).whereType<String>().toSet();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Nouvelle galerie', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: rdvId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Séance associée (facultatif)', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Aucune séance', style: TextStyle(fontFamily: 'Galey'))),
              for (final s in _seances)
                DropdownMenuItem<String?>(value: s['id'].toString(), child: Text(
                  '${DateFormat('dd/MM/yyyy').format(DateTime.parse(s['date_heure'].toString()).toLocal())} — ${_nomClient(s)}'
                  '${avecGalerie.contains(s['id'].toString()) ? ' (galerie existante)' : ''}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey'))),
            ],
            onChanged: (v) => setM(() => rdvId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: titreCtrl, decoration: const InputDecoration(labelText: 'Titre', hintText: 'Ex : Portraits de Tokyo',
              border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) setM(() => date = d);
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(date == null ? 'Date de la séance' : DateFormat('d MMM yyyy', 'fr_FR').format(date!), style: const TextStyle(fontFamily: 'Galey')),
          ),
          const SizedBox(height: 8),
          Text('La galerie est créée en brouillon : rien n\'est visible du client avant que vous la partagiez.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: _teal),
              child: const Text('Créer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        ]),
      )),
    );
    if (ok != true) return;
    final s = _seances.where((x) => x['id'].toString() == rdvId).firstOrNull;
    try {
      final row = await _supa.from('albums_photo').insert({
        'pro_uid': FirebaseAuth.instance.currentUser!.uid,
        'pro_profile_id': _pid,
        'titre': titreCtrl.text.trim().isNotEmpty ? titreCtrl.text.trim() : (s != null ? 'Séance photo — ${_nomClient(s)}' : 'Séance photo'),
        'date_seance': date != null ? DateFormat('yyyy-MM-dd').format(date!)
            : (s != null ? s['date_heure'].toString().substring(0, 10) : null),
        if (s != null) ...{'rdv_id': s['id'], 'client_uid': s['client_uid'], 'client_profile_id': s['client_profile_id']},
      }).select('id').single();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PhotographeAlbumPage(albumId: row['id'].toString(),
          clientName: s != null ? _nomClient(s) : '')));
      _charger();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().contains('column')
            ? 'Migrations des galeries à passer.' : 'Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _galeries.where((g) {
      final s = g['statut']?.toString() ?? 'brouillon';
      return _filtre == 'tous' ? true : _filtre == 'en_cours' ? !const {'livree', 'archivee'}.contains(s) : s == _filtre;
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mes galeries clients', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: _premium && !_loading
          ? FloatingActionButton.extended(onPressed: _creer, backgroundColor: _teal, foregroundColor: Colors.white,
              icon: const Icon(Icons.add), label: const Text('Nouvelle galerie', style: TextStyle(fontFamily: 'Galey')))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _charger, color: _teal,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
                if (!_premium)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6E8E6))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Les galeries clients privées sont réservées à la formule Premium.',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _ink)),
                      const SizedBox(height: 4),
                      Text('Aperçus compressés et protégés, partage privé au client, sélection et livraison des photos.',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotographeAbonnementPage())),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text('Voir les abonnements', style: TextStyle(fontFamily: 'Galey', color: _teal))),
                    ]),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in [('en_cours', 'En cours'), ...kStatutsGalerie, ('tous', 'Toutes')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _filtre == f.$1 ? Colors.white : _ink)),
                          selected: _filtre == f.$1, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                          side: BorderSide(color: _filtre == f.$1 ? _teal : Colors.grey.shade300),
                          onSelected: (_) => setState(() => _filtre = f.$1),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                if (visibles.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('Aucune galerie.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)))),
                for (final g in visibles)
                  Builder(builder: (_) {
                    final st = styleGalerie(g['statut']?.toString());
                    final n = _nb[g['id'].toString()] ?? 0;
                    final d = DateTime.tryParse(g['date_seance']?.toString() ?? '');
                    return Card(
                      elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE6E8E6))),
                      child: ListTile(
                        title: Text(g['titre']?.toString() ?? 'Galerie', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                        subtitle: Text([
                          if (_clients[g['client_profile_id']?.toString()] != null) _clients[g['client_profile_id']?.toString()]!,
                          if (d != null) DateFormat('dd/MM/yyyy').format(d),
                          '$n photo${n > 1 ? 's' : ''}',
                        ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        trailing: DashBadge(st.label, fg: st.fg, bg: st.bg),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => PhotographeAlbumPage(
                              albumId: g['id'].toString(), clientName: _clients[g['client_profile_id']?.toString()] ?? '')));
                          _charger();
                        },
                      ),
                    );
                  }),
              ]),
            ),
    );
  }
}
