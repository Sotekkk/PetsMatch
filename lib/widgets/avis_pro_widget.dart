import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Système d'avis générique pour les profils pro (`avis_pro`), scopé
// pro_profile_id dès la création. Conçu pour taxi_animalier, réutilisable
// tel quel par les futurs modules photographe/toiletteur — pas de module
// dédié par profession, contrairement à petfriendly_reviews (lieux).

class AvisProSection extends StatefulWidget {
  final String proUid;
  final String? proProfileId;
  const AvisProSection({super.key, required this.proUid, required this.proProfileId});

  @override
  State<AvisProSection> createState() => _AvisProSectionState();
}

class _AvisProSectionState extends State<AvisProSection> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _avis = [];
  bool _dejaNote = false;
  // Un avis n'est proposé qu'à un client ayant eu une interaction réelle
  // avec ce pro (RDV confirmé/terminé ou compte-rendu) — vérifié aussi côté
  // RLS (can_review_pro), ce check ne sert qu'à ne pas afficher un
  // formulaire qui échouerait de toute façon.
  bool _eligible = false;
  // Identité affichée sur chaque avis (nom + photo, comme Google) — résolue
  // par client_uid, profil principal.
  Map<String, Map<String, dynamic>> _reviewers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _supa.from('avis_pro').select().eq('pro_uid', widget.proUid);
      if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', widget.proProfileId!);
      }
      final rows = await q.order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Résout le nom + photo de chaque auteur d'avis (profil principal).
      Map<String, Map<String, dynamic>> reviewers = {};
      final clientUids = list.map((a) => a['client_uid']?.toString()).whereType<String>().toSet().toList();
      if (clientUids.isNotEmpty) {
        try {
          final profs = await _supa.from('user_profiles')
              .select('uid, firstname, lastname, nom, avatar_url, profile_type')
              .inFilter('uid', clientUids).eq('is_main', true);
          for (final p in profs as List) {
            final isElevage = p['profile_type'] == 'eleveur';
            final name = isElevage && (p['nom'] as String?)?.isNotEmpty == true
                ? p['nom'] as String
                : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
            reviewers[p['uid'].toString()] = {
              'name': name.isEmpty ? 'Utilisateur PetsMatch' : name,
              'photo': p['avatar_url'] as String?,
            };
          }
        } catch (_) {}
      }

      // Éligibilité résolue par PROFIL (particulier), pas seulement par
      // compte — un RDV pris avec un autre profil du même compte (éleveur,
      // pro…) ne doit pas rendre le profil particulier éligible.
      bool eligible = false;
      if (uid != null && uid != widget.proUid) {
        try {
          final myProfile = await _supa.from('user_profiles')
              .select('id').eq('uid', uid).eq('profile_type', 'particulier').maybeSingle();
          eligible = await _supa.rpc('can_review_pro', params: {
            'p_pro_uid': widget.proUid,
            'p_client_uid': uid,
            if (myProfile?['id'] != null) 'p_client_profile_id': myProfile!['id'],
            if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty)
              'p_pro_profile_id': widget.proProfileId,
          }) as bool? ?? false;
        } catch (_) {}
      }
      if (mounted) setState(() {
        _avis = list;
        _reviewers = reviewers;
        _dejaNote = uid != null && list.any((a) => a['client_uid'] == uid);
        _eligible = eligible;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _contester(String avisId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != widget.proUid) return;
    final motifCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Signaler cet avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: motifCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Motif du signalement…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('avis_pro_contests').insert({
        'avis_id': avisId,
        'pro_uid': widget.proUid,
        'motif': motifCtrl.text.trim().isEmpty ? 'Non précisé' : motifCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Signalement envoyé — notre équipe va l\'examiner.', style: TextStyle(fontFamily: 'Galey'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  double get _moyenne {
    if (_avis.isEmpty) return 0;
    return _avis.fold<int>(0, (s, a) => s + ((a['note'] as num?)?.toInt() ?? 0)) / _avis.length;
  }

  Future<void> _openForm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AvisProForm(
        proUid: widget.proUid,
        proProfileId: widget.proProfileId,
        clientUid: uid,
        onSubmit: () { Navigator.pop(context); _load(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Avis', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 8),
        if (_avis.isNotEmpty) ...[
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFA000)),
          const SizedBox(width: 2),
          Text('${_moyenne.toStringAsFixed(1)} (${_avis.length})',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ],
        const Spacer(),
        if (!_dejaNote && _eligible)
          TextButton(onPressed: _openForm, child: const Text('Laisser un avis', style: TextStyle(fontFamily: 'Galey', color: _teal))),
      ]),
      const SizedBox(height: 8),
      if (_avis.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Aucun avis pour l\'instant.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
        )
      else
        ..._avis.map((a) => _AvisTile(
              avis: a,
              reviewer: _reviewers[a['client_uid']?.toString()],
              isPro: FirebaseAuth.instance.currentUser?.uid == widget.proUid,
              onContester: () => _contester(a['id'].toString()),
            )),
    ]);
  }
}

class _AvisTile extends StatelessWidget {
  static const _teal = Color(0xFF0C5C6C);
  final Map<String, dynamic> avis;
  final Map<String, dynamic>? reviewer;
  final bool isPro;
  final VoidCallback onContester;
  const _AvisTile({required this.avis, this.reviewer, this.isPro = false, required this.onContester});

  @override
  Widget build(BuildContext context) {
    final note = (avis['note'] as num?)?.toInt() ?? 0;
    final dh = DateTime.tryParse(avis['created_at']?.toString() ?? '');
    final dateStr = dh != null ? DateFormat('d MMM yyyy', 'fr_FR').format(dh) : '';
    final name = reviewer?['name'] as String? ?? 'Utilisateur PetsMatch';
    final photo = reviewer?['photo'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFE8F4F6),
            backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
            child: (photo == null || photo.isEmpty)
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: _teal))
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text(dateStr, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
        ]),
        const SizedBox(height: 6),
        Row(children: List.generate(5, (i) =>
            Icon(i < note ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: const Color(0xFFFFA000)))),
        if ((avis['commentaire'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(avis['commentaire'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ],
        if (isPro) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onContester,
              icon: const Icon(Icons.flag_outlined, size: 14, color: Colors.grey),
              label: const Text('Signaler', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _AvisProForm extends StatefulWidget {
  final String proUid;
  final String? proProfileId;
  final String clientUid;
  final VoidCallback onSubmit;
  const _AvisProForm({required this.proUid, required this.proProfileId, required this.clientUid, required this.onSubmit});

  @override
  State<_AvisProForm> createState() => _AvisProFormState();
}

class _AvisProFormState extends State<_AvisProForm> {
  static const _teal = Color(0xFF0C5C6C);
  int _note = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_note == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci de choisir une note', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final profileRow = await Supabase.instance.client
          .from('user_profiles').select('id').eq('uid', widget.clientUid).eq('profile_type', 'particulier').maybeSingle();
      final clientProfileId = profileRow?['id'] as String?;
      await Supabase.instance.client.from('avis_pro').insert({
        'pro_uid': widget.proUid,
        if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) 'pro_profile_id': widget.proProfileId,
        'client_uid': widget.clientUid,
        if (clientProfileId != null) 'client_profile_id': clientProfileId,
        'note': _note,
        'commentaire': _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      });
      widget.onSubmit();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().contains('unique')
                ? 'Vous avez déjà laissé un avis'
                : 'Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Laisser un avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 16),
        Row(children: List.generate(5, (i) => GestureDetector(
          onTap: () => setState(() => _note = i + 1),
          child: Icon(i < _note ? Icons.star_rounded : Icons.star_border_rounded, size: 32, color: const Color(0xFFFFA000)),
        ))),
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          maxLines: 4,
          maxLength: 500,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: InputDecoration(
            hintText: 'Votre commentaire (optionnel)…',
            hintStyle: const TextStyle(fontFamily: 'Galey'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Publier l\'avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
