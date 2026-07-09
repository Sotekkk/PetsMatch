import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AnimalFichePensionPage extends StatefulWidget {
  final String animalId;
  final String? animalNom;

  const AnimalFichePensionPage({
    super.key,
    required this.animalId,
    this.animalNom,
  });

  @override
  State<AnimalFichePensionPage> createState() => _AnimalFichePensionPageState();
}

class _AnimalFichePensionPageState extends State<AnimalFichePensionPage>
    with SingleTickerProviderStateMixin {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _purple = Color(0xFF7B5EA7);

  final _supa = Supabase.instance.client;
  late TabController _tabs;

  bool _loading = true;

  // Identity
  Map<String, dynamic>? _animal;

  // Health
  List<Map<String, dynamic>> _vaccinations    = [];
  List<Map<String, dynamic>> _vermifuges      = [];
  List<Map<String, dynamic>> _antiparasitaires = [];
  List<Map<String, dynamic>> _traitements     = [];
  List<Map<String, dynamic>> _allergies       = [];
  List<Map<String, dynamic>> _visites         = [];
  List<Map<String, dynamic>> _poids           = [];

  // Alimentation
  Map<String, dynamic>? _alimentation;

  // Propriétaire réel (animaux_proprietes → user_profiles) + séjour en cours
  // (pension_entrees) — au lieu du texte libre saisi manuellement à l'entrée.
  Map<String, dynamic>? _proprietaire;
  Map<String, dynamic>? _sejourActuel;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supa.from('animaux').select('*').eq('id', widget.animalId).single(),
        _supa.from('vaccinations').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('vermifuges').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('antiparasitaires').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('traitements').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('allergies').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('poids').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('visites').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('alimentations').select().eq('animal_id', widget.animalId).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _animal           = results[0] as Map<String, dynamic>?;
        _vaccinations     = _toList(results[1]);
        _vermifuges       = _toList(results[2]);
        _antiparasitaires = _toList(results[3]);
        _traitements      = _toList(results[4]);
        _allergies        = _toList(results[5]);
        _poids            = _toList(results[6]);
        _visites          = _toList(results[7]);
        _alimentation     = results[8] as Map<String, dynamic>?;
        _loading          = false;
      });

      // Propriétaire réel + séjour en cours — chargés à part, ne doivent pas
      // bloquer l'affichage du reste de la fiche s'ils échouent.
      _loadProprietaireEtSejour();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProprietaireEtSejour() async {
    try {
      final lien = await _supa.from('animaux_proprietes').select()
          .eq('animal_id', widget.animalId).isFilter('date_fin', null)
          .order('date_debut', ascending: false).limit(1).maybeSingle();

      Map<String, dynamic>? profil;
      if (lien != null) {
        final profileId = lien['profile_id_proprio'] as String?;
        if (profileId != null && profileId.isNotEmpty) {
          profil = await _supa.from('user_profiles').select()
              .eq('id', profileId).maybeSingle();
        }
        // Repli : uid seul (données antérieures au multi-profil) → profil principal.
        profil ??= await _supa.from('user_profiles').select()
            .eq('uid', lien['uid_proprio']).eq('is_main', true).maybeSingle();

        // Repli téléphone : user_profiles.phone_number contient parfois le
        // placeholder "0000000000" jamais mis à jour depuis users (vraie donnée
        // saisie à l'inscription).
        final tel = (profil?['phone_number'] as String?)?.trim() ?? '';
        if (profil != null && (tel.isEmpty || tel == '0000000000')) {
          try {
            final u = await _supa.from('users').select('phone_number')
                .eq('uid', lien['uid_proprio']).maybeSingle();
            final uTel = (u?['phone_number'] as String?)?.trim() ?? '';
            if (uTel.isNotEmpty) profil = {...profil, 'phone_number': uTel};
          } catch (_) {}
        }
      }

      final sejour = await _supa.from('pension_entrees').select()
          .eq('animal_id', widget.animalId).eq('statut', 'en_pension')
          .order('date_entree', ascending: false).limit(1).maybeSingle();

      if (mounted) setState(() {
        _proprietaire = profil;
        _sejourActuel = sejour;
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> _toList(dynamic raw) =>
      raw is List ? List<Map<String, dynamic>>.from(raw) : [];

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso)); } catch (_) { return iso; }
  }

  static int? _ageMonths(String? iso) {
    if (iso == null) return null;
    try {
      final dob = DateTime.parse(iso);
      final now = DateTime.now();
      return (now.year - dob.year) * 12 + now.month - dob.month;
    } catch (_) { return null; }
  }

  static String _ageStr(String? iso) {
    final m = _ageMonths(iso);
    if (m == null) return '';
    if (m < 12) return '$m mois';
    final y = m ~/ 12;
    final rm = m % 12;
    return rm == 0 ? '$y an${y > 1 ? 's' : ''}' : '$y an${y > 1 ? 's' : ''} $rm mois';
  }

  @override
  Widget build(BuildContext context) {
    final nom = _animal?['nom'] ?? widget.animalNom ?? 'Animal';
    final espece = (_animal?['espece'] ?? '').toString();
    final photoUrl = _animal?['photo_url'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: Text(nom,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Identité'),
            Tab(text: 'Santé'),
            Tab(text: 'Alimentation'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : Column(children: [
              _ReadOnlyBanner(espece: espece, photoUrl: photoUrl),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _IdentiteTab(animal: _animal, proprietaire: _proprietaire, sejourActuel: _sejourActuel),
                  _SanteTab(
                    vaccinations: _vaccinations,
                    vermifuges: _vermifuges,
                    antiparasitaires: _antiparasitaires,
                    traitements: _traitements,
                    allergies: _allergies,
                    visites: _visites,
                    poids: _poids,
                    fmtDate: _fmtDate,
                  ),
                  _AlimentationTab(alimentation: _alimentation),
                ]),
              ),
            ]),
    );
  }
}

// ── Bannière lecture seule ────────────────────────────────────────────────────

class _ReadOnlyBanner extends StatelessWidget {
  final String espece;
  final String? photoUrl;

  const _ReadOnlyBanner({required this.espece, this.photoUrl});

  static const _purple = Color(0xFF7B5EA7);

  @override
  Widget build(BuildContext context) {
    final emoji = {
      'chien': '🐕', 'chat': '🐈', 'lapin': '🐇',
      'oiseau': '🦜', 'cheval': '🐴', 'nac': '🐹',
    }[espece] ?? '🐾';

    return Container(
      color: _purple.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        if (photoUrl != null && photoUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photoUrl!,
              width: 40, height: 40, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _speciesIcon(emoji),
            ),
          )
        else
          _speciesIcon(emoji),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Accès lecture seule · Accordé par le propriétaire',
              style: TextStyle(
                  fontFamily: 'Galey', fontSize: 12,
                  color: _purple, fontWeight: FontWeight.w600)),
        ),
        const Icon(Icons.lock_outline_rounded, size: 16, color: _purple),
      ]),
    );
  }

  Widget _speciesIcon(String emoji) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      color: _purple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
  );
}

// ── Onglet Identité ────────────────────────────────────────────────────────────

class _IdentiteTab extends StatelessWidget {
  final Map<String, dynamic>? animal;
  final Map<String, dynamic>? proprietaire;
  final Map<String, dynamic>? sejourActuel;

  const _IdentiteTab({required this.animal, this.proprietaire, this.sejourActuel});

  // Le nom d'affichage diffère selon le type de profil propriétaire :
  // un éleveur/asso a un nom d'établissement (colonne "nom"), un particulier
  // un nom de personne (souvent aussi dans "nom", sinon firstname/lastname).
  static String _ownerName(Map<String, dynamic> p) {
    final nom = (p['nom'] as String?)?.trim();
    if (nom != null && nom.isNotEmpty) return nom;
    final label = (p['profile_label'] as String?)?.trim();
    if (label != null && label.isNotEmpty) return label;
    final full = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    return full.isNotEmpty ? full : 'Propriétaire';
  }

  static String? _ownerPhone(Map<String, dynamic> p) =>
      (p['phone_number'] as String?)?.trim().isNotEmpty == true ? p['phone_number'] as String
      : (p['phone'] as String?)?.trim().isNotEmpty == true ? p['phone'] as String
      : (p['telephone'] as String?)?.trim().isNotEmpty == true ? p['telephone'] as String
      : null;

  static String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso)); } catch (_) { return iso; }
  }

  static String _age(String? iso) {
    if (iso == null) return '';
    try {
      final dob = DateTime.parse(iso);
      final now = DateTime.now();
      final m = (now.year - dob.year) * 12 + now.month - dob.month;
      if (m < 12) return '$m mois';
      final y = m ~/ 12; final r = m % 12;
      return r == 0 ? '$y an${y > 1 ? 's' : ''}' : '$y an${y > 1 ? 's' : ''} $r mois';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    if (animal == null) {
      return const Center(child: Text('Données non disponibles',
          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    }
    final d = animal!;
    final dob = d['date_naissance'] as String?;
    final age = _age(dob);

    final contacts = d['contacts_urgence'];
    final urgList = contacts is List ? contacts : [];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [
      if (proprietaire != null) ...[
        _Section(title: 'Propriétaire', children: [
          _Row(proprietaire!['profile_type'] == 'eleveur' || proprietaire!['profile_type'] == 'association'
              ? 'Établissement' : 'Nom', _ownerName(proprietaire!)),
          _Row('Téléphone', _ownerPhone(proprietaire!)),
          _Row('Email', proprietaire!['email_contact']?.toString()),
        ]),
        const SizedBox(height: 16),
      ],
      if (sejourActuel != null) ...[
        _Section(title: 'Séjour en cours', children: [
          _Row('Entré le', _fmt(sejourActuel!['date_entree']?.toString())),
          _Row('Sortie prévue', _fmt(sejourActuel!['date_sortie_prevue']?.toString())),
          _Row('Logement', sejourActuel!['logement_id']?.toString()),
        ]),
        const SizedBox(height: 16),
      ],
      _Section(title: 'Informations générales', children: [
        _Row('Espèce',      _capitalise(d['espece']?.toString())),
        _Row('Race',        d['race']?.toString()),
        _Row('Sexe',        _sexeLabel(d['sexe']?.toString())),
        _Row('Stérilisé(e)', d['sterilise'] == true ? 'Oui' : 'Non'),
        _Row('Naissance',   dob != null ? '${_fmt(dob)}${age.isNotEmpty ? '  ·  $age' : ''}' : null),
        _Row('Couleur / robe', d['couleur']?.toString()),
        _Row('Type de poil', d['type_poil']?.toString()),
        _Row('Poids',       d['poids'] != null ? '${d['poids']} kg' : null),
        _Row('Taille',      d['taille'] != null ? '${d['taille']} cm' : null),
      ]),
      const SizedBox(height: 16),
      _Section(title: 'Identification', children: [
        _Row('Puce électronique',   d['identification']?.toString()),
        _Row('Passeport européen',  d['passeport_europeen']?.toString()),
      ]),
      if (d['notes'] != null && d['notes'].toString().isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Notes du propriétaire', children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(d['notes'].toString(),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5,
                    color: Color(0xFF374151))),
          ),
        ]),
      ],
      if (urgList.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Contacts d\'urgence', children: [
          for (final c in urgList)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 8),
                Text(
                  [(c['nom'] ?? ''), (c['tel'] ?? '')]
                      .where((s) => s.toString().isNotEmpty).join(' — '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                ),
              ]),
            ),
        ]),
      ],
    ]);
  }

  static String _capitalise(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _sexeLabel(String? s) {
    switch (s) {
      case 'male':   return 'Mâle';
      case 'femelle': return 'Femelle';
      default: return s ?? '';
    }
  }
}

// ── Onglet Santé ──────────────────────────────────────────────────────────────

class _SanteTab extends StatelessWidget {
  final List<Map<String, dynamic>> vaccinations;
  final List<Map<String, dynamic>> vermifuges;
  final List<Map<String, dynamic>> antiparasitaires;
  final List<Map<String, dynamic>> traitements;
  final List<Map<String, dynamic>> allergies;
  final List<Map<String, dynamic>> visites;
  final List<Map<String, dynamic>> poids;
  final String Function(String?) fmtDate;

  const _SanteTab({
    required this.vaccinations,
    required this.vermifuges,
    required this.antiparasitaires,
    required this.traitements,
    required this.allergies,
    required this.visites,
    required this.poids,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [
      // Allergies en tête (important pour la pension)
      _HealthSection(
        title: 'Allergies',
        color: const Color(0xFFFF9800),
        icon: Icons.warning_amber_rounded,
        items: allergies,
        buildRow: (a) => _MedRow(
          label: a['description']?.toString() ?? a['allergene']?.toString() ?? '',
          sub: [a['type']?.toString(), a['severite']?.toString()]
              .where((s) => s != null && s.isNotEmpty).join(' · '),
          date: fmtDate(a['date'] as String?),
        ),
      ),
      const SizedBox(height: 16),

      // Vaccinations
      _HealthSection(
        title: 'Vaccinations',
        color: const Color(0xFF2196F3),
        icon: Icons.vaccines_outlined,
        items: vaccinations,
        buildRow: (v) => _MedRow(
          label: v['vaccin']?.toString() ?? v['nom_vaccin']?.toString() ?? '',
          sub: v['veterinaire']?.toString(),
          date: fmtDate(v['date'] as String?),
          extra: v['date_rappel'] != null ? 'Rappel : ${fmtDate(v['date_rappel'] as String?)}' : null,
        ),
      ),
      const SizedBox(height: 16),

      // Traitements (toujours visible)
      _HealthSection(
        title: 'Traitements',
        color: const Color(0xFF9C27B0),
        icon: Icons.medication_outlined,
        items: traitements,
        buildRow: (t) => _MedRow(
          label: t['nom']?.toString() ?? t['type']?.toString() ?? '',
          sub: t['posologie']?.toString(),
          date: fmtDate(t['date'] as String?),
          extra: t['date_fin'] != null ? 'Fin : ${fmtDate(t['date_fin'] as String?)}' : null,
        ),
      ),
      const SizedBox(height: 16),

      // Visites vétérinaires
      _HealthSection(
        title: 'Visites vétérinaires',
        color: const Color(0xFFF44336),
        icon: Icons.local_hospital_outlined,
        items: visites,
        buildRow: (v) => _MedRow(
          label: v['motif']?.toString() ?? 'Consultation',
          sub: v['veterinaire']?.toString(),
          date: fmtDate(v['date'] as String?),
          extra: (v['diagnostic'] ?? '').toString().isNotEmpty ? v['diagnostic'].toString() : null,
        ),
      ),
      const SizedBox(height: 16),

      // Vermifuges
      _HealthSection(
        title: 'Vermifugations',
        color: const Color(0xFF795548),
        icon: Icons.pest_control_outlined,
        items: vermifuges,
        buildRow: (v) => _MedRow(
          label: v['produit']?.toString() ?? '',
          sub: v['dosage']?.toString() ?? v['remarques']?.toString(),
          date: fmtDate(v['date'] as String?),
          extra: v['date_rappel'] != null ? 'Rappel : ${fmtDate(v['date_rappel'] as String?)}' : null,
        ),
      ),
      const SizedBox(height: 16),

      // Antiparasitaires
      _HealthSection(
        title: 'Antiparasitaires',
        color: const Color(0xFF4CAF50),
        icon: Icons.bug_report_outlined,
        items: antiparasitaires,
        buildRow: (a) => _MedRow(
          label: a['produit']?.toString() ?? '',
          sub: a['type']?.toString(),
          date: fmtDate(a['date'] as String?),
          extra: a['date_rappel'] != null ? 'Rappel : ${fmtDate(a['date_rappel'] as String?)}' : null,
        ),
      ),
      const SizedBox(height: 16),

      // Poids récent (collapsible)
      if (poids.isNotEmpty) _PoidsSection(poids: poids, fmtDate: fmtDate),
    ]);
  }
}

// ── Section poids collapsible ────────────────────────────────────────────────

class _PoidsSection extends StatefulWidget {
  final List<Map<String, dynamic>> poids;
  final String Function(String?) fmtDate;

  const _PoidsSection({required this.poids, required this.fmtDate});

  @override
  State<_PoidsSection> createState() => _PoidsSectionState();
}

class _PoidsSectionState extends State<_PoidsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.poids]..sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return db.compareTo(da); // plus récent en premier
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              const Icon(Icons.monitor_weight_outlined, size: 18, color: Color(0xFF0C5C6C)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Suivi du poids',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 13, color: Color(0xFF6B7280), letterSpacing: 0.3))),
              // Dernière valeur connue
              if (sorted.isNotEmpty) () {
                final v = double.tryParse(sorted.first['valeur']?.toString() ?? '');
                return v != null ? Text('${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)} kg',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E))) : const SizedBox.shrink();
              }(),
              const SizedBox(width: 6),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: Colors.grey.shade400),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          for (final p in sorted.take(10)) () {
            final v = double.tryParse(p['valeur']?.toString() ?? '');
            if (v == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(widget.fmtDate(p['date'] as String?),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                          color: Color(0xFF6B7280))),
                  Text('${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)} kg',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 14, color: Color(0xFF1F2A2E))),
                ]),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
              ]),
            );
          }(),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }
}

// ── Onglet Alimentation ───────────────────────────────────────────────────────

class _AlimentationTab extends StatelessWidget {
  final Map<String, dynamic>? alimentation;

  const _AlimentationTab({required this.alimentation});

  static const _teal = Color(0xFF0C5C6C);

  static Widget _statChip(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: const Color(0xFF0C5C6C).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
            fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
      ]),
    ),
  );

  static String _rationLabel(String? t) {
    switch (t) {
      case 'croquettes': return 'Croquettes';
      case 'barf':       return 'BARF (viande crue)';
      case 'mixte':      return 'Mixte';
      case 'menagere':   return 'Ration ménagère';
      case 'paturage':   return 'Pâturage';
      case 'foin':       return 'Foin';
      case 'complement': return 'Complément';
      case 'granules':   return 'Granulés';
      default:           return t ?? '';
    }
  }

  static String _activiteLabel(String? a) {
    switch (a) {
      case 'repos':       return 'Repos / faible';
      case 'leger':       return 'Léger';
      case 'modere':      return 'Modéré';
      case 'actif':       return 'Actif';
      case 'tres_actif':  return 'Très actif';
      default:            return a ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (alimentation == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.restaurant_menu_outlined, size: 48, color: Color(0xFFCCCCCC)),
          SizedBox(height: 12),
          Text('Aucune information sur l\'alimentation',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey)),
        ]),
      );
    }

    final a = alimentation!;
    final ration      = a['type_ration']?.toString();
    final activite    = a['niveau_activite']?.toString();
    final marque      = a['marque']?.toString() ?? '';
    final gamme       = a['gamme']?.toString() ?? '';
    final reference   = a['reference_produit']?.toString() ?? '';
    final complements = a['complements']?.toString() ?? '';

    // Le champ "notes" encode l'état du calculateur :
    // [0]=pctFoin [1]=pctGran [2]=pctComp [3]=nb_repas [4]=separe
    // [5]=dose_manuelle_g [6]=dose2 [7]=typeMixte2 ...
    final notesRaw = a['notes']?.toString() ?? '';
    final notesParts = notesRaw.contains('|') ? notesRaw.split('|') : <String>[];

    // nb_repas : colonne dédiée OU position [3] dans notes
    final nbRepasRaw = a['nb_repas'];
    int nbRepas = nbRepasRaw is num ? nbRepasRaw.round()
        : int.tryParse(nbRepasRaw?.toString() ?? '') ?? 0;
    if (nbRepas == 0 && notesParts.length > 3) {
      nbRepas = int.tryParse(notesParts[3]) ?? 0;
    }

    // ration_grammes : colonne dédiée OU dose manuelle dans notes[5]
    final rationGRaw    = a['ration_grammes'];
    final rationKcalRaw = a['ration_kcal'];
    int totalG = rationGRaw != null
        ? (double.tryParse(rationGRaw.toString()) ?? 0).round() : 0;
    if (totalG == 0 && notesParts.length > 5) {
      totalG = (double.tryParse(notesParts[5]) ?? 0).round();
    }
    final totalKcal = rationKcalRaw != null
        ? (double.tryParse(rationKcalRaw.toString()) ?? 0).round() : 0;

    // Composant 2 pour ration mixte (chien/chat)
    // notes[0]=pctCroq, [4]=separe, [6]=dose2_g, [7]=typeMixte2
    final isMixte   = ration == 'mixte';
    final pctCroq   = notesParts.isNotEmpty ? (double.tryParse(notesParts[0]) ?? 0) : 0.0;
    final separe    = notesParts.length > 4 && notesParts[4] == '1';
    final dose2     = notesParts.length > 6 ? (double.tryParse(notesParts[6]) ?? 0).round() : 0;
    final typeMixte2 = (notesParts.length > 7 && notesParts[7].isNotEmpty) ? notesParts[7] : 'patee';
    final secondLabel = typeMixte2 == 'barf' ? 'BARF'
        : typeMixte2 == 'menagere' ? 'Ration ménagère' : 'Pâtée';
    final secondEmoji = typeMixte2 == 'barf' ? '🥩'
        : typeMixte2 == 'menagere' ? '🍲' : '🥫';

    // Labels repas identiques à la fiche éleveur
    const repasLabels = [
      ['Repas unique 🍽️'],
      ['Matin 🌅', 'Soir 🌇'],
      ['Matin 🌅', 'Midi ☀️', 'Soir 🌇'],
      ['Matin 🌅', 'Midi ☀️', 'Après-midi 🌤️', 'Soir 🌇'],
    ];
    const mealColors = [
      Color(0xFF0C5C6C), Color(0xFF6E9E57),
      Color(0xFFB8860B), Color(0xFF8D6E63),
    ];

    final produitLabel = [
      if (marque.isNotEmpty) marque,
      if (gamme.isNotEmpty) gamme,
    ].join(' — ');
    final rationEmoji = const {
      'croquettes': '🥜', 'barf': '🥩', 'mixte': '🥜',
      'menagere': '🍲', 'foin': '🌾', 'paturage': '🌿',
      'granules': '🌾', 'complement': '💊',
    }[ration ?? ''] ?? '🍽️';

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [

      // ── Carte produit ─────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(rationEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                produitLabel.isNotEmpty ? produitLabel : _rationLabel(ration),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                    fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)),
              ),
              if (produitLabel.isNotEmpty && ration != null && ration.isNotEmpty)
                Text(_rationLabel(ration),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ])),
            if (activite != null && activite.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_activiteLabel(activite),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                        fontWeight: FontWeight.w600, color: _teal)),
              ),
          ]),
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Réf. $reference',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ],
          const Divider(height: 18),
          // Totaux journaliers
          Row(children: [
            _statChip(
              isMixte ? '🥜 Croquettes/jour' : '📦 Quantité/jour',
              totalG > 0 ? '$totalG g' : 'Non renseigné',
            ),
            const SizedBox(width: 10),
            if (isMixte && dose2 > 0)
              _statChip('$secondEmoji $secondLabel/jour', '$dose2 g')
            else if (totalKcal > 0)
              _statChip('🔥 Énergie/jour', '$totalKcal kcal'),
          ]),
        ]),
      ),

      // ── Cartes repas (Matin / Midi / Soir) ───────────────────────────────
      const SizedBox(height: 16),
      Row(children: [
        const Text('Rations journalières',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF1F2A2E))),
        const Spacer(),
        if (nbRepas > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text('$nbRepas repas/jour',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                    fontWeight: FontWeight.w600, color: _teal)),
          ),
      ]),
      const SizedBox(height: 10),

      if (nbRepas > 0 && (totalG > 0 || (isMixte && dose2 > 0))) ...[
        ...List.generate(nbRepas.clamp(1, 4), (i) {
          final labels_ = repasLabels[(nbRepas.clamp(1, 4)) - 1];
          final label   = labels_[i];
          final color   = mealColors[i % 4];

          // Build items list for this meal
          final List<Map<String, String>> items;
          if (isMixte) {
            if (separe && nbRepas >= 2) {
              final nCroq = ((nbRepas * pctCroq / 100).round()).clamp(1, nbRepas - 1);
              if (i < nCroq) {
                final rcPar = totalG > 0 ? (totalG / nCroq).round() : 0;
                items = rcPar > 0
                    ? [{'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : 'Croquettes', 'qte': '$rcPar g'}]
                    : [];
              } else {
                final nSec = nbRepas - nCroq;
                final rsPar = dose2 > 0 ? (dose2 / nSec).round() : 0;
                items = rsPar > 0
                    ? [{'emoji': secondEmoji, 'label': secondLabel, 'qte': '$rsPar g'}]
                    : [];
              }
            } else {
              final rcPar = totalG > 0 ? (totalG / nbRepas).round() : 0;
              final rsPar = dose2 > 0 ? (dose2 / nbRepas).round() : 0;
              items = [
                if (rcPar > 0) {'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : 'Croquettes', 'qte': '$rcPar g'},
                if (rsPar > 0) {'emoji': secondEmoji, 'label': secondLabel, 'qte': '$rsPar g'},
              ];
            }
          } else {
            final qteG = (totalG / nbRepas).round();
            items = [{'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : _rationLabel(ration), 'qte': '$qteG g'}];
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Text(label, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(children: [
                  Text(item['emoji']!, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item['label']!,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(item['qte']!,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                            fontWeight: FontWeight.w700, color: _teal)),
                  ),
                ]),
              )),
              const SizedBox(height: 2),
            ]),
          );
        }),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Expanded(child: Text(
              nbRepas == 0
                  ? 'Nombre de repas non renseigné par le propriétaire'
                  : 'Quantité journalière non renseignée par le propriétaire',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
            )),
          ]),
        ),
      ],

      // ── Compléments ──────────────────────────────────────────────────────
      if (complements.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Compléments alimentaires', children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(complements,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
          ),
        ]),
      ],
    ]);
  }
}

// ── Composants partagés ───────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Text(title,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF6B7280), letterSpacing: 0.3)),
      ),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 8),
    ]),
  );
}

class _Row extends StatelessWidget {
  final String? label;
  final String? value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 130,
              child: Text(label ?? '', style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF))),
            ),
            Expanded(child: Text(value!, style: const TextStyle(
                fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E),
                fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
      ]),
    );
  }
}

class _HealthSection extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) buildRow;

  const _HealthSection({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
    required this.buildRow,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 14, color: color)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${items.length}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text('Aucun enregistrement',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
        )
      else ...[
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        for (final item in items) buildRow(item),
      ],
    ]),
  );
}

class _MedRow extends StatelessWidget {
  final String label;
  final String? sub;
  final String date;
  final String? extra;

  const _MedRow({
    required this.label,
    required this.date,
    this.sub,
    this.extra,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)))),
        Text(date,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
      ]),
      if (sub != null && sub!.isNotEmpty)
        Text(sub!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
            color: Color(0xFF6B7280))),
      if (extra != null)
        Text(extra!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
            color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
    ]),
  );
}
