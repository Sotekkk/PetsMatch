import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _blue = Color(0xFF1E88E5);

const _kCategories = [
  'Randonnée / Parc',
  'Restaurant / Bar',
  'Hôtel / Hébergement',
  'Boutique',
  'Autre',
];

class FriendlyMapPage extends StatefulWidget {
  final String filterCategory;
  const FriendlyMapPage({super.key, this.filterCategory = ''});

  @override
  State<FriendlyMapPage> createState() => _FriendlyMapPageState();
}

class _FriendlyMapPageState extends State<FriendlyMapPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _lieux = [];
  bool _loading = true;
  bool _showMap = false;
  GoogleMapController? _mapCtrl;
  LatLng? _userPos;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadLieux();
    _locateUser();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _locateUser() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPos = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  Future<void> _loadLieux() async {
    setState(() => _loading = true);
    try {
      final data = await (widget.filterCategory.isNotEmpty
          ? _supa
              .from('animal_friendly_lieux')
              .select()
              .eq('categorie', widget.filterCategory)
              .order('created_at', ascending: false)
          : _supa
              .from('animal_friendly_lieux')
              .select()
              .order('created_at', ascending: false));
      final list = List<Map<String, dynamic>>.from(data);

      final markers = <Marker>{};
      for (final lieu in list) {
        final lat = (lieu['latitude'] as num?)?.toDouble();
        final lng = (lieu['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          markers.add(Marker(
            markerId: MarkerId(lieu['id'].toString()),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: lieu['nom']?.toString() ?? '',
              snippet: lieu['categorie']?.toString() ?? '',
            ),
          ));
        }
      }

      if (mounted) {
        setState(() {
          _lieux = list;
          _markers = markers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddForm() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddLieuSheet(),
    );
    if (added == true) _loadLieux();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.filterCategory.isNotEmpty ? widget.filterCategory : 'Animal Friendly';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list_rounded : Icons.map_outlined,
                color: Colors.white),
            onPressed: () => setState(() => _showMap = !_showMap),
            tooltip: _showMap ? 'Vue liste' : 'Vue carte',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _blue,
        onPressed: _openAddForm,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : _showMap
              ? _buildMap()
              : _buildList(),
    );
  }

  Widget _buildMap() {
    final center = _userPos ?? const LatLng(46.6034, 1.8883);
    return GoogleMap(
      initialCameraPosition:
          CameraPosition(target: center, zoom: _userPos != null ? 12 : 5),
      markers: _markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      onMapCreated: (c) => _mapCtrl = c,
    );
  }

  Widget _buildList() {
    if (_lieux.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_on_outlined, size: 72, color: _blue),
          const SizedBox(height: 16),
          Text(
            widget.filterCategory.isNotEmpty
                ? 'Aucun lieu "${widget.filterCategory}"'
                : 'Aucun lieu Animal Friendly',
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('Soyez le premier à en ajouter un !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLieux,
      color: _blue,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _lieux.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _LieuCard(lieu: _lieux[i]),
      ),
    );
  }
}

// ─── Lieu Card ────────────────────────────────────────────────────────────────

class _LieuCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  const _LieuCard({required this.lieu});

  @override
  Widget build(BuildContext context) {
    final nom = lieu['nom']?.toString() ?? '';
    final cat = lieu['categorie']?.toString() ?? '';
    final desc = lieu['description']?.toString() ?? '';
    final ville = lieu['ville']?.toString() ?? '';
    final adresse = lieu['adresse']?.toString() ?? '';
    final localisation = [adresse, ville].where((s) => s.isNotEmpty).join(', ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(nom,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1E2025))),
            ),
            if (cat.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cat,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: _blue,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          if (localisation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(localisation,
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }
}

// ─── Sheet ajout ─────────────────────────────────────────────────────────────

class _AddLieuSheet extends StatefulWidget {
  const _AddLieuSheet();

  @override
  State<_AddLieuSheet> createState() => _AddLieuSheetState();
}

class _AddLieuSheetState extends State<_AddLieuSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;

  String _nom = '';
  String _categorie = _kCategories.first;
  String _adresse = '';
  String _ville = '';
  String _description = '';
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await _supa.from('animal_friendly_lieux').insert({
        'nom': _nom,
        'categorie': _categorie,
        'adresse': _adresse,
        'ville': _ville,
        'description': _description,
        'ajout_par_uid': FirebaseAuth.instance.currentUser?.uid,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                    child: Text('Ajouter un lieu',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 18)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
                const SizedBox(height: 20),

                _lbl('Nom du lieu *'),
                TextFormField(
                  decoration: _dec('Ex : Parc de la Tête d\'Or'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _nom = v?.trim() ?? '',
                ),
                const SizedBox(height: 14),

                _lbl('Catégorie *'),
                InputDecorator(
                  decoration: _dec(''),
                  child: DropdownButton<String>(
                    value: _categorie,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _kCategories
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c,
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 14))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _categorie = v ?? _kCategories.first),
                  ),
                ),
                const SizedBox(height: 14),

                _lbl('Adresse'),
                TextFormField(
                  decoration: _dec('Rue, numéro'),
                  onSaved: (v) => _adresse = v?.trim() ?? '',
                ),
                const SizedBox(height: 14),

                _lbl('Ville'),
                TextFormField(
                  decoration: _dec('Ex : Lyon'),
                  onSaved: (v) => _ville = v?.trim() ?? '',
                ),
                const SizedBox(height: 14),

                _lbl('Description'),
                TextFormField(
                  decoration: _dec('Quelques mots sur ce lieu…'),
                  maxLines: 3,
                  onSaved: (v) => _description = v?.trim() ?? '',
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Ajouter ce lieu',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _blue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
