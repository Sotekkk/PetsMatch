import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:PetsMatch/pages/particulier/partage_animal_sheet.dart' show libellesSections;

/// Fiche d'un animal partagée par lien / QR code (`/partage/<token>`), en
/// lecture seule, ouverte dans l'appli quand elle est installée (sinon le
/// site). Seuls les onglets choisis par le propriétaire (partage_animal.sections)
/// sont affichés — la base n'ouvre que ceux-là : chaque requête porte le lien
/// dans l'en-tête x-pm-token (migration_partage_sections.sql).
/// Miroir site : website/src/app/partage/[token]/page.tsx.
class PartageAnimalPage extends StatefulWidget {
  final String token;
  const PartageAnimalPage({super.key, required this.token});

  @override
  State<PartageAnimalPage> createState() => _PartageAnimalPageState();
}

class _PartageAnimalPageState extends State<PartageAnimalPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _colonnes = 'id, nom, espece, race, sexe, date_naissance, identification, photo_url, description, '
      'couleur, couleur_yeux, poids, taille, sterilise, documents, nom_pere, race_pere, puce_pere, nom_pedigree_pere, '
      'nom_mere, race_mere, puce_mere, nom_pedigree_mere, nom_pedigree, pedigree_lof, pedigree_numero, club_registre';
  final _supa = Supabase.instance.client;

  String _etat = 'chargement'; // chargement | ok | expire | invalide
  Map<String, dynamic> _animal = {};
  List<String> _sections = const ['identite'];
  final Map<String, List<Map<String, dynamic>>> _sante = {};
  List<Map<String, dynamic>> _poids = [];
  Map<String, dynamic>? _alimentation;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<List<Map<String, dynamic>>> _lire(String table, String animalId) async {
    final r = await _supa.from(table).select().eq('animal_id', animalId)
        .order('date', ascending: false).setHeader('x-pm-token', widget.token);
    return List<Map<String, dynamic>>.from(r as List);
  }

  Future<void> _charger() async {
    try {
      final p = await _supa.from('partage_animal').select().eq('token', widget.token)
          .setHeader('x-pm-token', widget.token).maybeSingle();
      if (p == null) return setState(() => _etat = 'invalide');
      final expire = DateTime.tryParse(p['expire_at']?.toString() ?? '');
      if (p['actif'] != true || (expire != null && expire.isBefore(DateTime.now()))) {
        return setState(() => _etat = 'expire');
      }
      final sections = List<String>.from((p['sections'] as List?) ?? const []);
      final animalId = p['animal_id'].toString();
      final a = await _supa.from('animaux').select(_colonnes).eq('id', animalId)
          .setHeader('x-pm-token', widget.token).maybeSingle();
      if (a == null) return setState(() => _etat = 'invalide');

      if (sections.contains('sante')) {
        for (final t in ['vaccinations', 'traitements', 'vermifuges', 'antiparasitaires', 'chirurgies', 'visites', 'allergies']) {
          try { _sante[t] = await _lire(t, animalId); } catch (_) { _sante[t] = []; }
        }
      }
      if (sections.contains('poids')) {
        try { _poids = await _lire('poids', animalId); } catch (_) {}
      }
      if (sections.contains('alimentation')) {
        try {
          final r = await _supa.from('alimentations').select().eq('animal_id', animalId).limit(1)
              .setHeader('x-pm-token', widget.token);
          final l = List<Map<String, dynamic>>.from(r as List);
          _alimentation = l.isEmpty ? null : l.first;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _animal = Map<String, dynamic>.from(a);
        _sections = sections.isEmpty ? const ['identite'] : sections;
        _etat = 'ok';
      });
    } catch (_) {
      if (mounted) setState(() => _etat = 'invalide');
    }
  }

  String _jour(Object? v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '' : DateFormat('dd/MM/yyyy').format(d.toLocal());
  }

  String _cap(Object? s) {
    final t = (s ?? '').toString();
    return t.isEmpty ? '' : '${t[0].toUpperCase()}${t.substring(1)}';
  }

  String? _age() {
    final d = DateTime.tryParse(_animal['date_naissance']?.toString() ?? '');
    if (d == null) return null;
    final jours = DateTime.now().difference(d).inDays;
    final mois = (jours / 30.44).floor();
    if (mois < 2) return '$jours jours';
    if (mois < 24) return '$mois mois';
    return '${(mois / 12).floor()} ans';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: const Text('Fiche partagée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
      ),
      body: switch (_etat) {
        'chargement' => const Center(child: CircularProgressIndicator(color: _teal)),
        'expire' => _erreur('Lien expiré', 'Ce lien de partage n\'est plus valide. Demandez un nouveau lien à son propriétaire.'),
        'invalide' => _erreur('Lien invalide', 'Ce lien de partage est introuvable ou a été désactivé.'),
        _ => _fiche(),
      },
    );
  }

  Widget _erreur(String titre, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );

  Widget _fiche() {
    final a = _animal;
    final photo = a['photo_url']?.toString() ?? '';
    final age = _age();
    final infos = <(String, String)>[
      if ((a['espece'] ?? '').toString().isNotEmpty) ('Espèce', _cap(a['espece'])),
      if ((a['sexe'] ?? '').toString().isNotEmpty) ('Sexe', _cap(a['sexe'])),
      if (age != null) ('Âge', age),
      if (a['date_naissance'] != null) ('Naissance', _jour(a['date_naissance'])),
      if ((a['couleur'] ?? '').toString().isNotEmpty) ('Couleur', a['couleur'].toString()),
      if ((a['couleur_yeux'] ?? '').toString().isNotEmpty) ('Couleur des yeux', a['couleur_yeux'].toString()),
      if (a['taille'] != null) ('Taille', '${a['taille']} cm'),
      if (a['sterilise'] != null) ('Stérilisé(e)', a['sterilise'] == true ? 'Oui' : 'Non'),
    ];
    final docs = List<Map<String, dynamic>>.from(((a['documents'] as List?) ?? const []).whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (photo.isNotEmpty)
            CachedNetworkImage(imageUrl: photo, height: 220, width: double.infinity, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((a['nom'] ?? 'Sans nom').toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 22)),
              if ((a['race'] ?? '').toString().isNotEmpty)
                Text(a['race'].toString(), style: const TextStyle(color: _teal, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final i in infos) _info(i.$1, i.$2)]),
              if ((a['identification'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Identification : ${a['identification']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
              if ((a['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(a['description'].toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ]),
          ),
        ]),
      ),
      if (_sections.contains('sante'))
        _bloc('Carnet de santé', [
          _liste('Vaccins', _sante['vaccinations'], (v) => [v['vaccin'], _jour(v['date']),
            if (v['date_rappel'] != null) 'rappel ${_jour(v['date_rappel'])}']),
          _liste('Traitements', _sante['traitements'], (t) => [t['nom'], t['posologie'],
            t['date_fin'] != null ? 'du ${_jour(t['date'])} au ${_jour(t['date_fin'])}' : (t['date'] != null ? 'depuis le ${_jour(t['date'])}' : '')]),
          _liste('Vermifuges', _sante['vermifuges'], (v) => [v['produit'], _jour(v['date']),
            if (v['date_rappel'] != null) 'rappel ${_jour(v['date_rappel'])}']),
          _liste('Antiparasitaires', _sante['antiparasitaires'], (v) => [v['produit'], _jour(v['date']),
            if (v['date_rappel'] != null) 'rappel ${_jour(v['date_rappel'])}']),
          _liste('Chirurgie / hospitalisation', _sante['chirurgies'], (c) => [c['intitule'], _jour(c['date']),
            c['statut'] == 'realise' ? 'réalisée' : c['statut'] == 'annule' ? 'annulée' : 'prévue']),
          _liste('Visites', _sante['visites'], (v) => [v['motif'], _jour(v['date']), v['veterinaire']]),
          _liste('Allergies', _sante['allergies'], (x) => [x['description'], x['severite']]),
        ]),
      if (_sections.contains('poids'))
        _bloc('Poids', [
          if (_poids.isEmpty) _vide()
          else for (final p in _poids.take(12))
            Padding(padding: const EdgeInsets.only(bottom: 4),
                child: Text('${_jour(p['date'])} — ${p['valeur']} kg', style: const TextStyle(fontSize: 13))),
        ]),
      if (_sections.contains('alimentation'))
        _bloc('Alimentation', [
          if (_alimentation == null) _vide()
          else ...[
            for (final l in [
              if (_alimentation!['type_ration'] != null) 'Type de ration : ${_alimentation!['type_ration']}',
              if (_alimentation!['marque'] != null) 'Aliment : ${[_alimentation!['marque'], _alimentation!['gamme']].where((e) => e != null).join(' ')}',
              if (_alimentation!['ration_grammes'] != null) 'Ration : ${_alimentation!['ration_grammes']} g / jour',
              if (_alimentation!['nb_repas'] != null) 'Repas : ${_alimentation!['nb_repas']} par jour',
              if (_alimentation!['notes'] != null) _alimentation!['notes'].toString(),
            ])
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: const TextStyle(fontSize: 13))),
          ],
        ]),
      if (_sections.contains('documents'))
        _bloc('Documents', [
          if (docs.isEmpty) _vide()
          else for (final d in docs)
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, color: _teal),
              title: Text((d['nom'] ?? 'Document').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: d['date_expiration'] != null ? Text('expire le ${_jour(d['date_expiration'])}') : null,
              onTap: (d['url'] ?? '').toString().isEmpty ? null
                  : () => launchUrl(Uri.parse(d['url'].toString()), mode: LaunchMode.externalApplication),
            ),
        ]),
      if (_sections.contains('genealogie'))
        _bloc('Généalogie', [
          Row(children: [
            Expanded(child: _parent('Père', a['nom_pedigree_pere'] ?? a['nom_pere'], a['race_pere'], a['puce_pere'])),
            const SizedBox(width: 8),
            Expanded(child: _parent('Mère', a['nom_pedigree_mere'] ?? a['nom_mere'], a['race_mere'], a['puce_mere'])),
          ]),
          if ((a['nom_pedigree'] ?? a['pedigree_lof'] ?? a['pedigree_numero']) != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Pedigree : ${[a['nom_pedigree'], a['club_registre'], a['pedigree_lof'] ?? a['pedigree_numero']].where((e) => (e ?? '').toString().isNotEmpty).join(' · ')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Fiche partagée via PetsMatch · ${libellesSections(_sections)} · lecture seule',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ),
    ]);
  }

  Widget _info(String label, String valeur) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(valeur, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _bloc(String titre, List<Widget> enfants) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          ...enfants,
        ]),
      );

  Widget _liste(String titre, List<Map<String, dynamic>>? lignes, List<Object?> Function(Map<String, dynamic>) rendu) {
    if (lignes == null || lignes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        for (final l in lignes.take(20))
          Text(rendu(l).where((e) => (e ?? '').toString().isNotEmpty).join(' · '), style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _parent(String titre, Object? nom, Object? race, Object? puce) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text((nom ?? '—').toString().isEmpty ? '—' : nom.toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((race ?? '').toString().isNotEmpty) Text(race.toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if ((puce ?? '').toString().isNotEmpty) Text(puce.toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      );

  Widget _vide() => Text('Rien de renseigné.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500));
}
