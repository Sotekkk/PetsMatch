// Fiche technique d'une prestation de toilettage (une par rendez-vous) :
// travail effectué, préférences appliquées, produits, comportement,
// observations, photos avant / après et compte rendu court — partagé avec
// le propriétaire seulement si le pro le choisit. Table seances_toilettage
// (migration_toilettage_fiche.sql) ; photos : fiches_toilettage_photos
// (rdv_id). Miroir site : components/toilettage/SeanceToilettageModal.tsx.
// Scopé au profil actif (pro_profile_id).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/pages/pro/toilettage_constantes.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

class ToilettageSeancePage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  /// Rendez-vous de la prestation (null = fiche saisie hors rendez-vous).
  final Map<String, dynamic>? rdv;
  /// Fiche existante à rouvrir (historique).
  final Map<String, dynamic>? seance;
  const ToilettageSeancePage({super.key, required this.animalId, required this.animalNom, this.rdv, this.seance});

  @override
  State<ToilettageSeancePage> createState() => _ToilettageSeancePageState();
}

class _ToilettageSeancePageState extends State<ToilettageSeancePage> {
  final _supa = Supabase.instance.client;
  bool _loading = true, _saving = false, _uploading = false;
  String? _seanceId, _ficheId;
  bool _dejaPartage = false;
  final Set<String> _travaux = {};
  String? _cooperation;
  bool _partage = false;
  DateTime _date = DateTime.now();
  final _c = {
    for (final k in ['longueur_coupe', 'zones', 'finition', 'produits', 'sensibilites', 'difficultes', 'precautions', 'observations', 'compte_rendu', 'conseils_pelage', 'duree'])
      k: TextEditingController(),
  };
  List<Map<String, dynamic>> _photos = [];

  String get _pid => User_Info.activeProfileId;
  String? get _rdvId => (widget.rdv?['id'] ?? widget.seance?['rdv_id'])?.toString();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      var f = await _supa.from('fiches_toilettage').select().eq('pro_profile_id', _pid).eq('animal_id', widget.animalId).maybeSingle();
      _ficheId = f?['id']?.toString();
      Map<String, dynamic>? s = widget.seance;
      if (s == null && _rdvId != null) {
        s = await _supa.from('seances_toilettage').select().eq('rdv_id', _rdvId!).maybeSingle();
      }
      if (s != null) {
        _seanceId = s['id']?.toString();
        _travaux.addAll(((s['travaux'] as List?) ?? const []).map((e) => e.toString()));
        _cooperation = s['cooperation']?.toString();
        _partage = s['partage_proprietaire'] == true;
        _dejaPartage = _partage;
        _date = DateTime.tryParse(s['date_seance']?.toString() ?? '') ?? _date;
        for (final k in _c.keys) {
          if (k == 'duree') continue;
          _c[k]!.text = s[k]?.toString() ?? '';
        }
        if (s['duree_minutes'] != null) _c['duree']!.text = s['duree_minutes'].toString();
      } else {
        // Nouvelle fiche : préremplie depuis le rendez-vous et les consignes
        // permanentes (coupe habituelle), modifiable.
        final rdvDate = DateTime.tryParse(widget.rdv?['date_heure']?.toString() ?? '')?.toLocal();
        if (rdvDate != null) _date = rdvDate;
        final debut = DateTime.tryParse(widget.rdv?['prestation_debut_le']?.toString() ?? '');
        final fin = DateTime.tryParse(widget.rdv?['pret_le']?.toString() ?? '');
        final duree = debut != null && fin != null ? fin.difference(debut).inMinutes : (widget.rdv?['duree_minutes'] as num?)?.toInt();
        if (duree != null && duree > 0) _c['duree']!.text = '$duree';
        _c['longueur_coupe']!.text = f?['longueur_coupe']?.toString() ?? '';
        _c['produits']!.text = f?['shampooing_prefere']?.toString() ?? '';
      }
      if (_rdvId != null && _ficheId != null) {
        _photos = List<Map<String, dynamic>>.from(await _supa.from('fiches_toilettage_photos').select()
            .eq('fiche_id', _ficheId!).eq('rdv_id', _rdvId!).order('created_at'));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<String> _assurerFiche() async {
    if (_ficheId != null) return _ficheId!;
    final row = await _supa.from('fiches_toilettage').insert({
      'pro_uid': FirebaseAuth.instance.currentUser!.uid,
      'pro_profile_id': _pid,
      'animal_id': widget.animalId,
      if (widget.rdv?['client_uid'] != null) 'client_uid': widget.rdv!['client_uid'],
      if (widget.rdv?['client_profile_id'] != null) 'client_profile_id': widget.rdv!['client_profile_id'],
    }).select('id').single();
    return _ficheId = row['id'].toString();
  }

  Future<void> _ajouterPhoto(String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choisir dans la galerie', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ])),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final ficheId = await _assurerFiche();
      final url = await storage.uploadPhoto(File(file.path),
          'fiches_toilettage/${ficheId}_${type}_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final row = await _supa.from('fiches_toilettage_photos').insert({
        'fiche_id': ficheId, if (_rdvId != null) 'rdv_id': _rdvId, 'type': type, 'url': url,
      }).select().single();
      setState(() => _photos.add(Map<String, dynamic>.from(row)));
    } catch (e) {
      _snack('Photo non enregistrée : $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _supprimerPhoto(Map<String, dynamic> p) async {
    try {
      await _supa.from('fiches_toilettage_photos').delete().eq('id', p['id']);
      setState(() => _photos.remove(p));
    } catch (_) {}
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t, style: const TextStyle(fontFamily: 'Galey'))));
  }

  String? _v(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  Future<void> _enregistrer() async {
    if (_partage && (_v('compte_rendu') == null)) {
      _snack('Rédigez le compte rendu à partager avec le propriétaire.');
      return;
    }
    setState(() => _saving = true);
    try {
      final ficheId = await _assurerFiche();
      final data = {
        'fiche_id': ficheId,
        'animal_id': widget.animalId,
        'pro_uid': FirebaseAuth.instance.currentUser!.uid,
        'pro_profile_id': _pid,
        if (_rdvId != null) 'rdv_id': _rdvId,
        if (widget.rdv?['employe_id'] != null) 'employe_id': widget.rdv!['employe_id'],
        'date_seance': DateFormat('yyyy-MM-dd').format(_date),
        'duree_minutes': int.tryParse(_c['duree']!.text.trim()),
        'travaux': _travaux.toList(),
        'longueur_coupe': _v('longueur_coupe'),
        'zones': _v('zones'),
        'finition': _v('finition'),
        'produits': _v('produits'),
        'cooperation': _cooperation,
        'sensibilites': _v('sensibilites'),
        'difficultes': _v('difficultes'),
        'precautions': _v('precautions'),
        'observations': _v('observations'),
        'compte_rendu': _v('compte_rendu'),
        'conseils_pelage': _v('conseils_pelage'),
        'partage_proprietaire': _partage,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_seanceId != null) {
        await _supa.from('seances_toilettage').update(data).eq('id', _seanceId!);
      } else {
        final row = await _supa.from('seances_toilettage').insert(data).select('id').single();
        _seanceId = row['id'].toString();
      }
      // Compte rendu partagé pour la première fois : le propriétaire est
      // prévenu (le pro l'a choisi explicitement).
      final clientUid = widget.rdv?['client_uid']?.toString();
      if (_partage && !_dejaPartage && clientUid != null && clientUid.isNotEmpty) {
        try {
          await _supa.from('notifications').insert({
            'uid': clientUid,
            'type': 'toilettage_cr',
            'title': 'Compte rendu de toilettage',
            'body': 'Le compte rendu du toilettage de ${widget.animalNom} est disponible.',
            if ((widget.rdv?['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': widget.rdv!['client_profile_id'],
            'data': {'animalId': widget.animalId, 'seance_id': _seanceId},
            'read': false,
          });
        } catch (_) {}
        _dejaPartage = true;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString().contains('seances_toilettage') ? 'Migration migration_toilettage_fiche.sql à passer.' : 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  Widget _section(String titre, List<Widget> enfants) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
          const SizedBox(height: 10),
          ...enfants,
        ]),
      );

  Widget _champ(String k, String label, {int lignes = 1, TextInputType? clavier}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k], maxLines: lignes, minLines: 1, keyboardType: clavier,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(),
              labelStyle: const TextStyle(fontFamily: 'Galey')),
        ),
      );

  Widget _photosType(String type, String titre) {
    final liste = _photos.where((p) => p['type'] == type).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: _ink)),
        const Spacer(),
        TextButton.icon(
          onPressed: _uploading ? null : () => _ajouterPhoto(type),
          icon: const Icon(Icons.add_a_photo_outlined, size: 16),
          label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
          style: TextButton.styleFrom(foregroundColor: _teal),
        ),
      ]),
      if (liste.isEmpty)
        Text('Aucune photo.', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade500))
      else
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: liste.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.network(liste[i]['url'].toString(), width: 92, height: 92, fit: BoxFit.cover)),
              Positioned(right: 2, top: 2, child: InkWell(
                onTap: () => _supprimerPhoto(liste[i]),
                child: Container(padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 14, color: Colors.white)),
              )),
            ]),
          ),
        ),
      const SizedBox(height: 6),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final presta = widget.rdv?['_prestation']?.toString();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: Text('Fiche technique — ${widget.animalNom}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
              _section('Prestation', [
                if (presta != null && presta.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                      child: Text(presta, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _ink))),
                Row(children: [
                  Expanded(child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _date,
                          firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setState(() => _date = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date', isDense: true, border: OutlineInputBorder(),
                          labelStyle: TextStyle(fontFamily: 'Galey')),
                      child: Text(DateFormat('d MMM yyyy', 'fr_FR').format(_date), style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                    ),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(width: 130, child: Padding(padding: const EdgeInsets.only(top: 10),
                      child: _champ('duree', 'Durée (min)', clavier: TextInputType.number))),
                ]),
              ]),
              _section('Travail effectué', [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in kTravauxToilettage)
                    FilterChip(
                      label: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                          color: _travaux.contains(t.$1) ? Colors.white : _ink)),
                      selected: _travaux.contains(t.$1),
                      showCheckmark: false,
                      selectedColor: _teal,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _travaux.contains(t.$1) ? _teal : Colors.grey.shade300),
                      onSelected: (v) => setState(() => v ? _travaux.add(t.$1) : _travaux.remove(t.$1)),
                    ),
                ]),
                const SizedBox(height: 12),
                _champ('longueur_coupe', 'Longueur de coupe / sabot'),
                _champ('zones', 'Zones travaillées', lignes: 2),
                _champ('finition', 'Finition'),
                _champ('produits', 'Produits utilisés', lignes: 2),
              ]),
              _section('Comportement', [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in kCooperationToilettage)
                    ChoiceChip(
                      label: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                          color: _cooperation == t.$1 ? Colors.white : _ink)),
                      selected: _cooperation == t.$1,
                      showCheckmark: false,
                      selectedColor: _teal,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _cooperation == t.$1 ? _teal : Colors.grey.shade300),
                      onSelected: (v) => setState(() => _cooperation = v ? t.$1 : null),
                    ),
                ]),
                const SizedBox(height: 12),
                _champ('sensibilites', 'Sensibilités observées', lignes: 2),
                _champ('difficultes', 'Difficultés rencontrées', lignes: 2),
                _champ('precautions', 'Précautions pour la prochaine fois', lignes: 2),
              ]),
              _section('Observations', [
                _champ('observations', 'Observations (peau, pelage, parasites, nœuds…) — usage interne', lignes: 3),
                Text('Une anomalie de santé se signale au propriétaire, sans diagnostic.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ]),
              _section('Photos avant / après', [
                _photosType('avant', 'Avant'),
                _photosType('apres', 'Après'),
                Text('Les photos restent dans la fiche du salon : elles ne sont jamais publiées.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ]),
              _section('Compte rendu pour le propriétaire', [
                _champ('compte_rendu', 'Compte rendu court', lignes: 4),
                _champ('conseils_pelage', 'Conseils de soin du pelage (brossage, produits, prochain toilettage conseillé…)', lignes: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _partage,
                  activeThumbColor: _teal,
                  onChanged: (v) => setState(() => _partage = v),
                  title: const Text('Partager avec le propriétaire', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  subtitle: Text(_dejaPartage
                      ? 'Déjà partagé : visible dans l\'onglet Consultations de son animal.'
                      : 'Il le retrouvera dans l\'onglet Consultations de son animal et sera prévenu.',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                ),
              ]),
            ]),
      bottomNavigationBar: _loading ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _saving ? null : _enregistrer,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer la fiche technique',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
