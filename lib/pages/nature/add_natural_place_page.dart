import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

const _catEmoji = {
  'foret': '🌲', 'plage': '🏖️', 'parc': '🌿', 'lac': '💧', 'riviere': '🏞️',
};
const _catLabel = {
  'foret': 'Forêt', 'plage': 'Plage', 'parc': 'Parc', 'lac': 'Lac', 'riviere': 'Rivière',
};

class AddNaturalPlacePage extends StatefulWidget {
  const AddNaturalPlacePage({super.key});

  @override
  State<AddNaturalPlacePage> createState() => _AddNaturalPlacePageState();
}

class _AddNaturalPlacePageState extends State<AddNaturalPlacePage> {
  final _supa = Supabase.instance.client;
  final _nomCtrl      = TextEditingController();
  final _adresseCtrl  = TextEditingController();
  final _descCtrl     = TextEditingController();

  String _categorie = 'plage';
  LatLng _position   = const LatLng(46.603354, 1.888334);
  bool _positionSet  = false;
  File? _photo;
  bool _saving       = false;
  bool _locating     = true;
  bool _geocoding    = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _fetchInitialPosition();
    _adresseCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _adresseCtrl.removeListener(_onAddressChanged);
    _nomCtrl.dispose();
    _adresseCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    _addressDebounce?.cancel();
    final val = _adresseCtrl.text.trim();
    if (val.length < 4) return;
    _addressDebounce = Timer(const Duration(milliseconds: 700), () => _geocodeAddress(val));
  }

  Future<void> _geocodeAddress(String address) async {
    setState(() => _geocoding = true);
    try {
      final uri = Uri.https('api-adresse.data.gouv.fr', '/search/', {'q': address, 'limit': '1'});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final feats = data['features'] as List?;
        if (feats != null && feats.isNotEmpty) {
          final coords = (feats.first['geometry']['coordinates'] as List);
          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          if (mounted) {
            setState(() {
              _position    = LatLng(lat, lng);
              _positionSet = true;
            });
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _fetchInitialPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) {
        setState(() {
          _position    = LatLng(pos.latitude, pos.longitude);
          _positionSet = true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await pickAndCropBanner();
    if (file != null && mounted) setState(() => _photo = file);
  }

  Future<void> _submit() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Le nom du lieu est obligatoire', style: TextStyle(fontFamily: 'Galey')),
      ));
      return;
    }
    if (!_positionSet) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Place le repère sur la carte à l\'emplacement du lieu',
            style: TextStyle(fontFamily: 'Galey')),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      List<String> photos = [];
      if (_photo != null) {
        final path = 'natural_places/${DateTime.now().millisecondsSinceEpoch}_${User_Info.uid}.jpg';
        final url = await uploadPhoto(_photo!, path);
        photos = [url];
      }

      await _supa.from('natural_places').insert({
        'nom':                     nom,
        'categorie':               _categorie,
        'lat':                     _position.latitude,
        'lng':                     _position.longitude,
        'adresse':                 _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'description':             _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'photos':                  photos,
        'photo_url':               photos.isNotEmpty ? photos.first : null,
        'statut':                  'en_attente',
        'submitted_by_uid':        User_Info.uid,
        'submitted_by_profile_id': User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Merci ! Ton lieu sera visible après validation par un admin (sous 48h).',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      debugPrint('[AddNaturalPlace] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors de l\'envoi, réessaie.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Proposer un lieu',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: _teal, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ton lieu sera vérifié par un administrateur avant d\'apparaître pour tout le monde.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          _Label('Nom du lieu *'),
          const SizedBox(height: 6),
          _TextInput(controller: _nomCtrl, hint: 'Ex: Plage du Grand Travers'),
          const SizedBox(height: 16),

          _Label('Catégorie *'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _catLabel.entries.map((e) {
            final active = _categorie == e.key;
            return GestureDetector(
              onTap: () => setState(() => _categorie = e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _teal : Colors.white,
                  border: Border.all(color: active ? _teal : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_catEmoji[e.key]} ${e.value}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.black87)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),

          Row(children: [
            _Label('Adresse / ville'),
            if (_geocoding) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _teal)),
            ],
          ]),
          const SizedBox(height: 6),
          _TextInput(controller: _adresseCtrl, hint: 'Ex: Carnon, Hérault'),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('La carte se positionne automatiquement sur l\'adresse tapée',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
          ),
          const SizedBox(height: 16),

          _Label('Description'),
          const SizedBox(height: 6),
          _TextInput(controller: _descCtrl, hint: 'Règles chiens, accès, équipements...', maxLines: 4),
          const SizedBox(height: 16),

          _Label('Photo'),
          const SizedBox(height: 8),
          _PhotoPicker(photo: _photo, onTap: _pickPhoto, onClear: () => setState(() => _photo = null)),
          const SizedBox(height: 16),

          _Label('Position sur la carte *'),
          const SizedBox(height: 6),
          const Text('Déplace le repère à l\'endroit exact du lieu',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          _locating
              ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: _teal)))
              : _MapPicker(
                  position: _position,
                  onChanged: (p) => setState(() { _position = p; _positionSet = true; }),
                ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Envoyer pour validation',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPicker extends StatelessWidget {
  final LatLng position;
  final void Function(LatLng) onChanged;
  const _MapPicker({required this.position, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: 13),
          onTap: onChanged,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
          markers: {
            Marker(
              markerId: const MarkerId('picked'),
              position: position,
              draggable: true,
              onDragEnd: onChanged,
            ),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final File? photo;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _PhotoPicker({required this.photo, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    if (photo == null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Ajouter une photo (optionnel)',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ),
      );
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(photo!, height: 160, width: double.infinity, fit: BoxFit.cover),
      ),
      Positioned(
        top: 8, right: 8,
        child: GestureDetector(
          onTap: onClear,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          ),
        ),
      ),
    ]);
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14));
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _TextInput({required this.controller, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: maxLines,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
      contentPadding: const EdgeInsets.all(12),
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal)),
    ),
  );
}
