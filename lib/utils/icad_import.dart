// Import I-CAD (exports « actuellement détenus » / « anciennement détenus »,
// CSV « ; ») → fiches animaux du profil actif. Rapprochement : puce, sinon
// prénom identique + même date de naissance. Rien n'est écrit sans
// validation. Miroir site : website/src/lib/icad-import.ts.
import 'package:intl/intl.dart';

class IcadAcquereur {
  final String nom, prenom, adresse, email, tel;
  const IcadAcquereur({required this.nom, required this.prenom, required this.adresse, required this.email, required this.tel});
}

class IcadAnimal {
  final String puce, nom, espece, sexe, race, couleur, dateNaissance, dateEntree, dateCession;
  final IcadAcquereur? acquereur;
  const IcadAnimal({required this.puce, required this.nom, required this.espece, required this.sexe, required this.race,
      required this.couleur, required this.dateNaissance, required this.dateEntree, required this.dateCession, this.acquereur});
  String get cle => puce.isNotEmpty ? puce : '$nom|$dateNaissance';
}

class IcadChangement {
  final String champ, libelle, actuel, icad;
  final Object? valeur;
  const IcadChangement(this.champ, this.libelle, this.actuel, this.icad, this.valeur);
}

class IcadMiseAJour {
  final Map<String, dynamic> fiche;
  final IcadAnimal icad;
  final bool parPuce;
  final List<IcadChangement> changements;
  const IcadMiseAJour(this.fiche, this.icad, this.parPuce, this.changements);
}

class IcadAnalyse {
  final nouvelles = <IcadAnimal>[];
  final majs = <IcadMiseAJour>[];
  final aJour = <Map<String, dynamic>>[];
  final alertes = <String>[];
}

String _norm(Object? s) {
  var t = (s?.toString() ?? '').trim().toLowerCase();
  const a = 'àâäéèêëîïôöùûüç', b = 'aaaeeeeiioouuuc';
  for (var i = 0; i < a.length; i++) { t = t.replaceAll(a[i], b[i]); }
  return t;
}
String _chiffres(Object? s) => (s?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
String _jour(Object? s) { final t = s?.toString() ?? ''; return t.length >= 10 ? t.substring(0, 10) : t; }
String _casse(String s) => s.toLowerCase().replaceAllMapped(RegExp(r"(^|[\s\-'])(\S)"), (m) => '${m[1]}${m[2]!.toUpperCase()}');
String _casseLibelle(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1).toLowerCase();
/// Entrée au registre : I-CAD donne la date d'identification (pose de la
/// puce). Identifié dans les 4 mois suivant sa naissance = né à l'élevage :
/// l'entrée est la date de naissance.
String icadEntreeRegistre(IcadAnimal a) {
  if (a.dateNaissance.isEmpty || a.dateEntree.isEmpty) return a.dateEntree.isNotEmpty ? a.dateEntree : a.dateNaissance;
  final n = DateTime.tryParse(a.dateNaissance), e = DateTime.tryParse(a.dateEntree);
  if (n == null || e == null) return a.dateEntree;
  final ecart = e.difference(n).inDays;
  return ecart >= 0 && ecart <= 120 ? a.dateNaissance : a.dateEntree;
}
bool icadNeALElevage(IcadAnimal a) => a.dateNaissance.isNotEmpty && icadEntreeRegistre(a) == a.dateNaissance;

/// Mêmes mots, dans n'importe quel ordre (« NOM Prénom » ≈ « Prénom Nom »).
bool _memesMots(Object? a, Object? b) {
  List<String> m(Object? x) => _norm(x).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList()..sort();
  return m(a).join(' ') == m(b).join(' ');
}

String icadDate(String iso) {
  final d = DateTime.tryParse(iso.length >= 10 ? iso.substring(0, 10) : iso);
  return d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
}

List<String> _cellules(String ligne) {
  final out = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < ligne.length; i++) {
    final c = ligne[i];
    if (q) {
      if (c == '"' && i + 1 < ligne.length && ligne[i + 1] == '"') { cur.write('"'); i++; }
      else if (c == '"') { q = false; }
      else { cur.write(c); }
    } else if (c == '"') { q = true; }
    else if (c == ';') { out.add(cur.toString().trim()); cur.clear(); }
    else { cur.write(c); }
  }
  out.add(cur.toString().trim());
  return out;
}

List<IcadAnimal> lireCsvIcad(String texte) {
  final lignes = texte.replaceFirst('﻿', '').split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lignes.length < 2) return [];
  final entetes = _cellules(lignes[0]).map(_norm).toList();
  int col(List<String> noms) => entetes.indexWhere((e) => noms.any((n) => e == _norm(n)));
  final iPuce = col(['Insert', 'Transpondeur', 'Puce']), iNom = col(['Nom']), iEsp = col(['Espèce']), iSexe = col(['Sexe']),
      iRace = col(['Race']), iRobe = col(['Robe']), iNais = col(['Date de naissance']), iEnt = col(['Date entrée']),
      iCes = col(['Date cession']), iDet = col(['Nom et prénom']), iAdr = col(['Adresse du détenteur']),
      iMail = col(['Email du détenteur']), iTel = col(['Téléphone du détenteur']);
  if (iPuce < 0 || iNom < 0) {
    throw const FormatException("Fichier non reconnu : ce n'est pas un export I-CAD (colonnes « Insert » et « Nom » absentes).");
  }
  final out = <IcadAnimal>[];
  for (final l in lignes.skip(1)) {
    final c = _cellules(l);
    String v(int k) => k >= 0 && k < c.length ? c[k] : '';
    final sexe = _norm(v(iSexe));
    final cession = _jour(v(iCes));
    final det = v(iDet).trim();
    final mots = det.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    final esp = _norm(v(iEsp));
    final a = IcadAnimal(
      puce: _chiffres(v(iPuce)), nom: _casse(v(iNom)),
      espece: esp.isEmpty ? 'chien' : esp,
      sexe: sexe.startsWith('m') ? 'male' : sexe.startsWith('f') ? 'femelle' : '',
      race: _casse(v(iRace)), couleur: _casseLibelle(v(iRobe)),
      dateNaissance: _jour(v(iNais)), dateEntree: _jour(v(iEnt)), dateCession: cession,
      // I-CAD : « NOM PRÉNOM » — le prénom est le dernier mot.
      acquereur: cession.isNotEmpty && det.isNotEmpty ? IcadAcquereur(
        prenom: _casse(mots.length > 1 ? mots.last : ''), nom: _casse(mots.length > 1 ? mots.sublist(0, mots.length - 1).join(' ') : det),
        adresse: v(iAdr).trim(), email: v(iMail).trim(), tel: v(iTel).trim()) : null,
    );
    if (a.puce.isNotEmpty || a.nom.isNotEmpty) out.add(a);
  }
  return out;
}

IcadAnalyse analyserIcad(List<IcadAnimal> icad, List<Map<String, dynamic>> fiches, Set<String> pucesAutres) {
  final res = IcadAnalyse();
  final vus = <String>{};
  for (final a in icad) {
    if (a.puce.isNotEmpty && !vus.add(a.puce)) continue;
    var fiche = a.puce.isEmpty ? null : fiches.where((f) => _chiffres(f['identification']) == a.puce).firstOrNull;
    var parPuce = true;
    if (fiche == null && a.dateNaissance.isNotEmpty) {
      fiche = fiches.where((f) => _norm(f['nom']) == _norm(a.nom) && _jour(f['date_naissance']) == a.dateNaissance).firstOrNull;
      parPuce = false;
      if (fiche != null && _chiffres(fiche['identification']).isNotEmpty && _chiffres(fiche['identification']) != a.puce) {
        res.alertes.add('${a.nom} (né le ${icadDate(a.dateNaissance)}) : une fiche porte ce prénom et cette date mais une autre puce '
            '(${fiche['identification']}). Rien n\'est modifié : vérifiez la puce.');
        continue;
      }
    }
    if (fiche == null) {
      if (a.puce.isNotEmpty && pucesAutres.contains(a.puce)) {
        res.alertes.add('${a.nom} (puce ${a.puce}) est déjà enregistré sur un autre compte PetsMatch : fiche non créée.');
      } else {
        res.nouvelles.add(a);
      }
      continue;
    }
    final ch = <IcadChangement>[];
    void ajoute(String champ, String libelle, Object? actuel, String icadV, [Object? valeur]) {
      if (icadV.isEmpty || _norm(actuel) == _norm(icadV)) return;
      final act = actuel?.toString() ?? '';
      ch.add(IcadChangement(champ, libelle, act.isEmpty ? '—' : act, icadV, valeur ?? icadV));
    }
    String sx(Object? s) => s == 'male' ? 'Mâle' : s == 'femelle' ? 'Femelle' : (s?.toString() ?? '');
    if (_chiffres(fiche['identification']).isEmpty) ajoute('identification', 'Puce', fiche['identification'], a.puce);
    ajoute('nom', 'Nom', fiche['nom'], a.nom);
    ajoute('sexe', 'Sexe', sx(fiche['sexe']), sx(a.sexe), a.sexe);
    ajoute('race', 'Race', fiche['race'], a.race);
    ajoute('couleur', 'Robe', fiche['couleur'], a.couleur);
    if (a.dateNaissance.isNotEmpty && _jour(fiche['date_naissance']) != a.dateNaissance) {
      ch.add(IcadChangement('date_naissance', 'Naissance', icadDate(_jour(fiche['date_naissance'])), icadDate(a.dateNaissance), a.dateNaissance));
    }
    final entree = icadEntreeRegistre(a);
    if (entree.isNotEmpty && _jour(fiche['date_entree']) != entree) {
      ch.add(IcadChangement('date_entree', 'Entrée (registre)', icadDate(_jour(fiche['date_entree'])),
          '${icadDate(entree)}${icadNeALElevage(a) ? " (naissance à l'élevage)" : ''}', entree));
    }
    if (a.dateCession.isNotEmpty) {
      final dejaSorti = fiche['statut'] == 'sorti' && _jour(fiche['date_sortie']) == a.dateCession;
      if (!dejaSorti) {
        ch.add(IcadChangement('sortie', 'Sortie (registre)',
            fiche['statut'] == 'sorti' ? 'Sorti le ${icadDate(_jour(fiche['date_sortie']))}' : 'Présent',
            'Sorti le ${icadDate(a.dateCession)}', a.dateCession));
      }
      final acq = a.acquereur;
      if (acq != null) {
        final nomIcad = '${acq.prenom} ${acq.nom}'.trim();
        if ((fiche['uid_acquereur']?.toString() ?? '').isNotEmpty) {
          // Cession enregistrée vers un compte PetsMatch (cession test…) alors
          // qu'I-CAD indique un particulier sans compte : à corriger.
          ch.add(IcadChangement('acquereur', 'Acquéreur',
              '${(fiche['_compte_acquereur']?.toString() ?? '').isNotEmpty ? fiche['_compte_acquereur'] : 'un compte'} (compte PetsMatch)',
              '$nomIcad (particulier, sans compte) — la cession vers ce compte sera annulée', acq));
        } else if (!_memesMots(fiche['destinataire_nom'], nomIcad)) {
          final act = fiche['destinataire_nom']?.toString() ?? '';
          ch.add(IcadChangement('acquereur', 'Acquéreur', act.isEmpty ? '—' : act, nomIcad, acq));
        }
      }
    } else if (fiche['statut'] == 'sorti') {
      res.alertes.add('${a.nom} : I-CAD vous indique encore détenteur, mais la fiche est « sortie ». '
          'Vérifiez sur I-CAD (déclaration de cession non faite ?). Rien n\'est modifié.');
    }
    if (ch.isNotEmpty) {
      res.majs.add(IcadMiseAJour(fiche, a, parPuce, ch));
    } else {
      res.aJour.add(fiche);
    }
  }
  return res;
}

Map<String, dynamic> icadChampsSortie(IcadAnimal a) => {
      'statut': 'sorti',
      'date_sortie': a.dateCession,
      if (a.acquereur != null) ...{
        'destinataire_nom': '${a.acquereur!.prenom} ${a.acquereur!.nom}'.trim(),
        'destinataire_qualite': 'particulier',
        'destinataire_adresse': a.acquereur!.adresse,
        'acquereur_contact_manuel': {
          'prenom': a.acquereur!.prenom, 'nom': a.acquereur!.nom, 'tel': a.acquereur!.tel,
          'email': a.acquereur!.email, 'adresse': a.acquereur!.adresse,
        },
      },
    };

Map<String, dynamic> icadLigneNouvelle(IcadAnimal a) => {
      'nom': a.nom, 'identification': a.puce, 'espece': a.espece,
      if (a.sexe.isNotEmpty) 'sexe': a.sexe,
      'race': a.race, 'couleur': a.couleur,
      if (a.dateNaissance.isNotEmpty) 'date_naissance': a.dateNaissance,
      if (icadEntreeRegistre(a).isNotEmpty) 'date_entree': icadEntreeRegistre(a),
      'statut': a.dateCession.isNotEmpty ? 'sorti' : 'present',
      if (a.dateCession.isNotEmpty) ...icadChampsSortie(a),
    };

/// La correction de l'acquéreur passe par le serveur quand la fiche est
/// rattachée à un compte PetsMatch (retrait de ce compte).
bool icadCorrectionCompte(IcadMiseAJour m, Set<String> choisis) =>
    choisis.contains('acquereur') && (m.fiche['uid_acquereur']?.toString() ?? '').isNotEmpty;

/// Champs animaux à écrire (côté client) pour les changements validés.
Map<String, dynamic> icadChampsMiseAJour(IcadMiseAJour m, Set<String> choisis) {
  final out = <String, dynamic>{};
  for (final c in m.changements) {
    if (!choisis.contains(c.champ)) continue;
    if (c.champ == 'sortie') {
      out.addAll({'statut': 'sorti', 'date_sortie': m.icad.dateCession});
    } else if (c.champ == 'acquereur') {
      if (icadCorrectionCompte(m, choisis) || m.icad.acquereur == null) continue;
      final dest = icadChampsSortie(m.icad)..remove('statut')..remove('date_sortie');
      out.addAll(dest);
    } else {
      out[c.champ] = c.valeur;
    }
  }
  return out;
}
