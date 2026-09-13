import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart';
import 'package:PetsMatch/pages/pro/garde_facture_helper.dart';
import 'package:PetsMatch/pages/pro/garde_sejour_helper.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Registre visites — liste des RDV (visites/promenades) du profil garde,
// avec statut de compte-rendu. Contrairement à la pension (logements avec
// check-in/check-out), le modèle petsitter est événementiel : chaque visite
// est déjà un RDV dans le système agenda générique (table `rdv`).
//
// Les gardes-journée (motif garde_journee, hébergement chez le prestataire)
// sont regroupées en "séjours" (garde_sejour_helper.dart) et bénéficient
// d'une validation de présence (arrivée / départ) + d'un registre légal
// dédié (obligation d'entrée-sortie, cf. arrêté du 3 avril 2014 — les
// promenades/visites à domicile client, « sans hébergement », n'y sont pas
// soumises et restent de simples RDV événementiels).

class RegistreVisitesPage extends StatefulWidget {
  final int initialTab; // 0 = À venir, 1 = Passées, 2 = Mes contrats, 3 = Registre
  const RegistreVisitesPage({super.key, this.initialTab = 0});

  @override
  State<RegistreVisitesPage> createState() => _RegistreVisitesPageState();
}

class _RegistreVisitesPageState extends State<RegistreVisitesPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _visites = [];
  late int _tab; // 0 = À venir, 1 = Passées, 2 = Mes contrats, 3 = Registre
  // client_uid → {nom, email, tel, profile_id, doc_token, doc_statut}
  Map<String, Map<String, dynamic>> _clients = {};
  Set<String> _facturedRdvIds = {};

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 3);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      var q = _supa.from('rdv').select().eq('pro_uid', uid);
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q
          .inFilter('statut', ['confirme', 'termine'])
          .order('date_heure', ascending: true);

      final list = List<Map<String, dynamic>>.from(rows as List);

      // Résolution du client par SON profil (client_profile_id) — jamais
      // uid+is_main, qui renverrait le profil éleveur d'un compte multi-profils.
      final clientProfileIds = list.map((r) => r['client_profile_id']?.toString())
          .whereType<String>().where((s) => s.isNotEmpty).toSet().toList();
      final clientUidsNoPid = list
          .where((r) => (r['client_profile_id']?.toString() ?? '').isEmpty)
          .map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds  = list.map((r) => r['animal_id']?.toString()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList();

      final results = await Future.wait([
        clientProfileIds.isNotEmpty
            ? _supa.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact, phone_number').inFilter('id', clientProfileIds)
            : Future.value(<Map<String, dynamic>>[]),
        clientUidsNoPid.isNotEmpty
            ? _supa.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact, phone_number').inFilter('uid', clientUidsNoPid).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom, espece, race, identification').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      // Contrats de prestation « cadre » du profil garde actif, indexés par client.
      var docsQ = _supa.from('documents_animaux')
          .select('token, statut, metadata')
          .eq('uid_eleveur', uid)
          .eq('type', 'contrat_garde');
      if (pid.isNotEmpty) docsQ = docsQ.eq('pro_profile_id', pid);
      final docs = List<Map<String, dynamic>>.from(await docsQ as List);

      String nomOf(Map<String, dynamic> c) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        return full.isNotEmpty ? full : 'Client';
      }
      final nameByPid = <String, String>{};
      final emailByPid = <String, String>{};
      final telByPid = <String, String>{};
      final nameByUid = <String, String>{};
      final emailByUid = <String, String>{};
      final telByUid = <String, String>{};
      for (final c in (results[0] as List)) {
        nameByPid[c['id'] as String] = nomOf(c);
        emailByPid[c['id'] as String] = (c['email_contact'] as String?) ?? '';
        telByPid[c['id'] as String] = (c['phone_number'] as String?) ?? '';
      }
      for (final c in (results[1] as List)) {
        nameByUid[c['uid'] as String] = nomOf(c);
        emailByUid[c['uid'] as String] = (c['email_contact'] as String?) ?? '';
        telByUid[c['uid'] as String] = (c['phone_number'] as String?) ?? '';
      }
      final animalInfo = <String, Map<String, String>>{
        for (final a in (results[2] as List))
          a['id'].toString(): {
            'nom': a['nom']?.toString() ?? '',
            'espece': a['espece']?.toString() ?? '',
            'race': a['race']?.toString() ?? '',
            'puce': a['identification']?.toString() ?? '',
          },
      };
      final animalNames = <String, String>{
        for (final e in animalInfo.entries) e.key: e.value['nom'] ?? '',
      };

      final docByClient = <String, Map<String, dynamic>>{};
      for (final d in docs) {
        final meta = (d['metadata'] as Map?) ?? {};
        final cu = meta['client_uid']?.toString();
        if (cu != null && cu.isNotEmpty) docByClient[cu] = d;
      }

      String clientName(Map<String, dynamic> r) {
        final cp = r['client_profile_id']?.toString() ?? '';
        if (cp.isNotEmpty && nameByPid[cp] != null) return nameByPid[cp]!;
        return nameByUid[r['client_uid']?.toString() ?? ''] ?? 'Client';
      }
      String clientEmail(Map<String, dynamic> r) {
        final cp = r['client_profile_id']?.toString() ?? '';
        if (cp.isNotEmpty && (emailByPid[cp] ?? '').isNotEmpty) return emailByPid[cp]!;
        return emailByUid[r['client_uid']?.toString() ?? ''] ?? '';
      }
      String clientTel(Map<String, dynamic> r) {
        final cp = r['client_profile_id']?.toString() ?? '';
        if (cp.isNotEmpty && (telByPid[cp] ?? '').isNotEmpty) return telByPid[cp]!;
        return telByUid[r['client_uid']?.toString() ?? ''] ?? '';
      }

      final clients = <String, Map<String, dynamic>>{};
      // Un contrat cadre couvre toutes les gardes d'un client, potentiellement
      // pour plusieurs animaux — on affiche la liste complète sous son nom
      // plutôt que celui de la seule première visite rencontrée.
      final animauxByClient = <String, Set<String>>{};
      for (final r in list) {
        r['_client_nom'] = clientName(r);
        r['_client_email'] = clientEmail(r);
        r['_client_tel'] = clientTel(r);
        final info = animalInfo[r['animal_id']?.toString()];
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
        r['_animal_espece'] = info?['espece'] ?? '';
        r['_animal_race'] = info?['race'] ?? '';
        r['_animal_puce'] = info?['puce'] ?? '';
        final cu = r['client_uid']?.toString();
        if (cu != null && cu.isNotEmpty) {
          if ((r['_animal_nom'] as String).isNotEmpty) {
            animauxByClient.putIfAbsent(cu, () => {}).add(r['_animal_nom'] as String);
          }
          if (!clients.containsKey(cu)) {
            final doc = docByClient[cu];
            clients[cu] = {
              'nom': clientName(r),
              'email': clientEmail(r),
              'tel': clientTel(r),
              'profile_id': r['client_profile_id'],
              'doc_token': doc?['token'],
              'doc_statut': doc?['statut'],
            };
          }
        }
      }
      for (final entry in clients.entries) {
        final animaux = (animauxByClient[entry.key]?.toList() ?? [])..sort();
        entry.value['animaux'] = animaux.join(', ');
      }

      // RDV déjà facturés — porté directement par `rdv.facture_id`.
      final facturedIds = <String>{
        for (final r in list)
          if ((r['facture_id']?.toString() ?? '').isNotEmpty) r['id'].toString(),
      };

      if (mounted) setState(() {
        _visites = list;
        _clients = clients;
        _facturedRdvIds = facturedIds;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ouvre (ou crée) le contrat de prestation « cadre » d'un client — un seul
  /// par (profil garde, client), réutilisé pour toutes ses gardes. Scopé
  /// `pro_profile_id` + `metadata.client_uid` (aucun mélange de profils).
  Future<void> _openClientContrat(String clientUid, [Map<String, dynamic>? rdv]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final client = _clients[clientUid];
    if (client == null) return;
    final pid = User_Info.activeProfileId;
    final animalId  = rdv?['animal_id']?.toString();
    final animalNom = (rdv?['_animal_nom'] ?? rdv?['animal_nom'] ?? '').toString();
    try {
      var q = _supa.from('documents_animaux')
          .select('id, token, statut, animal_id, metadata')
          .eq('uid_eleveur', uid)
          .eq('type', 'contrat_garde')
          .eq('metadata->>client_uid', clientUid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final existing = await q.maybeSingle();

      String? token = existing?['token'] as String?;
      if (token == null) {
        final row = await _supa.from('documents_animaux').insert({
          'uid_eleveur': uid,
          if (pid.isNotEmpty) 'pro_profile_id': pid,
          'type': 'contrat_garde',
          'titre': 'Contrat de prestation — ${client['nom']}',
          'statut': 'en_attente',
          if (animalId != null && animalId.isNotEmpty) 'animal_id': animalId,
          'metadata': {
            'client_nom': client['nom'],
            'client_uid': clientUid,
            if (client['profile_id'] != null) 'client_profile_id': client['profile_id'],
            if ((client['email'] as String?)?.isNotEmpty == true) 'client_email': client['email'],
            if (animalNom.isNotEmpty) 'animal_nom': animalNom,
            if (animalNom.isNotEmpty) 'animal_noms': [animalNom],
          },
        }).select('token').single();
        token = row['token'] as String?;
      } else if (animalNom.isNotEmpty) {
        // Contrat déjà là : on rattache l'animal courant s'il manque.
        final meta = Map<String, dynamic>.from((existing!['metadata'] as Map?) ?? {});
        final noms = List<String>.from((meta['animal_noms'] as List?) ?? const []);
        final needAnimalId = (existing['animal_id'] == null) && animalId != null && animalId.isNotEmpty;
        if (!noms.contains(animalNom) || needAnimalId) {
          if (!noms.contains(animalNom)) noms.add(animalNom);
          meta['animal_noms'] = noms;
          meta['animal_nom'] ??= animalNom;
          await _supa.from('documents_animaux').update({
            'metadata': meta,
            if (needAnimalId) 'animal_id': animalId,
          }).eq('id', existing['id'] as String);
        }
      }
      if (token == null) return;
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ContratSignaturePage(token: token),
        ));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _marquerTermine(Map<String, dynamic> rdv) async {
    try {
      await _supa.from('rdv').update({'statut': 'termine'}).eq('id', rdv['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  /// Facture une prestation de garde via le moteur commun `factures`
  /// (garde-journée multi-jours → une facture pour toute la période).
  Future<void> _facturerVisite(Map<String, dynamic> rdv) async {
    await facturerGardeDepuisRdv(context, rdv);
    if (mounted) await _load();
  }

  /// Validation de présence (registre légal garde à domicile) — l'animal est
  /// arrivé chez le prestataire : posé sur la ligne du 1er jour du séjour.
  Future<void> _validerArrivee(GardeSejour sejour) async {
    try {
      await _supa.from('rdv')
          .update({'arrivee_validee_le': DateTime.now().toIso8601String()})
          .eq('id', sejour.premierJour['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  /// L'animal est reparti — posé sur la ligne du dernier jour du séjour.
  Future<void> _validerDepart(GardeSejour sejour) async {
    try {
      await _supa.from('rdv')
          .update({'depart_valide_le': DateTime.now().toIso8601String()})
          .eq('id', sejour.dernierJour['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  static String _sejourStatutLabel(String statut) => switch (statut) {
        'termine' => 'Terminé',
        'en_garde' => 'En garde',
        _ => 'À venir',
      };

  List<List<String>> _registreRows(List<GardeSejour> sejours) {
    final fmt = DateFormat('dd/MM/yyyy');
    String d(DateTime? dt) => dt != null ? fmt.format(dt) : '—';
    return sejours.map((s) => [
          s.animalNom,
          (s.premierJour['_animal_espece'] as String?)?.isNotEmpty == true ? s.premierJour['_animal_espece'] as String : '—',
          (s.premierJour['_animal_race'] as String?)?.isNotEmpty == true ? s.premierJour['_animal_race'] as String : '—',
          (s.premierJour['_animal_puce'] as String?)?.isNotEmpty == true ? s.premierJour['_animal_puce'] as String : '—',
          s.clientNom,
          (s.premierJour['_client_tel'] as String?)?.isNotEmpty == true ? s.premierJour['_client_tel'] as String : '—',
          (s.premierJour['_client_email'] as String?)?.isNotEmpty == true ? s.premierJour['_client_email'] as String : '—',
          d(s.dateEntree),
          d(s.dateSortiePrevue),
          d(s.departValideLe),
          _sejourStatutLabel(s.statut),
        ]).toList();
  }

  static const _registreHeaders = [
    'Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Téléphone', 'Email',
    'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut',
  ];

  Future<void> _exportPdfRegistre(List<GardeSejour> sejours) async {
    if (sejours.isEmpty) return;
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final rows = _registreRows(sejours);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('REGISTRE GARDE À DOMICILE — ENTRÉES & SORTIES',
              style: pw.TextStyle(font: fontBold, fontSize: 11)),
          pw.Text('Édité le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        ]),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
      ]),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: _registreHeaders,
          data: rows,
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
          cellStyle: pw.TextStyle(font: font, fontSize: 6.5),
          cellAlignments: {for (var i = 0; i < _registreHeaders.length; i++) i: pw.Alignment.centerLeft},
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  DateTime _itemStartDate(dynamic item) => item is GardeSejour
      ? item.dateEntree
      : DateTime.tryParse((item as Map)['date_heure']?.toString() ?? '') ?? DateTime(0);
  DateTime _itemEndDate(dynamic item) =>
      item is GardeSejour ? item.dateSortiePrevue : _itemStartDate(item);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Gardes-journée (hébergement chez le prestataire) regroupées en séjours ;
    // le reste (promenades/visites, l'animal reste chez son propriétaire)
    // affiché individuellement, comme avant.
    final tousSejours = groupeGardeSejours(_visites);
    final sejoursActifs = tousSejours.where((s) => s.statut != 'termine').toList();
    final sejoursTermines = tousSejours.where((s) => s.statut == 'termine').toList()
      ..sort((a, b) => b.dateSortiePrevue.compareTo(a.dateSortiePrevue));

    final visitesSimples = _visites.where((r) => !estGardeJournee(r)).toList();
    final aVenirSimples = visitesSimples.where((r) {
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '');
      return r['statut'] != 'termine' && (dh == null || dh.isAfter(now));
    }).toList();
    final passeesSimples = visitesSimples.where((r) => !aVenirSimples.contains(r)).toList().reversed.toList();

    final aVenirItems = <dynamic>[...sejoursActifs, ...aVenirSimples]
      ..sort((a, b) => _itemStartDate(a).compareTo(_itemStartDate(b)));
    final passeesItems = <dynamic>[...sejoursTermines, ...passeesSimples]
      ..sort((a, b) => _itemEndDate(b).compareTo(_itemEndDate(a)));

    final clientsList = _clients.entries.toList()
      ..sort((a, b) => (a.value['nom'] as String).compareTo(b.value['nom'] as String));

    Widget content;
    if (_tab == 3) {
      content = _RegistreLegalView(
        sejours: tousSejours,
        onValiderArrivee: _validerArrivee,
        onValiderDepart: _validerDepart,
        onExportPdf: _exportPdfRegistre,
      );
    } else if (_tab == 2) {
      content = clientsList.isEmpty
          ? const _Empty('Aucun client — un RDV confirmé est requis.')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: clientsList.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                    child: Text(
                      'Un seul contrat de prestation par client — signé une fois, il couvre toutes ses gardes.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                final e = clientsList[i - 1];
                return _ClientContratCard(
                  nom: e.value['nom'] as String,
                  animaux: e.value['animaux'] as String? ?? '',
                  statut: e.value['doc_statut'] as String?,
                  onTap: () => _openClientContrat(e.key),
                );
              },
            );
    } else {
      final displayed = _tab == 1 ? passeesItems : aVenirItems;
      content = displayed.isEmpty
          ? _Empty(_tab == 1 ? 'Aucune visite passée' : 'Aucune visite à venir')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: displayed.length,
              itemBuilder: (_, i) {
                final item = displayed[i];
                if (item is GardeSejour) {
                  final factured = item.jours.any((j) => _facturedRdvIds.contains(j['id']?.toString()));
                  return _SejourTourneeCard(
                    sejour: item,
                    factured: factured,
                    onValiderArrivee: () => _validerArrivee(item),
                    onValiderDepart: () => _validerDepart(item),
                    onFacturer: factured ? null : () => _facturerVisite(item.dernierJour),
                  );
                }
                final rdv = item as Map<String, dynamic>;
                return _VisiteCard(
                  rdv: rdv,
                  factured: _facturedRdvIds.contains(rdv['id']?.toString()),
                  onTerminer: () => _marquerTermine(rdv),
                  onRapport: () => sendGardeNews(context, rdv),
                  onFacturer: rdv['statut'] == 'termine'
                      ? () => _facturerVisite(rdv)
                      : null,
                  onContrat: () {
                    final cu = rdv['client_uid']?.toString();
                    if (cu != null && cu.isNotEmpty) _openClientContrat(cu, rdv);
                  },
                );
              },
            );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Registre visites',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in [
                  (0, 'À venir (${aVenirItems.length})'),
                  (1, 'Passées (${passeesItems.length})'),
                  (2, 'Mes contrats (${clientsList.length})'),
                  (3, 'Registre (${tousSejours.length})'),
                ]) ...[
                  _TabChip(label: t.$2, selected: _tab == t.$1,
                      onTap: () => setState(() => _tab = t.$1)),
                  if (t.$1 != 3) const SizedBox(width: 8),
                ],
              ]),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(onRefresh: _load, child: content),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)),
      );
}

class _ClientContratCard extends StatelessWidget {
  final String nom;
  final String animaux;
  final String? statut;
  final VoidCallback onTap;
  static const _teal = Color(0xFF0C5C6C);
  const _ClientContratCard({required this.nom, required this.animaux, required this.statut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (statut) {
      'signe' => ('Signé', const Color(0xFF6E9E57)),
      'partiellement_signe' => ('Partiellement signé', const Color(0xFF3E7CB1)),
      'en_attente' => ('En attente de signature', const Color(0xFFCA8A04)),
      null => ('À générer', Colors.grey),
      _ => (statut!, Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.draw_outlined, color: _teal),
        title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (animaux.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(animaux, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            ),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color)),
        ]),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF0C5C6C) : Colors.white)),
        ),
      );
}

class _VisiteCard extends StatelessWidget {
  final Map<String, dynamic> rdv;
  final bool factured;
  final VoidCallback onTerminer;
  final VoidCallback onRapport;
  final VoidCallback? onFacturer;
  final VoidCallback onContrat;
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _VisiteCard({
    required this.rdv,
    required this.onTerminer,
    required this.onRapport,
    required this.onContrat,
    this.onFacturer,
    this.factured = false,
  });

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '');
    final dateStr = dh != null ? DateFormat('EEE d MMM · HH:mm', 'fr_FR').format(dh) : '';
    final isTermine = rdv['statut'] == 'termine';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${rdv['_animal_nom']} — ${rdv['_client_nom']}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text('🚶 ${gardeMotifLabel(gardePrestationKey(rdv['motif']?.toString()), rdv['_animal_espece']?.toString())} · animal chez son propriétaire',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isTermine ? const Color(0xFFEEF5EA) : const Color(0xFFE8F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(isTermine ? 'Terminée' : 'Confirmée',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                      color: isTermine ? const Color(0xFF6E9E57) : _teal)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (!isTermine)
              Expanded(
                child: OutlinedButton(
                  onPressed: onTerminer,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                  child: const Text('Marquer terminée', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                ),
              ),
            if (!isTermine) const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: onRapport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 0,
                ),
                child: const Text('Rapport de visite', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ),
            IconButton(
              onPressed: onContrat,
              tooltip: 'Contrat de prestation',
              icon: const Icon(Icons.draw_outlined, size: 18, color: _teal),
            ),
          ]),
          if (isTermine && (onFacturer != null || factured)) ...[
            const SizedBox(height: 8),
            factured
                ? Row(children: const [
                    Icon(Icons.check_circle_outline, size: 16, color: _green),
                    SizedBox(width: 6),
                    Text('Facturé', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w600, color: _green)),
                  ])
                : SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onFacturer,
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('Facturer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: const BorderSide(color: _green),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
          ],
        ]),
      ),
    );
  }
}

/// Carte "tournée" d'un séjour de garde à domicile (une par séjour, pas par
/// jour) : arrivée/départ à valider, jours intermédiaires sans action.
/// Une fois terminé : lecture seule + facturation (couvre tout le séjour,
/// cf. gardeJoursAFacturer).
class _SejourTourneeCard extends StatelessWidget {
  final GardeSejour sejour;
  final bool factured;
  final VoidCallback onValiderArrivee;
  final VoidCallback onValiderDepart;
  final VoidCallback? onFacturer;
  static const _teal = Color(0xFF0C5C6C);
  static const _amber = Color(0xFFCA8A04);
  static const _green = Color(0xFF6E9E57);

  const _SejourTourneeCard({
    required this.sejour,
    required this.onValiderArrivee,
    required this.onValiderDepart,
    this.factured = false,
    this.onFacturer,
  });

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM', 'fr_FR');
    final fCourt = DateFormat('d MMM', 'fr_FR');
    final periode = sejour.unSeulJour
        ? 'le ${f.format(sejour.dateEntree)}'
        : 'du ${f.format(sejour.dateEntree)} au ${f.format(sejour.dateSortiePrevue)}';
    final statut = sejour.statut;
    final statutLabel = statut == 'termine' ? 'Terminé' : statut == 'en_garde' ? 'En cours' : 'À venir';
    final statutColor = statut == 'termine' ? _teal : statut == 'en_garde' ? _green : _amber;
    final statutBg = statut == 'termine' ? const Color(0xFFE8F4F6) : statut == 'en_garde' ? const Color(0xFFEEF5EA) : const Color(0xFFFFF8E1);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _teal, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🏠 Garde à domicile — ${sejour.animalNom} — ${sejour.clientNom}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text('Chez vous $periode',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: statutBg, borderRadius: BorderRadius.circular(10)),
              child: Text(statutLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w600, color: statutColor)),
            ),
          ]),
          const SizedBox(height: 10),
          if (statut == 'a_venir')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onValiderArrivee,
                icon: const Icon(Icons.home_outlined, size: 16),
                label: const Text('Valider l\'arrivée', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8), elevation: 0,
                ),
              ),
            )
          else if (statut == 'en_garde') ...[
            if (sejour.arriveeValideeLe != null) ...[
              Row(children: [
                const Icon(Icons.check_circle_outline, size: 16, color: _green),
                const SizedBox(width: 6),
                Text('Arrivé le ${fCourt.format(sejour.arriveeValideeLe!)}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onValiderDepart,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Valider le départ', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal, side: const BorderSide(color: _teal),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ] else ...[
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 16, color: _teal),
              const SizedBox(width: 6),
              Text(
                sejour.departValideLe != null ? 'Départ le ${fCourt.format(sejour.departValideLe!)}' : 'Garde terminée',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600),
              ),
            ]),
            if (factured) ...[
              const SizedBox(height: 8),
              Row(children: const [
                Icon(Icons.check_circle_outline, size: 16, color: _green),
                SizedBox(width: 6),
                Text('Facturé', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w600, color: _green)),
              ]),
            ] else if (onFacturer != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onFacturer,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('Facturer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green, side: const BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

/// Onglet "Registre" — vue légale : uniquement les séjours de garde à
/// domicile (hébergement), jamais les promenades/visites. Filtre par
/// statut + export PDF (le CSV reste réservé au site, plus adapté à un
/// usage tableur que sur mobile).
class _RegistreLegalView extends StatefulWidget {
  final List<GardeSejour> sejours;
  final Future<void> Function(GardeSejour) onValiderArrivee;
  final Future<void> Function(GardeSejour) onValiderDepart;
  final Future<void> Function(List<GardeSejour>) onExportPdf;

  const _RegistreLegalView({
    required this.sejours,
    required this.onValiderArrivee,
    required this.onValiderDepart,
    required this.onExportPdf,
  });

  @override
  State<_RegistreLegalView> createState() => _RegistreLegalViewState();
}

class _RegistreLegalViewState extends State<_RegistreLegalView> {
  static const _teal = Color(0xFF0C5C6C);
  String _filtre = 'tous'; // a_venir | en_garde | termine | tous

  @override
  Widget build(BuildContext context) {
    final filtered = _filtre == 'tous'
        ? widget.sejours
        : widget.sejours.where((s) => s.statut == _filtre).toList();
    final sorted = filtered.toList()..sort((a, b) => b.dateEntree.compareTo(a.dateEntree));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in const [
                  ('a_venir', 'À venir'), ('en_garde', 'En garde'), ('termine', 'Terminés'), ('tous', 'Tous'),
                ]) ...[
                  ChoiceChip(
                    label: Text(f.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    selected: _filtre == f.$1,
                    onSelected: (_) => setState(() => _filtre = f.$1),
                    selectedColor: _teal,
                    labelStyle: TextStyle(color: _filtre == f.$1 ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: sorted.isEmpty ? null : () => widget.onExportPdf(sorted),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Exporter en PDF', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
          ),
        ),
      ),
      Expanded(
        child: sorted.isEmpty
            ? const _Empty('Aucun séjour de garde à domicile')
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: sorted.length,
                itemBuilder: (_, i) => _SejourRegistreCard(
                  sejour: sorted[i],
                  onValiderArrivee: () => widget.onValiderArrivee(sorted[i]),
                  onValiderDepart: () => widget.onValiderDepart(sorted[i]),
                ),
              ),
      ),
    ]);
  }
}

/// Ligne du registre légal : identité complète de l'animal (nom, espèce,
/// race, puce I-CAD) + coordonnées du client + dates d'entrée/sortie.
class _SejourRegistreCard extends StatelessWidget {
  final GardeSejour sejour;
  final VoidCallback onValiderArrivee;
  final VoidCallback onValiderDepart;
  static const _teal = Color(0xFF0C5C6C);
  static const _amber = Color(0xFFCA8A04);
  static const _green = Color(0xFF6E9E57);

  const _SejourRegistreCard({
    required this.sejour,
    required this.onValiderArrivee,
    required this.onValiderDepart,
  });

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd/MM/yyyy');
    final j = sejour.premierJour;
    final espece = (j['_animal_espece'] as String?) ?? '';
    final race = (j['_animal_race'] as String?) ?? '';
    final puce = (j['_animal_puce'] as String?) ?? '';
    final tel = (j['_client_tel'] as String?) ?? '';
    final email = (j['_client_email'] as String?) ?? '';
    final (label, color) = switch (sejour.statut) {
      'termine' => ('Terminé', _green),
      'en_garde' => ('En garde', _teal),
      _ => ('À venir', _amber),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(sejour.animalNom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
          if (espece.isNotEmpty || race.isNotEmpty || puce.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text([espece, race, if (puce.isNotEmpty) 'Puce $puce'].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 6),
          Text('👤 ${sejour.clientNom}${tel.isNotEmpty ? ' · $tel' : ''}${email.isNotEmpty ? ' · $email' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            'Entrée le ${f.format(sejour.dateEntree)}'
            '${sejour.departValideLe != null ? ' · Sortie le ${f.format(sejour.departValideLe!)}' : ' · Sortie prévue le ${f.format(sejour.dateSortiePrevue)}'}',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (sejour.statut != 'termine') ...[
            const SizedBox(height: 10),
            Row(children: [
              if (sejour.statut == 'a_venir')
                Expanded(
                  child: OutlinedButton(
                    onPressed: onValiderArrivee,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                    child: const Text('Valider l\'arrivée', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton(
                    onPressed: onValiderDepart,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                    child: const Text('Valider le départ', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
