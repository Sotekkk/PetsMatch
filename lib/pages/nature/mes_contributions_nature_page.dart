import 'package:PetsMatch/pages/nature/add_natural_place_page.dart';
import 'package:PetsMatch/pages/nature/natural_place_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mes contributions aux lieux naturels : lieux proposés (statut, motif du
/// refus), photos et équipements proposés. Même règle que les lieux
/// pet-friendly : l'auteur modifie ou supprime son lieu tant qu'il n'est pas
/// publié ; une fois publié, il propose photos / équipements depuis la fiche et
/// la suppression revient à l'équipe PetsMatch. Miroir site :
/// /lieux-naturels/mes-contributions.
class MesContributionsNaturePage extends StatefulWidget {
  const MesContributionsNaturePage({super.key});
  @override
  State<MesContributionsNaturePage> createState() => _MesContributionsNaturePageState();
}

class _MesContributionsNaturePageState extends State<MesContributionsNaturePage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  bool _chargement = true;
  List<Map<String, dynamic>> _lieux = [], _photos = [], _equipements = [];

  static const _statuts = {
    'en_attente': ('En attente de validation', Color(0xFFB45309)),
    'valide': ('Publié', Color(0xFF16A34A)),
    'refuse': ('Non publié', Color(0xFFDC2626)),
  };

  static const _equipementsLabels = {
    'has_eau': 'Eau potable', 'has_parking': 'Parking', 'has_fontaine': 'Fontaine',
    'has_poubelle': 'Poubelles', 'parcours_ombre': 'Parcours ombragé', 'baignade_possible': 'Baignade',
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
        _supa.from('natural_places').select().eq('submitted_by_uid', uid).order('created_at', ascending: false),
        _supa.from('natural_place_photo_suggestions').select('*, place:natural_places(id, nom)')
            .eq('submitted_by_uid', uid).order('created_at', ascending: false),
        _supa.from('natural_place_amenity_suggestions').select('*, place:natural_places(id, nom)')
            .eq('submitted_by_uid', uid).order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _lieux = List<Map<String, dynamic>>.from(r[0] as List);
        _photos = List<Map<String, dynamic>>.from(r[1] as List);
        _equipements = List<Map<String, dynamic>>.from(r[2] as List);
        _chargement = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<bool> _confirmer(String titre, String texte) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
          content: Text(texte),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
          ],
        ),
      ) ??
      false;

  Future<void> _supprimer(String table, String id, String titre, String texte) async {
    if (!await _confirmer(titre, texte)) return;
    try {
      // .select() : une suppression refusée par la base ne renvoie aucune ligne.
      final r = await _supa.from(table).delete().eq('id', id).select('id');
      if ((r as List).isEmpty) throw Exception('refus');
      _charger();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Suppression impossible : ce contenu a peut-être déjà été validé.'),
          backgroundColor: Colors.red,
        ));
      }
      _charger();
    }
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

  Widget _carte({required String titre, required String sousTitre, required String statut, String? motif,
      String? photo, List<Widget> actions = const []}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (photo != null && photo.isNotEmpty) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Image.network(photo, width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44))),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15))),
          _pastille(statut),
        ]),
        const SizedBox(height: 2),
        Text(sousTitre, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        if (motif != null && motif.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Motif de la modération : $motif', style: const TextStyle(fontSize: 13, color: Color(0xFF33454B))),
        ],
        if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 6, children: actions)],
      ]),
    );
  }

  Widget _boutonSupprimer(VoidCallback onPressed) => OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: BorderSide(color: Colors.red.shade200)),
        onPressed: onPressed,
        child: const Text('Supprimer'),
      );

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
                _titre('Lieux proposés'),
                if (_lieux.isEmpty)
                  Text('Vous n\'avez pas encore proposé de lieu.', style: TextStyle(color: Colors.grey.shade600)),
                for (final l in _lieux)
                  _carte(
                    titre: (l['nom'] ?? '').toString(),
                    sousTitre: '${(l['adresse'] ?? '').toString().isNotEmpty ? '${l['adresse']} · ' : ''}proposé le ${_date(l['created_at'])}',
                    statut: (l['statut'] ?? '').toString(),
                    photo: l['photo_url']?.toString(),
                    motif: l['statut'] == 'refuse' ? l['rejection_reason']?.toString() : null,
                    actions: [
                      if (l['statut'] != 'valide') ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                          onPressed: () async {
                            final ok = await Navigator.push<bool>(context,
                                MaterialPageRoute(builder: (_) => AddNaturalPlacePage(existant: l)));
                            if (ok == true) _charger();
                          },
                          child: Text(l['statut'] == 'refuse' ? 'Modifier et renvoyer' : 'Modifier'),
                        ),
                        _boutonSupprimer(() => _supprimer('natural_places', l['id'].toString(),
                            'Supprimer ce lieu ?', '« ${l['nom']} » sera définitivement supprimé.')),
                      ] else
                        OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => NaturalPlaceDetailPage(place: l))),
                          child: const Text('Voir la fiche'),
                        ),
                    ],
                  ),
                if (_lieux.any((l) => l['statut'] == 'valide'))
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(
                      'Un lieu publié ne se modifie plus directement : proposez une photo ou un équipement depuis sa fiche. '
                      'Pour le faire retirer, contactez l\'équipe PetsMatch.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
                _titre('Photos proposées'),
                if (_photos.isEmpty)
                  Text('Aucune photo proposée.', style: TextStyle(color: Colors.grey.shade600)),
                for (final p in _photos)
                  _carte(
                    titre: ((p['place'] as Map?)?['nom'] ?? 'Lieu').toString(),
                    sousTitre: 'Proposée le ${_date(p['created_at'])}',
                    statut: (p['statut'] ?? '').toString(),
                    photo: p['photo_url']?.toString(),
                    motif: p['statut'] == 'refuse' ? p['rejection_reason']?.toString() : null,
                    actions: [
                      if (p['statut'] == 'en_attente')
                        _boutonSupprimer(() => _supprimer('natural_place_photo_suggestions', p['id'].toString(),
                            'Retirer cette photo ?', 'La photo ne sera pas proposée à la modération.')),
                    ],
                  ),
                _titre('Équipements proposés'),
                if (_equipements.isEmpty)
                  Text('Aucun équipement proposé.', style: TextStyle(color: Colors.grey.shade600)),
                for (final e in _equipements)
                  _carte(
                    titre: ((e['place'] as Map?)?['nom'] ?? 'Lieu').toString(),
                    sousTitre: '${_equipementsLabels[e['field']] ?? e['field']} : ${e['value'] == true ? 'oui' : e['value'] == false ? 'non' : e['value']} · proposé le ${_date(e['created_at'])}',
                    statut: (e['statut'] ?? '').toString(),
                    photo: e['photo_url']?.toString(),
                    motif: e['statut'] == 'refuse' ? e['rejection_reason']?.toString() : null,
                    actions: [
                      if (e['statut'] == 'en_attente')
                        _boutonSupprimer(() => _supprimer('natural_place_amenity_suggestions', e['id'].toString(),
                            'Retirer cette proposition ?', 'L\'équipement ne sera pas proposé à la modération.')),
                    ],
                  ),
              ]),
            ),
    );
  }
}
