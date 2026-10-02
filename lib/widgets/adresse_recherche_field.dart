import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:PetsMatch/main.dart' show getApiKey;

/// Adresse trouvée via Google Maps (Places) : de quoi remplir rue / CP /
/// ville et géolocaliser.
class AdresseTrouvee {
  final String rue, codePostal, ville, pays, formatee;
  final double? lat, lng;
  const AdresseTrouvee({required this.rue, required this.codePostal, required this.ville,
      required this.pays, required this.formatee, this.lat, this.lng});
}

/// Champ « Rechercher l'adresse » avec suggestions Google Maps — même logique
/// que le profil élevage (info_elevage.dart), réutilisable. [onSelection]
/// reçoit l'adresse choisie ; les champs Rue / CP / Ville restent modifiables
/// par l'écran appelant.
class AdresseRechercheField extends StatefulWidget {
  final ValueChanged<AdresseTrouvee> onSelection;
  final String label;
  const AdresseRechercheField({super.key, required this.onSelection, this.label = 'Rechercher l\'adresse (Google Maps)'});

  @override
  State<AdresseRechercheField> createState() => _AdresseRechercheFieldState();
}

class _AdresseRechercheFieldState extends State<AdresseRechercheField> {
  final _ctrl = TextEditingController();
  final _places = GoogleMapsPlaces(apiKey: getApiKey());
  Timer? _debounce;
  List<Prediction> _suggestions = [];
  bool _chargement = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _places.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await _places.autocomplete(text, language: 'fr',
          components: [Component(Component.country, 'fr')]);
      if (!mounted) return;
      setState(() => _suggestions = r.isOkay ? r.predictions : []);
    });
  }

  Future<void> _choisir(Prediction p) async {
    if (p.placeId == null) return;
    setState(() => _chargement = true);
    final det = await _places.getDetailsByPlaceId(p.placeId!, language: 'fr');
    if (!mounted) return;
    setState(() => _chargement = false);
    if (!det.isOkay) return;
    String num = '', route = '', cp = '', ville = '', pays = '', lieuDit = '';
    for (final c in det.result.addressComponents) {
      if (c.types.contains('street_number')) num = c.longName;
      if (c.types.contains('route')) route = c.longName;
      if (c.types.contains('postal_code')) cp = c.longName;
      if (c.types.contains('locality')) ville = c.longName;
      if (c.types.contains('country')) pays = c.longName;
      // Lieu-dit (adresses rurales sans numéro ni voie chez Google).
      if (lieuDit.isEmpty && (c.types.contains('sublocality') || c.types.contains('neighborhood') ||
          c.types.contains('administrative_area_level_3'))) {
        lieuDit = c.longName;
      }
    }
    final rue = [num, route].where((s) => s.isNotEmpty).join(' ');
    final loc = det.result.geometry?.location;
    final formatee = det.result.formattedAddress ?? p.description ?? '';
    setState(() {
      _ctrl.text = formatee;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
    widget.onSelection(AdresseTrouvee(
      rue: rue.isNotEmpty ? rue : lieuDit, codePostal: cp, ville: ville,
      pays: pays.isNotEmpty ? pays : 'France', formatee: formatee, lat: loc?.lat, lng: loc?.lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        onChanged: _onChanged,
        style: const TextStyle(fontFamily: 'Galey'),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'Tapez l\'adresse, puis choisissez-la dans la liste',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _chargement
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      if (_suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
          ),
          child: Column(children: [
            for (final p in _suggestions.take(5))
              ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, size: 20),
                title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                onTap: () => _choisir(p),
              ),
          ]),
        ),
    ]);
  }
}
