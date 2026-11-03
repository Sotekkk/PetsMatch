// Trame dentaire du compte rendu opératoire (détartrage, extractions) :
// dents en numérotation de Triadan (chien / chat), actes cochés ; le résultat
// est une ligne « Soins dentaires : … » des gestes réalisés, remplacée à
// chaque passage. Miroir site : website/src/lib/trame-dentaire.ts.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal = Color(0xFF0C5C6C);
const kActesDentaires = ['Détartrage ultrasonique', 'Polissage', 'Sondage parodontal', 'Radiographies dentaires'];
const _prefixe = 'Soins dentaires :';
const kQuadrants = [(1, 'Maxillaire droit (100)'), (2, 'Maxillaire gauche (200)'), (4, 'Mandibule droite (400)'), (3, 'Mandibule gauche (300)')];

Map<int, List<int>> dentsTriadan(bool chat) {
  List<int> seq(int q, List<int> n) => [for (final x in n) q * 100 + x];
  if (chat) {
    const haut = [1, 2, 3, 4, 6, 7, 8, 9], bas = [1, 2, 3, 4, 7, 8, 9];
    return {1: seq(1, haut), 2: seq(2, haut), 3: seq(3, bas), 4: seq(4, bas)};
  }
  final haut = [for (var i = 1; i <= 10; i++) i], bas = [for (var i = 1; i <= 11; i++) i];
  return {1: seq(1, haut), 2: seq(2, haut), 3: seq(3, bas), 4: seq(4, bas)};
}

String ligneDentaire(List<String> actes, List<int> extractions) {
  final parts = <String>[];
  if (actes.isNotEmpty) {
    parts.add('${[for (var i = 0; i < actes.length; i++) i == 0 ? actes[i] : actes[i].toLowerCase()].join(', ')}.');
  }
  if (extractions.isNotEmpty) {
    final t = [...extractions]..sort();
    parts.add('Extractions (numérotation de Triadan) : ${t.join(', ')}.');
  }
  return parts.isEmpty ? '' : '$_prefixe ${parts.join(' ')}';
}

({List<String> actes, List<int> extractions}) lireLigneDentaire(String texte) {
  final l = texte.split('\n').firstWhere((x) => x.trim().startsWith(_prefixe), orElse: () => '');
  final m = RegExp(r'Extractions[^:]*:\s*([\d,\s]+)').firstMatch(l);
  return (
    actes: [for (final a in kActesDentaires) if (l.toLowerCase().contains(a.toLowerCase())) a],
    extractions: m == null ? <int>[] : [for (final x in m.group(1)!.split(',')) if (int.tryParse(x.trim()) != null) int.parse(x.trim())],
  );
}

String avecLigneDentaire(String texte, String ligne) {
  final autres = texte.split('\n').where((x) => !x.trim().startsWith(_prefixe));
  return [if (ligne.isNotEmpty) ligne, ...autres].join('\n').trim();
}

/// Ouvre le schéma ; renvoie la ligne à reporter (null si annulé).
Future<String?> ouvrirTrameDentaire(BuildContext context, {required String gestes, String? animalId}) async {
  var chat = false;
  if (animalId != null && animalId.isNotEmpty) {
    try {
      final a = await Supabase.instance.client.from('animaux').select('espece').eq('id', animalId).maybeSingle();
      chat = RegExp('chat', caseSensitive: false).hasMatch(a?['espece']?.toString() ?? '');
    } catch (_) {}
  }
  final depart = lireLigneDentaire(gestes);
  final actes = depart.actes.isNotEmpty || depart.extractions.isNotEmpty ? [...depart.actes] : ['Détartrage ultrasonique', 'Polissage'];
  final ext = [...depart.extractions];
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
      final dents = dentsTriadan(chat);
      final toutes = dents.values.expand((x) => x).toSet();
      final apercu = ligneDentaire(actes, ext.where(toutes.contains).toList());
      return SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Schéma dentaire', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700))),
            for (final (c, l) in const [(false, 'Chien'), (true, 'Chat')])
              Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
                label: Text(l, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: chat == c ? Colors.white : Colors.black87)),
                selected: chat == c, selectedColor: _teal, showCheckmark: false, onSelected: (_) => setM(() => chat = c))),
          ]),
          const SizedBox(height: 10),
          const Text('Actes', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
          Wrap(spacing: 6, children: [
            for (final a in kActesDentaires)
              FilterChip(label: Text(a, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)), selected: actes.contains(a),
                  selectedColor: _teal.withValues(alpha: 0.15), checkmarkColor: _teal,
                  onSelected: (v) => setM(() => v ? actes.add(a) : actes.remove(a))),
          ]),
          const SizedBox(height: 10),
          const Text('Dents extraites (touchez une dent)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
          for (final (q, label) in kQuadrants) ...[
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final n in dents[q]!)
                GestureDetector(
                  onTap: () => setM(() => ext.contains(n) ? ext.remove(n) : ext.add(n)),
                  child: Container(
                    width: 42, padding: const EdgeInsets.symmetric(vertical: 6), alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ext.contains(n) ? const Color(0xFFB91C1C) : Colors.white,
                      border: Border.all(color: ext.contains(n) ? const Color(0xFFB91C1C) : const Color(0xFFD1D5DB)),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('$n', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                        color: ext.contains(n) ? Colors.white : const Color(0xFF1F2A2E))),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF1F7F8), borderRadius: BorderRadius.circular(10)),
            child: Text(apercu.isEmpty ? 'Aucun soin dentaire sélectionné.' : apercu, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, apercu),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Reporter dans les gestes réalisés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      ));
    }),
  );
}
