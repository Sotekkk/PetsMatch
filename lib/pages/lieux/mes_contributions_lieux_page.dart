import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';
import 'package:PetsMatch/pages/lieux/recommander_lieu_page.dart';
import 'package:PetsMatch/widgets/demande_retrait_lieu.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mes contributions aux lieux pet-friendly : lieux recommandés (avec statut et
/// motif de la modération, fiche à compléter), corrections proposées,
/// revendications. Ouvert depuis la liste des lieux et les notifications.
class MesContributionsLieuxPage extends StatefulWidget {
  const MesContributionsLieuxPage({super.key});
  @override
  State<MesContributionsLieuxPage> createState() => _MesContributionsLieuxPageState();
}

class _MesContributionsLieuxPageState extends State<MesContributionsLieuxPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  bool _chargement = true;
  List<Map<String, dynamic>> _lieux = [], _corrections = [], _revendications = [], _retraits = [];

  static const _statuts = {
    'brouillon': ('Brouillon', Color(0xFF64748B)),
    'en_attente_validation': ('En attente de validation', Color(0xFFB45309)),
    'actif': ('Publié', Color(0xFF16A34A)),
    'a_corriger': ('À compléter', Color(0xFF2563EB)),
    'refuse': ('Non publié', Color(0xFFDC2626)),
    'masque': ('Masqué', Color(0xFF64748B)),
    'suspendu': ('Suspendu', Color(0xFFDC2626)),
    'en_attente': ('En attente', Color(0xFFB45309)),
    'appliquee': ('Appliquée', Color(0xFF16A34A)),
    'refusee': ('Refusée', Color(0xFFDC2626)),
    'validee': ('Validée', Color(0xFF16A34A)),
    'acceptee': ('Acceptée', Color(0xFF16A34A)),
  };

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _chargement = true);
    try {
      final r = await Future.wait([
        _supa.from('petfriendly_places').select().eq('ajoute_par_uid', uid).order('created_at', ascending: false),
        _supa.from('petfriendly_corrections').select('*, place:petfriendly_places(id, nom)').eq('uid', uid).order('created_at', ascending: false),
        _supa.from('petfriendly_revendications').select('*, place:petfriendly_places(id, nom)').eq('uid', uid).order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _lieux = List<Map<String, dynamic>>.from(r[0] as List);
        _corrections = List<Map<String, dynamic>>.from(r[1] as List);
        _revendications = List<Map<String, dynamic>>.from(r[2] as List);
        _chargement = false;
      });
      // À part : la page reste utilisable si la table n'existe pas encore.
      final ret = await _supa.from('lieux_demandes_retrait').select('*, place:petfriendly_places(id, nom)')
          .eq('uid', uid).eq('nature', 'petfriendly').order('created_at', ascending: false);
      if (mounted) setState(() => _retraits = List<Map<String, dynamic>>.from(ret as List));
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _annulerRetrait(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler cette demande ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
        content: const Text('La demande de retrait ne sera pas examinée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Annuler la demande', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('lieux_demandes_retrait').delete().eq('id', d['id'].toString()).eq('statut', 'en_attente');
    } catch (_) {}
    _charger();
  }

  Future<void> _supprimer(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce lieu ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
        content: Text('« ${l['nom']} » sera définitivement supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // .select() : une suppression refusée par la base ne renvoie aucune ligne.
      final r = await _supa.from('petfriendly_places').delete().eq('id', l['id']).select('id');
      if ((r as List).isEmpty) throw Exception('refus');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Suppression impossible : la fiche a peut-être déjà été publiée.'),
          backgroundColor: Colors.red,
        ));
      }
    }
    _charger();
  }

  Widget _pastille(String statut) {
    final s = _statuts[statut] ?? (statut, Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: s.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(s.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.$2)),
    );
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '' : DateFormat('dd/MM/yyyy').format(d.toLocal());
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16)),
      );

  Widget _carte({required String titre, required String sousTitre, required String statut, String? motif, List<Widget> actions = const []}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15))),
          _pastille(statut),
        ]),
        const SizedBox(height: 2),
        Text(sousTitre, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        if (motif != null && motif.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Motif de la modération : $motif', style: const TextStyle(fontSize: 13, color: Color(0xFF33454B))),
        ],
        if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, children: actions)],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white,
          title: const Text('Mes contributions', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800))),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _titre('Lieux recommandés'),
                if (_lieux.isEmpty)
                  Text('Vous n\'avez pas encore recommandé de lieu.', style: TextStyle(color: Colors.grey.shade600)),
                for (final l in _lieux)
                  _carte(
                    titre: (l['nom'] ?? '').toString(),
                    sousTitre: '${l['ville'] ?? ''} · proposé le ${_date(l['created_at'])}',
                    statut: (l['statut'] ?? '').toString(),
                    motif: ['a_corriger', 'refuse', 'masque'].contains(l['statut']) ? l['motif_moderation']?.toString() : null,
                    actions: [
                      if (['a_corriger', 'brouillon', 'en_attente_validation'].contains(l['statut']))
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                          onPressed: () async {
                            final ok = await Navigator.push<bool>(context,
                                MaterialPageRoute(builder: (_) => RecommanderLieuPage(existant: l)));
                            if (ok == true) _charger();
                          },
                          child: Text(l['statut'] == 'en_attente_validation' ? 'Modifier' : 'Compléter et renvoyer'),
                        ),
                      // Comme la base (pf_delete + pf_garde_suppression_fiche) : l'auteur
                      // retire sa fiche tant qu'elle n'est pas publiée ; ensuite, l'équipe.
                      if (['a_corriger', 'brouillon', 'en_attente_validation', 'refuse'].contains(l['statut']))
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: BorderSide(color: Colors.red.shade200)),
                          onPressed: () => _supprimer(l),
                          child: const Text('Supprimer'),
                        ),
                      if (l['statut'] == 'actif')
                        OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LieuDetailPage(id: l['id'].toString()))),
                          child: const Text('Voir la fiche'),
                        ),
                    ],
                  ),
                _titre('Corrections proposées'),
                if (_corrections.isEmpty)
                  Text('Aucune correction proposée.', style: TextStyle(color: Colors.grey.shade600)),
                for (final c in _corrections)
                  _carte(
                    titre: ((c['place'] as Map?)?['nom'] ?? 'Lieu').toString(),
                    sousTitre: 'Proposée le ${_date(c['created_at'])}',
                    statut: (c['statut'] ?? '').toString(),
                    motif: c['statut'] == 'refusee' ? c['motif']?.toString() : null,
                  ),
                _titre('Demandes de retrait'),
                if (_retraits.isEmpty)
                  Text('Aucune demande de retrait.', style: TextStyle(color: Colors.grey.shade600)),
                for (final d in _retraits)
                  _carte(
                    titre: ((d['place'] as Map?)?['nom'] ?? d['place_nom'] ?? 'Lieu').toString(),
                    sousTitre: '${libelleRaisonRetrait(d['raison']?.toString())} · demandée le ${_date(d['created_at'])}',
                    statut: (d['statut'] ?? '').toString(),
                    motif: d['statut'] != 'en_attente' ? d['motif']?.toString() : null,
                    actions: [
                      if (d['statut'] == 'en_attente')
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: BorderSide(color: Colors.red.shade200)),
                          onPressed: () => _annulerRetrait(d),
                          child: const Text('Annuler la demande'),
                        ),
                    ],
                  ),
                _titre('Revendications'),
                if (_revendications.isEmpty)
                  Text('Aucune revendication.', style: TextStyle(color: Colors.grey.shade600)),
                for (final r in _revendications)
                  _carte(
                    titre: ((r['place'] as Map?)?['nom'] ?? 'Lieu').toString(),
                    sousTitre: 'Envoyée le ${_date(r['created_at'])}',
                    statut: (r['statut'] ?? '').toString(),
                    motif: r['statut'] == 'refusee' ? r['motif']?.toString() : null,
                    actions: [
                      if (r['statut'] == 'validee')
                        OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => LieuDetailPage(id: ((r['place'] as Map?)?['id'] ?? r['place_id']).toString()))),
                          child: const Text('Voir ma fiche'),
                        ),
                    ],
                  ),
              ]),
            ),
    );
  }
}
