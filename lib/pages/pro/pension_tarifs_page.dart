import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/pension_horaires.dart';
import 'package:PetsMatch/utils/document_pro.dart' show choisirDocumentPdf, deposerDocumentPro;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Pension — tarification par espèce : prix/nuit (seul vs logement partagé)
/// pour chaque espèce acceptée + réductions séjour long. Utilisé pour
/// pré-remplir le tarif dans la facturation
/// (registre_pension_page.dart::_FacturationSheet).

/// Espèces gérées par une pension. La `key` est stockée dans
/// tarifs_pension.especes[].espece ; le `label` correspond aux valeurs de
/// user_profiles.especes_acceptees.
const List<Map<String, String>> kPensionEspeces = [
  {'key': 'chien',         'label': 'Chien',               'emoji': '🐕'},
  {'key': 'chat',          'label': 'Chat',                'emoji': '🐈'},
  {'key': 'cheval',        'label': 'Cheval',              'emoji': '🐴'},
  {'key': 'ane',           'label': 'Âne',                 'emoji': '🫏'},
  {'key': 'bovin',         'label': 'Bovins',              'emoji': '🐄'},
  {'key': 'ovin',          'label': 'Ovins',               'emoji': '🐑'},
  {'key': 'caprin',        'label': 'Caprins',             'emoji': '🐐'},
  {'key': 'porcin',        'label': 'Porcins',             'emoji': '🐖'},
  {'key': 'volaille',      'label': 'Volailles',           'emoji': '🐓'},
  {'key': 'lapin',         'label': 'Lapin',               'emoji': '🐇'},
  {'key': 'nac',           'label': 'NAC',                 'emoji': '🐹'},
  {'key': 'oiseau',        'label': 'Oiseaux',             'emoji': '🦜'},
  {'key': 'poisson',       'label': 'Poissons',            'emoji': '🐟'},
];

/// Ancien tarif unique « Animaux de la ferme » (avant bovins / ovins / …
/// séparés) : encore lu tant que la pension n'a pas réenregistré ses tarifs.
const Map<String, String> kPensionEspeceFermeLegacy =
    {'key': 'animaux_ferme', 'label': 'Animaux de la ferme', 'emoji': '🐐'};

/// entree.espece (minuscule) OU label d'espèce acceptée -> key canonique.
String? pensionTarifKeyForEspece(String? espece) {
  final s = (espece ?? '').toLowerCase().trim();
  switch (s) {
    case 'chien':
    case 'chiens':  return 'chien';
    case 'chat':
    case 'chats':   return 'chat';
    case 'cheval':
    case 'chevaux':
    case 'équidés':
    case 'equides': return 'cheval';
    case 'lapin':   return 'lapin';
    case 'ane':
    case 'âne':     return 'ane';
    case 'oiseau':
    case 'oiseaux': return 'oiseau';
    case 'nac':     return 'nac';
    case 'poisson':
    case 'poissons': return 'poisson';
    case 'bovin':
    case 'bovins':
    case 'vache':
    case 'taureau': return 'bovin';
    case 'ovin':
    case 'ovins':
    case 'mouton':
    case 'brebis':  return 'ovin';
    case 'caprin':
    case 'caprins':
    case 'chevre':
    case 'chèvre':  return 'caprin';
    case 'porcin':
    case 'porcins':
    case 'porc':
    case 'cochon':  return 'porcin';
    case 'volaille':
    case 'volailles':
    case 'poule':   return 'volaille';
    case 'animaux de la ferme': return 'animaux_ferme';
  }
  for (final e in kPensionEspeces) {
    if (e['label']!.toLowerCase() == s) return e['key'];
  }
  return null;
}

/// Rubrique large d'une key de tarif : depuis la liste commune des pros
/// (« NAC », « Équidés »), un lapin relève des NAC et un âne des équidés.
/// Les bovins, ovins… relèvent de l'ancien « Animaux de la ferme ».
String pensionGroupe(String k) {
  switch (k) {
    case 'lapin': return 'nac';
    case 'ane': return 'cheval';
    case 'bovin': case 'ovin': case 'caprin': case 'porcin': case 'volaille':
      return 'animaux_ferme';
  }
  return k;
}

/// Prix d'une espèce dans tarifs_pension.especes ; repli sur la rubrique
/// large (ancien tarif « Animaux de la ferme ») si l'espèce n'a pas le sien.
Map? pensionTarifPourKey(List especesTarifs, String key) {
  Map? find(String k) {
    for (final e in especesTarifs) {
      if (e is Map && e['espece']?.toString() == k) return e;
    }
    return null;
  }
  return find(key) ?? find(pensionGroupe(key));
}

/// Équidés : tarif au box ou au pré (au lieu de seul / partagé).
bool pensionTarifEquin(String? key) => key == 'cheval' || key == 'ane';

/// Prix par nuit d'un tarif d'espèce. Équidés : box ou pré selon
/// l'hébergement (`enclos_chenil.type` ou choix du client) ; sinon seul /
/// partagé.
double pensionPrixNuit(Map t, {bool seul = true, String? hebergement}) {
  double? n(String k) { final v = (t[k] as num?)?.toDouble(); return v != null && v > 0 ? v : null; }
  final box = n('prix_box'), pre = n('prix_pre');
  if (box != null || pre != null) {
    final h = (hebergement ?? '').toLowerCase();
    final auPre = h.contains('pre') || h.contains('pré') || h.contains('paddock');
    return (auPre ? (pre ?? box) : (box ?? pre)) ?? 0;
  }
  return seul ? (n('prix_seul') ?? 0) : (n('prix_partage') ?? n('prix_seul') ?? 0);
}

/// La pension a-t-elle coché une espèce couvrant ce tarif ?
bool pensionTarifAccepte(String key, Iterable<String> acceptees) => acceptees.any((a) {
  final k = pensionTarifKeyForEspece(a);
  return k == key || (k != null && k == pensionGroupe(key));
});

/// Un logement (enclos_chenil.especes) accepte-t-il cette espèce d'animal ?
/// Logement sans espèce configurée = accepte tout.
bool especeMatchesLogement(String? animalEspece, List? logementEspeces) {
  if (logementEspeces == null || logementEspeces.isEmpty) return true;
  final animalKey = pensionTarifKeyForEspece(animalEspece)
      ?? (animalEspece ?? '').toLowerCase().trim();
  if (animalKey.isEmpty) return true;
  return logementEspeces.any((e) {
    final k = pensionTarifKeyForEspece(e?.toString()) ?? (e?.toString() ?? '').toLowerCase().trim();
    return k == animalKey || k == pensionGroupe(animalKey);
  });
}

/// Types de logement d'une pension (`enclos_chenil.type`, texte libre).
/// Box / Pré / Paddock d'abord (trio équin), puis les logements classiques.
const List<(String, String)> kPensionLogementTypes = [
  ('box', 'Box'),
  ('pre', 'Pré'),
  ('paddock', 'Paddock'),
  ('enclos', 'Enclos'),
  ('parc', 'Parc'),
  ('chatterie', 'Chatterie'),
  ('cage', 'Cage'),
];

const Map<String, String> kPensionLogementTypeLabels = {
  'box': 'Box', 'pre': 'Pré', 'paddock': 'Paddock', 'enclos': 'Enclos',
  'parc': 'Parc', 'chatterie': 'Chatterie', 'cage': 'Cage',
};

String pensionLogementTypeLabel(String? type) =>
    kPensionLogementTypeLabels[(type ?? '').toLowerCase().trim()] ?? (type ?? '');

/// L'alimentation « pour ce séjour » (foin / granulés / compléments) est-elle
/// pertinente pour cette espèce ? Équidés + animaux de la ferme.
bool pensionAlimentationSejourApplicable(String? espece) {
  final k = pensionTarifKeyForEspece(espece)
      ?? (espece ?? '').toLowerCase().trim();
  return k == 'cheval' || k == 'ane' || k == 'poney' || pensionGroupe(k) == 'animaux_ferme';
}

class PensionTarifsPage extends StatefulWidget {
  const PensionTarifsPage({super.key});

  @override
  State<PensionTarifsPage> createState() => _PensionTarifsPageState();
}

class _EspeceTarifCtrl {
  final String key;
  final String label;
  final String emoji;
  final bool accepte;
  final TextEditingController prixSeul;
  final TextEditingController prixPartage;
  _EspeceTarifCtrl({
    required this.key,
    required this.label,
    required this.emoji,
    required this.accepte,
    String prixSeul = '',
    String prixPartage = '',
  })  : prixSeul = TextEditingController(text: prixSeul),
        prixPartage = TextEditingController(text: prixPartage);
  void dispose() { prixSeul.dispose(); prixPartage.dispose(); }
}

class _ReductionCtrl {
  final TextEditingController minNuits;
  final TextEditingController pourcentage;
  _ReductionCtrl({String minNuits = '', String pourcentage = ''})
      : minNuits = TextEditingController(text: minNuits),
        pourcentage = TextEditingController(text: pourcentage);
  void dispose() { minNuits.dispose(); pourcentage.dispose(); }
}

class _PensionTarifsPageState extends State<PensionTarifsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _afficherPublic = false;
  // Essai obligatoire avant le premier séjour (réservation en ligne).
  bool _essaiRequis = false;
  // Horaires d'arrivée / de départ (null = pas d'horaires).
  Map<String, dynamic>? _horaires;
  // Modèle de contrat de la pension (envoyé à la place du contrat PetsMatch).
  Map<String, dynamic>? _modele;
  bool _envoiModele = false;
  final _essaiInfo = TextEditingController();
  // Essai : facturé ou non (au choix de la pension), et son prix.
  bool _essaiFacture = false;
  final _essaiPrix = TextEditingController();
  /// Jours de désinfection d'un logement entre deux séjours (0 : resservi le jour du départ).
  final _desinfection = TextEditingController(text: '0');
  // Durée d'une visite de la pension (RDV « visite », durees_motifs.visite).
  int _dureeVisite = 30;
  Map<String, dynamic> _dureesMotifs = {};
  bool _showAutresEspeces = false;
  // Règlement du séjour (repris dans le contrat) : arrhes à la réservation
  // (facultatives) et moment du solde.
  bool _arrhes = false;
  final _arrhesPct = TextEditingController(text: '30');
  String _solde = 'arrivee';
  final List<_EspeceTarifCtrl> _especes = [];
  final List<_ReductionCtrl> _reductions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final e in _especes) { e.dispose(); }
    for (final r in _reductions) { r.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    final pid = User_Info.activeProfileId;
    Map<String, dynamic>? tarifs;
    List<String> acceptees = List<String>.from(User_Info.especesAcceptees);
    try {
      if (pid.isNotEmpty) {
        final row = await _supa.from('user_profiles_complet')
            .select('tarifs_pension, especes_acceptees').eq('id', pid).maybeSingle();
        try {
          final e = await _supa.from('user_profiles').select('pension_essai_requis, pension_essai_info').eq('id', pid).maybeSingle();
          _essaiRequis = e?['pension_essai_requis'] == true;
          _essaiInfo.text = e?['pension_essai_info']?.toString() ?? '';
        } catch (_) {}
        // Colonne absente tant que migration_pension_horaires.sql n'est pas passée.
        try {
          final h = await _supa.from('user_profiles').select('pension_horaires').eq('id', pid).maybeSingle();
          _horaires = lireHorairesPension(h?['pension_horaires']);
        } catch (_) {}
        try {
          final md = await _supa.from('user_profiles').select('pension_contrat_modele').eq('id', pid).maybeSingle();
          final m = md?['pension_contrat_modele'];
          _modele = m is Map && (m['url']?.toString() ?? '').isNotEmpty ? Map<String, dynamic>.from(m) : null;
        } catch (_) {}
        final data = row?['tarifs_pension'];
        if (data is Map) tarifs = Map<String, dynamic>.from(data);
        if (row?['especes_acceptees'] is List) {
          acceptees = List<String>.from(row!['especes_acceptees']);
        }
      }
    } catch (_) {}

    _afficherPublic = tarifs?['afficher_public'] == true;
    final essai = tarifs?['essai'];
    if (essai is Map) {
      _essaiFacture = essai['facture'] == true;
      final px = (essai['prix'] as num?)?.toDouble();
      _essaiPrix.text = px != null && px > 0 ? px.toStringAsFixed(px % 1 == 0 ? 0 : 2) : '';
    }
    _desinfection.text = '${(tarifs?['desinfection_jours'] as num?)?.toInt() ?? 0}';
    try {
      final dm = await _supa.from('user_profiles').select('durees_motifs').eq('id', User_Info.activeProfileId).maybeSingle();
      if (dm?['durees_motifs'] is Map) _dureesMotifs = Map<String, dynamic>.from(dm!['durees_motifs'] as Map);
      final v = (_dureesMotifs['visite'] as num?)?.toInt();
      if (v != null && v > 0) _dureeVisite = v;
    } catch (_) {}
    final reglement = tarifs?['reglement'];
    if (reglement is Map) {
      final pct = (reglement['arrhes_pct'] as num?)?.toDouble() ?? 0;
      _arrhes = pct > 0;
      if (pct > 0) _arrhesPct.text = pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1);
      _solde = reglement['solde']?.toString() == 'depart' ? 'depart' : 'arrivee';
    }

    // Prix déjà saisis, par key d'espèce.
    final prixParEspece = <String, Map<String, String>>{};
    final especesJson = tarifs?['especes'];
    if (especesJson is List) {
      for (final e in especesJson) {
        if (e is! Map) continue;
        final k = e['espece']?.toString() ?? '';
        if (k.isEmpty) continue;
        prixParEspece[k] = pensionTarifEquin(k)
            ? {
                'seul': (e['prix_box'] ?? (e['prix_pre'] == null ? e['prix_seul'] : null))?.toString() ?? '',
                'partage': e['prix_pre']?.toString() ?? '',
              }
            : {
                'seul': e['prix_seul']?.toString() ?? '',
                'partage': e['prix_partage']?.toString() ?? '',
              };
      }
    } else {
      // Rétro-compat : ancien modèle tranches_poids -> on reprend le prix
      // de la 1re tranche comme défaut pour toutes les espèces acceptées.
      final tranches = tarifs?['tranches_poids'];
      if (tranches is List && tranches.isNotEmpty && tranches.first is Map) {
        final t = tranches.first as Map;
        final seul = t['prix_seul']?.toString() ?? '';
        final partage = t['prix_partage']?.toString() ?? '';
        for (final sp in kPensionEspeces) {
          if (pensionTarifAccepte(sp['key']!, acceptees)) {
            prixParEspece[sp['key']!] = {'seul': seul, 'partage': partage};
          }
        }
      }
    }

    // Ancien tarif unique « Animaux de la ferme » → repris pour chaque espèce
    // de la ferme qui n'a pas encore son prix.
    for (final sp in kPensionEspeces) {
      final legacy = prixParEspece[pensionGroupe(sp['key']!)];
      if (legacy != null && pensionGroupe(sp['key']!) == 'animaux_ferme') {
        prixParEspece.putIfAbsent(sp['key']!, () => legacy);
      }
    }

    for (final sp in kPensionEspeces) {
      final k = sp['key']!;
      final saved = prixParEspece[k];
      _especes.add(_EspeceTarifCtrl(
        key: k,
        label: sp['label']!,
        emoji: sp['emoji']!,
        accepte: pensionTarifAccepte(k, acceptees),
        prixSeul: saved?['seul'] ?? '',
        prixPartage: saved?['partage'] ?? '',
      ));
    }

    final reductions = tarifs?['reductions_long_sejour'];
    if (reductions is List) {
      for (final r in reductions) {
        if (r is! Map) continue;
        _reductions.add(_ReductionCtrl(
          minNuits: r['min_nuits']?.toString() ?? '',
          pourcentage: r['pourcentage']?.toString() ?? '',
        ));
      }
    }

    // Espèces acceptées d'abord, ordre canonique conservé dans chaque groupe.
    int rank(String k) => kPensionEspeces.indexWhere((e) => e['key'] == k);
    _especes.sort((a, b) {
      if (a.accepte != b.accepte) return a.accepte ? -1 : 1;
      return rank(a.key).compareTo(rank(b.key));
    });

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final especes = _especes
          .where((e) => e.prixSeul.text.trim().isNotEmpty || e.prixPartage.text.trim().isNotEmpty)
          .map((e) {
        final seul = double.tryParse(e.prixSeul.text.replaceAll(',', '.'))
            ?? double.tryParse(e.prixPartage.text.replaceAll(',', '.')) ?? 0;
        if (pensionTarifEquin(e.key)) {
          // Équidés : box / pré ; prix_seul repris pour les anciens lecteurs.
          final box = double.tryParse(e.prixSeul.text.replaceAll(',', '.'));
          final pre = double.tryParse(e.prixPartage.text.replaceAll(',', '.'));
          return {'espece': e.key, 'prix_box': box, 'prix_pre': pre, 'prix_seul': seul, 'prix_partage': seul};
        }
        final partage = double.tryParse(e.prixPartage.text.replaceAll(',', '.')) ?? seul;
        return {'espece': e.key, 'prix_seul': seul, 'prix_partage': partage};
      }).toList();

      final reductions = _reductions
          .where((r) => r.minNuits.text.trim().isNotEmpty)
          .map((r) => {
                'min_nuits': int.tryParse(r.minNuits.text) ?? 0,
                'pourcentage': double.tryParse(r.pourcentage.text.replaceAll(',', '.')) ?? 0,
              })
          .toList()
        ..sort((a, b) => (a['min_nuits'] as int).compareTo(b['min_nuits'] as int));

      await _supa.from('user_profiles').update({
        'tarifs_pension': {
          'especes': especes,
          'reductions_long_sejour': reductions,
          'afficher_public': _afficherPublic,
          'reglement': {
            'arrhes_pct': _arrhes ? (double.tryParse(_arrhesPct.text.replaceAll(',', '.')) ?? 0) : null,
            'solde': _solde,
          },
          'essai': {
            'facture': _essaiFacture,
            'prix': _essaiFacture ? (double.tryParse(_essaiPrix.text.replaceAll(',', '.')) ?? 0) : null,
          },
          'desinfection_jours': (int.tryParse(_desinfection.text.trim()) ?? 0).clamp(0, 7),
        },
      }).eq('id', pid);
      try {
        await _supa.from('user_profiles').update({'durees_motifs': {..._dureesMotifs, 'visite': _dureeVisite}}).eq('id', pid);
      } catch (_) {}
      try {
        await _supa.from('user_profiles').update({
          'pension_essai_requis': _essaiRequis,
          'pension_essai_info': _essaiInfo.text.trim().isEmpty ? null : _essaiInfo.text.trim(),
        }).eq('id', pid);
      } catch (_) {}
      try {
        await _supa.from('user_profiles').update({'pension_horaires': _horaires}).eq('id', pid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Horaires non enregistrés : $e')));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tarifs enregistrés.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mon contrat d'hébergement : modèle (PDF ou photo) envoyé à la place du
  /// contrat PetsMatch, signé en ligne par le client. Enregistré tout de suite.
  Widget _modeleContrat() {
    final pid = User_Info.activeProfileId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _modele != null ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Mon contrat d'hébergement", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text("Vous avez votre propre contrat ? Chargez-le (PDF ou photo) : à l'arrivée, vous pourrez l'envoyer à la place du contrat PetsMatch. Il est signé en ligne par le client, avec votre signature enregistrée.",
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        if (_modele != null)
          Row(children: [
            const Icon(Icons.description_outlined, size: 18, color: _green),
            const SizedBox(width: 6),
            Expanded(child: Text(_modele!['nom']?.toString() ?? 'Mon contrat', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: () async {
                try {
                  await _supa.from('user_profiles').update({'pension_contrat_modele': null}).eq('id', pid);
                  setState(() => _modele = null);
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
                }
              },
              child: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFFB3261E))),
            ),
          ]),
        TextButton.icon(
          onPressed: _envoiModele ? null : () async {
            final pdf = await choisirDocumentPdf(context);
            if (pdf == null || !mounted) return;
            setState(() => _envoiModele = true);
            try {
              final url = await deposerDocumentPro(pdf);
              final m = {'url': url, 'nom': 'Mon contrat', 'le': DateTime.now().toUtc().toIso8601String()};
              await _supa.from('user_profiles').update({'pension_contrat_modele': m}).eq('id', pid);
              setState(() => _modele = m);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modèle de contrat enregistré.')));
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Modèle non enregistré : $e')));
            }
            if (mounted) setState(() => _envoiModele = false);
          },
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(_envoiModele ? 'Envoi…' : _modele != null ? 'Remplacer le modèle' : 'Charger mon contrat',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(foregroundColor: _green, padding: EdgeInsets.zero),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Tarifs pension',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _afficherPublic ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _afficherPublic,
                    onChanged: (v) => setState(() => _afficherPublic = v),
                    activeColor: _green,
                    title: const Text('Afficher mes tarifs sur ma fiche publique',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Les clients verront le prix par nuit et par espèce dans l\'annuaire des pros.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _essaiRequis ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
                  ),
                  child: Column(children: [
                    SwitchListTile.adaptive(
                      value: _essaiRequis,
                      onChanged: (v) => setState(() => _essaiRequis = v),
                      activeColor: _green,
                      title: const Text('Essai obligatoire avant le premier séjour',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("À la réservation en ligne, le client propose une date d'essai (une journée) avant le premier séjour de son animal.",
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                    ),
                    if (_essaiRequis)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          TextField(controller: _essaiInfo, maxLines: 2, minLines: 1,
                              decoration: const InputDecoration(labelText: 'Précisions pour le client (facultatif)',
                                  hintText: "Ex : journée de 9 h à 17 h, ce que l'essai permet d'observer", border: OutlineInputBorder(), isDense: true)),
                          CheckboxListTile(
                            value: _essaiFacture, onChanged: (v) => setState(() => _essaiFacture = v ?? false),
                            dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: _green,
                            title: const Text('Essai facturé', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                          ),
                          if (_essaiFacture)
                            SizedBox(width: 160, child: TextField(controller: _essaiPrix, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: "Prix de l'essai", suffixText: '€', border: OutlineInputBorder(), isDense: true)))
                          else
                            Text("Essai non facturé : il sert à observer le comportement de l'animal ; il n'apparaît jamais comme « à facturer ».",
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text("Avec vos horaires d'arrivée, le client choisit aussi l'heure de l'essai.",
                              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                HorairesPensionForm(valeur: _horaires, onChange: (h) => setState(() => _horaires = h), couleur: _green),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEEEEE))),
                  child: Row(children: [
                    const Expanded(child: Text("Durée d'une visite de la pension", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5))),
                    IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _dureeVisite <= 5 ? null : () => setState(() => _dureeVisite -= 5)),
                    Text('$_dureeVisite min', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => setState(() => _dureeVisite += 5)),
                  ]),
                ),
                const SizedBox(height: 12),
                _modeleContrat(),
                const SizedBox(height: 20),
                const Text('Prix par espèce',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Tarif par nuit selon l\'espèce et selon que l\'animal est seul '
                    'ou partage son logement. Le tarif est ensuite suggéré automatiquement '
                    'à la facturation.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                ..._buildEspeceCards(),
                const SizedBox(height: 24),
                const Text('Désinfection des logements',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Temps entre deux séjours dans un même logement. Les réservations et les attributions en tiennent compte '
                    '(0 : le logement peut resservir le jour du départ).',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(width: 80, child: TextField(controller: _desinfection, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  const Text('jour(s) entre deux séjours', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ]),
                const SizedBox(height: 24),
                const Text('Réductions séjour long',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Réduction appliquée sur le tarif total à partir d\'un nombre de nuits (toutes espèces).',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                for (int i = 0; i < _reductions.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: TextField(
                        controller: _reductions[i].minNuits,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'À partir de (nuits)', isDense: true, border: OutlineInputBorder()),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: _reductions[i].pourcentage,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Réduction (%)', isDense: true, border: OutlineInputBorder()),
                      )),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() {
                          _reductions[i].dispose();
                          _reductions.removeAt(i);
                        }),
                      ),
                    ]),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _reductions.add(_ReductionCtrl())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une réduction', style: TextStyle(fontFamily: 'Galey')),
                ),
                const SizedBox(height: 24),
                const Text('Règlement du séjour',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text("Repris dans le contrat d'hébergement. Les arrhes confirment la réservation : si le client "
                    "annule, elles restent acquises à la pension ; si la pension annule, elle les rembourse au double.",
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    SwitchListTile.adaptive(
                      value: _arrhes,
                      onChanged: (v) => setState(() => _arrhes = v),
                      activeColor: _green,
                      title: const Text('Demander des arrhes à la réservation',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    if (_arrhes)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(controller: _arrhesPct, keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Arrhes (% du séjour)', helperText: 'Souvent 25 à 30 %',
                                isDense: true, border: OutlineInputBorder())),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(_arrhes ? 'Solde réglé :' : 'Séjour réglé :', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                        for (final (v, lib) in [('arrivee', "à l'arrivée"), ('depart', 'au départ')])
                          ChoiceChip(
                            label: Text(lib, style: TextStyle(fontFamily: 'Galey', color: _solde == v ? Colors.white : Colors.black87)),
                            selected: _solde == v, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                            onSelected: (_) => setState(() => _solde = v),
                          ),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(_saving ? '...' : 'Enregistrer',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                )),
              ],
            ),
    );
  }

  List<Widget> _buildEspeceCards() {
    final acceptees = _especes.where((e) => e.accepte).toList();
    final autres = _especes.where((e) => !e.accepte).toList();
    final w = <Widget>[];

    if (acceptees.isEmpty) {
      w.add(Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Text(
          "Aucune espèce acceptée définie. Ajoutez vos espèces dans votre profil pour ne remplir que celles-ci.",
          style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.orange.shade900),
        ),
      ));
      w.addAll(_especes.map(_especeCard));
      return w;
    }

    w.addAll(acceptees.map(_especeCard));

    if (autres.isNotEmpty) {
      w.add(TextButton.icon(
        onPressed: () => setState(() => _showAutresEspeces = !_showAutresEspeces),
        icon: Icon(_showAutresEspeces ? Icons.expand_less : Icons.add, size: 18),
        label: Text(_showAutresEspeces ? 'Masquer les autres espèces' : 'Tarif pour une autre espèce',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ));
      if (_showAutresEspeces) w.addAll(autres.map(_especeCard));
    }
    return w;
  }

  Widget _especeCard(_EspeceTarifCtrl e) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: e.accepte ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(e.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(width: 8),
        if (e.accepte)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: const Text('Accepté', style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(
          controller: e.prixSeul,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: pensionTarifEquin(e.key) ? 'Box (€ TTC/nuit)' : 'Prix seul (€ TTC/nuit)', isDense: true, border: const OutlineInputBorder()),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: e.prixPartage,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: pensionTarifEquin(e.key) ? 'Pré (€ TTC/nuit)' : 'Prix partagé (€ TTC/nuit)', isDense: true, border: const OutlineInputBorder()),
        )),
      ]),
    ]),
  );
}

/// Clé d'espèce commune (animal, logement, séjour) ; '' = inconnue.
String cleEspecePension(String? e) {
  final s = (e ?? '').trim();
  if (s.isEmpty) return '';
  return pensionTarifKeyForEspece(s) ?? s.toLowerCase();
}

/// Le logement (enclos_chenil.especes) accepte l'espèce de l'animal : aucune
/// espèce cochée = toutes ; « NAC » accepte un lapin, « Équidés » un âne.
/// Espèce inconnue : accepté. Miroir site : lib/pension-especes.ts.
bool logementAccepteEspece(List? especesLogement, String? espece) {
  final k = cleEspecePension(espece);
  final liste = [for (final e in especesLogement ?? const []) e.toString()];
  if (k.isEmpty || liste.isEmpty) return true;
  return liste.any((x) { final c = cleEspecePension(x); return c == k || pensionGroupe(c) == pensionGroupe(k); });
}
