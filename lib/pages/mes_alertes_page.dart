import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/services/alertes_notifications.dart';

class MesAlertesPage extends StatefulWidget {
  const MesAlertesPage({super.key});
  @override
  State<MesAlertesPage> createState() => _MesAlertesPageState();
}

class _MesAlertesPageState extends State<MesAlertesPage> {
  final _supa = Supabase.instance.client;
  static const _teal  = Color(0xFF0C5C6C);
  static const _orange = Color(0xFFE65100);

  List<Map<String, dynamic>> _alertes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlertes();
  }

  Future<void> _fetchAlertes() async {
    final uid = User_Info.uid;
    if (uid.isEmpty) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _alertes = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retrouveAlerte(String id) async {
    await _supa.from('alertes_perdus').update({
      'statut': 'retrouve',
      'date_retrouve': DateTime.now().toIso8601String().substring(0, 10),
    }).eq('id', id);
    _fetchAlertes();
  }

  Future<void> _deleteAlerte(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'alerte ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('alertes_perdus').delete().eq('id', id);
    _fetchAlertes();
  }

  Future<void> _editAlerte(Map<String, dynamic> a) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AlertePerduFormPage(
        alerteId: a['id'] as String?,
        animalId: a['animal_id'] as String?,
        photoUrl: a['photo_url'] as String?,
        nom:      a['nom_animal'] as String?,
        espece:   a['espece'] as String?,
        race:     a['race'] as String?,
        sexe:     a['sexe'] as String?,
        couleur:  a['couleur'] as String?,
      ),
    ));
    _fetchAlertes();
  }

  void _showUpdateLocationSheet(Map<String, dynamic> alerte) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UpdateLocationSheet(
        alerteId: alerte['id'] as String,
        nomAnimal: alerte['nom_animal'] as String? ?? 'Animal',
        espece: alerte['espece'] as String?,
        proprietaireUid: alerte['uid_proprietaire'] as String? ?? User_Info.uid,
        onSaved: () { Navigator.pop(context); _fetchAlertes(); },
      ),
    );
  }

  void _nouvelleAlerte() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))
        .then((_) => _fetchAlertes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: const Text('Mes animaux perdus',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _orange,
        child: const Icon(Icons.add_location_alt, color: Colors.white),
        onPressed: _nouvelleAlerte,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _alertes.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _fetchAlertes,
                  color: _teal,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _alertes.length,
                    itemBuilder: (_, i) => _AlerteCard(
                      data: _alertes[i],
                      onRetrouve:      () => _retrouveAlerte(_alertes[i]['id']),
                      onDelete:        () => _deleteAlerte(_alertes[i]['id']),
                      onEdit:          () => _editAlerte(_alertes[i]),
                      onUpdateLocation:() => _showUpdateLocationSheet(_alertes[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.location_searching, size: 64, color: Colors.orange.shade200),
      const SizedBox(height: 16),
      const Text('Aucune alerte active',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      const SizedBox(height: 6),
      Text('Déclarez un animal perdu via sa fiche\nou le bouton +',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500, fontSize: 13)),
    ]),
  );
}

// ── Alerte card ───────────────────────────────────────────────────────────────

class _AlerteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onRetrouve;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onUpdateLocation;

  const _AlerteCard({
    required this.data,
    required this.onRetrouve,
    required this.onDelete,
    required this.onEdit,
    required this.onUpdateLocation,
  });

  @override
  Widget build(BuildContext context) {
    final nom      = data['nom_animal'] as String? ?? 'Animal inconnu';
    final espece   = data['espece'] as String?;
    final sexe     = data['sexe'] as String?;
    final loc      = data['derniere_localisation'] as String?;
    final statut   = data['statut'] as String? ?? 'perdu';
    final photoUrl = data['photo_url'] as String?;
    final numero   = data['numero_alerte'] as String?;
    final retrouve = statut == 'retrouve';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade300, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: photoUrl, width: 56, height: 56, fit: BoxFit.cover)
                : Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                        color: retrouve ? const Color(0xFFEEF5EA) : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(50)),
                    child: Icon(Icons.pets,
                        color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade700, size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: retrouve ? const Color(0xFFEEF5EA) : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(retrouve ? 'Retrouvé' : 'Perdu',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: retrouve ? const Color(0xFF6E9E57) : Colors.orange.shade700)),
                ),
              ]),
              if (espece != null || sexe != null)
                Text(
                  [if (espece != null) _capitalize(espece),
                   if (sexe != null && sexe.isNotEmpty) _capitalize(sexe)].join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                ),
              if (loc != null && loc.isNotEmpty)
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 12, color: Colors.orange.shade600),
                  const SizedBox(width: 3),
                  Expanded(child: Text(loc,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              if (numero != null && numero.isNotEmpty)
                Text('N° $numero',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        color: Colors.orange.shade400, fontWeight: FontWeight.w600)),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
            onSelected: (v) {
              if (v == 'retrouve') onRetrouve();
              if (v == 'edit') onEdit();
              if (v == 'location') onUpdateLocation();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',
                child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0C5C6C)),
                    SizedBox(width: 8), Text('Modifier l\'alerte', style: TextStyle(fontFamily: 'Galey'))])),
              const PopupMenuItem(value: 'location',
                child: Row(children: [Icon(Icons.my_location, size: 18, color: Color(0xFFE65100)),
                    SizedBox(width: 8), Text('Mettre à jour le lieu', style: TextStyle(fontFamily: 'Galey'))])),
              if (!retrouve)
                const PopupMenuItem(value: 'retrouve',
                  child: Row(children: [Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57), size: 18),
                      SizedBox(width: 8), Text('Marquer retrouvé', style: TextStyle(fontFamily: 'Galey'))])),
              const PopupMenuItem(value: 'delete',
                child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8), Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))])),
            ],
          ),
        ]),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Update location bottom sheet ──────────────────────────────────────────────

class _UpdateLocationSheet extends StatefulWidget {
  final String alerteId;
  final String nomAnimal;
  final String? espece;
  final String proprietaireUid;
  final VoidCallback onSaved;

  const _UpdateLocationSheet({
    required this.alerteId,
    required this.nomAnimal,
    required this.proprietaireUid,
    this.espece,
    required this.onSaved,
  });

  @override
  State<_UpdateLocationSheet> createState() => _UpdateLocationSheetState();
}

class _UpdateLocationSheetState extends State<_UpdateLocationSheet> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;
  Timer? _debounce;

  final _searchCtrl = TextEditingController();
  final _rueCtrl    = TextEditingController();
  final _cpCtrl     = TextEditingController();
  final _villeCtrl  = TextEditingController();

  List<Prediction> _predictions = [];
  bool _loadingPredictions = false;
  bool _locating = false;
  bool _saving = false;
  double? _lat, _lng;

  static const _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _places.dispose();
    _searchCtrl.dispose(); _rueCtrl.dispose();
    _cpCtrl.dispose(); _villeCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _lat = null; _lng = null;
    _debounce?.cancel();
    if (val.trim().length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    try {
      final res = await _places.autocomplete(input,
          components: [Component(Component.country, 'fr'), Component(Component.country, 'be'),
                       Component(Component.country, 'ch'), Component(Component.country, 'lu')],
          language: 'fr');
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPredictions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPredictions = false);
    }
  }

  Future<void> _selectPrediction(Prediction p) async {
    setState(() { _predictions = []; _searchCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    try {
      final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
      if (!mounted || !det.isOkay) return;
      String num = '', route = '', cp = '', ville = '';
      for (final c in det.result.addressComponents) {
        if (c.types.contains('street_number')) num   = c.longName;
        if (c.types.contains('route'))         route = c.longName;
        if (c.types.contains('postal_code'))   cp    = c.longName;
        if (c.types.contains('locality') ||
            c.types.contains('administrative_area_level_2')) ville = c.longName;
      }
      final loc = det.result.geometry?.location;
      setState(() {
        _rueCtrl.text   = [num, route].where((s) => s.isNotEmpty).join(' ');
        _cpCtrl.text    = cp;
        _villeCtrl.text = ville;
        if (loc != null) { _lat = loc.lat; _lng = loc.lng; }
      });
    } catch (_) {}
  }

  Future<void> _geolocate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _lat = pos.latitude; _lng = pos.longitude;
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return;
      final m = marks.first;
      setState(() {
        _rueCtrl.text   = m.street ?? '';
        _cpCtrl.text    = m.postalCode ?? '';
        _villeCtrl.text = m.locality ?? m.subAdministrativeArea ?? '';
        _searchCtrl.text = [_rueCtrl.text, _cpCtrl.text, _villeCtrl.text].where((s) => s.isNotEmpty).join(', ');
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final localisation = [_rueCtrl.text.trim(), _cpCtrl.text.trim(), _villeCtrl.text.trim()]
        .where((s) => s.isNotEmpty).join(', ');
    if (localisation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez saisir une localisation')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _supa.from('alertes_perdus').update({
        'derniere_localisation': localisation,
        'lat': _lat,
        'lng': _lng,
      }).eq('id', widget.alerteId);
      if (_lat != null && _lng != null) {
        notifyNearbyUsersAboutLostAnimal(
          lat: _lat!,
          lng: _lng!,
          nomAnimal: widget.nomAnimal,
          espece: widget.espece,
          alerteId: widget.alerteId,
          proprietaireUid: widget.proprietaireUid,
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _locField(TextEditingController c, String label, {bool num = false}) =>
      TextField(
        controller: c,
        keyboardType: num ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Mettre à jour la localisation',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: TextField(
              controller: _searchCtrl, onChanged: _onChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une adresse…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: (_loadingPredictions || _locating)
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
                    : IconButton(icon: const Icon(Icons.my_location, size: 18, color: _orange),
                        onPressed: _geolocate),
              ),
            ),
          ),
          if (_predictions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8,
                      offset: const Offset(0, 4))]),
              child: Column(children: _predictions.take(5).map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                onTap: () => _selectPrediction(p),
              )).toList()),
            ),
          const SizedBox(height: 10),
          _locField(_rueCtrl, 'Rue / Voie'),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: _locField(_cpCtrl, 'Code postal', num: true)),
            const SizedBox(width: 8),
            Expanded(child: _locField(_villeCtrl, 'Ville')),
          ]),
          if (_lat != null)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.check_circle, size: 13, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('GPS enregistré',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.green.shade600)),
              ])),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey')),
            ),
          ),
        ]),
      ),
    );
  }
}
