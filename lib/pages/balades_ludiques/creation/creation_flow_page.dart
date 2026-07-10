import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import '../balades_ludiques_shared.dart';

part 'step_infos_generales.dart';
part 'step_points_carte.dart';
part 'step_defi_point.dart';
part 'step_recap_publication.dart';

class CreationFlowPage extends StatefulWidget {
  final String? baladeId;
  const CreationFlowPage({super.key, this.baladeId});

  @override
  State<CreationFlowPage> createState() => _CreationFlowPageState();
}

class _CreationFlowPageState extends State<CreationFlowPage> {
  final _supa = Supabase.instance.client;
  final _pageCtrl = PageController();
  int _page = 0;
  bool _loading = false;
  bool _publishing = false;

  // ── Infos générales
  final titreCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  File? coverFile;
  String? coverUrl;
  String espece = 'tous';
  bool famille = false;
  bool sportif = false;
  bool pmr = false;
  bool gratuit = true;
  final prixCtrl = TextEditingController();
  String difficulte = 'facile';
  final dureeCtrl = TextEditingController();
  final distanceCtrl = TextEditingController();
  String typeEvenement = 'communautaire';
  final partenaireNomCtrl = TextEditingController();
  DateTime? eventDebut;
  DateTime? eventFin;

  // ── Points & défis
  final List<Map<String, dynamic>> points = [];

  bool get isEdit => widget.baladeId != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final b = await _supa.from('balades_ludiques').select().eq('id', widget.baladeId!).single();
    final pts = await _supa.from('balades_ludiques_points').select().eq('balade_id', widget.baladeId!).order('ordre');
    titreCtrl.text = b['titre'] ?? '';
    descriptionCtrl.text = b['description'] ?? '';
    coverUrl = b['cover_url'];
    espece = b['espece_cible'] ?? 'tous';
    famille = b['famille'] ?? false;
    sportif = b['sportif'] ?? false;
    pmr = b['accessible_pmr'] ?? false;
    gratuit = b['gratuit'] ?? true;
    prixCtrl.text = b['prix']?.toString() ?? '';
    difficulte = b['difficulte'] ?? 'facile';
    dureeCtrl.text = b['duree_min']?.toString() ?? '';
    distanceCtrl.text = b['distance_km']?.toString() ?? '';
    typeEvenement = b['type_evenement'] ?? 'communautaire';
    partenaireNomCtrl.text = b['partenaire_nom'] ?? '';
    eventDebut = DateTime.tryParse(b['event_debut']?.toString() ?? '');
    eventFin = DateTime.tryParse(b['event_fin']?.toString() ?? '');
    points
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(pts as List).map((p) => Map<String, dynamic>.from(p)));
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    titreCtrl.dispose();
    descriptionCtrl.dispose();
    prixCtrl.dispose();
    dureeCtrl.dispose();
    distanceCtrl.dispose();
    partenaireNomCtrl.dispose();
    super.dispose();
  }

  bool get _canGoNextFromInfos => titreCtrl.text.trim().isNotEmpty;
  bool get _canGoNextFromPoints => points.isNotEmpty;

  void _next() {
    if (_page == 0 && !_canGoNextFromInfos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donnez un titre à votre parcours')));
      return;
    }
    if (_page == 1 && !_canGoNextFromPoints) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez au moins un point d\'intérêt')));
      return;
    }
    if (_page < 2) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    } else {
      _publier();
    }
  }

  void _previous() {
    if (_page > 0) _pageCtrl.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
  }

  Future<void> _publier() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _publishing = true);
    try {
      String? finalCoverUrl = coverUrl;
      final baladeId = widget.baladeId ?? '';
      if (coverFile != null) {
        finalCoverUrl = await uploadPhoto(coverFile!, 'balades_ludiques/${baladeId.isEmpty ? DateTime.now().millisecondsSinceEpoch : baladeId}/cover.jpg');
      }

      final premierPoint = points.first;
      final row = <String, dynamic>{
        'createur_uid': uid,
        'titre': titreCtrl.text.trim(),
        'description': descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
        'cover_url': finalCoverUrl,
        'statut': 'publie',
        'espece_cible': espece,
        'famille': famille,
        'sportif': sportif,
        'accessible_pmr': pmr,
        'gratuit': gratuit,
        'prix': gratuit ? null : double.tryParse(prixCtrl.text.replaceAll(',', '.')),
        'difficulte': difficulte,
        'duree_min': int.tryParse(dureeCtrl.text),
        'distance_km': double.tryParse(distanceCtrl.text.replaceAll(',', '.')),
        'lat_depart': premierPoint['lat'],
        'lng_depart': premierPoint['lng'],
        'type_evenement': User_Info.isAdmin ? typeEvenement : 'communautaire',
        'partenaire_nom': User_Info.isAdmin && typeEvenement == 'officiel_partenaire' ? partenaireNomCtrl.text.trim() : null,
        'event_debut': User_Info.isAdmin ? eventDebut?.toIso8601String() : null,
        'event_fin': User_Info.isAdmin ? eventFin?.toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      String id;
      if (isEdit) {
        id = widget.baladeId!;
        await _supa.from('balades_ludiques').update(row).eq('id', id);
        await _supa.from('balades_ludiques_points').delete().eq('balade_id', id);
      } else {
        row['published_at'] = DateTime.now().toIso8601String();
        final inserted = await _supa.from('balades_ludiques').insert(row).select().single();
        id = inserted['id'] as String;
      }

      var ordre = 1;
      for (final p in points) {
        await _supa.from('balades_ludiques_points').insert({
          'balade_id': id,
          'ordre': ordre++,
          'titre': p['titre'],
          'description': p['description'],
          'lat': p['lat'],
          'lng': p['lng'],
          'rayon_validation_m': p['rayon_validation_m'] ?? 30,
          'type_defi': p['type_defi'],
          'question_texte': p['question_texte'],
          'question_reponse': p['question_reponse'],
          'consigne_texte': p['consigne_texte'],
          'qr_code_value': p['qr_code_value'],
          'indice': p['indice'],
        });
      }

      if (!isEdit) {
        try {
          final existing = await _supa.from('joueurs_xp').select().eq('user_uid', uid).maybeSingle();
          final nouveauNbCrees = ((existing?['nb_parcours_crees'] as int?) ?? 0) + 1;
          await _supa.from('joueurs_xp').upsert({
            'user_uid': uid,
            'xp_total': existing?['xp_total'] ?? 0,
            'nb_parcours_completes': existing?['nb_parcours_completes'] ?? 0,
            'nb_parcours_crees': nouveauNbCrees,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_uid');

          if (nouveauNbCrees == 1) {
            final badge = await _supa.from('badges').select().eq('code', 'createur_premier').maybeSingle();
            if (badge != null) {
              try {
                await _supa.from('badges_obtenus').insert({'user_uid': uid, 'badge_id': badge['id'], 'balade_id': id});
              } catch (_) {} // déjà obtenu
            }
          }
        } catch (_) {}
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBlTeal)));
    final isLast = _page == 2;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: Text(isEdit ? 'Modifier le parcours' : 'Nouveau parcours', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _page == i ? 22 : 8, height: 8,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: _page >= i ? kBlTeal : Colors.grey.shade300),
          ))),
        ),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _StepInfosGenerales(s: this),
              _StepPointsCarte(s: this),
              _StepRecapPublication(s: this),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              if (_page > 0) Expanded(
                child: OutlinedButton(onPressed: _previous, child: const Text('Précédent', style: TextStyle(fontFamily: 'Galey'))),
              ),
              if (_page > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _publishing ? null : _next,
                  style: ElevatedButton.styleFrom(backgroundColor: isLast ? kBlOrange : kBlTeal, padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _publishing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isLast ? (isEdit ? 'Enregistrer' : 'Publier') : 'Suivant',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
