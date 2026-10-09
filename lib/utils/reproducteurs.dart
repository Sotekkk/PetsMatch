// Reproducteurs éligibles à une NOUVELLE saillie / portée.
// Miroir site : website/src/lib/reproducteurs.ts — garder les deux synchronisés.
// Contrôle serveur : supabase/migration_saillies_reproducteurs_eligibles.sql.
//
// Règle : sexe demandé + case « Reproducteur » cochée sur la fiche + présent
// dans le cheptel (non cédé, non décédé, pas en cours de cession) + ni
// retraité, ni stérilisé. Le statut commercial (réservé…) n'entre pas en jeu.
// Les historiques (saillies passées) gardent leurs reproducteurs tels quels.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kStatutsHorsCheptel = {
  'sorti', 'decede', 'en_attente_cession', 'cession_en_cours', 'adopte', 'transfere',
};

bool estReproducteurEligible(Map<String, dynamic> a) =>
    a['reproducteur'] == true &&
    a['is_retraite'] != true &&
    a['sterilise'] != true &&
    !kStatutsHorsCheptel.contains((a['statut'] ?? '').toString());

/// Raison lisible de l'inéligibilité (null si éligible).
String? raisonNonEligible(Map<String, dynamic> a) {
  final statut = (a['statut'] ?? '').toString();
  if (statut == 'decede') return 'animal décédé';
  if (kStatutsHorsCheptel.contains(statut)) return 'animal cédé ou en cours de cession';
  if (a['is_retraite'] == true) return 'reproducteur retraité';
  if (a['sterilise'] == true) return 'animal stérilisé';
  if (a['reproducteur'] != true) return 'case « Reproducteur » non cochée sur la fiche';
  return null;
}

class Reproducteur {
  final String? id;            // id de la fiche (null pour un étalon extérieur saisi)
  final String nom;
  final String? race;
  final String? identification;
  final String source;         // 'elevage' | 'historique' | 'reseau'
  final String? elevage;
  const Reproducteur({this.id, required this.nom, this.race, this.identification,
      required this.source, this.elevage});

  String get detail => [race, identification, elevage].where((v) => v != null && v.isNotEmpty).join(' · ');
}

const _selectRepro = 'id, nom, nom_pedigree, race, identification, statut, reproducteur, is_retraite, sterilise, uid_eleveur';

/// Reproducteurs actifs de l'élevage (filtrés à la source, puis règle complète).
Future<List<Reproducteur>> chargerReproducteurs({
  required String uidEleveur,
  required String sexe,
  String? espece,
  String? exclureId,
}) async {
  var q = Supabase.instance.client.from('animaux').select(_selectRepro)
      .eq('uid_eleveur', uidEleveur).eq('sexe', sexe).eq('reproducteur', true);
  if (espece != null && espece.isNotEmpty) q = q.eq('espece', espece);
  final rows = List<Map<String, dynamic>>.from(await q.order('nom'));
  return rows
      .where((a) => a['id'] != exclureId && estReproducteurEligible(a))
      .map((a) => Reproducteur(
            id: a['id'] as String?,
            nom: ((a['nom'] as String?)?.isNotEmpty == true ? a['nom'] : a['nom_pedigree'] ?? 'Sans nom').toString(),
            race: a['race'] as String?, identification: a['identification'] as String?,
            source: 'elevage'))
      .toList();
}

/// Reproducteurs extérieurs déjà enregistrés : partenaires extérieurs de vos
/// saillies passées + reproducteurs publiés par d'autres élevages PetsMatch.
/// Ils ne sont jamais ajoutés au cheptel.
Future<List<Reproducteur>> chargerReproducteursExterieurs({
  required String uidEleveur,
  required String sexe,
  String? espece,
}) async {
  final supa = Supabase.instance.client;
  final out = <Reproducteur>[];
  final vus = <String>{};
  try {
    // Mes animaux du sexe opposé → leurs saillies avec un partenaire hors élevage
    var qa = supa.from('animaux').select('id').eq('uid_eleveur', uidEleveur).neq('sexe', sexe);
    if (espece != null && espece.isNotEmpty) qa = qa.eq('espece', espece);
    final ids = List<Map<String, dynamic>>.from(await qa).map((r) => r['id'] as String).toList();
    if (ids.isNotEmpty) {
      final sa = await supa.from('saillies').select('nom_partenaire, ident_partenaire')
          .inFilter('animal_id', ids).isFilter('partenaire_animal_id', null).order('date', ascending: false);
      for (final s in List<Map<String, dynamic>>.from(sa)) {
        final nom = (s['nom_partenaire'] ?? '').toString().trim();
        if (nom.isEmpty) continue;
        final ident = (s['ident_partenaire'] ?? '').toString().trim();
        if (!vus.add('${nom.toLowerCase()}|$ident')) continue;
        out.add(Reproducteur(nom: nom, identification: ident.isEmpty ? null : ident, source: 'historique'));
      }
    }
  } catch (_) {}
  try {
    var qr = supa.from('animaux').select(_selectRepro)
        .eq('reproducteur_public', true).eq('sexe', sexe).neq('uid_eleveur', uidEleveur);
    if (espece != null && espece.isNotEmpty) qr = qr.eq('espece', espece);
    for (final a in List<Map<String, dynamic>>.from(await qr.limit(80))) {
      if (!estReproducteurEligible(a)) continue;
      final nom = ((a['nom_pedigree'] as String?)?.isNotEmpty == true ? a['nom_pedigree'] : a['nom'] ?? '').toString();
      final ident = (a['identification'] ?? '').toString();
      if (nom.isEmpty || !vus.add('${nom.toLowerCase()}|$ident')) continue;
      out.add(Reproducteur(nom: nom, race: a['race'] as String?,
          identification: ident.isEmpty ? null : ident, source: 'reseau', elevage: 'Réseau PetsMatch'));
    }
  } catch (_) {}
  return out;
}

/// Champ compact « Sélectionner un étalon / une reproductrice ».
class ChampReproducteur extends StatelessWidget {
  final String label;
  final String? valeur;
  final String? detail;
  final VoidCallback onTap;
  final VoidCallback? onEffacer;
  const ChampReproducteur({super.key, required this.label, this.valeur, this.detail,
      required this.onTap, this.onEffacer});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: valeur == null ? null : label,
          hintText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          suffixIcon: onEffacer != null && valeur != null
              ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onEffacer)
              : const Icon(Icons.expand_more, size: 20, color: Color(0xFF6F767B)),
        ),
        child: valeur == null
            ? Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF9CA3AF)))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(valeur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5,
                    fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                if (detail != null && detail!.isNotEmpty)
                  Text(detail!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF6F767B))),
              ]),
      ),
    );
  }
}

/// Liste déroulante avec recherche (feuille du bas) — sélection unique.
Future<Reproducteur?> choisirReproducteur(BuildContext context, {
  required String titre,
  required List<Reproducteur> options,
  required String vide,
}) {
  return showModalBottomSheet<Reproducteur>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _ReproducteurSheet(titre: titre, options: options, vide: vide),
  );
}

class _ReproducteurSheet extends StatefulWidget {
  final String titre;
  final List<Reproducteur> options;
  final String vide;
  const _ReproducteurSheet({required this.titre, required this.options, required this.vide});
  @override
  State<_ReproducteurSheet> createState() => _ReproducteurSheetState();
}

class _ReproducteurSheetState extends State<_ReproducteurSheet> {
  String _q = '';

  static const _groupes = {'elevage': 'Mon élevage', 'historique': 'Déjà utilisés dans vos saillies', 'reseau': 'Réseau PetsMatch'};

  @override
  Widget build(BuildContext context) {
    final t = _q.trim().toLowerCase();
    final liste = widget.options.where((r) => t.isEmpty ||
        r.nom.toLowerCase().contains(t) || (r.identification ?? '').toLowerCase().contains(t) ||
        (r.race ?? '').toLowerCase().contains(t)).toList();
    final lignes = <Widget>[];
    String? groupe;
    final plusieursGroupes = widget.options.map((r) => r.source).toSet().length > 1;
    for (final r in liste) {
      if (plusieursGroupes && r.source != groupe) {
        groupe = r.source;
        lignes.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(_groupes[r.source] ?? r.source, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5,
              fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        ));
      }
      lignes.add(ListTile(
        dense: true,
        minVerticalPadding: 10,
        title: Text(r.nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: r.detail.isEmpty ? null
            : Text(r.detail, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        onTap: () => Navigator.pop(context, r),
      ));
    }
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(child: Text(widget.titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 16,
                  fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: widget.options.length > 8,
              onChanged: (v) => setState(() => _q = v),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, race ou identification',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade500),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: liste.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(widget.options.isEmpty ? widget.vide : 'Aucun résultat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)))
              : ListView(children: lignes)),
        ]),
      ),
    ));
  }
}
