import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/inline_video.dart';
import 'morpho_constants.dart';
import 'morpho_silhouette.dart';
import 'morpho_pdf_service.dart';
import 'morpho_form_page.dart';

/// Consultation d'un suivi morphologique existant. [readOnly] n'affecte
/// pas grand-chose en V1 (pas d'édition depuis cette page — un suivi est
/// un compte rendu daté, on en crée un nouveau plutôt que de le corriger,
/// comme le reste du carnet de santé) mais reste le paramètre attendu par
/// le host pour rester cohérent avec les autres onglets.
class MorphoDetailPage extends StatefulWidget {
  final Map<String, dynamic> suivi;
  final String espece;
  final bool readOnly;
  const MorphoDetailPage({super.key, required this.suivi, required this.espece, this.readOnly = true});

  @override
  State<MorphoDetailPage> createState() => _MorphoDetailPageState();
}

class _MorphoDetailPageState extends State<MorphoDetailPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _points = [];
  List<Map<String, dynamic>> _observations = [];
  List<Map<String, dynamic>> _mouvements = [];
  late String _vue = vuesDisponibles(morphoSpeciesKey(widget.espece) ?? 'chien').first.$1;
  Map<String, dynamic> _animal = {};
  Map<String, dynamic> _pro = {};
  bool _exporting = false;
  bool _sendingNotif = false;
  late DateTime? _notifieA = DateTime.tryParse(widget.suivi['notifie_a']?.toString() ?? '');

  String get _suiviId => widget.suivi['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _supa.from('suivis_morpho_photos').select().eq('suivi_id', _suiviId),
        _supa.from('suivis_morpho_videos').select().eq('suivi_id', _suiviId),
        _supa.from('suivis_morpho_points').select().eq('suivi_id', _suiviId),
        _supa.from('suivis_morpho_observations').select().eq('suivi_id', _suiviId),
        _supa.from('suivis_morpho_mouvements').select().eq('suivi_id', _suiviId),
      ]);
      if (!mounted) return;
      setState(() {
        _photos = List<Map<String, dynamic>>.from(results[0] as List);
        _videos = List<Map<String, dynamic>>.from(results[1] as List);
        _points = List<Map<String, dynamic>>.from(results[2] as List);
        _observations = List<Map<String, dynamic>>.from(results[3] as List);
        _mouvements = List<Map<String, dynamic>>.from(results[4] as List);
        _loading = false;
      });
      unawaited(_loadAnimalEtPro());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAnimalEtPro() async {
    try {
      final animalId = widget.suivi['animal_id']?.toString();
      final proProfileId = widget.suivi['pro_profile_id']?.toString();
      final uidAuteur = widget.suivi['uid_auteur']?.toString();
      final futures = <Future<dynamic>>[
        if (animalId != null) _supa.from('animaux').select('nom, espece, race').eq('id', animalId).maybeSingle() else Future.value(null),
        if (proProfileId != null)
          _supa.from('user_profiles').select('nom, firstname, lastname, adress, phone_number, email_contact, profession_pro').eq('id', proProfileId).maybeSingle()
        else if (uidAuteur != null)
          _supa.from('user_profiles').select('nom, firstname, lastname, adress, phone_number, email_contact, profession_pro').eq('uid', uidAuteur).eq('is_main', true).maybeSingle()
        else
          Future.value(null),
      ];
      final res = await Future.wait(futures);
      if (!mounted) return;
      final animalRow = res[0] as Map<String, dynamic>?;
      final proRow = res[1] as Map<String, dynamic>?;
      final proNom = (proRow?['nom'] as String?)?.trim().isNotEmpty == true
          ? proRow!['nom'] as String
          : '${proRow?['firstname'] ?? ''} ${proRow?['lastname'] ?? ''}'.trim();
      setState(() {
        _animal = animalRow ?? {
          'nom': widget.suivi['animal_nom_libre'] ?? 'Animal',
          'espece': widget.suivi['espece_libre'] ?? widget.espece,
        };
        _pro = {
          'nom': proNom.isNotEmpty ? proNom : '',
          'profession': proRow?['profession_pro'] ?? '',
          'adresse': proRow?['adress'] ?? '',
          'tel': proRow?['phone_number'] ?? '',
          'email': proRow?['email_contact'] ?? '',
        };
      });
    } catch (_) {}
  }

  Future<void> _exporterPdf() async {
    setState(() => _exporting = true);
    try {
      final bytes = await morphoSuiviPdfBytes(
        suivi: widget.suivi, animal: _animal, pro: _pro,
        photos: _photos, points: _points, observations: _observations, mouvements: _mouvements,
      );
      final nomAnimal = (_animal['nom'] as String?)?.replaceAll(' ', '_') ?? 'animal';
      final nomPraticien = ((_pro['nom'] as String?)?.trim().isNotEmpty == true)
          ? (_pro['nom'] as String).replaceAll(' ', '_') : null;
      final dateStr = (widget.suivi['date']?.toString() ?? '').split('T').first;
      final filename = [
        'suivi_morpho', nomAnimal, if (nomPraticien != null) nomPraticien, dateStr,
      ].join('_');
      await sharemorphoSuiviPdf(bytes, filename: '$filename.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export : $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // Modifier / supprimer — pro uniquement (widget.readOnly == false), pour
  // corriger une erreur avant (ou après) que le propriétaire ait consulté
  // son bilan. La modification réutilise le même id (pas de nouvelle
  // notification) ; la suppression est définitive (cascade sur les enfants).
  Future<void> _modifier() async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => MorphoFormPage(
        animalId: widget.suivi['animal_id']?.toString(),
        espece: widget.espece,
        proProfileId: widget.suivi['pro_profile_id']?.toString(),
        existingSuivi: widget.suivi,
      ),
    ));
    if (updated == true && mounted) Navigator.pop(context, true);
  }

  /// Envoi manuel de la notification au(x) propriétaire(s) — décidé par le
  /// pro (pas automatique à l'enregistrement), pour ne prévenir le client
  /// qu'une fois le suivi réellement complet.
  Future<void> _envoyerNotification() async {
    if (widget.suivi['animal_id'] == null) return;
    setState(() => _sendingNotif = true);
    try {
      // Tout se passe côté serveur (notifyOwnerMorphoBilan) : notification
      // in-app + push FCM — une simple ligne dans `notifications` ne
      // déclenche pas de push, il faut passer par la Cloud Function comme
      // pour les autres notifications de l'appli.
      final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyOwnerMorphoBilan')
          .call({'suiviId': _suiviId});
      final data = result.data;
      final sent = data is Map ? (data['sent'] as num?)?.toInt() ?? 0 : 0;
      if (mounted) {
        setState(() { _notifieA = DateTime.now(); _sendingNotif = false; });
        if (sent == 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
              'Envoyé, mais aucun propriétaire distinct trouvé à notifier (peut-être le même compte que vous).')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingNotif = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _supprimer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce suivi ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est définitive et supprime aussi ses photos, vidéos et points.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supa.from('suivis_morpho').delete().eq('id', _suiviId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Map<String, dynamic>? _photoForVue(String vue) =>
      _photos.cast<Map<String, dynamic>?>().firstWhere((p) => p?['vue'] == vue, orElse: () => null);

  List<MorphoPoint> _displayedPoints() => [
        for (final p in _points.where((p) => p['vue'] == _vue))
          MorphoPoint(
            id: p['id'].toString(),
            xPct: ((p['x_pct'] as num).toDouble()) / 100,
            yPct: ((p['y_pct'] as num).toDouble()) / 100,
            categorie: p['categorie']?.toString() ?? 'autre',
            note: p['note']?.toString(),
            couleur: p['couleur']?.toString(),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final s = widget.suivi;
    final date = DateTime.tryParse(s['date']?.toString() ?? '');
    final source = s['source']?.toString() ?? 'proprietaire';
    final extra = _photos.where((p) => p['vue'] == 'autre').toList();

    return Scaffold(
      backgroundColor: kMorphoBg,
      appBar: AppBar(
        backgroundColor: kMorphoTeal, foregroundColor: Colors.white, elevation: 0,
        title: Text(labelTypeSuivi(s['type_suivi']?.toString()),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          if (!_loading)
            IconButton(
              tooltip: 'Exporter / partager en PDF',
              icon: _exporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.ios_share),
              onPressed: _exporting ? null : _exporterPdf,
            ),
          if (!_loading && !widget.readOnly)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) { if (v == 'modifier') _modifier(); if (v == 'supprimer') _supprimer(); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'modifier', child: Text('Modifier', style: TextStyle(fontFamily: 'Galey'))),
                PopupMenuItem(value: 'supprimer', child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kMorphoTeal))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(kMorphoAvertissement, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600))),
                ]),
              ),
              const SizedBox(height: 14),
              _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (date != null)
                  _infoLine('Date', DateFormat('d MMMM yyyy', 'fr_FR').format(date)),
                if (s['animal_id'] == null && (s['animal_nom_libre'] as String?)?.isNotEmpty == true)
                  _infoLine('Animal', s['animal_nom_libre']),
                if ((s['client_nom_libre'] as String?)?.isNotEmpty == true)
                  _infoLine('Client', s['client_nom_libre']),
                if ((s['client_contact_libre'] as String?)?.isNotEmpty == true)
                  _infoLine('Contact', s['client_contact_libre']),
                if ((s['professionnel_nom'] as String?)?.isNotEmpty == true)
                  _infoLine('Professionnel', s['professionnel_nom']),
                if ((s['motif'] as String?)?.isNotEmpty == true) _infoLine('Motif', s['motif']),
                if (s['poids'] != null) _infoLine('Poids', '${s['poids']} kg'),
                if (s['taille'] != null) _infoLine('Taille', '${s['taille']} cm'),
                if ((s['niveau_activite'] as String?) != null && s['niveau_activite'] != 'non_evalue')
                  _infoLine('Niveau d\'activité', kNiveauxActivite.firstWhere((n) => n.$1 == s['niveau_activite'], orElse: () => ('', '')).$2),
                if ((s['activite_sportive'] as String?)?.isNotEmpty == true) _infoLine('Activité sportive', s['activite_sportive']),
                if ((s['checkpoint_age'] as String?)?.isNotEmpty == true) _infoLine('Étape', s['checkpoint_age']),
                if ((s['commentaires'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(s['commentaires'], style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kMorphoDark)),
                ],
                const SizedBox(height: 10),
                if (source == 'professionnel' && (_pro['nom'] as String?)?.isNotEmpty == true) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kMorphoTeal.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.medical_information_outlined, size: 14, color: kMorphoTeal),
                        const SizedBox(width: 6),
                        Text('Réalisé par', style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: kMorphoTeal.withValues(alpha: 0.8))),
                      ]),
                      const SizedBox(height: 4),
                      Text(_pro['nom'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: kMorphoDark)),
                      if ((_pro['profession'] as String?)?.isNotEmpty == true)
                        Text(_pro['profession'] as String, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
                      if ([_pro['adresse'], _pro['tel'], _pro['email']].any((v) => (v as String?)?.isNotEmpty == true)) ...[
                        const SizedBox(height: 3),
                        Text([_pro['adresse'], _pro['tel'], _pro['email']].where((v) => (v as String?)?.isNotEmpty == true).join('  ·  '),
                            style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, color: Colors.grey.shade500)),
                      ],
                    ]),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: kMorphoTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(kSourceLabels[source] ?? source,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: kMorphoTeal)),
                  ),
              ])),

              if (!widget.readOnly && s['animal_id'] != null) ...[
                const SizedBox(height: 10),
                _card(child: _notifieA != null
                    ? Row(children: [
                        const Icon(Icons.check_circle, color: kMorphoTeal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Envoyé au client le ${DateFormat('d MMM à HH:mm', 'fr_FR').format(_notifieA!)}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
                      ])
                    : Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Le client ne voit pas encore ce bilan', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: kMorphoDark)),
                          const SizedBox(height: 2),
                          Text('Envoyez-le une fois le suivi complet et vérifié.', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                        ])),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _sendingNotif ? null : _envoyerNotification,
                          icon: _sendingNotif
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send, size: 16),
                          label: const Text('Envoyer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ]),
                ),
              ],

              if (kVuesPhotos.any((v) => _photoForVue(v.$1) != null)) ...[
                _sectionTitle('Photos de référence'),
                _card(child: Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final v in kVuesPhotos)
                    if (_photoForVue(v.$1) != null)
                      _photoThumb(_photoForVue(v.$1)!['url'] as String, v.$2),
                ])),
              ],
              if (extra.isNotEmpty) ...[
                const SizedBox(height: 10),
                _card(child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in extra)
                    ClipRRect(borderRadius: BorderRadius.circular(10),
                        child: Image.network(p['url'] as String, width: 70, height: 70, fit: BoxFit.cover)),
                ])),
              ],

              if (_videos.isNotEmpty) ...[
                _sectionTitle('Vidéos'),
                for (final v in _videos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(labelActivite(v['activite']?.toString()),
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                      if ((v['commentaire'] as String?)?.isNotEmpty == true)
                        Padding(padding: const EdgeInsets.only(top: 2, bottom: 8),
                            child: Text(v['commentaire'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))),
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: InlineVideo(url: v['url'] as String)),
                    ])),
                  ),
              ],

              if (_points.isNotEmpty) ...[
                _sectionTitle('Silhouette'),
                _card(child: Column(children: [
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    for (final v in vuesDisponibles(morphoSpeciesKey(widget.espece) ?? 'chien'))
                      _segButton(v.$2, _vue == v.$1, () => setState(() => _vue = v.$1)),
                  ]),
                  const SizedBox(height: 12),
                  MorphoSilhouette(
                    espece: morphoSpeciesKey(widget.espece) ?? 'chien',
                    vue: _vue,
                    points: _displayedPoints(),
                    onTapPoint: (mp) async => _showPointInfo(context, mp.id!),
                    refreshPoints: _displayedPoints,
                    onVueChanged: (v) => setState(() => _vue = v),
                  ),
                ])),
                for (final p in _points.where((p) => (p['note'] as String?)?.isNotEmpty == true))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _card(child: _PointSummary(point: p)),
                  ),
              ],

              if (_observations.isNotEmpty) ...[
                _sectionTitle('Observation statique'),
                _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final o in _observations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(
                            kCategoriesObservationStatique.firstWhere((c) => c.$1 == o['categorie'], orElse: () => ('', o['categorie'].toString())).$2,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: colorValeurObservation(o['valeur'].toString()).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Text(labelsValeurObservation(o['categorie'].toString())[o['valeur']] ?? o['valeur'].toString(),
                              style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: colorValeurObservation(o['valeur'].toString()))),
                        ),
                      ]),
                    ),
                ])),
              ],

              if (_mouvements.isNotEmpty) ...[
                _sectionTitle('Observation en mouvement'),
                for (final m in _mouvements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _card(child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(labelActivite(m['activite']?.toString()), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                        if ((m['observation'] as String?)?.isNotEmpty == true)
                          Text(m['observation'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                      ])),
                      if (m['gene_observee'] == true)
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                    ])),
                  ),
              ],
            ]),
    );
  }

  void _showPointInfo(BuildContext context, String pointId) {
    final p = _points.cast<Map<String, dynamic>?>().firstWhere((p) => p?['id'].toString() == pointId, orElse: () => null);
    if (p == null) return;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(padding: const EdgeInsets.all(20), child: _PointSummary(point: p)),
    );
  }

  Widget _photoThumb(String url, String label) => Column(children: [
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, width: 92, height: 92, fit: BoxFit.cover)),
      ]);

  Widget _infoLine(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '$label : ', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: kMorphoDark)),
          TextSpan(text: value.toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kMorphoDark)),
        ])),
      );

  Widget _segButton(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: selected ? kMorphoTeal : const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey.shade700)),
        ),
      );
}

/// Un point = sa couleur propre (choisie librement, indépendante de la
/// catégorie) + son libellé (ce qui a été travaillé) comme légende
/// principale ; la catégorie reste affichée en complément, plus discrète.
class _PointSummary extends StatelessWidget {
  final Map<String, dynamic> point;
  const _PointSummary({required this.point});

  @override
  Widget build(BuildContext context) {
    final categorie = point['categorie']?.toString() ?? 'autre';
    final note = (point['note'] as String?)?.trim() ?? '';
    final couleur = colorPointEffectif(categorie, point['couleur']?.toString());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: couleur)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.isNotEmpty ? note : labelCategoriePoint(categorie),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(labelCategoriePoint(categorie),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ),
          ]),
        ),
      ]),
    ]);
  }
}

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
