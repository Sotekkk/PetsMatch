import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/data/annonce_objet_categories.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

/// Publier / modifier une petite annonce « objet & matériel » liée aux animaux.
/// JAMAIS un animal vivant — voir `annonces_objets`. Publication gratuite.
class CreateAnnonceObjetPage extends StatefulWidget {
  final String? annonceId;
  final Map<String, dynamic>? initialData;
  const CreateAnnonceObjetPage({super.key, this.annonceId, this.initialData});

  @override
  State<CreateAnnonceObjetPage> createState() => _CreateAnnonceObjetPageState();
}

class _CreateAnnonceObjetPageState extends State<CreateAnnonceObjetPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _maxPhotos = 6;

  final _supa = Supabase.instance.client;
  final _titreCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _prixCtrl  = TextEditingController();
  final _cpCtrl    = TextEditingController();

  String  _categorie   = kAnnonceObjetCategories.first.slug;
  String  _transaction = 'vente';
  String? _etat;
  bool    _negociable  = false;
  final List<String> _photosUrls  = [];
  final List<File>   _photosFiles = [];
  bool _saving = false;

  // Localisation : on saisit le code postal, puis on choisit la commune.
  // Région + département sont pré-remplis depuis le code postal (modifiables).
  List<String> _villes = [];
  String? _ville;
  String? _region;
  String? _departement;
  bool _loadingVilles = false;

  bool get _isEdit => widget.annonceId != null;
  bool get _priced => _transaction == 'vente' || _transaction == 'location';

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      _titreCtrl.text = (d['titre'] ?? '').toString();
      _descCtrl.text  = (d['description'] ?? '').toString();
      _categorie   = (d['categorie'] ?? _categorie).toString();
      _transaction = (d['type_transaction'] ?? 'vente').toString();
      _etat        = d['etat'] as String?;
      _negociable  = d['prix_negociable'] == true;
      if (d['prix'] != null) _prixCtrl.text = (d['prix'] as num).toString();
      _ville       = (d['ville'] ?? User_Info.ville).toString().trim();
      _cpCtrl.text = (d['code_postal'] ?? User_Info.codePostal).toString();
      _photosUrls.addAll(List<String>.from(d['photos'] ?? const []));
    } else {
      _ville       = User_Info.ville.trim();
      _cpCtrl.text = User_Info.codePostal;
    }
    if (_ville != null && _ville!.isNotEmpty) _villes = [_ville!];
    _region      = (d?['region'] as String?)?.trim();
    _departement = (d?['departement'] as String?)?.trim();
    _applyGeoFromCp(_cpCtrl.text.trim());
    if (_cpCtrl.text.trim().length == 5) _fetchVilles(_cpCtrl.text.trim());
  }

  void _applyGeoFromCp(String cp) {
    final geo = FrenchGeo.fromPostalCode(cp);
    if (geo == null) return;
    _region ??= geo.region;
    _departement ??= geo.departement;
    // Si le CP change et ne colle plus, on recale.
    if (_region != geo.region) { _region = geo.region; _departement = geo.departement; }
  }

  Future<void> _fetchVilles(String cp) async {
    setState(() => _loadingVilles = true);
    try {
      final uri = Uri.https('geo.api.gouv.fr', '/communes',
          {'codePostal': cp, 'fields': 'nom', 'format': 'json'});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      final list = (jsonDecode(res.body) as List)
          .map((e) => (e['nom'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _villes = list;
        if (_ville == null || !list.contains(_ville)) {
          _ville = list.length == 1 ? list.first : null;
        }
      });
    } catch (_) {
      // Repli : on garde la saisie libre existante.
    } finally {
      if (mounted) setState(() => _loadingVilles = false);
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descCtrl.dispose();
    _prixCtrl.dispose();
    _cpCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Galey'))),
      );

  Future<void> _addPhoto() async {
    final room = _maxPhotos - (_photosUrls.length + _photosFiles.length);
    if (room <= 0) {
      _snack('$_maxPhotos photos maximum.');
      return;
    }
    try {
      // pickMultiImage + requestFullMetadata:false : évite le blocage iOS avec
      // les photos iCloud et permet d'en choisir plusieurs d'un coup.
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
        requestFullMetadata: false,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() => _photosFiles.addAll(
            picked.take(room).map((x) => File(x.path)),
          ));
    } catch (e) {
      if (mounted) _snack('Impossible d\'ouvrir la galerie : $e');
    }
  }

  Future<void> _save() async {
    final titre = _titreCtrl.text.trim();
    if (titre.isEmpty) { _snack('Donnez un titre à votre annonce.'); return; }
    if (_photosUrls.isEmpty && _photosFiles.isEmpty) {
      _snack('Ajoutez au moins une photo.'); return;
    }
    if (_cpCtrl.text.trim().length != 5) { _snack('Indiquez un code postal.'); return; }
    if ((_ville ?? '').isEmpty) { _snack('Sélectionnez votre commune.'); return; }
    // Garde-fou : cette rubrique ne concerne pas les animaux vivants.
    final txt = '$titre ${_descCtrl.text}'.toLowerCase();
    const interdits = [
      'chiot', 'chaton', 'à adopter', 'a adopter', 'portée de', 'portee de',
      'lapereau', 'poussin à vendre', 'poussin a vendre',
    ];
    if (interdits.any(txt.contains)) {
      _snack('Cette rubrique est réservée au matériel. Pour un animal, utilisez « Trouver un compagnon ».');
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = User_Info.uid;
      final pid = User_Info.activeProfileId;
      final newUrls = <String>[];
      for (final f in _photosFiles) {
        newUrls.add(await uploadPhoto(
            f, 'annonces_objets/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg'));
      }
      final nom = '${User_Info.firstname} ${User_Info.lastname}'.trim();
      final now = DateTime.now().toIso8601String();
      final prix = _priced ? double.tryParse(_prixCtrl.text.trim().replaceAll(',', '.')) : null;
      final geo = FrenchGeo.fromPostalCode(_cpCtrl.text.trim());

      final data = <String, dynamic>{
        'uid': uid,
        if (pid.isNotEmpty) 'profile_id': pid,
        'titre': titre,
        'categorie': _categorie,
        'type_transaction': _transaction,
        'prix': prix,
        'prix_unite': _transaction == 'location'
            ? '/mois'
            : null,
        'prix_negociable': _negociable,
        'etat': _priced ? _etat : null,
        'description': _descCtrl.text.trim(),
        'photos': [..._photosUrls, ...newUrls],
        'ville': _ville ?? '',
        'code_postal': _cpCtrl.text.trim(),
        'departement': _departement ?? geo?.departement,
        'region': _region ?? geo?.region,
        'nom_vendeur': nom.isEmpty ? 'Particulier' : nom,
        'statut': 'disponible',
        'updated_at': now,
      };

      if (_isEdit) {
        await _supa.from('annonces_objets').update(data).eq('id', widget.annonceId!);
      } else {
        data['created_at'] = now;
        data['expires_at'] =
            DateTime.now().add(const Duration(days: 60)).toIso8601String();
        await _supa.from('annonces_objets').insert(data);
      }
      if (!mounted) return;
      _snack(_isEdit ? 'Annonce mise à jour.' : 'Annonce publiée !');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => _saving = false); _snack('Erreur : $e'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = kAnnonceObjetCategories.firstWhere((c) => c.slug == _categorie,
        orElse: () => kAnnonceObjetCategories.last);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_isEdit ? 'Modifier l\'annonce' : 'Publier une annonce',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Matériel lié aux animaux uniquement (cage, harnais, foin, location '
              'de prairie, matériel agricole…). La vente d\'un animal n\'est pas '
              'autorisée ici.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF41525A), height: 1.4),
            ),
          ),
          const SizedBox(height: 18),

          // Photos
          _label('Photos (${_photosUrls.length + _photosFiles.length}/$_maxPhotos)'),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _photosUrls.length; i++)
                _thumb(child: Image.network(_photosUrls[i], width: 88, height: 88, fit: BoxFit.cover),
                    onRemove: () => setState(() => _photosUrls.removeAt(i))),
              for (var i = 0; i < _photosFiles.length; i++)
                _thumb(child: Image.file(_photosFiles[i], width: 88, height: 88, fit: BoxFit.cover),
                    onRemove: () => setState(() => _photosFiles.removeAt(i))),
              if (_photosUrls.length + _photosFiles.length < _maxPhotos)
                GestureDetector(
                  onTap: _addPhoto,
                  child: Container(
                    width: 88, height: 88,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: _teal),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 18),

          _label('Titre'),
          _field(_titreCtrl, hint: 'Ex : Cage à lapin XXL, Harnais taille L, Foin 2024…'),
          const SizedBox(height: 16),

          _label('Catégorie'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _categorie,
            isExpanded: true,
            decoration: _dec(),
            items: [
              for (final c in kAnnonceObjetCategories)
                DropdownMenuItem(value: c.slug, child: Text('${c.emoji}  ${c.label}',
                    overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _categorie = v ?? _categorie),
          ),
          const SizedBox(height: 4),
          Text(cat.exemples, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
          const SizedBox(height: 16),

          _label('Type d\'annonce'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final e in kAnnonceObjetTransactions.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _transaction == e.key,
                onSelected: (_) => setState(() => _transaction = e.key),
                selectedColor: _teal.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    fontFamily: 'Galey',
                    color: _transaction == e.key ? _teal : Colors.grey.shade700,
                    fontWeight: FontWeight.w600),
              ),
          ]),
          const SizedBox(height: 16),

          if (_priced) ...[
            _label(_transaction == 'location' ? 'Prix (par mois)' : 'Prix'),
            _field(_prixCtrl, hint: 'En euros', keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]),
            const SizedBox(height: 6),
            Row(children: [
              Checkbox(
                value: _negociable,
                activeColor: _teal,
                onChanged: (v) => setState(() => _negociable = v ?? false),
              ),
              const Text('Prix négociable', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            _label('État'),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final e in kAnnonceObjetEtats.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _etat == e.key,
                  onSelected: (_) => setState(() => _etat = _etat == e.key ? null : e.key),
                  selectedColor: _green.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                      fontFamily: 'Galey',
                      color: _etat == e.key ? _green : Colors.grey.shade700,
                      fontWeight: FontWeight.w600),
                ),
            ]),
            const SizedBox(height: 16),
          ],

          _label('Description'),
          _field(_descCtrl, hint: 'Dimensions, marque, état, retrait sur place / envoi…', maxLines: 5),
          const SizedBox(height: 16),

          _sectionTitle('📍 Localisation'),
          const SizedBox(height: 10),
          _label('Code postal'),
          _field(_cpCtrl, hint: '5 chiffres', keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              onChanged: (v) {
                final cp = v.trim();
                if (cp.length == 5) {
                  setState(() => _applyGeoFromCp(cp));
                  _fetchVilles(cp);
                } else {
                  setState(() { _villes = []; _ville = null; });
                }
              }),
          const SizedBox(height: 12),
          _label('Commune'),
          const SizedBox(height: 6),
          if (_loadingVilles)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Recherche des communes…', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ]),
            )
          else if (_villes.isEmpty)
            Text(
              _cpCtrl.text.trim().length == 5
                  ? 'Aucune commune trouvée pour ce code postal.'
                  : 'Saisissez d\'abord le code postal.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade500),
            )
          else if (_villes.length == 1)
            _readonlyBox(_villes.first)
          else
            DropdownButtonFormField<String>(
              initialValue: _villes.contains(_ville) ? _ville : null,
              isExpanded: true,
              decoration: _dec(hint: 'Sélectionnez votre commune'),
              items: [
                for (final v in _villes) DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _ville = v),
            ),
          const SizedBox(height: 12),

          _label('Région'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: FrenchGeo.regions.contains(_region) ? _region : null,
            isExpanded: true,
            decoration: _dec(hint: 'Région'),
            items: [
              for (final r in FrenchGeo.regions)
                DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() { _region = v; _departement = null; }),
          ),
          const SizedBox(height: 12),

          _label('Département'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: (_region != null &&
                    FrenchGeo.departmentsInRegion(_region!).contains(_departement))
                ? _departement
                : null,
            isExpanded: true,
            decoration: _dec(hint: _region == null ? 'Choisissez d\'abord une région' : 'Département'),
            items: [
              if (_region != null)
                for (final d in FrenchGeo.departmentsInRegion(_region!))
                  DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _region == null ? null : (v) => setState(() => _departement = v),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isEdit ? 'Enregistrer' : 'Publier gratuitement',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E)));

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _teal));

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
      );

  Widget _field(TextEditingController c,
      {String? hint, int maxLines = 1, TextInputType? keyboard,
      List<TextInputFormatter>? formatters, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters: formatters,
        onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _dec(hint: hint),
      ),
    );
  }

  Widget _readonlyBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(children: [
          const Icon(Icons.place_outlined, size: 16, color: _teal),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _thumb({required Widget child, required VoidCallback onRemove}) => Container(
        margin: const EdgeInsets.only(right: 8),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
          Positioned(
            top: 2, right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ]),
      );
}
