import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as stockage;
import 'package:PetsMatch/widgets/liste_especes_cocher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Catégories d'un lieu recommandé : mêmes valeurs que les fiches des
/// établissements (categorie + sous_categorie), plus commerce et activité.
/// Miroir site : website/src/lib/lieux-categories.ts.
const kTypesLieu = [
  ('restaurant', 'restauration', 'Restaurant'),
  ('cafe', 'restauration', 'Café / Salon de thé'),
  ('bar', 'restauration', 'Bar / Brasserie'),
  ('boulangerie', 'restauration', 'Boulangerie / Pâtisserie'),
  ('hotel', 'hebergement', 'Hôtel'),
  ('gite', 'hebergement', 'Gîte / Chambre d\'hôtes'),
  ('camping', 'hebergement', 'Camping'),
  ('villa_location', 'hebergement', 'Location saisonnière'),
  ('hebergement_insolite', 'hebergement', 'Hébergement insolite'),
  ('commerce', 'commerce', 'Commerce'),
  ('activite', 'activite', 'Activité ou loisir'),
];

/// « Recommander un lieu » (particulier) : recherche préalable (pas de
/// doublon), informations, conditions d'accueil (oui / non / je ne sais pas),
/// expérience, validation → fiche « en attente de validation » (modération).
class RecommanderLieuPage extends StatefulWidget {
  /// Fiche du contributeur à compléter (statut brouillon / à corriger / en
  /// attente) : formulaire prérempli, enregistrement puis renvoi en validation.
  final Map<String, dynamic>? existant;
  const RecommanderLieuPage({super.key, this.existant});
  @override
  State<RecommanderLieuPage> createState() => _RecommanderLieuPageState();
}

class _RecommanderLieuPageState extends State<RecommanderLieuPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  int _etape = 0; // 0 recherche, 1 infos, 2 conditions, 3 expérience, 4 validation
  bool _envoi = false;

  // Étape 1 — recherche
  final _rechercheCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _trouves = [];
  bool _recherche = false;

  // Étape 2 — informations
  late final GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: getApiKey());
  final _nomCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  List<Prediction> _predictions = [];
  String? _type;
  String _rue = '', _cp = '', _ville = '';
  double? _lat, _lng;

  // Étape 3 — conditions (null = je ne sais pas)
  Set<String> _especes = {};
  bool? _interieur, _terrasse, _taille, _supplement;
  final _nbCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  DateTime? _visite;

  // Étape 4 — expérience
  final _pourquoiCtrl = TextEditingController();
  final List<File> _photos = [];
  bool _confirme = false;

  // Doublons détectés avant envoi (lieux à moins de 150 m)
  List<Map<String, dynamic>> _proches = [];
  List<String> _photosExistantes = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existant;
    if (e == null) return;
    _etape = 1;
    _nomCtrl.text = (e['nom'] ?? '').toString();
    final sc = (e['sous_categorie'] ?? '').toString();
    _type = kTypesLieu.any((t) => t.$1 == sc) ? sc : null;
    _rue = (e['adresse'] ?? '').toString();
    _cp = (e['code_postal'] ?? '').toString();
    _ville = (e['ville'] ?? '').toString();
    _adresseCtrl.text = [_rue, _cp, _ville].where((x) => x.isNotEmpty).join(' ');
    _lat = (e['lat'] as num?)?.toDouble();
    _lng = (e['lng'] as num?)?.toDouble();
    _siteCtrl.text = (e['site_web'] ?? '').toString();
    _telCtrl.text = (e['telephone'] ?? '').toString();
    _especes = Set<String>.from(e['especes_acceptees'] as List? ?? []);
    _interieur = e['animaux_en_salle'] as bool?;
    _terrasse = e['terrasse'] as bool?;
    _taille = e['restriction_taille'] as bool?;
    _supplement = e['supplement_animal'] as bool?;
    _nbCtrl.text = e['nb_animaux_max']?.toString() ?? '';
    _conditionsCtrl.text = (e['conditions_particulieres'] ?? '').toString();
    _visite = DateTime.tryParse(e['derniere_confirmation_le']?.toString() ?? '');
    _pourquoiCtrl.text = (e['recommandation'] ?? '').toString();
    _photosExistantes = List<String>.from(e['photos'] as List? ?? []);
    _confirme = true;
  }

  @override
  void dispose() {
    for (final c in [_rechercheCtrl, _nomCtrl, _adresseCtrl, _siteCtrl, _telCtrl, _nbCtrl, _conditionsCtrl, _pourquoiCtrl]) {
      c.dispose();
    }
    _debounce?.cancel();
    _places.dispose();
    super.dispose();
  }

  // ── Recherche préalable ─────────────────────────────────────────────────
  void _onRecherche(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) { setState(() => _trouves = []); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () => _chercher(v.trim()));
  }

  Future<void> _chercher(String q) async {
    setState(() => _recherche = true);
    try {
      final motif = '%${q.replaceAll('%', '')}%';
      final rows = await _supa.from('petfriendly_places')
          .select('id, nom, ville, adresse, categorie, sous_categorie, origine, uid_pro, plan, verification, lat, lng')
          .eq('statut', 'actif')
          .or('nom.ilike.$motif,ville.ilike.$motif,adresse.ilike.$motif')
          .limit(20);
      if (mounted) setState(() => _trouves = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  Future<void> _autourDeMoi() async {
    setState(() => _recherche = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _message('Localisation refusée : recherchez par nom ou par ville.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      const d = 0.02; // ~2 km
      final rows = await _supa.from('petfriendly_places')
          .select('id, nom, ville, adresse, categorie, sous_categorie, origine, uid_pro, plan, verification, lat, lng')
          .eq('statut', 'actif')
          .gte('lat', pos.latitude - d).lte('lat', pos.latitude + d)
          .gte('lng', pos.longitude - d * 1.5).lte('lng', pos.longitude + d * 1.5)
          .limit(30);
      if (mounted) setState(() => _trouves = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {
      _message('Position indisponible pour le moment.');
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  // ── Adresse (Google Places, comme l'inscription d'un établissement) ─────
  void _onAdresse(String v) {
    _debounce?.cancel();
    if (v.length < 3) { setState(() => _predictions = []); return; }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await _places.autocomplete(v, components: [Component(Component.country, 'fr')], language: 'fr');
      if (mounted) setState(() => _predictions = res.isOkay ? res.predictions : []);
    });
  }

  Future<void> _choisirAdresse(Prediction p) async {
    _debounce?.cancel();
    setState(() { _predictions = []; _adresseCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    String num = '', route = '', cp = '', ville = '';
    for (final c in det.result.addressComponents) {
      if (c.types.contains('street_number')) num = c.longName;
      if (c.types.contains('route')) route = c.longName;
      if (c.types.contains('postal_code')) cp = c.longName;
      if (c.types.contains('locality')) {
        ville = c.longName;
      } else if (c.types.contains('administrative_area_level_2') && ville.isEmpty) {
        ville = c.longName;
      }
    }
    final loc = det.result.geometry?.location;
    var rue = [num, route].where((s) => s.isNotEmpty).join(' ');
    if (rue.isEmpty) rue = (det.result.formattedAddress ?? p.description ?? '').split(',').first.trim();
    setState(() {
      _rue = rue; _cp = cp; _ville = ville;
      if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
    });
  }

  double _distance(double la1, double lo1, double la2, double lo2) {
    const r = math.pi / 180;
    final h = math.pow(math.sin((la2 - la1) * r / 2), 2) +
        math.cos(la1 * r) * math.cos(la2 * r) * math.pow(math.sin((lo2 - lo1) * r / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(h));
  }

  Future<void> _chercherProches() async {
    if (_lat == null || _lng == null) return;
    try {
      const d = 0.003;
      final rows = await _supa.from('petfriendly_places')
          .select('id, nom, ville, lat, lng')
          .eq('statut', 'actif')
          .gte('lat', _lat! - d).lte('lat', _lat! + d)
          .gte('lng', _lng! - d).lte('lng', _lng! + d);
      final proches = List<Map<String, dynamic>>.from(rows as List).where((p) {
        final la = (p['lat'] as num?)?.toDouble(), lo = (p['lng'] as num?)?.toDouble();
        return la != null && lo != null && _distance(_lat!, _lng!, la, lo) < 150;
      }).toList();
      if (mounted) setState(() => _proches = proches);
    } catch (_) {}
  }

  // ── Navigation entre étapes ─────────────────────────────────────────────
  bool _etapeValide() {
    switch (_etape) {
      case 1:
        if (_nomCtrl.text.trim().isEmpty) return _err('Indiquez le nom du lieu.');
        if (_type == null) return _err('Choisissez une catégorie.');
        if (_lat == null || _lng == null) return _err('Choisissez l\'adresse dans la liste pour placer le lieu sur la carte.');
        return true;
      case 2:
        if (_especes.isEmpty) return _err('Indiquez au moins une espèce accueillie.');
        if (_visite == null) return _err('Indiquez la date de votre dernière visite.');
        return true;
      case 3:
        if (_pourquoiCtrl.text.trim().length < 10) return _err('Dites en quelques mots pourquoi vous recommandez ce lieu.');
        if (!_confirme) return _err('Merci de cocher la confirmation.');
        return true;
    }
    return true;
  }

  bool _err(String m) { _message(m); return false; }
  void _message(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _suivant() async {
    if (!_etapeValide()) return;
    if (_etape == 3) await _chercherProches();
    setState(() => _etape++);
  }

  // ── Envoi ──────────────────────────────────────────────────────────────
  Future<void> _envoyer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _envoi = true);
    try {
      final type = kTypesLieu.firstWhere((t) => t.$1 == _type);
      final dossier = '${uid}_${DateTime.now().millisecondsSinceEpoch}';
      final urls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        urls.add(await stockage.uploadPhoto(_photos[i], 'lieux/communaute/$dossier/photo_$i.jpg'));
      }
      final pid = User_Info.activeProfileId;
      final donnees = <String, dynamic>{
        'nom': _nomCtrl.text.trim(),
        'categorie': type.$2,
        'sous_categorie': type.$1,
        'adresse': _rue,
        'code_postal': _cp.isEmpty ? null : _cp,
        'ville': _ville,
        'lat': _lat,
        'lng': _lng,
        'site_web': _siteCtrl.text.trim().isEmpty ? null : _siteCtrl.text.trim(),
        'telephone': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'especes_acceptees': _especes.toList(),
        // Je ne sais pas = null : jamais transformé en « oui ».
        'animaux_en_salle': _interieur,
        'terrasse': _terrasse,
        'restriction_taille': _taille,
        'supplement_animal': _supplement,
        'nb_animaux_max': int.tryParse(_nbCtrl.text.trim()),
        'conditions_particulieres': _conditionsCtrl.text.trim().isEmpty ? null : _conditionsCtrl.text.trim(),
        'derniere_confirmation_le': DateFormat('yyyy-MM-dd').format(_visite!),
        'recommandation': _pourquoiCtrl.text.trim(),
        'photos': [..._photosExistantes, ...urls],
        'statut': 'en_attente_validation',
      };
      if (widget.existant != null) {
        // Fiche complétée : mise à jour puis renvoi en validation.
        await _supa.from('petfriendly_places').update(donnees).eq('id', widget.existant!['id']);
      } else {
        await _supa.from('petfriendly_places').insert({
          ...donnees,
          'origine': 'communaute',
          'source_conditions': 'communaute',
          'ajoute_par_uid': uid,
          if (pid.isNotEmpty) 'ajoute_par_profile_id': pid,
        });
      }
      if (!mounted) return;
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text(widget.existant != null ? 'Fiche renvoyée en validation' : 'Merci pour votre recommandation',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Votre proposition est en attente de validation. Vous serez prévenu(e) dès qu\'elle sera publiée, '
            'ou si des précisions sont nécessaires.', style: TextStyle(fontFamily: 'Galey')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _message('Envoi impossible : $e');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  // ── Interface ──────────────────────────────────────────────────────────
  static const _titres = ['Recommander un lieu', 'Le lieu', 'Conditions d\'accueil', 'Votre expérience', 'Vérification'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Étape ${_etape + 1} sur 5', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
          Text(_titres[_etape], style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_etape + 1) / 5, minHeight: 4,
              backgroundColor: Colors.white24, color: Colors.white),
        ),
      ),
      body: SafeArea(child: switch (_etape) {
        0 => _etapeRecherche(),
        1 => _etapeInfos(),
        2 => _etapeConditions(),
        3 => _etapeExperience(),
        _ => _etapeValidation(),
      }),
      bottomNavigationBar: _etape == 0 ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _envoi ? null : () => (widget.existant != null && _etape == 1) ? Navigator.pop(context) : setState(() => _etape--),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Retour', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: _envoi ? null : (_etape == 4 ? _envoyer : _suivant),
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _envoi
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_etape == 4 ? (widget.existant != null ? 'Renvoyer en validation' : 'Envoyer ma recommandation') : 'Continuer',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }

  InputDecoration _deco(String label, {String? aide}) => InputDecoration(
        labelText: label, hintText: aide, filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      );

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
      );

  String _libelleReferencement(Map<String, dynamic> l) {
    if (l['uid_pro'] == null) return 'Recommandé par la communauté';
    if ((l['plan'] ?? 'decouverte') != 'decouverte') return 'Partenaire PetsMatch';
    return 'Établissement vérifié';
  }

  Widget _etapeRecherche() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Vérifions d\'abord que le lieu n\'est pas déjà sur PetsMatch.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
      const SizedBox(height: 12),
      TextField(controller: _rechercheCtrl, onChanged: _onRecherche,
          decoration: _deco('Nom, adresse ou ville').copyWith(prefixIcon: const Icon(Icons.search))),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _autourDeMoi,
        icon: const Icon(Icons.my_location, size: 18),
        label: const Text('Autour de moi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      if (_recherche) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_trouves.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('DÉJÀ SUR PETSMATCH', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 0.6, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        for (final l in _trouves)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((l['nom'] ?? '').toString(), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15)),
                Text([l['adresse'], l['ville'], _libelleReferencement(l)].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                const Text('Ce lieu est déjà référencé. Souhaitez-vous partager votre expérience ou proposer une modification ?',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LieuDetailPage(id: l['id'].toString()))),
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                  child: const Text('Voir la fiche', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                )),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 20),
      Text('Le lieu n\'apparaît pas dans la liste ?', textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: () => setState(() {
          if (_nomCtrl.text.isEmpty) _nomCtrl.text = _rechercheCtrl.text.trim();
          _etape = 1;
        }),
        style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: const Text('Ajouter ce lieu', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _etapeInfos() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _nomCtrl, decoration: _deco('Nom de l\'établissement *')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _type,
        isExpanded: true,
        decoration: _deco('Catégorie *'),
        items: [for (final t in kTypesLieu) DropdownMenuItem(value: t.$1, child: Text(t.$3))],
        onChanged: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 12),
      TextField(controller: _adresseCtrl, onChanged: _onAdresse, decoration: _deco('Adresse *', aide: 'Commencez à taper puis choisissez')),
      for (final p in _predictions)
        ListTile(dense: true, leading: const Icon(Icons.place_outlined), title: Text(p.description ?? ''), onTap: () => _choisirAdresse(p)),
      if (_lat != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Lieu placé sur la carte : $_rue, $_cp $_ville',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
        ),
      const SizedBox(height: 12),
      TextField(controller: _siteCtrl, keyboardType: TextInputType.url, decoration: _deco('Site internet (facultatif)')),
      const SizedBox(height: 12),
      TextField(controller: _telCtrl, keyboardType: TextInputType.phone, decoration: _deco('Téléphone public (facultatif)')),
    ]);
  }

  Widget _troisEtats(String libelle, bool? valeur, ValueChanged<bool?> onChanged) {
    Widget choix(String t, bool? v) {
      final sel = valeur == v;
      return Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          onPressed: () => onChanged(v),
          style: OutlinedButton.styleFrom(
            backgroundColor: sel ? const Color(0xFFE8F4F6) : Colors.white,
            side: BorderSide(color: sel ? _teal : Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? _teal : const Color(0xFF33454B))),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [choix('Oui', true), choix('Non', false), choix('Je ne sais pas', null)]),
      ]),
    );
  }

  Widget _etapeConditions() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Répondez selon ce que vous avez constaté. « Je ne sais pas » restera affiché comme non renseigné.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 12),
      _titre('Espèces accueillies (une ou plusieurs) *'),
      ListeEspecesACocher(selection: _especes, onChanged: (v) => setState(() => _especes = v)),
      const SizedBox(height: 16),
      _troisEtats('Accès à l\'intérieur', _interieur, (v) => setState(() => _interieur = v)),
      _troisEtats('Terrasse ou extérieur', _terrasse, (v) => setState(() => _terrasse = v)),
      _troisEtats('Restriction de taille constatée', _taille, (v) => setState(() => _taille = v)),
      _troisEtats('Supplément tarifaire', _supplement, (v) => setState(() => _supplement = v)),
      TextField(controller: _nbCtrl, keyboardType: TextInputType.number, decoration: _deco('Nombre d\'animaux autorisés (si connu)')),
      const SizedBox(height: 12),
      TextField(controller: _conditionsCtrl, maxLines: 2, decoration: _deco('Conditions particulières', aide: 'Ex. laisse obligatoire en salle')),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: _visite ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)), lastDate: DateTime.now());
          if (d != null) setState(() => _visite = d);
        },
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text(_visite == null ? 'Date de votre dernière visite *' : 'Dernière visite : ${DateFormat('dd/MM/yyyy').format(_visite!)}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _etapeExperience() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _pourquoiCtrl, maxLines: 5, maxLength: 1500,
          decoration: _deco('Pourquoi recommandez-vous ce lieu ? *', aide: 'Votre expérience avec votre animal')),
      _titre('Photos (facultatif, prises par vous)'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < _photos.length; i++)
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_photos[i], width: 84, height: 84, fit: BoxFit.cover)),
            Positioned(right: 0, top: 0, child: IconButton(
              tooltip: 'Retirer', icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: () => setState(() => _photos.removeAt(i)),
            )),
          ]),
        if (_photos.length < 6)
          InkWell(
            onTap: () async {
              final picks = await ImagePicker().pickMultiImage(imageQuality: 80);
              if (picks.isNotEmpty) setState(() => _photos.addAll(picks.take(6 - _photos.length).map((x) => File(x.path))));
            },
            child: Container(width: 84, height: 84,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.add_a_photo_outlined, color: _teal)),
          ),
      ]),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: _confirme,
        onChanged: (v) => setState(() => _confirme = v == true),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: _teal,
        contentPadding: EdgeInsets.zero,
        title: const Text('Je confirme que les informations communiquées correspondent à mon expérience ou à des éléments '
            'que je peux raisonnablement vérifier, et que les photos ont été prises par moi.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
      ),
    ]);
  }

  Widget _etapeValidation() {
    final type = kTypesLieu.where((t) => t.$1 == _type);
    String etat(bool? v) => v == true ? 'Oui' : v == false ? 'Non' : 'Non renseigné';
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_proches.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFDF6EC), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF1D9B5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Un lieu très proche existe déjà. S\'agit-il du même ?',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFF6B4A12))),
            for (final p in _proches)
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LieuDetailPage(id: p['id'].toString()))),
                child: Text('Oui, voir « ${p['nom']} »', style: const TextStyle(fontFamily: 'Galey')),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      Text(_nomCtrl.text.trim(), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
      Text('${type.isEmpty ? '' : type.first.$3} · $_rue, $_cp $_ville',
          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 12),
      Text('Espèces : ${kEspecesLieux.where((e) => _especes.contains(e.$1)).map((e) => e.$2).join(', ')}',
          style: const TextStyle(fontFamily: 'Galey')),
      Text('Intérieur : ${etat(_interieur)} · Terrasse : ${etat(_terrasse)}', style: const TextStyle(fontFamily: 'Galey')),
      Text('Taille : ${etat(_taille)} · Supplément : ${etat(_supplement)}', style: const TextStyle(fontFamily: 'Galey')),
      if (_visite != null) Text('Dernière visite : ${DateFormat('dd/MM/yyyy').format(_visite!)}', style: const TextStyle(fontFamily: 'Galey')),
      const SizedBox(height: 12),
      Text('« ${_pourquoiCtrl.text.trim()} »', style: const TextStyle(fontFamily: 'Galey', fontStyle: FontStyle.italic)),
      const SizedBox(height: 16),
      Text('Votre recommandation sera vérifiée par l\'équipe PetsMatch avant d\'apparaître sur la carte, avec la mention '
          '« Recommandé par la communauté ». Votre prénom n\'est pas affiché publiquement avec la fiche.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
    ]);
  }
}
