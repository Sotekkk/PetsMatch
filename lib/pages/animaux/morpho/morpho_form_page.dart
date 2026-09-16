import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'morpho_constants.dart';
import 'morpho_silhouette.dart';

const int _kMaxVideoBytes = 50 * 1024 * 1024; // 50 Mo — aligné sur pension_journal_page.dart

/// Création d'un nouveau suivi morphologique. Page complète (pas une bottom
/// sheet — trop de contenu), sections dans l'ordre du formulaire papier
/// d'origine : infos générales → données animal → photos → vidéos →
/// silhouette → observations statiques → observations dynamiques.
class MorphoFormPage extends StatefulWidget {
  /// Null pour un client/animal saisi à la main (pas de fiche animal
  /// existante — voir [animalNomLibre]/[clientNomLibre]).
  final String? animalId;
  final String espece;
  final String? proProfileId; // non-null si créé par un pro (source = professionnel)
  final String? proNom;
  final String? animalNomLibre;
  final String? clientNomLibre;
  /// Non-null pour modifier un suivi existant (pro uniquement) — pré-remplit
  /// tout le formulaire ; l'enregistrement met à jour la même ligne au lieu
  /// d'en créer une nouvelle (aucune notification renvoyée au propriétaire).
  final Map<String, dynamic>? existingSuivi;

  const MorphoFormPage({
    super.key,
    this.animalId,
    required this.espece,
    this.proProfileId,
    this.proNom,
    this.animalNomLibre,
    this.clientNomLibre,
    this.existingSuivi,
  });

  @override
  State<MorphoFormPage> createState() => _MorphoFormPageState();
}

class _MorphoFormPageState extends State<MorphoFormPage> {
  final _supa = Supabase.instance.client;
  bool _saving = false;

  DateTime _date = DateTime.now();
  String _typeSuivi = 'bilan_morphologique';
  final _professionnelCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();
  final _commentairesCtrl = TextEditingController();
  final _poidsCtrl = TextEditingController();
  final _tailleCtrl = TextEditingController();
  final _checkpointCtrl = TextEditingController();
  String _niveauActivite = 'non_evalue';
  final _activiteSportiveCtrl = TextEditingController();
  late final _animalNomCtrl = TextEditingController(text: widget.animalNomLibre ?? '');
  late final _clientNomCtrl = TextEditingController(text: widget.clientNomLibre ?? '');
  final _clientContactCtrl = TextEditingController();

  final Map<String, File> _photosVues = {}; // face/dos/profil_g/profil_d — nouvelles
  final Map<String, String> _photosVuesExistantes = {}; // vue -> url déjà enregistrée
  final List<File> _photosExtra = [];
  final List<String> _photosExtraExistantes = [];
  final List<_VideoEntree> _videos = [];
  final List<_PointEntree> _points = [];
  late final Map<String, _ObsStatique> _observations = {
    for (final c in kCategoriesObservationStatique) c.$1: _ObsStatique(),
  };
  final List<_Mouvement> _mouvements = [];

  late String _vueSilhouette = vuesDisponibles(morphoSpeciesKey(widget.espece) ?? 'chien').first.$1;
  bool _loadingExisting = false;

  bool get _saisieLibre => widget.animalId == null;
  bool get _isEditing => widget.existingSuivi != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _prefillFromExisting();
    } else {
      if (widget.proNom != null) _professionnelCtrl.text = widget.proNom!;
      if (widget.animalId != null) _prefillAnimal();
    }
  }

  Future<void> _prefillFromExisting() async {
    setState(() => _loadingExisting = true);
    final s = widget.existingSuivi!;
    final suiviId = s['id'].toString();
    _typeSuivi = s['type_suivi']?.toString() ?? _typeSuivi;
    _date = DateTime.tryParse(s['date']?.toString() ?? '') ?? _date;
    _professionnelCtrl.text = s['professionnel_nom']?.toString() ?? '';
    _motifCtrl.text = s['motif']?.toString() ?? '';
    _commentairesCtrl.text = s['commentaires']?.toString() ?? '';
    _poidsCtrl.text = s['poids']?.toString() ?? '';
    _tailleCtrl.text = s['taille']?.toString() ?? '';
    _niveauActivite = s['niveau_activite']?.toString() ?? _niveauActivite;
    _activiteSportiveCtrl.text = s['activite_sportive']?.toString() ?? '';
    _checkpointCtrl.text = s['checkpoint_age']?.toString() ?? '';
    _animalNomCtrl.text = s['animal_nom_libre']?.toString() ?? _animalNomCtrl.text;
    _clientNomCtrl.text = s['client_nom_libre']?.toString() ?? _clientNomCtrl.text;
    _clientContactCtrl.text = s['client_contact_libre']?.toString() ?? '';

    try {
      final results = await Future.wait([
        _supa.from('suivis_morpho_photos').select().eq('suivi_id', suiviId),
        _supa.from('suivis_morpho_videos').select().eq('suivi_id', suiviId),
        _supa.from('suivis_morpho_points').select().eq('suivi_id', suiviId),
        _supa.from('suivis_morpho_observations').select().eq('suivi_id', suiviId),
        _supa.from('suivis_morpho_mouvements').select().eq('suivi_id', suiviId),
      ]);
      final photos = List<Map<String, dynamic>>.from(results[0] as List);
      final videos = List<Map<String, dynamic>>.from(results[1] as List);
      final points = List<Map<String, dynamic>>.from(results[2] as List);
      final observations = List<Map<String, dynamic>>.from(results[3] as List);
      final mouvements = List<Map<String, dynamic>>.from(results[4] as List);

      for (final p in photos) {
        final vue = p['vue']?.toString() ?? '';
        if (kVuesPhotos.any((v) => v.$1 == vue)) {
          _photosVuesExistantes[vue] = p['url'] as String;
        } else if (vue == 'autre') {
          _photosExtraExistantes.add(p['url'] as String);
        }
      }

      final videoIdToIndex = <String, int>{};
      for (final v in videos) {
        videoIdToIndex[v['id'].toString()] = _videos.length;
        _videos.add(_VideoEntree(
          existingUrl: v['url'] as String,
          activite: v['activite']?.toString() ?? kActivitesMouvement.first.$1,
          commentaire: v['commentaire']?.toString() ?? '',
        ));
      }

      for (final p in points) {
        final photoRow = photos.cast<Map<String, dynamic>?>().firstWhere(
            (ph) => ph?['point_id']?.toString() == p['id'].toString(), orElse: () => null);
        _points.add(_PointEntree(
          xPct: ((p['x_pct'] as num).toDouble()) / 100,
          yPct: ((p['y_pct'] as num).toDouble()) / 100,
          vue: p['vue']?.toString() ?? _vueSilhouette,
          categorie: p['categorie']?.toString() ?? 'autre',
          note: p['note']?.toString() ?? '',
          couleur: p['couleur']?.toString(),
          existingPhotoUrl: photoRow?['url'] as String?,
        ));
      }

      for (final o in observations) {
        final cat = o['categorie']?.toString();
        if (cat != null && _observations.containsKey(cat)) {
          _observations[cat]!.valeur = o['valeur']?.toString() ?? 'non_evalue';
          _observations[cat]!.commentaire = o['commentaire']?.toString() ?? '';
        }
      }

      for (final m in mouvements) {
        final vid = m['video_id']?.toString();
        _mouvements.add(_Mouvement()
          ..activite = m['activite']?.toString() ?? kActivitesMouvement.first.$1
          ..observation = m['observation']?.toString() ?? ''
          ..geneObservee = m['gene_observee'] as bool?
          ..commentaire = m['commentaire']?.toString() ?? ''
          ..videoIndex = vid != null ? videoIdToIndex[vid] : null);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingExisting = false);
  }

  Future<void> _prefillAnimal() async {
    try {
      final a = await _supa.from('animaux').select('poids, taille, date_naissance')
          .eq('id', widget.animalId!).maybeSingle();
      if (a == null || !mounted) return;
      if (a['poids'] != null) _poidsCtrl.text = a['poids'].toString();
      if (a['taille'] != null) _tailleCtrl.text = a['taille'].toString();
    } catch (_) {}
  }

  @override
  void dispose() {
    _professionnelCtrl.dispose();
    _motifCtrl.dispose();
    _commentairesCtrl.dispose();
    _poidsCtrl.dispose();
    _tailleCtrl.dispose();
    _checkpointCtrl.dispose();
    _activiteSportiveCtrl.dispose();
    _animalNomCtrl.dispose();
    _clientNomCtrl.dispose();
    _clientContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVuePhoto(String vue) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (f == null) return;
    setState(() { _photosVues[vue] = File(f.path); _photosVuesExistantes.remove(vue); });
  }

  Future<void> _pickVuePhotoCamera(String vue) async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88);
    if (f == null) return;
    setState(() { _photosVues[vue] = File(f.path); _photosVuesExistantes.remove(vue); });
  }

  Future<void> _ajouterPhotoExtra() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f == null) return;
    setState(() => _photosExtra.add(File(f.path)));
  }

  Future<void> _ajouterVideo() async {
    final choix = await showModalBottomSheet<_VideoEntree>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _AjoutVideoSheet(),
    );
    if (choix != null) setState(() => _videos.add(choix));
  }

  Future<void> _ajouterPoint(double xPct, double yPct) async {
    final result = await showModalBottomSheet<_PointEntree>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PointSheet(initial: _PointEntree(xPct: xPct, yPct: yPct, vue: _vueSilhouette)),
    );
    if (result != null) setState(() => _points.add(result));
  }

  Future<void> _editerPoint(_PointEntree point) async {
    final result = await showModalBottomSheet<_PointEntree>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PointSheet(initial: point, allowDelete: true),
    );
    if (result != null) {
      setState(() {
        final i = _points.indexOf(point);
        if (result.deleted) {
          _points.removeAt(i);
        } else {
          _points[i] = result;
        }
      });
    }
  }

  /// Points du profil actuellement affiché, avec pour id l'index dans la
  /// liste complète [_points] (permet de retrouver la bonne entrée au tap).
  List<MorphoPoint> _displayedPoints() => [
        for (var i = 0; i < _points.length; i++)
          if (_points[i].vue == _vueSilhouette)
            MorphoPoint(id: '$i', xPct: _points[i].xPct, yPct: _points[i].yPct, categorie: _points[i].categorie, note: _points[i].note, couleur: _points[i].couleur),
      ];

  Future<void> _ajouterMouvement() async {
    final result = await showModalBottomSheet<_Mouvement>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _MouvementSheet(),
    );
    if (result != null) setState(() => _mouvements.add(result));
  }

  Future<void> _enregistrer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final source = widget.proProfileId != null ? 'professionnel' : 'proprietaire';
      final headerData = <String, dynamic>{
        'type_suivi': _typeSuivi,
        'date': _date.toIso8601String().split('T').first,
        'professionnel_nom': _professionnelCtrl.text.trim().isEmpty ? null : _professionnelCtrl.text.trim(),
        'motif': _motifCtrl.text.trim().isEmpty ? null : _motifCtrl.text.trim(),
        'commentaires': _commentairesCtrl.text.trim().isEmpty ? null : _commentairesCtrl.text.trim(),
        'poids': double.tryParse(_poidsCtrl.text.replaceAll(',', '.')),
        'taille': double.tryParse(_tailleCtrl.text.replaceAll(',', '.')),
        'niveau_activite': _niveauActivite,
        'activite_sportive': _activiteSportiveCtrl.text.trim().isEmpty ? null : _activiteSportiveCtrl.text.trim(),
        'checkpoint_age': _checkpointCtrl.text.trim().isEmpty ? null : _checkpointCtrl.text.trim(),
        if (_saisieLibre) ...{
          'animal_nom_libre': _animalNomCtrl.text.trim().isEmpty ? null : _animalNomCtrl.text.trim(),
          'espece_libre': morphoSpeciesKey(widget.espece) ?? widget.espece,
          'client_nom_libre': _clientNomCtrl.text.trim().isEmpty ? null : _clientNomCtrl.text.trim(),
          'client_contact_libre': _clientContactCtrl.text.trim().isEmpty ? null : _clientContactCtrl.text.trim(),
        },
      };

      final String suiviId;
      if (_isEditing) {
        suiviId = widget.existingSuivi!['id'].toString();
        await _supa.from('suivis_morpho').update(headerData).eq('id', suiviId);
        // Les enfants sont entièrement recréés à chaque enregistrement (plus
        // simple et sûr qu'un diff champ par champ) ; les fichiers déjà
        // uploadés (photos/vidéos non remplacées) sont réutilisés tels quels
        // ci-dessous, sans nouvel upload.
        await Future.wait([
          _supa.from('suivis_morpho_photos').delete().eq('suivi_id', suiviId),
          _supa.from('suivis_morpho_videos').delete().eq('suivi_id', suiviId),
          _supa.from('suivis_morpho_points').delete().eq('suivi_id', suiviId),
          _supa.from('suivis_morpho_observations').delete().eq('suivi_id', suiviId),
          _supa.from('suivis_morpho_mouvements').delete().eq('suivi_id', suiviId),
        ]);
      } else {
        final inserted = await _supa.from('suivis_morpho').insert({
          if (widget.animalId != null) 'animal_id': widget.animalId,
          'uid_auteur': uid,
          if (widget.proProfileId != null) 'pro_profile_id': widget.proProfileId,
          'source': source,
          ...headerData,
        }).select('id').single();
        suiviId = inserted['id'] as String;
      }
      final base = 'animaux/${widget.animalId ?? 'libre'}/morpho/$suiviId';

      // Photos de vues guidées — nouvelle (upload) ou existante conservée
      for (final vue in {..._photosVues.keys, ..._photosVuesExistantes.keys}) {
        final url = _photosVues.containsKey(vue)
            ? await storage.uploadPhoto(_photosVues[vue]!, '$base/$vue.jpg')
            : _photosVuesExistantes[vue];
        if (url != null) {
          await _supa.from('suivis_morpho_photos').insert({'suivi_id': suiviId, 'vue': vue, 'url': url});
        }
      }
      // Photos extra — nouvelles (upload) + existantes non retirées
      for (var i = 0; i < _photosExtra.length; i++) {
        final url = await storage.uploadPhoto(_photosExtra[i], '$base/extra_$i.jpg');
        await _supa.from('suivis_morpho_photos').insert({'suivi_id': suiviId, 'vue': 'autre', 'url': url});
      }
      for (final url in _photosExtraExistantes) {
        await _supa.from('suivis_morpho_photos').insert({'suivi_id': suiviId, 'vue': 'autre', 'url': url});
      }
      // Vidéos — nouvelle (upload) ou existante conservée
      final videoIds = <int, String>{};
      for (var i = 0; i < _videos.length; i++) {
        final v = _videos[i];
        final String url;
        if (v.file != null) {
          final ext = v.file!.path.split('.').last.toLowerCase();
          url = await storage.uploadRawFile(v.file!, '$base/video_$i.$ext');
        } else {
          url = v.existingUrl!;
        }
        final row = await _supa.from('suivis_morpho_videos').insert({
          'suivi_id': suiviId, 'activite': v.activite,
          if (v.commentaire.trim().isNotEmpty) 'commentaire': v.commentaire.trim(),
          'url': url,
        }).select('id').single();
        videoIds[i] = row['id'] as String;
      }
      // Points (silhouette — pointage libre)
      for (var i = 0; i < _points.length; i++) {
        final p = _points[i];
        final row = await _supa.from('suivis_morpho_points').insert({
          'suivi_id': suiviId, 'vue': p.vue,
          'x_pct': p.xPct * 100, 'y_pct': p.yPct * 100,
          'categorie': p.categorie,
          if (p.note.trim().isNotEmpty) 'note': p.note.trim(),
          if (p.couleur != null) 'couleur': p.couleur,
        }).select('id').single();
        final pointPhotoUrl = p.photo != null
            ? await storage.uploadPhoto(p.photo!, '$base/point_$i.jpg')
            : p.existingPhotoUrl;
        if (pointPhotoUrl != null) {
          await _supa.from('suivis_morpho_photos').insert({
            'suivi_id': suiviId, 'vue': 'zone', 'point_id': row['id'], 'url': pointPhotoUrl,
          });
        }
      }
      // Observations statiques
      for (final entry in _observations.entries) {
        final o = entry.value;
        if (o.valeur == 'non_evalue' && o.commentaire.trim().isEmpty) continue;
        await _supa.from('suivis_morpho_observations').insert({
          'suivi_id': suiviId, 'categorie': entry.key, 'valeur': o.valeur,
          if (o.commentaire.trim().isNotEmpty) 'commentaire': o.commentaire.trim(),
        });
      }
      // Observations dynamiques
      for (final m in _mouvements) {
        await _supa.from('suivis_morpho_mouvements').insert({
          'suivi_id': suiviId, 'activite': m.activite,
          if (m.observation.trim().isNotEmpty) 'observation': m.observation.trim(),
          'gene_observee': m.geneObservee,
          if (m.commentaire.trim().isNotEmpty) 'commentaire': m.commentaire.trim(),
          if (m.videoIndex != null && videoIds.containsKey(m.videoIndex)) 'video_id': videoIds[m.videoIndex],
        });
      }

      // Pas de notification automatique ici : le pro décide lui-même quand
      // le suivi est prêt à être transmis, via le bouton "Envoyer au
      // client" sur la fiche du suivi (morpho_detail_page.dart).

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMorphoBg,
      appBar: AppBar(
        backgroundColor: kMorphoTeal, foregroundColor: Colors.white, elevation: 0,
        title: Text(_isEditing ? 'Modifier le suivi' : 'Nouveau suivi', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator(color: kMorphoTeal))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        _sectionTitle('Informations générales'),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dateField(),
          const SizedBox(height: 12),
          _dropdown('Type de suivi', _typeSuivi, kTypesSuivi, (v) => setState(() => _typeSuivi = v)),
          const SizedBox(height: 12),
          _textField('Professionnel (si applicable)', _professionnelCtrl),
          const SizedBox(height: 12),
          _textField('Motif / raison du suivi', _motifCtrl, maxLines: 2),
          const SizedBox(height: 12),
          _textField('Commentaires généraux', _commentairesCtrl, maxLines: 3),
        ])),

        if (_saisieLibre) ...[
          _sectionTitle('Client'),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Client occasionnel, sans fiche existante dans l\'application.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 10),
            _textField('Nom de l\'animal', _animalNomCtrl),
            const SizedBox(height: 12),
            _textField('Nom du client (facultatif)', _clientNomCtrl),
            const SizedBox(height: 12),
            _textField('Contact — téléphone ou email (facultatif)', _clientContactCtrl),
          ])),
        ],

        _sectionTitle('Données de l\'animal'),
        _card(child: Column(children: [
          Row(children: [
            Expanded(child: _textField('Poids (kg)', _poidsCtrl, keyboardType: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: _textField('Taille (cm)', _tailleCtrl, keyboardType: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _dropdown('Niveau d\'activité', _niveauActivite, kNiveauxActivite, (v) => setState(() => _niveauActivite = v)),
          const SizedBox(height: 12),
          _textField('Activité sportive éventuelle', _activiteSportiveCtrl),
          const SizedBox(height: 12),
          _textField('Étape (éleveur, optionnel — ex. "8 semaines")', _checkpointCtrl),
        ])),

        _sectionTitle('Photos de référence'),
        _card(child: _PhotoGrid(
          photos: _photosVues,
          existingUrls: _photosVuesExistantes,
          onPickGallery: _pickVuePhoto,
          onPickCamera: _pickVuePhotoCamera,
        )),
        const SizedBox(height: 10),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Photos supplémentaires', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final url in _photosExtraExistantes)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: Image.network(url, width: 70, height: 70, fit: BoxFit.cover)),
                Positioned(
                  top: 2, right: 2,
                  child: InkWell(
                    onTap: () => setState(() => _photosExtraExistantes.remove(url)),
                    child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 12)),
                  ),
                ),
              ]),
            for (final f in _photosExtra)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: Image.file(f, width: 70, height: 70, fit: BoxFit.cover)),
                Positioned(
                  top: 2, right: 2,
                  child: InkWell(
                    onTap: () => setState(() => _photosExtra.remove(f)),
                    child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 12)),
                  ),
                ),
              ]),
            InkWell(
              onTap: _ajouterPhotoExtra,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(color: const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.add, color: kMorphoTeal),
              ),
            ),
          ]),
        ])),

        _sectionTitle('Vidéos'),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final v in _videos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.videocam_outlined, color: kMorphoTeal, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(labelActivite(v.activite), style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => setState(() => _videos.remove(v)),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: _ajouterVideo,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une vidéo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: kMorphoTeal),
          ),
        ])),

        _sectionTitle('Silhouette anatomique'),
        _card(child: Column(children: [
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final v in vuesDisponibles(morphoSpeciesKey(widget.espece) ?? 'chien'))
              _segButton(v.$2, _vueSilhouette == v.$1, () => setState(() => _vueSilhouette = v.$1)),
          ]),
          const SizedBox(height: 12),
          MorphoSilhouette(
            espece: morphoSpeciesKey(widget.espece) ?? 'chien',
            vue: _vueSilhouette,
            points: _displayedPoints(),
            onTapEmpty: _ajouterPoint,
            onTapPoint: (mp) => _editerPoint(_points[int.parse(mp.id!)]),
            refreshPoints: _displayedPoints,
            onVueChanged: (v) => setState(() => _vueSilhouette = v),
          ),
          const SizedBox(height: 8),
          const MorphoLegende(),
          const SizedBox(height: 6),
          Text('Touchez la silhouette pour poser un point', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ])),

        _sectionTitle('Observation statique (posture)'),
        _card(child: Column(children: [
          for (final c in kCategoriesObservationStatique)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ObservationStatiqueRow(
                categorie: c.$1, label: c.$2, state: _observations[c.$1]!,
                onChanged: () => setState(() {}),
              ),
            ),
        ])),

        _sectionTitle('Observation en mouvement'),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in _mouvements)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(kActivitesMouvement.firstWhere((a) => a.$1 == m.activite, orElse: () => ('', '', Icons.circle)).$3,
                    color: kMorphoTeal, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(labelActivite(m.activite), style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                if (m.geneObservee == true)
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => setState(() => _mouvements.remove(m)),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: _ajouterMouvement,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une observation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: kMorphoTeal),
          ),
        ])),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _enregistrer,
              style: ElevatedButton.styleFrom(
                backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEditing ? 'Enregistrer les modifications' : 'Enregistrer le suivi', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segButton(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kMorphoTeal : const Color(0xFFF1F5F4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: TextStyle(
              fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade700)),
        ),
      );

  Widget _dateField() => InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context, initialDate: _date,
            firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) setState(() => _date = picked);
        },
        child: InputDecorator(
          decoration: _decoration('Date'),
          child: Text('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        ),
      );
}

// ── Widgets/petites classes internes ────────────────────────────────────────

InputDecoration _decoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kMorphoTeal, width: 1.5)),
    );

Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: kMorphoDark)),
    );

Widget _card({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade100)),
      child: child,
    );

Widget _textField(String label, TextEditingController c, {int maxLines = 1, TextInputType? keyboardType}) => TextField(
      controller: c, maxLines: maxLines, keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: _decoration(label),
    );

Widget _dropdown(String label, String value, List<(String, String)> options, void Function(String) onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _decoration(label),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
      items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))],
      onChanged: (v) { if (v != null) onChanged(v); },
    );

class _PhotoGrid extends StatelessWidget {
  final Map<String, File> photos;
  final Map<String, String> existingUrls;
  final void Function(String vue) onPickGallery;
  final void Function(String vue) onPickCamera;
  const _PhotoGrid({required this.photos, this.existingUrls = const {}, required this.onPickGallery, required this.onPickCamera});

  @override
  Widget build(BuildContext context) {
    Widget slot(String vue, String label) {
      final f = photos[vue];
      final existingUrl = existingUrls[vue];
      final hasImage = f != null || existingUrl != null;
      return Column(children: [
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _choix(context, vue),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 92, height: 92,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(12),
              image: f != null
                  ? DecorationImage(image: FileImage(f), fit: BoxFit.cover)
                  : existingUrl != null
                      ? DecorationImage(image: NetworkImage(existingUrl), fit: BoxFit.cover)
                      : null,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: !hasImage
                ? const Center(child: Icon(Icons.camera_alt_outlined, color: kMorphoTeal, size: 26))
                : Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, color: Colors.white, size: 14),
                    ),
                  ),
          ),
        ),
      ]);
    }

    return Column(children: [
      slot('face', 'FACE'),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        slot('profil_g', 'PROFIL G'),
        slot('profil_d', 'PROFIL D'),
      ]),
      const SizedBox(height: 14),
      slot('dos', 'ARRIÈRE / DOS'),
    ]);
  }

  Future<void> _choix(BuildContext context, String vue) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.camera_alt_outlined, color: kMorphoTeal),
              title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey')),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: kMorphoTeal),
              title: const Text('Choisir dans la galerie', style: TextStyle(fontFamily: 'Galey')),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == ImageSource.camera) onPickCamera(vue);
    if (source == ImageSource.gallery) onPickGallery(vue);
  }
}

class _ObsStatique {
  String valeur = 'non_evalue';
  String commentaire = '';
}

class _ObservationStatiqueRow extends StatefulWidget {
  final String categorie;
  final String label;
  final _ObsStatique state;
  final VoidCallback onChanged;
  const _ObservationStatiqueRow({required this.categorie, required this.label, required this.state, required this.onChanged});

  @override
  State<_ObservationStatiqueRow> createState() => _ObservationStatiqueRowState();
}

class _ObservationStatiqueRowState extends State<_ObservationStatiqueRow> {
  late final _ctrl = TextEditingController(text: widget.state.commentaire);

  @override
  Widget build(BuildContext context) {
    final labels = labelsValeurObservation(widget.categorie);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: kMorphoDark)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final entry in labels.entries)
          ChoiceChip(
            label: Text(entry.value, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
            selected: widget.state.valeur == entry.key,
            showCheckmark: false,
            selectedColor: colorValeurObservation(entry.key).withValues(alpha: 0.18),
            labelStyle: TextStyle(color: widget.state.valeur == entry.key ? colorValeurObservation(entry.key) : Colors.grey.shade700),
            onSelected: (_) { widget.state.valeur = entry.key; widget.onChanged(); },
          ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: _ctrl,
        onChanged: (v) => widget.state.commentaire = v,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: _decoration('Commentaire (facultatif)'),
      ),
    ]);
  }
}

class _PointEntree {
  final double xPct;
  final double yPct;
  final String vue; // 'profil_g' | 'profil_d' — vue sur laquelle le point a été posé
  String categorie;
  String note;
  String? couleur; // hex sans # — indépendante de categorie, cf. kPaletteCouleursPoints
  File? photo;
  String? existingPhotoUrl; // photo déjà enregistrée (édition), conservée si non remplacée
  bool deleted;
  _PointEntree({
    required this.xPct, required this.yPct, required this.vue,
    this.categorie = 'autre', this.note = '', this.couleur, this.photo, this.existingPhotoUrl, this.deleted = false,
  });

  _PointEntree copyWith({String? categorie, String? note, String? couleur, File? photo, bool? deleted}) => _PointEntree(
        xPct: xPct, yPct: yPct, vue: vue,
        categorie: categorie ?? this.categorie, note: note ?? this.note,
        couleur: couleur ?? this.couleur,
        photo: photo ?? this.photo,
        // Une nouvelle photo choisie remplace l'existante (elle ne sera pas
        // reconservée à l'enregistrement — cf. _enregistrer).
        existingPhotoUrl: photo != null ? null : existingPhotoUrl,
        deleted: deleted ?? this.deleted,
      );
}

class _PointSheet extends StatefulWidget {
  final _PointEntree initial;
  final bool allowDelete;
  const _PointSheet({required this.initial, this.allowDelete = false});

  @override
  State<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<_PointSheet> {
  late String _categorie = widget.initial.categorie;
  late String _couleur = widget.initial.couleur ?? colorToHex(colorCategoriePoint(widget.initial.categorie));
  late final _noteCtrl = TextEditingController(text: widget.initial.note);
  File? _photo;
  bool _labelError = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.initial.photo;
  }

  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f != null) setState(() => _photo = File(f.path));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Point', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            const Text('Couleur', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in kPaletteCouleursPoints)
                GestureDetector(
                  onTap: () => setState(() => _couleur = colorToHex(c)),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: c,
                      border: Border.all(
                          color: _couleur == colorToHex(c) ? kMorphoDark : Colors.transparent, width: 2.5),
                    ),
                    child: _couleur == colorToHex(c)
                        ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            const Text('Catégorie (optionnel, pour classer le point)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in kCategoriesOsteo)
                ChoiceChip(
                  label: Text(c.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  selected: _categorie == c.$1, showCheckmark: false,
                  selectedColor: c.$3.withValues(alpha: 0.25),
                  onSelected: (_) => setState(() => _categorie = c.$1),
                ),
            ]),
            const SizedBox(height: 14),
            Text('Ce qui a été travaillé *', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: _labelError ? Colors.red : null)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              onChanged: (_) { if (_labelError) setState(() => _labelError = false); },
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: _decoration('Ex. « Point tendu », « Zone travaillée en profondeur »').copyWith(
                errorText: _labelError ? 'Décrivez ce point pour la légende' : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              if (_photo != null)
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(_photo!, width: 50, height: 50, fit: BoxFit.cover)),
              if (_photo != null) const SizedBox(width: 10),
              TextButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(_photo == null ? 'Ajouter une photo' : 'Changer la photo', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: kMorphoTeal)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              if (widget.allowDelete) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context, widget.initial.copyWith(deleted: true)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: ElevatedButton(
                onPressed: () {
                  if (_noteCtrl.text.trim().isEmpty) { setState(() => _labelError = true); return; }
                  Navigator.pop(context, widget.initial.copyWith(
                      categorie: _categorie, note: _noteCtrl.text.trim(), couleur: _couleur, photo: _photo));
                },
                style: ElevatedButton.styleFrom(backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Valider', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _VideoEntree {
  final File? file; // nouvelle vidéo, à uploader
  final String? existingUrl; // vidéo déjà enregistrée (édition), conservée telle quelle
  final String activite;
  final String commentaire;
  const _VideoEntree({this.file, this.existingUrl, required this.activite, this.commentaire = ''});
}

class _AjoutVideoSheet extends StatefulWidget {
  const _AjoutVideoSheet();
  @override
  State<_AjoutVideoSheet> createState() => _AjoutVideoSheetState();
}

class _AjoutVideoSheetState extends State<_AjoutVideoSheet> {
  File? _file;
  String _activite = kActivitesMouvement.first.$1;
  final _commentCtrl = TextEditingController();
  bool _picking = false;

  Future<void> _pick() async {
    setState(() => _picking = true);
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f != null) {
      final size = await File(f.path).length();
      if (size > _kMaxVideoBytes) {
        if (mounted) {
          setState(() => _picking = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vidéo trop lourde (max 50 Mo).', style: TextStyle(fontFamily: 'Galey'))));
        }
        return;
      }
      setState(() { _file = File(f.path); _picking = false; });
    } else {
      setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ajouter une vidéo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _picking ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(_file == null ? 'Choisir une vidéo' : 'Vidéo sélectionnée ✓', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          _dropdown('Activité filmée', _activite, kActivitesMouvement.map((a) => (a.$1, a.$2)).toList(), (v) => setState(() => _activite = v)),
          const SizedBox(height: 12),
          TextField(controller: _commentCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13), decoration: _decoration('Commentaire (facultatif)')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _file == null ? null : () => Navigator.pop(context, _VideoEntree(file: _file!, activite: _activite, commentaire: _commentCtrl.text)),
            style: ElevatedButton.styleFrom(backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }
}

class _Mouvement {
  String activite = kActivitesMouvement.first.$1;
  String observation = '';
  bool? geneObservee;
  String commentaire = '';
  int? videoIndex;
}

class _MouvementSheet extends StatefulWidget {
  const _MouvementSheet();
  @override
  State<_MouvementSheet> createState() => _MouvementSheetState();
}

class _MouvementSheetState extends State<_MouvementSheet> {
  String _activite = kActivitesMouvement.first.$1;
  final _obsCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  bool? _gene;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Observation en mouvement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            _dropdown('Activité', _activite, kActivitesMouvement.map((a) => (a.$1, a.$2)).toList(), (v) => setState(() => _activite = v)),
            const SizedBox(height: 12),
            TextField(controller: _obsCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13), decoration: _decoration('Observation')),
            const SizedBox(height: 12),
            const Text('Gêne observée ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Non', style: TextStyle(fontFamily: 'Galey', fontSize: 12)), selected: _gene == false, showCheckmark: false, onSelected: (_) => setState(() => _gene = false)),
              ChoiceChip(label: const Text('Oui', style: TextStyle(fontFamily: 'Galey', fontSize: 12)), selected: _gene == true, showCheckmark: false, selectedColor: const Color(0xFFD97706).withValues(alpha: 0.2), onSelected: (_) => setState(() => _gene = true)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _commentCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13), decoration: _decoration('Commentaire')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _Mouvement()
                ..activite = _activite ..observation = _obsCtrl.text
                ..geneObservee = _gene ..commentaire = _commentCtrl.text),
              style: ElevatedButton.styleFrom(backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }
}
