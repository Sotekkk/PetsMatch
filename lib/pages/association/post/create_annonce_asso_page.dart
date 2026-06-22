import 'dart:io';
import 'dart:math';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateAnnonceAssoPage extends StatefulWidget {
  final String? annonceId;
  final Map<String, dynamic>? initialData;
  final String? animalId;
  final Map<String, dynamic>? initialAnimal;

  const CreateAnnonceAssoPage({
    super.key,
    this.annonceId,
    this.initialData,
    this.animalId,
    this.initialAnimal,
  });

  @override
  State<CreateAnnonceAssoPage> createState() => _CreateAnnonceAssoPageState();
}

String _genUuid() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
}

class _CreateAnnonceAssoPageState extends State<CreateAnnonceAssoPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  final _titreCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _raceCtrl  = TextEditingController();

  String _espece = 'chien';
  String _sexe   = 'inconnu';

  List<String> _photosUrls  = [];
  List<File>   _photosFiles = [];

  bool _vaccines       = false;
  bool _vermifuge      = false;
  bool _identification = false;
  bool _sterilise      = false;
  bool _contratAdoption = true;

  // Animal sélectionné dans mes animaux
  String? _linkedAnimalId;
  String? _linkedAnimalNom;

  // Animaux association pour le picker
  List<Map<String, dynamic>> _mesAnimaux = [];
  bool _loadingAnimaux = true;

  bool _saving = false;

  static const _especes = [
    ('chien',  'Chien'),
    ('chat',   'Chat'),
    ('lapin',  'Lapin'),
    ('nac',    'NAC'),
    ('oiseau', 'Oiseau'),
    ('cheval', 'Cheval'),
    ('autre',  'Autre'),
  ];

  @override
  void initState() {
    super.initState();
    _loadMesAnimaux();
    if (widget.initialAnimal != null) {
      _prefillFromAnimal(widget.initialAnimal!);
    } else if (widget.initialData != null) {
      _prefillFromAnnonce(widget.initialData!);
    }
  }

  void _prefillFromAnimal(Map<String, dynamic> a) {
    _linkedAnimalId  = a['id']?.toString() ?? widget.animalId;
    _linkedAnimalNom = a['nom']?.toString();
    _espece = a['espece']?.toString() ?? 'chien';
    _raceCtrl.text = a['race']?.toString() ?? '';
    _sexe = a['sexe']?.toString() ?? 'inconnu';
    final photo = a['photo_url']?.toString() ?? '';
    if (photo.isNotEmpty) _photosUrls = [photo];
    if (_titreCtrl.text.isEmpty && _linkedAnimalNom != null) {
      _titreCtrl.text = 'Adoption — $_linkedAnimalNom';
    }
  }

  void _prefillFromAnnonce(Map<String, dynamic> d) {
    _titreCtrl.text = d['titre'] ?? '';
    _descCtrl.text  = d['description'] ?? '';
    _espece = d['espece'] ?? 'chien';
    _raceCtrl.text = d['race'] ?? '';
    _sexe = d['sexe'] ?? 'inconnu';
    _photosUrls = List<String>.from(d['photos'] ?? []);
    _vaccines       = d['vaccines'] ?? false;
    _vermifuge      = d['vermifuge'] ?? false;
    _identification = d['identification'] ?? false;
    _sterilise      = d['sterilise'] ?? false;
    _contratAdoption = d['contrat_adoption'] ?? true;
    _linkedAnimalId = d['animal_id']?.toString();
  }

  Future<void> _loadMesAnimaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingAnimaux = false); return; }
    try {
      final data = await Supabase.instance.client
          .from('animaux')
          .select('id,nom,espece,race,sexe,statut,photo_url')
          .eq('uid_eleveur', uid)
          .inFilter('statut', ['disponible', 'en_soin'])
          .order('nom');
      if (mounted) setState(() { _mesAnimaux = List<Map<String, dynamic>>.from(data as List); _loadingAnimaux = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingAnimaux = false);
    }
  }

  Future<void> _addPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    final f = await pickAndCropSquare(source: src);
    if (f != null && mounted) setState(() => _photosFiles.add(f));
  }

  Future<String> _uploadFile(File f) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final path = 'annonces/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    return uploadPhoto(f, path);
  }

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez saisir un titre')));
      return;
    }
    setState(() => _saving = true);
    try {
      final newUrls = <String>[];
      for (final f in _photosFiles) newUrls.add(await _uploadFile(f));
      final allPhotos = [..._photosUrls, ...newUrls];

      final uid = FirebaseAuth.instance.currentUser!.uid;
      debugPrint('[ASSO] uid=$uid step=userRow');
      final userRow = await Supabase.instance.client
          .from('users').select().eq('uid', uid).single();

      final nomAsso = (userRow['name_elevage'] as String?)?.isNotEmpty == true
          ? userRow['name_elevage'] as String
          : '${userRow['firstname'] ?? ''} ${userRow['lastname'] ?? ''}'.trim();
      final ville  = (userRow['ville_elevage'] as String?) ?? (userRow['ville'] as String?) ?? '';
      final dep    = () {
        final d = userRow['departement_elevage'] as String?;
        if (d != null && d.isNotEmpty) return d;
        final cp = (userRow['code_postal_elevage'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.departement ?? '';
      }();
      final region = () {
        final r = userRow['region_elevage'] as String?;
        if (r != null && r.isNotEmpty) return r;
        final cp = (userRow['code_postal_elevage'] as String?) ?? '';
        return FrenchGeo.fromPostalCode(cp)?.region ?? '';
      }();

      final now = DateTime.now().toIso8601String();
      final data = <String, dynamic>{
        'uid_eleveur':         uid,
        'nom_eleveur':         nomAsso,
        'ville_eleveur':       ville,
        'departement_eleveur': dep,
        'region_eleveur':      region,
        'pays_eleveur':        userRow['pays_elevage'] ?? 'France',
        'type':                'animal',
        'type_vente':          'adoption',
        'profil_source':       'association',
        'espece':              _espece,
        'race':                _raceCtrl.text.trim(),
        'titre':               _titreCtrl.text.trim(),
        'description':         _descCtrl.text.trim(),
        'photos':              allPhotos,
        'prix':                null,
        'prix_negociable':     false,
        'statut':              'disponible',
        'sexe':                _sexe,
        'vaccines':            _vaccines,
        'vermifuge':           _vermifuge,
        'identification':      _identification,
        'sterilise':           _sterilise,
        'contrat_adoption':    _contratAdoption,
        'animal_id':           _linkedAnimalId,
        'updated_at':          now,
      };

      if (widget.annonceId != null) {
        await Supabase.instance.client.from('annonces')
            .update(data).eq('id', widget.annonceId!);
      } else {
        data['id']         = _genUuid();
        data['created_at'] = now;
        data['expires_at'] = DateTime.now().add(const Duration(days: 60)).toIso8601String();
        data['vues']       = 0;
        data['contacts']   = 0;
        await Supabase.instance.client.from('annonces').insert(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Annonce publiée !')));
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      if (mounted) {
        final msg = e is PostgrestException
            ? '[${e.code}] ${e.message}\n${e.details ?? ''}'
            : e.toString();
        debugPrint('CreateAnnonceAsso error: $e\n$st');
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Erreur publication'),
            content: SingleChildScrollView(child: Text(msg)),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectAnimal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Text('Choisir un animal', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (_loadingAnimaux)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else if (_mesAnimaux.isEmpty)
            const Padding(padding: EdgeInsets.all(24),
                child: Text('Aucun animal disponible/en soin', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
          else
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: _mesAnimaux.length,
                itemBuilder: (_, i) {
                  final a = _mesAnimaux[i];
                  final photo = a['photo_url']?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                      backgroundColor: const Color(0xFFDCEDD5),
                      child: photo.isEmpty ? const Icon(Icons.pets, color: Color(0xFF6E9E57), size: 18) : null,
                    ),
                    title: Text(a['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                    subtitle: Text('${a['espece'] ?? ''} · ${a['race'] ?? ''}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _prefillFromAnimal(a));
                    },
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descCtrl.dispose();
    _raceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.annonceId != null ? 'Modifier l\'annonce' : 'Mettre en adoption',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : TextButton(
                  onPressed: _save,
                  child: const Text('Publier', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sélecteur animal
          _Section(
            title: 'Animal concerné',
            child: OutlinedButton.icon(
              onPressed: _selectAnimal,
              icon: const Icon(Icons.pets_outlined),
              label: Text(
                _linkedAnimalNom != null ? 'Animal : $_linkedAnimalNom' : 'Sélectionner un animal',
                style: const TextStyle(fontFamily: 'Galey'),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: Color(0xFF0C5C6C)),
                minimumSize: const Size(double.infinity, 44),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Espèce
          _Section(
            title: 'Espèce',
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _especes.map((e) {
                final active = _espece == e.$1;
                return ChoiceChip(
                  label: Text(e.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  selected: active,
                  onSelected: (_) => setState(() => _espece = e.$1),
                  selectedColor: _teal,
                  labelStyle: TextStyle(color: active ? Colors.white : Colors.black87),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: active ? _teal : Colors.grey.shade300),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Titre + race
          _Section(
            title: 'Titre de l\'annonce',
            child: TextField(
              controller: _titreCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex : Bella cherche une famille aimante',
                hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: _Section(
                title: 'Race',
                child: TextField(
                  controller: _raceCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ex : Labrador, Croisé…',
                    hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Section(
                title: 'Sexe',
                child: DropdownButtonFormField<String>(
                  value: _sexe,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male',    child: Text('Mâle',   style: TextStyle(fontFamily: 'Galey'))),
                    DropdownMenuItem(value: 'femelle', child: Text('Femelle',style: TextStyle(fontFamily: 'Galey'))),
                    DropdownMenuItem(value: 'inconnu', child: Text('N/A',    style: TextStyle(fontFamily: 'Galey'))),
                  ],
                  onChanged: (v) { if (v != null) setState(() => _sexe = v); },
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Description
          _Section(
            title: 'Description',
            child: TextField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Décrivez l\'animal, son caractère, ses besoins…',
                hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Photos
          _Section(
            title: 'Photos',
            child: Column(children: [
              if (_photosUrls.isNotEmpty || _photosFiles.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ..._photosUrls.asMap().entries.map((e) => _PhotoThumb(
                        url: e.value,
                        onRemove: () => setState(() => _photosUrls.removeAt(e.key)),
                      )),
                      ..._photosFiles.asMap().entries.map((e) => _PhotoThumb(
                        file: e.value,
                        onRemove: () => setState(() => _photosFiles.removeAt(e.key)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _addPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Ajouter une photo', style: TextStyle(fontFamily: 'Galey')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: Color(0xFF6E9E57)),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Santé
          _Section(
            title: 'Santé & identification',
            child: Column(children: [
              _CheckRow(label: 'Vacciné(e)', value: _vaccines,        onChanged: (v) => setState(() => _vaccines = v)),
              _CheckRow(label: 'Vermifugé(e)', value: _vermifuge,     onChanged: (v) => setState(() => _vermifuge = v)),
              _CheckRow(label: 'Identifié(e) (puce)', value: _identification, onChanged: (v) => setState(() => _identification = v)),
              _CheckRow(label: 'Stérilisé(e)', value: _sterilise,     onChanged: (v) => setState(() => _sterilise = v)),
            ]),
          ),

          const SizedBox(height: 16),

          // Contrat d'adoption
          _Section(
            title: 'Conditions d\'adoption',
            child: _CheckRow(
              label: 'Contrat d\'adoption obligatoire',
              value: _contratAdoption,
              onChanged: (v) => setState(() => _contratAdoption = v),
            ),
          ),

          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Publier l\'annonce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Checkbox(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        activeColor: const Color(0xFF0C5C6C),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      Flexible(child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14))),
    ]);
  }
}

class _PhotoThumb extends StatelessWidget {
  final String? url;
  final File? file;
  final VoidCallback onRemove;
  const _PhotoThumb({this.url, this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: file != null
              ? Image.file(file!, fit: BoxFit.cover)
              : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4, right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ]),
    );
  }
}
