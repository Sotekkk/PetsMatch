import 'package:PetsMatch/main.dart' show User_Info;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raisons d'une demande de retrait de lieu (lieux_demandes_retrait.raison).
/// `nature` : null = commune aux deux, sinon 'naturel' / 'petfriendly'.
const kRaisonsRetraitLieu = <(String, String, String?)>[
  ('ferme', 'Le lieu a fermé définitivement', null),
  ('inexistant', 'Ce lieu n\'existe pas ou l\'adresse est fausse', null),
  ('doublon', 'Doublon d\'un autre lieu', null),
  ('animaux_refuses', 'Les animaux n\'y sont plus acceptés', 'petfriendly'),
  ('dangereux', 'Lieu dangereux ou interdit d\'accès', 'naturel'),
  ('prive', 'Propriété privée', null),
  ('autre', 'Autre raison', null),
];

String libelleRaisonRetrait(String? raison) =>
    kRaisonsRetraitLieu.where((r) => r.$1 == raison).map((r) => r.$2).firstOrNull ?? (raison ?? '');

/// « Demander le retrait de ce lieu » : lieu naturel publié, ou lieu
/// pet-friendly publié sans gestionnaire. La demande part à l'équipe
/// PetsMatch, qui l'accepte ou la refuse (suivi dans Mes contributions).
/// Miroir site : components/lieux/DemandeRetraitLieu.tsx.
class BoutonDemandeRetraitLieu extends StatefulWidget {
  final String nature; // 'naturel' | 'petfriendly'
  final String placeId;
  final String placeNom;
  const BoutonDemandeRetraitLieu({super.key, required this.nature, required this.placeId, required this.placeNom});

  @override
  State<BoutonDemandeRetraitLieu> createState() => _BoutonDemandeRetraitLieuState();
}

class _BoutonDemandeRetraitLieuState extends State<BoutonDemandeRetraitLieu> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  bool _enAttente = false;

  String get _colonne => widget.nature == 'naturel' ? 'natural_place_id' : 'petfriendly_place_id';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final r = await _supa.from('lieux_demandes_retrait').select('id')
          .eq('uid', uid).eq(_colonne, widget.placeId).eq('statut', 'en_attente').limit(1);
      if (mounted) setState(() => _enAttente = (r as List).isNotEmpty);
    } catch (_) {}
  }

  Future<void> _demander() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour faire cette demande.')));
      return;
    }
    final raisons = kRaisonsRetraitLieu.where((r) => r.$3 == null || r.$3 == widget.nature).toList();
    String? raison;
    final commentaireCtrl = TextEditingController();
    final envoye = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final commentaireRequis = raison == 'autre' || raison == 'doublon';
        final valide = raison != null && (!commentaireRequis || commentaireCtrl.text.trim().isNotEmpty);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Demander le retrait de ce lieu',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 4),
            Text('L\'équipe PetsMatch vérifie la demande avant de retirer « ${widget.placeNom} ». '
                'Vous serez prévenu(e) de sa décision.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: raison,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Raison', border: OutlineInputBorder()),
              items: [for (final r in raisons) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
              onChanged: (v) => setS(() => raison = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentaireCtrl,
              maxLines: 3,
              onChanged: (_) => setS(() {}),
              decoration: InputDecoration(
                labelText: raison == 'doublon'
                    ? 'Nom ou adresse du lieu en double (obligatoire)'
                    : commentaireRequis ? 'Précisions (obligatoire)' : 'Précisions (facultatif)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: valide ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Envoyer la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ])),
        );
      }),
    );
    final commentaire = commentaireCtrl.text.trim();
    commentaireCtrl.dispose();
    if (envoye != true || raison == null) return;
    try {
      await _supa.from('lieux_demandes_retrait').insert({
        'nature': widget.nature,
        _colonne: widget.placeId,
        'place_nom': widget.placeNom,
        'uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'profile_id': User_Info.activeProfileId,
        'raison': raison,
        if (commentaire.isNotEmpty) 'commentaire': commentaire,
      });
      if (!mounted) return;
      setState(() => _enAttente = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande envoyée : l\'équipe PetsMatch va l\'examiner.')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.code == '23505'
            ? 'Vous avez déjà une demande de retrait en cours pour ce lieu.'
            : 'Envoi impossible : ${e.message}'),
        backgroundColor: Colors.red,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(Icons.delete_sweep_outlined, color: _enAttente ? Colors.grey : Colors.red.shade400, size: 20),
      title: Text(_enAttente ? 'Demande de retrait envoyée' : 'Demander le retrait de ce lieu',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: _enAttente
          ? const Text('En attente de l\'équipe PetsMatch (suivi dans Mes contributions)', style: TextStyle(fontSize: 11))
          : null,
      trailing: _enAttente ? null : const Icon(Icons.chevron_right, size: 18),
      onTap: _enAttente ? null : _demander,
    );
  }
}
