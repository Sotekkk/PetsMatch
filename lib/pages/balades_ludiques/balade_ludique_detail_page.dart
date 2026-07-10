import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';
import 'balade_ludique_jouer_page.dart';
import 'creation/creation_flow_page.dart';
import 'parcours_stats_page.dart';

class BaladeLudiqueDetailPage extends StatefulWidget {
  final String baladeId;
  const BaladeLudiqueDetailPage({super.key, required this.baladeId});

  @override
  State<BaladeLudiqueDetailPage> createState() => _BaladeLudiqueDetailPageState();
}

class _BaladeLudiqueDetailPageState extends State<BaladeLudiqueDetailPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _balade;
  List<Map<String, dynamic>> _points = [];
  List<Map<String, dynamic>> _avis = [];
  Map<String, dynamic>? _progression;
  bool _isFavori = false;
  bool _busy = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isOwner => _balade != null && _uid != null && _balade!['createur_uid'] == _uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final balade = await _supa.from('balades_ludiques').select().eq('id', widget.baladeId).single();
      final points = await _supa.from('balades_ludiques_points').select().eq('balade_id', widget.baladeId).order('ordre');
      final avis = await _supa.from('balades_ludiques_avis').select().eq('balade_id', widget.baladeId).order('created_at', ascending: false);

      Map<String, dynamic>? progression;
      bool isFavori = false;
      if (_uid != null) {
        final prog = await _supa.from('balades_ludiques_progressions').select()
            .eq('balade_id', widget.baladeId).eq('joueur_uid', _uid!).maybeSingle();
        progression = prog;
        final fav = await _supa.from('balades_ludiques_favoris').select()
            .eq('balade_id', widget.baladeId).eq('user_uid', _uid!).maybeSingle();
        isFavori = fav != null;
      }

      if (mounted) {
        setState(() {
          _balade = balade;
          _points = List<Map<String, dynamic>>.from(points as List);
          _avis = List<Map<String, dynamic>>.from(avis as List);
          _progression = progression;
          _isFavori = isFavori;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavori() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _isFavori = !_isFavori);
    try {
      if (_isFavori) {
        await _supa.from('balades_ludiques_favoris').insert({'user_uid': uid, 'balade_id': widget.baladeId});
      } else {
        await _supa.from('balades_ludiques_favoris').delete().eq('user_uid', uid).eq('balade_id', widget.baladeId);
      }
      final nbFavoris = await _supa.from('balades_ludiques_favoris').select().eq('balade_id', widget.baladeId).count(CountOption.exact);
      await _supa.from('balades_ludiques').update({'nb_favoris': nbFavoris.count}).eq('id', widget.baladeId);
    } catch (_) {}
  }

  Future<void> _commencer() async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour commencer un parcours')));
      return;
    }
    if (_progression == null) {
      try {
        final inserted = await _supa.from('balades_ludiques_progressions').insert({
          'balade_id': widget.baladeId, 'joueur_uid': uid,
        }).select().single();
        final nbJoueurs = await _supa.from('balades_ludiques_progressions').select().eq('balade_id', widget.baladeId).count(CountOption.exact);
        await _supa.from('balades_ludiques').update({'nb_joueurs': nbJoueurs.count}).eq('id', widget.baladeId);
        setState(() => _progression = inserted);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BaladeLudiqueJouerPage(baladeId: widget.baladeId)));
    _load();
  }

  Future<void> _signaler() async {
    final uid = _uid;
    if (uid == null) return;
    final raison = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Signaler ce parcours',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          for (final r in const [
            ('contenu_inapproprie', 'Contenu inapproprié'),
            ('spam', 'Spam'),
            ('maltraitance', 'Défi dangereux / maltraitance'),
            ('autre', 'Autre'),
          ])
            ListTile(title: Text(r.$2, style: const TextStyle(fontFamily: 'Galey')), onTap: () => Navigator.pop(context, r.$1)),
        ]),
      ),
    );
    if (raison == null) return;
    try {
      await _supa.from('signalements').insert({
        'reporter_uid': uid, 'target_type': 'balade_ludique', 'target_id': widget.baladeId, 'raison': raison,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement envoyé, merci.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vous avez déjà signalé ce parcours.')));
    }
  }

  Future<void> _laisserAvis() async {
    final uid = _uid;
    if (uid == null) return;
    int note = 5;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Votre avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) =>
            IconButton(
              icon: Icon(i < note ? Icons.star : Icons.star_border, color: Colors.amber),
              onPressed: () => setD(() => note = i + 1),
            ),
          )),
          TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Un commentaire (optionnel)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
        ],
      )),
    );
    if (ok != true) return;
    try {
      await _supa.from('balades_ludiques_avis').upsert({
        'balade_id': widget.baladeId, 'user_uid': uid, 'note': note, 'commentaire': ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
      }, onConflict: 'balade_id,user_uid');
      final rows = await _supa.from('balades_ludiques_avis').select('note').eq('balade_id', widget.baladeId);
      final notes = List<Map<String, dynamic>>.from(rows as List).map((r) => (r['note'] as num).toDouble()).toList();
      final moyenne = notes.isEmpty ? null : notes.reduce((a, b) => a + b) / notes.length;
      await _supa.from('balades_ludiques').update({
        'note_moyenne': moyenne == null ? null : double.parse(moyenne.toStringAsFixed(1)),
        'nb_avis': notes.length,
      }).eq('id', widget.baladeId);

      if (moyenne != null && moyenne >= 4.5) {
        try {
          final badge = await _supa.from('badges').select().eq('code', 'createur_bien_note').maybeSingle();
          if (badge != null) {
            await _supa.from('badges_obtenus').insert({
              'user_uid': _balade!['createur_uid'], 'badge_id': badge['id'], 'balade_id': widget.baladeId,
            });
          }
        } catch (_) {} // déjà obtenu
      }

      _load();
    } catch (_) {}
  }

  Future<void> _changerStatut(String statut) async {
    setState(() => _busy = true);
    try {
      await _supa.from('balades_ludiques').update({'statut': statut}).eq('id', widget.baladeId);
      if (statut == 'supprime' && mounted) {
        Navigator.pop(context);
        return;
      }
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmerSuppression() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce parcours ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible. Si des joueurs ont déjà progressé, préférez la désactivation.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) _changerStatut('supprime');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBlTeal)));
    }
    final b = _balade;
    if (b == null) {
      return const Scaffold(body: Center(child: Text('Parcours introuvable', style: TextStyle(fontFamily: 'Galey'))));
    }

    final statut = _progression?['statut'] as String?;
    final ctaLabel = statut == 'termine' ? 'Rejouer' : statut == 'en_cours' ? 'Continuer' : 'Commencer';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          backgroundColor: kBlTeal,
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.flag_outlined), tooltip: 'Signaler', onPressed: _signaler),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: (b['cover_url'] as String?)?.isNotEmpty == true
                ? CachedNetworkImage(imageUrl: b['cover_url'], fit: BoxFit.cover)
                : Container(color: kBlGreen, child: const Center(child: Icon(Icons.map_outlined, size: 60, color: Colors.white))),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (b['type_evenement'] != 'communautaire')
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: kBlOrange, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    b['type_evenement'] == 'officiel_petsmatch' ? '🏆 Chasse au trésor officielle PetsMatch' : '🏆 Événement partenaire${b['partenaire_nom'] != null ? ' — ${b['partenaire_nom']}' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              Text(b['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 22)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _infoChip(blDifficulteLabel(b['difficulte']?.toString() ?? 'facile'), blDifficulteColor(b['difficulte']?.toString() ?? 'facile')),
                if (b['duree_min'] != null) _infoChip(blDureeLabel(b['duree_min'] as int?), Colors.grey.shade700),
                if (b['distance_km'] != null) _infoChip('${b['distance_km']} km', Colors.grey.shade700),
                _infoChip(b['gratuit'] == true ? 'Gratuit' : '${b['prix']} €', kBlTeal),
                if (b['note_moyenne'] != null) _infoChip('⭐ ${b['note_moyenne']} (${b['nb_avis']})', Colors.amber.shade700),
                _infoChip('❤️ ${b['nb_favoris'] ?? 0}', Colors.pink.shade400),
              ]),
              const SizedBox(height: 16),
              Text(b['description']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
              const SizedBox(height: 20),
              Text('${_points.length} étape(s)', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              ..._points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  CircleAvatar(radius: 12, backgroundColor: kBlTeal.withOpacity(0.1),
                      child: Text('${p['ordre']}', style: const TextStyle(fontSize: 11, fontFamily: 'Galey', color: kBlTeal))),
                  const SizedBox(width: 8),
                  Icon(blTypeDefiIcon(p['type_defi']?.toString() ?? ''), size: 16, color: kBlGreen),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                ]),
              )),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _commencer,
                    style: ElevatedButton.styleFrom(backgroundColor: kBlOrange, padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: Text(ctaLabel, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _toggleFavori,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300)),
                    child: Icon(_isFavori ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
                  ),
                ),
              ]),
              if (statut == 'termine' && !_isOwner) ...[
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _laisserAvis, child: const Text('Laisser un avis', style: TextStyle(fontFamily: 'Galey'))),
              ],
              if (_isOwner) ...[
                const SizedBox(height: 20),
                const Divider(),
                const Text('Gestion du parcours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.bar_chart, size: 16),
                    label: const Text('Statistiques', style: TextStyle(fontFamily: 'Galey')),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParcoursStatsPage(baladeId: widget.baladeId))),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey')),
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => CreationFlowPage(baladeId: widget.baladeId)));
                      _load();
                    },
                  ),
                  OutlinedButton.icon(
                    icon: Icon(b['statut'] == 'desactive' ? Icons.play_arrow : Icons.pause, size: 16),
                    label: Text(b['statut'] == 'desactive' ? 'Réactiver' : 'Désactiver', style: const TextStyle(fontFamily: 'Galey')),
                    onPressed: _busy ? null : () => _changerStatut(b['statut'] == 'desactive' ? 'publie' : 'desactive'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                    onPressed: _busy ? null : _confirmerSuppression,
                  ),
                ]),
              ],
              if (_avis.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Divider(),
                Text('Avis (${_avis.length})', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                ..._avis.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: List.generate(5, (i) =>
                      Icon(i < (a['note'] as num).toInt() ? Icons.star : Icons.star_border, size: 14, color: Colors.amber),
                    )),
                    if ((a['commentaire'] as String?)?.isNotEmpty == true)
                      Text(a['commentaire'], style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  ]),
                )),
              ],
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _infoChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}
