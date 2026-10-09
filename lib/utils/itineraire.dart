// Itinéraire vers une adresse d'intervention : choix de l'application de
// navigation (Google Maps, Waze, Plans sur iPhone, ou toute appli GPS
// installée via le sélecteur Android « geo: »). Miroir site :
// website/src/components/dashboard/ItineraireMenu.tsx.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> ouvrirItineraire(BuildContext context, {double? lat, double? lng, String? adresse}) async {
  final a = adresse?.trim() ?? '';
  final coords = lat != null && lng != null;
  if (!coords && a.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adresse d\'intervention non renseignée.', style: TextStyle(fontFamily: 'Galey'))));
    return;
  }
  final dest = coords ? '$lat,$lng' : Uri.encodeComponent(a);
  final options = <(IconData, String, Uri)>[
    (Icons.map_outlined, 'Google Maps', Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest')),
    (Icons.navigation_outlined, 'Waze',
        Uri.parse(coords ? 'https://waze.com/ul?ll=$dest&navigate=yes' : 'https://waze.com/ul?q=$dest&navigate=yes')),
    if (Platform.isIOS)
      (Icons.explore_outlined, 'Plans', Uri.parse('https://maps.apple.com/?daddr=$dest')),
    if (Platform.isAndroid)
      // Le système propose toutes les applis GPS installées.
      (Icons.apps_outlined, 'Autre application GPS',
          Uri.parse(coords ? 'geo:$dest?q=$dest' : 'geo:0,0?q=$dest')),
  ];
  final choix = await showModalBottomSheet<Uri>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(alignment: Alignment.centerLeft,
              child: Text('Ouvrir l\'itinéraire avec', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700))),
        ),
        if (a.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
                child: Text(a, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600))),
          ),
        for (final o in options)
          ListTile(
            leading: Icon(o.$1, color: const Color(0xFF0C5C6C)),
            title: Text(o.$2, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, o.$3),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choix == null) return;
  var ok = false;
  try {
    ok = await launchUrl(choix, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible d\'ouvrir cette application.', style: TextStyle(fontFamily: 'Galey'))));
  }
}
