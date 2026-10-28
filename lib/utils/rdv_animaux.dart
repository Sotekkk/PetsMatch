import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// RDV à plusieurs animaux (vétérinaire, ostéo, toiletteur, éducateur) :
// rdv.animaux_detail = [{ id, nom, motif, motif_cle, duree_minutes, prestation_id?, prix? }]
// (migration_rdv_animaux_detail.sql). rdv.animal_id = le premier animal,
// rdv.duree_minutes = la somme des durées. Miroir site : lib/rdv-animaux.ts.

/// Détail par animal — vide pour un RDV à un seul animal.
List<Map<String, dynamic>> animauxDetailRdv(Map<String, dynamic> rdv) {
  final d = rdv['animaux_detail'];
  if (d is! List || d.length < 2) return const [];
  return [for (final x in d) if (x is Map) Map<String, dynamic>.from(x)];
}

String dureeRdvLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
}

/// « Rex — Consultation · 30 min »
String ligneAnimalRdv(Map<String, dynamic> a) {
  final duree = (a['duree_minutes'] as num?)?.toInt();
  return [
    a['nom']?.toString() ?? '',
    [a['motif']?.toString() ?? '', if (duree != null) dureeRdvLabel(duree)].where((s) => s.isNotEmpty).join(' · '),
  ].where((s) => s.isNotEmpty).join(' — ');
}

/// RDV à plusieurs animaux : choix de l'animal dont on rédige le compte rendu
/// (ou la séance), avec l'état de chacun — fait / brouillon / à faire —
/// d'après [table] (comptes_rendus, suivis_morpho) liée au RDV par rdv_id ;
/// sans [table] (ouvrir une fiche), pas d'état. Renvoie { id, nom, espece } ou null.
Future<Map<String, dynamic>?> choisirAnimalRdv(BuildContext context, Map<String, dynamic> rdv,
    {String? table, required Color color, String titre = 'Compte rendu de quel animal ?'}) async {
  final detail = animauxDetailRdv(rdv);
  if (detail.isEmpty) return null;
  final supa = Supabase.instance.client;
  final ids = detail.map((a) => a['id'].toString()).toList();
  final etats = <String, String>{};
  final especes = <String, String>{};
  if (table != null) try {
    final rows = await supa.from(table).select(table == 'comptes_rendus' ? 'animal_id, statut' : 'animal_id')
        .eq('rdv_id', rdv['id'].toString());
    for (final r in rows as List) {
      final id = r['animal_id']?.toString() ?? '';
      if (etats[id] != 'fait') etats[id] = r['statut'] == 'brouillon' ? 'brouillon' : 'fait';
    }
  } catch (_) {}
  try {
    final rows = await supa.from('animaux').select('id, espece').inFilter('id', ids);
    for (final r in rows as List) {
      especes[r['id'].toString()] = r['espece']?.toString() ?? '';
    }
  } catch (_) {}
  if (!context.mounted) return null;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      for (final a in detail)
        () {
          final id = a['id'].toString();
          final etat = etats[id];
          final (lib, fg) = switch (etat) {
            'fait' => ('Fait', const Color(0xFF2E7D32)),
            'brouillon' => ('Brouillon', const Color(0xFF8A5A00)),
            _ => ('À faire', Colors.grey.shade600),
          };
          return ListTile(
            leading: Icon(etat == 'fait' && table != null ? Icons.check_circle : Icons.pets, color: etat == 'fait' ? fg : color),
            title: Text(a['nom']?.toString() ?? '—', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: (a['motif']?.toString() ?? '').isEmpty ? null
                : Text(a['motif'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
            trailing: table == null ? null : Text(lib, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            onTap: () => Navigator.pop(ctx, {'id': id, 'nom': a['nom'], 'espece': especes[id] ?? ''}),
          );
        }(),
      const SizedBox(height: 8),
    ])),
  );
}
