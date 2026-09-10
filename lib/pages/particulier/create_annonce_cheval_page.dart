import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/widgets/inline_video.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Publication d'une annonce **cheval** par un particulier (cavalier /
/// propriétaire). La reproduction reste réservée aux éleveurs ; ici : vente,
/// location, demi-pension, pension complète, valorisation. Le cheval n'est pas
/// toujours possédé par le posteur (valo, cheval confié) → animal lié optionnel.
class CreateAnnonceChevalPage extends StatefulWidget {
  final String? annonceId;
  final Map<String, dynamic>? initialData;
  final String? preselectedAnimalId;

  const CreateAnnonceChevalPage({
    super.key,
    this.annonceId,
    this.initialData,
    this.preselectedAnimalId,
  });

  @override
  State<CreateAnnonceChevalPage> createState() => _CreateAnnonceChevalPageState();
}

String _genUuid() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
}

class _CreateAnnonceChevalPageState extends State<CreateAnnonceChevalPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _maxVideoBytes = 60 * 1024 * 1024;
  static const _maxPhotos = 4;

  static const _types = [
    ('vente',            'Vente',            Icons.sell_outlined),
    ('location',         'Location',         Icons.event_repeat_outlined),
    ('demi_pension',     'Demi-pension',     Icons.groups_2_outlined),
    ('pension_complete', 'Pension complète', Icons.night_shelter_outlined),
    ('valorisation',     'Valorisation',     Icons.trending_up_outlined),
  ];
  static const _niveaux = [
    'Débutant', 'Galops 1-4', 'Galops 5-7', 'Club', 'Amateur', 'Pro', 'Tous niveaux',
  ];

  final _titreCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _raceCtrl     = TextEditingController();
  final _couleurCtrl  = TextEditingController();
  final _prixCtrl     = TextEditingController();
  final _sireCtrl     = TextEditingController();
  final _palmaresCtrl = TextEditingController();
  final _isoCtrl      = TextEditingController();
  final _idrCtrl      = TextEditingController();
  final _iccCtrl      = TextEditingController();

  String _typeVente = 'vente';
  String _prixUnite = 'total'; // 'total' | 'mois' | 'semaine' | 'convenir'
  String _sexe = 'hongre';
  String _niveau = '';
  DateTime? _dateNaissance;
  bool _prixNegociable = false;

  List<String> _photosUrls  = [];
  List<File>   _photosFiles = [];
  String? _videoMonteUrl;
  String? _videoLibreUrl;
  bool _uploadingVideo = false;

  List<String> _breeds = [];

  // Animal lié (optionnel)
  String? _linkedAnimalId;
  String? _linkedAnimalNom;
  List<Map<String, dynamic>> _mesChevaux = [];
  bool _loadingChevaux = true;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBreeds();
    _loadMesChevaux();
    if (widget.initialData != null) {
      _prefillFromAnnonce(widget.initialData!);
    }
  }

  Future<void> _loadBreeds() async {
    try {
      final raw = await rootBundle.loadString('assets/horse_breeds.json');
      final list = List<String>.from(jsonDecode(raw));
      if (mounted) setState(() => _breeds = list);
    } catch (_) {}
  }

  void _prefillFromAnnonce(Map<String, dynamic> d) {
    _titreCtrl.text = d['titre'] ?? '';
    _descCtrl.text  = d['description'] ?? '';
    _raceCtrl.text  = d['race'] ?? '';
    _couleurCtrl.text = d['couleur'] ?? '';
    _typeVente = d['type_vente'] ?? 'vente';
    _prixUnite = d['prix_unite'] ?? 'total';
    _sexe = d['sexe'] ?? 'hongre';
    _niveau = d['niveau_recommande'] ?? '';
    _prixNegociable = d['prix_negociable'] ?? false;
    final p = d['prix'];
    if (p != null) _prixCtrl.text = (p is num ? p : num.tryParse('$p'))?.toStringAsFixed(0) ?? '';
    _sireCtrl.text = d['num_sire'] ?? '';
    _palmaresCtrl.text = d['palmares'] ?? '';
    _isoCtrl.text = d['indice_iso']?.toString() ?? '';
    _idrCtrl.text = d['indice_idr']?.toString() ?? '';
    _iccCtrl.text = d['indice_icc']?.toString() ?? '';
    _photosUrls = List<String>.from(d['photos'] ?? []);
    _videoMonteUrl = (d['video_monte_url'] as String?)?.isNotEmpty == true ? d['video_monte_url'] : null;
    _videoLibreUrl = (d['video_libre_url'] as String?)?.isNotEmpty == true ? d['video_libre_url'] : null;
    _linkedAnimalId = d['animal_id']?.toString();
    final dn = d['date_naissance_animal']?.toString();
    if (dn != null && dn.isNotEmpty) _dateNaissance = DateTime.tryParse(dn);
  }

  Future<void> _loadMesChevaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingChevaux = false); return; }
    try {
      final ids = <String>{};
      final pid = User_Info.activeProfileId;
      final props = await Supabase.instance.client
          .from('animaux_proprietes')
          .select('animal_id, profile_id_proprio')
          .eq('uid_proprio', uid)
          .isFilter('date_fin', null);
      for (final r in (props as List)) {
        final apid = r['profile_id_proprio']?.toString();
        if (pid.isEmpty || apid == null || apid == pid) {
          final aid = r['animal_id']?.toString();
          if (aid != null && aid.isNotEmpty) ids.add(aid);
        }
      }
      final owned = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece, race, sexe, couleur, date_naissance, photo_url, num_sire')
          .or('uid_eleveur.eq.$uid,uid_acquereur.eq.$uid');
      final rows = <Map<String, dynamic>>[];
      for (final a in (owned as List)) {
        if ((a['espece']?.toString() ?? '') == 'cheval') rows.add(Map<String, dynamic>.from(a));
      }
      if (ids.isNotEmpty) {
        final linked = await Supabase.instance.client
            .from('animaux')
            .select('id, nom, espece, race, sexe, couleur, date_naissance, photo_url, num_sire')
            .inFilter('id', ids.toList());
        for (final a in (linked as List)) {
          if ((a['espece']?.toString() ?? '') == 'cheval' &&
              !rows.any((r) => r['id'] == a['id'])) {
            rows.add(Map<String, dynamic>.from(a));
          }
        }
      }
      if (mounted) {
        setState(() { _mesChevaux = rows; _loadingChevaux = false; });
        final pre = widget.preselectedAnimalId;
        if (pre != null && _linkedAnimalId == null) {
          final match = rows.where((r) => r['id']?.toString() == pre).toList();
          if (match.isNotEmpty) _prefillFromAnimal(match.first);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChevaux = false);
    }
  }

  void _prefillFromAnimal(Map<String, dynamic> a) {
    setState(() {
      _linkedAnimalId  = a['id']?.toString();
      _linkedAnimalNom = a['nom']?.toString();
      if (_raceCtrl.text.isEmpty) _raceCtrl.text = a['race']?.toString() ?? '';
      if (_couleurCtrl.text.isEmpty) _couleurCtrl.text = a['couleur']?.toString() ?? '';
      if (_sireCtrl.text.isEmpty) _sireCtrl.text = a['num_sire']?.toString() ?? '';
      final s = a['sexe']?.toString();
      if (s == 'male' || s == 'femelle' || s == 'hongre' || s == 'entier' || s == 'jument') _sexe = s!;
      final dn = a['date_naissance']?.toString();
      if (dn != null && dn.isNotEmpty) _dateNaissance = DateTime.tryParse(dn);
      if (_titreCtrl.text.isEmpty && _linkedAnimalNom?.isNotEmpty == true) {
        _titreCtrl.text = _linkedAnimalNom!;
      }
    });
  }

  Future<void> _addPhoto() async {
    if (_photosUrls.length + _photosFiles.length >= _maxPhotos) {
      _snack('$_maxPhotos photos maximum.');
      return;
    }
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

  Future<void> _pickVideo({required bool monte}) async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    if (await file.length() > _maxVideoBytes) {
      _snack('Vidéo trop lourde (max 60 Mo).');
      return;
    }
    setState(() => _uploadingVideo = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'x';
      final ext = picked.path.split('.').last.toLowerCase();
      final url = await uploadRawFile(file,
          'annonces/$uid/video_${monte ? 'monte' : 'libre'}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      if (mounted) setState(() {
        if (monte) { _videoMonteUrl = url; } else { _videoLibreUrl = url; }
      });
    } catch (_) {
      _snack('Échec de l\'envoi vidéo.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Galey'))));
    }
  }

  Future<void> _save() async {
    final priced = _typeVente != 'valorisation';
    if (_titreCtrl.text.trim().isEmpty) { _snack('Un titre est requis.'); return; }
    if (_sireCtrl.text.trim().length < 6) { _snack('Le n° SIRE est obligatoire (Décret 2013-879).'); return; }
    if (_photosUrls.isEmpty && _photosFiles.isEmpty) { _snack('Ajoutez au moins une photo.'); return; }
    if (priced && double.tryParse(_prixCtrl.text.trim()) == null && _prixUnite != 'convenir') {
      _snack('Indiquez un prix (ou passez en « à convenir »).');
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final pid = User_Info.activeProfileId;

      // Quota : max 5 annonces actives pour ce profil.
      if (widget.annonceId == null) {
        final actives = await Supabase.instance.client
            .from('annonces')
            .select('id')
            .eq('uid_eleveur', uid)
            .eq('profil_source', 'particulier')
            .inFilter('statut', ['disponible', 'reserve']);
        if ((actives as List).length >= 5) {
          _snack('Limite de 5 annonces actives atteinte. Mettez-en une en pause d\'abord.');
          setState(() => _saving = false);
          return;
        }
      }

      // Profil particulier actif (géo + nom).
      final q = Supabase.instance.client.from('user_profiles').select(
          'firstname, lastname, nom, ville, code_postal, departement, region, pays');
      final row = pid.isEmpty
          ? await q.eq('uid', uid).eq('is_main', true).maybeSingle()
          : await q.eq('id', pid).maybeSingle();
      final u = row ?? <String, dynamic>{};
      final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
      final cp  = (u['code_postal'] as String?) ?? '';
      final dep = () {
        final d = u['departement'] as String?;
        if (d != null && d.isNotEmpty) return d;
        return FrenchGeo.fromPostalCode(cp)?.departement ?? '';
      }();
      final region = () {
        final r = u['region'] as String?;
        if (r != null && r.isNotEmpty) return r;
        return FrenchGeo.fromPostalCode(cp)?.region ?? '';
      }();

      final newUrls = <String>[];
      for (final f in _photosFiles) {
        newUrls.add(await uploadPhoto(f, 'annonces/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg'));
      }
      final allPhotos = [..._photosUrls, ...newUrls];

      final now = DateTime.now().toIso8601String();
      final prix = priced && _prixUnite != 'convenir' ? double.tryParse(_prixCtrl.text.trim()) : null;

      final data = <String, dynamic>{
        'uid_eleveur':         uid,
        if (pid.isNotEmpty) 'profile_id': pid,
        'nom_eleveur':         nom.isEmpty ? (u['nom'] ?? 'Particulier') : nom,
        'ville_eleveur':       u['ville'] ?? '',
        'departement_eleveur': dep,
        'region_eleveur':      region,
        'pays_eleveur':        u['pays'] ?? 'France',
        'profil_source':       'particulier',
        'type':                'animal',
        'type_vente':          _typeVente,
        'espece':              'cheval',
        'race':                _raceCtrl.text.trim(),
        'titre':               _titreCtrl.text.trim(),
        'description':         _descCtrl.text.trim(),
        'photos':              allPhotos,
        'prix':                prix,
        'prix_unite':          _typeVente == 'vente' ? null : _prixUnite,
        'prix_negociable':     _prixNegociable,
        'statut':              'disponible',
        'sexe':                _sexe,
        'couleur':             _couleurCtrl.text.trim(),
        'date_naissance_animal': _dateNaissance?.toIso8601String().substring(0, 10),
        'num_sire':            _sireCtrl.text.trim(),
        'niveau_recommande':   _niveau.isEmpty ? null : _niveau,
        'palmares':            _palmaresCtrl.text.trim().isEmpty ? null : _palmaresCtrl.text.trim(),
        'indice_iso':          int.tryParse(_isoCtrl.text.trim()),
        'indice_idr':          int.tryParse(_idrCtrl.text.trim()),
        'indice_icc':          int.tryParse(_iccCtrl.text.trim()),
        'video_monte_url':     _videoMonteUrl,
        'video_libre_url':     _videoLibreUrl,
        // `annonces.animal_id` est TEXT (migration_annonces_animal_id_text) :
        // on stocke l'ID tel quel, y compris les anciens IDs courts (timestamp).
        'animal_id':           (_linkedAnimalId?.isNotEmpty ?? false) ? _linkedAnimalId : null,
        'updated_at':          now,
      };

      // Anti-fraude léger : uniquement sur une vente ferme.
      if (_typeVente == 'vente') {
        final reasons = <String>[];
        if (prix != null && prix > 0 && prix < 800) reasons.add('prix_tres_bas');
        if (prix != null && prix > 150000) reasons.add('prix_tres_eleve');
        final txt = '${data['titre']} ${data['description']}'.toLowerCase();
        for (final w in const ['bitcoin', 'crypto', 'western union', 'mandat cash', 'paypal friends']) {
          if (txt.contains(w)) reasons.add('mot_suspect:$w');
        }
        data['is_suspect'] = reasons.isNotEmpty;
        data['suspect_reasons'] = reasons;
      }

      if (widget.annonceId != null) {
        await Supabase.instance.client.from('annonces').update(data).eq('id', widget.annonceId!);
      } else {
        data['id']         = _genUuid();
        data['created_at'] = now;
        data['expires_at'] = DateTime.now().add(const Duration(days: 60)).toIso8601String();
        data['vues']       = 0;
        data['contacts']   = 0;
        await Supabase.instance.client.from('annonces').insert(data);
      }

      if (mounted) {
        _snack('Annonce publiée !');
        Navigator.pop(context, true);
      }
    } catch (e) {
      final msg = e is PostgrestException ? '[${e.code}] ${e.message}' : e.toString();
      if (mounted) {
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
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(children: [
          const Padding(padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Text('Lier un de mes chevaux',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
          if (_loadingChevaux)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else if (_mesChevaux.isEmpty)
            const Padding(padding: EdgeInsets.all(24),
                child: Text('Aucun cheval dans votre profil — saisie libre ci-dessous.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
          else
            Expanded(child: ListView(controller: ctrl, children: [
              for (final a in _mesChevaux)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFDCEDD5),
                    backgroundImage: (a['photo_url']?.toString().isNotEmpty ?? false)
                        ? CachedNetworkImageProvider(a['photo_url']) as ImageProvider : null,
                    child: (a['photo_url']?.toString().isEmpty ?? true)
                        ? const Icon(Icons.pets, color: _green, size: 18) : null,
                  ),
                  title: Text(a['nom']?.toString() ?? '—',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: Text(a['race']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                  trailing: _linkedAnimalId == a['id']?.toString()
                      ? const Icon(Icons.check_circle, color: _green) : null,
                  onTap: () { Navigator.pop(context); _prefillFromAnimal(a); },
                ),
            ])),
        ]),
      ),
    );
  }

  Future<void> _pickBreed() async {
    if (_breeds.isEmpty) return;
    final ctrl = TextEditingController();
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        final query = ctrl.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? _breeds
            : _breeds.where((b) => b.toLowerCase().contains(query)).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  onChanged: (_) => setSheet(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une race…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(filtered[i], style: const TextStyle(fontFamily: 'Galey')),
                  onTap: () => Navigator.pop(ctx, filtered[i]),
                ),
              )),
            ]),
          ),
        );
      }),
    );
    if (sel != null) setState(() => _raceCtrl.text = sel);
  }

  @override
  void dispose() {
    for (final c in [
      _titreCtrl, _descCtrl, _raceCtrl, _couleurCtrl, _prixCtrl, _sireCtrl,
      _palmaresCtrl, _isoCtrl, _idrCtrl, _iccCtrl,
    ]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final priced = _typeVente != 'valorisation';
    final showCadence = const {'location', 'demi_pension', 'pension_complete'}.contains(_typeVente);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.annonceId != null ? 'Modifier l\'annonce' : 'Annonce cheval',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : TextButton(onPressed: _save,
                  child: const Text('Publier', style: TextStyle(color: Colors.white,
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _section('Type d\'annonce', child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _types)
            ChoiceChip(
              avatar: Icon(t.$3, size: 16,
                  color: _typeVente == t.$1 ? Colors.white : Colors.grey),
              label: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              selected: _typeVente == t.$1,
              onSelected: (_) => setState(() {
                _typeVente = t.$1;
                _prixUnite = switch (t.$1) {
                  'location' || 'demi_pension' || 'pension_complete' => 'mois',
                  'valorisation' => 'convenir',
                  _ => 'total',
                };
              }),
              selectedColor: _green,
              labelStyle: TextStyle(color: _typeVente == t.$1 ? Colors.white : Colors.black87),
              backgroundColor: Colors.white,
              side: BorderSide(color: _typeVente == t.$1 ? _green : Colors.grey.shade300),
            ),
        ])),

        const SizedBox(height: 16),
        _section('Mon cheval (optionnel)', child: OutlinedButton.icon(
          onPressed: _selectAnimal,
          icon: const Icon(Icons.pets_outlined),
          label: Text(_linkedAnimalNom != null ? 'Lié : $_linkedAnimalNom' : 'Lier un de mes chevaux',
              style: const TextStyle(fontFamily: 'Galey')),
          style: OutlinedButton.styleFrom(
            foregroundColor: _teal,
            side: const BorderSide(color: _teal),
            minimumSize: const Size(double.infinity, 44),
            alignment: Alignment.centerLeft,
          ),
        )),

        const SizedBox(height: 16),
        _section('Titre', child: _tf(_titreCtrl, 'Ex : Jument PS, 8 ans, prête club 1')),

        const SizedBox(height: 12),
        if (priced) ...[
          _section(_typeVente == 'valorisation' ? 'Rémunération' : 'Prix', child: Row(children: [
            Expanded(child: _tf(_prixCtrl, _prixUnite == 'convenir' ? 'À convenir' : '€',
                keyboardType: TextInputType.number, enabled: _prixUnite != 'convenir')),
            if (showCadence) ...[
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _prixUnite == 'total' || _prixUnite == 'convenir' ? 'mois' : _prixUnite,
                items: const [
                  DropdownMenuItem(value: 'mois', child: Text('/ mois', style: TextStyle(fontFamily: 'Galey'))),
                  DropdownMenuItem(value: 'semaine', child: Text('/ semaine', style: TextStyle(fontFamily: 'Galey'))),
                ],
                onChanged: (v) => setState(() => _prixUnite = v ?? 'mois'),
              ),
            ],
          ])),
          Row(children: [
            Checkbox(
              value: _prixNegociable,
              activeColor: _teal,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => _prixNegociable = v ?? false),
            ),
            const Text('Prix négociable', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
          ]),
          const SizedBox(height: 4),
        ],

        _section('Race', child: GestureDetector(
          onTap: _breeds.isEmpty ? null : _pickBreed,
          child: AbsorbPointer(
            absorbing: _breeds.isNotEmpty,
            child: _tf(_raceCtrl, _breeds.isEmpty ? 'Ex : Selle Français, PS, Poney…' : 'Choisir une race'),
          ),
        )),

        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _section('Sexe', child: DropdownButtonFormField<String>(
            value: _sexe,
            decoration: _deco(''),
            items: const [
              DropdownMenuItem(value: 'jument', child: Text('Jument', style: TextStyle(fontFamily: 'Galey'))),
              DropdownMenuItem(value: 'hongre', child: Text('Hongre', style: TextStyle(fontFamily: 'Galey'))),
              DropdownMenuItem(value: 'entier', child: Text('Entier', style: TextStyle(fontFamily: 'Galey'))),
            ],
            onChanged: (v) => setState(() => _sexe = v ?? 'hongre'),
          ))),
          const SizedBox(width: 12),
          Expanded(child: _section('Robe', child: _tf(_couleurCtrl, 'Bai, alezan…'))),
        ]),

        const SizedBox(height: 12),
        _section('Date de naissance', child: InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _dateNaissance ?? DateTime(DateTime.now().year - 8),
              firstDate: DateTime(1990),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _dateNaissance = d);
          },
          child: InputDecorator(
            decoration: _deco(''),
            child: Text(
              _dateNaissance == null ? 'Choisir…'
                  : '${_dateNaissance!.day.toString().padLeft(2, '0')}/${_dateNaissance!.month.toString().padLeft(2, '0')}/${_dateNaissance!.year}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            ),
          ),
        )),

        const SizedBox(height: 12),
        _section('N° SIRE (obligatoire)', child: _tf(_sireCtrl, '250 00X XXX XXX XXX',
            keyboardType: TextInputType.number)),

        const SizedBox(height: 16),
        _section('Niveau recommandé', child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final n in _niveaux)
            ChoiceChip(
              label: Text(n, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              selected: _niveau == n,
              onSelected: (_) => setState(() => _niveau = _niveau == n ? '' : n),
              selectedColor: _teal,
              labelStyle: TextStyle(color: _niveau == n ? Colors.white : Colors.black87),
              backgroundColor: Colors.white,
              side: BorderSide(color: _niveau == n ? _teal : Colors.grey.shade300),
            ),
        ])),

        const SizedBox(height: 16),
        _section('Palmarès / résultats (optionnel)',
            child: _tf(_palmaresCtrl, 'Ex : 3e Amateur 2 GP Lamotte 2025…', maxLines: 3)),

        const SizedBox(height: 12),
        _section('Indices (optionnel)', child: Row(children: [
          Expanded(child: _tf(_isoCtrl, 'ISO', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _tf(_idrCtrl, 'IDR', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _tf(_iccCtrl, 'ICC', keyboardType: TextInputType.number)),
        ])),

        const SizedBox(height: 16),
        _section('Photos (max $_maxPhotos)', child: Column(children: [
          if (_photosUrls.isNotEmpty || _photosFiles.isNotEmpty)
            SizedBox(height: 90, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _photosUrls.length; i++)
                _thumb(url: _photosUrls[i], onRemove: () => setState(() => _photosUrls.removeAt(i))),
              for (var i = 0; i < _photosFiles.length; i++)
                _thumb(file: _photosFiles[i], onRemove: () => setState(() => _photosFiles.removeAt(i))),
            ])),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Ajouter une photo', style: TextStyle(fontFamily: 'Galey')),
            style: OutlinedButton.styleFrom(
              foregroundColor: _green, side: const BorderSide(color: _green),
              minimumSize: const Size(double.infinity, 44)),
          ),
        ])),

        const SizedBox(height: 16),
        _section('Vidéo sous selle', child: _videoSlot(_videoMonteUrl, monte: true)),
        const SizedBox(height: 12),
        _section('Vidéo en liberté', child: _videoSlot(_videoLibreUrl, monte: false)),

        const SizedBox(height: 16),
        _section('Description', child: _tf(_descCtrl, 'Caractère, aptitudes, conditions…', maxLines: 5)),

        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal, foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Publier l\'annonce',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _videoSlot(String? url, {required bool monte}) {
    if (url != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10),
            child: InlineVideo(url: url, placeholderHeight: 150)),
        TextButton.icon(
          onPressed: () => setState(() { if (monte) { _videoMonteUrl = null; } else { _videoLibreUrl = null; } }),
          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
          label: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red)),
        ),
      ]);
    }
    return OutlinedButton.icon(
      onPressed: _uploadingVideo ? null : () => _pickVideo(monte: monte),
      icon: _uploadingVideo
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.video_call_outlined, size: 18),
      label: Text(_uploadingVideo ? 'Envoi…' : 'Ajouter une vidéo',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _teal, side: const BorderSide(color: _teal),
        minimumSize: const Size(double.infinity, 44)),
    );
  }

  Widget _section(String title, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 14, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 8),
      child,
    ]);

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 13),
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  Widget _tf(TextEditingController c, String hint,
          {int maxLines = 1, TextInputType? keyboardType, bool enabled = true}) =>
      TextField(
        controller: c, maxLines: maxLines, keyboardType: keyboardType, enabled: enabled,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: _deco(hint),
      );

  Widget _thumb({String? url, File? file, required VoidCallback onRemove}) => Container(
    width: 84, height: 84, margin: const EdgeInsets.only(right: 8),
    child: Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(10),
          child: file != null ? Image.file(file, fit: BoxFit.cover)
              : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)),
      Positioned(top: 4, right: 4, child: GestureDetector(
        onTap: onRemove,
        child: Container(
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: const Icon(Icons.close, color: Colors.white, size: 16),
        ),
      )),
    ]),
  );
}
