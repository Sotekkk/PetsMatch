import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Types d'actes ──────────────────────────────────────────────────────────────

const _kActeTypes = [
  (value: 'vaccination',     label: 'Vaccination',          icon: Icons.vaccines_outlined,          color: Color(0xFFE8F5E9)),
  (value: 'visite',          label: 'Visite vétérinaire',   icon: Icons.medical_services_outlined,  color: Color(0xFFE3F2FD)),
  (value: 'traitement',      label: 'Traitement',           icon: Icons.medication_outlined,        color: Color(0xFFE0F2F1)),
  (value: 'vermifuge',       label: 'Vermifuge',            icon: Icons.bug_report_outlined,        color: Color(0xFFFFF8E1)),
  (value: 'antiparasitaire', label: 'Antiparasitaire',      icon: Icons.pest_control_outlined,      color: Color(0xFFFFF3E0)),
  (value: 'osteopathie',     label: 'Ostéopathie',          icon: Icons.self_improvement_outlined,  color: Color(0xFFF3E5F5)),
  (value: 'ferrage',         label: 'Ferrage',              icon: Icons.hardware_outlined,          color: Color(0xFFEFEBE9)),
  (value: 'radiographie',    label: 'Radiographie',         icon: Icons.camera_alt_outlined,        color: Color(0xFFECEFF1)),
  (value: 'chirurgie',       label: 'Chirurgie',            icon: Icons.healing_outlined,           color: Color(0xFFFFEBEE)),
  (value: 'autre',           label: 'Autre',                icon: Icons.more_horiz,                 color: Color(0xFFF5F5F5)),
];

typedef _ActeType = ({String value, String label, IconData icon, Color color});

_ActeType _typeFor(String? v) =>
    _kActeTypes.firstWhere((t) => t.value == v, orElse: () => _kActeTypes.last);

String _espLabel(String e) {
  const m = {
    'chien': 'Chien', 'chat': 'Chat', 'cheval': 'Cheval', 'lapin': 'Lapin',
    'ovin': 'Ovin', 'caprin': 'Caprin', 'porcin': 'Porcin', 'nac': 'NAC',
    'oiseau': 'Oiseau', 'autre': 'Autre',
  };
  return m[e] ?? e;
}

// ── Helper public — appelé depuis animal_fiche.dart ────────────────────────────

class RegistreHelper {
  static Future<void> writeActe({
    required String animalId,
    required String typeActe,
    required DateTime dateActe,
    required String intervenant,
    required String description,
    String ordonnanceNum = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final supa = Supabase.instance.client;
      final rows = await supa.from('animaux')
          .select('nom, espece, date_naissance, identification, sexe')
          .eq('id', animalId);
      final d = (rows as List).isNotEmpty ? (rows.first as Map<String, dynamic>) : <String, dynamic>{};
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await supa.from('registre_sanitaire').insert({
        'id':             id,
        'uid_eleveur':    uid,
        if (User_Info.activeProfileId != null) 'eleveur_profile_id': User_Info.activeProfileId,
        'animal_id':      animalId,
        'animal_nom':     (d['nom'] ?? '') as String,
        'espece':         (d['espece'] ?? '') as String,
        'date_naissance': d['date_naissance'],
        'identification': (d['identification'] ?? '') as String,
        'sexe':           (d['sexe'] ?? '') as String,
        'date_acte':      dateActe.toIso8601String(),
        'type_acte':      typeActe,
        'intervenant':    intervenant,
        'description':    description,
        'ordonnance_num': ordonnanceNum,
        'profil_source':  (User_Info.activeType == 'association' || User_Info.isAssociation) ? 'association' : 'eleveur',
      });
    } catch (_) {}
  }
}

// ── Page principale ────────────────────────────────────────────────────────────

class RegistreSanitairePage extends StatefulWidget {
  final bool isAssociation;
  const RegistreSanitairePage({super.key, this.isAssociation = false});

  @override
  State<RegistreSanitairePage> createState() => _RegistreSanitairePageState();
}

class _RegistreSanitairePageState extends State<RegistreSanitairePage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  String? _filterEspece; // null = tous
  String? _filterType;   // null = tous
  bool _exporting   = false;
  bool _planLoading = true;
  bool _hasRegistres = false;

  // IDs des animaux association (chargés si isAssociation = true)
  Set<String> _assoAnimalIds = {};
  bool _assoIdsLoaded = false;

  @override
  void initState() {
    super.initState();
    _checkPlan();
    if (widget.isAssociation) _loadAssoAnimalIds();
  }

  Future<void> _loadAssoAnimalIds() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('animaux')
          .select('id')
          .eq('uid_eleveur', uid)
          .inFilter('statut', ['en_soin', 'disponible', 'en_fa', 'adopte', 'transfere', 'decede']);
      final ids = (rows as List).map((r) => r['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      if (mounted) setState(() { _assoAnimalIds = ids; _assoIdsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _assoIdsLoaded = true);
    }
  }

  Future<void> _checkPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _planLoading = false); return; }
    final code   = await PlanService.getPlanCode(uid);
    final config = PlanService.getConfig(code);
    if (!mounted) return;
    setState(() { _hasRegistres = config.hasRegistres; _planLoading = false; });
  }

  int get _activeFilterCount =>
      (_filterEspece != null ? 1 : 0) + (_filterType != null ? 1 : 0);

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _openFilterSheet() async {
    Set<String> availableEspeces = {};
    try {
      final rows = await Supabase.instance.client
          .from('registre_sanitaire')
          .select('espece')
          .eq('uid_eleveur', _uid);
      for (final row in (rows as List)) {
        final esp = (row['espece'] as String?) ?? '';
        if (esp.isNotEmpty) availableEspeces.add(esp);
      }
    } catch (_) {}

    if (!mounted) return;

    String? tmpEspece = _filterEspece;
    String? tmpType   = _filterType;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [

            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            Row(children: [
              const Text('Filtrer le registre',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 17, color: Color(0xFF1F2A2E))),
              const Spacer(),
              if (tmpEspece != null || tmpType != null)
                TextButton(
                  onPressed: () {
                    setSheet(() { tmpEspece = null; tmpType = null; });
                    setState(() { _filterEspece = null; _filterType = null; });
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Réinitialiser',
                      style: TextStyle(fontFamily: 'Galey', color: _green)),
                ),
            ]),
            const SizedBox(height: 16),

            // ── Espèce ──────────────────────────────────────────────────────
            const Text('Espèce', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
                children: kSpeciesData.where((sp) =>
                    sp.value == 'tous' || availableEspeces.contains(sp.value))
                    .map((sp) {
                  final sel = sp.value == 'tous'
                      ? tmpEspece == null
                      : tmpEspece == sp.value;
                  return GestureDetector(
                    onTap: () {
                      final v = sp.value == 'tous' ? null : sp.value;
                      setSheet(() => tmpEspece = v);
                      setState(() => _filterEspece = v);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? sp.color : Colors.transparent,
                        border: Border.all(
                            color: sel ? sp.color : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (sp.value != 'tous') ...[
                          speciesIcon(sp.value, 13,
                              sel ? Colors.white : sp.color),
                          const SizedBox(width: 5),
                        ],
                        Text(sp.label,
                            style: TextStyle(
                                fontFamily: 'Galey', fontSize: 12,
                                color: sel ? Colors.white : Colors.black87,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ]),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 18),

            // ── Type d'acte ─────────────────────────────────────────────────
            const Text('Type d\'acte', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              // Chip "Tous"
              _typeChip(null, 'Tous', Icons.list, const Color(0xFFF0F0EE),
                  tmpType == null, (v) {
                setSheet(() => tmpType = v);
                setState(() => _filterType = v);
              }),
              ..._kActeTypes.map((t) => _typeChip(
                  t.value, t.label, t.icon, t.color,
                  tmpType == t.value, (v) {
                setSheet(() => tmpType = v);
                setState(() => _filterType = v);
              })),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  static Widget _typeChip(
    String? value, String label, IconData icon, Color bg,
    bool sel, ValueChanged<String?> onTap,
  ) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF0C5C6C) : Colors.transparent,
          border: Border.all(
              color: sel ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
              color: sel ? Colors.white : const Color(0xFF6F767B)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Galey', fontSize: 12,
                  color: sel ? Colors.white : Colors.black87,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    setState(() => _exporting = true);
    try {
      var allRows = await Supabase.instance.client
          .from('registre_sanitaire')
          .select()
          .eq('uid_eleveur', uid)
          .order('date_acte', ascending: true);
      var docsList = List<Map<String, dynamic>>.from(allRows as List);
      if (_filterEspece != null) {
        docsList = docsList.where((d) => d['espece'] == _filterEspece).toList();
      }
      if (_filterType != null) {
        docsList = docsList.where((d) => d['type_acte'] == _filterType).toList();
      }
      if (!mounted) return;
      if (docsList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aucun acte à exporter',
                style: TextStyle(fontFamily: 'Galey'))));
        return;
      }

      final font     = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final fmt      = DateFormat('dd/MM/yyyy');
      final logo = pw.MemoryImage(
          (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png')).buffer.asUint8List());

      final headers = ['Animal', 'Espèce', 'Né(e) le', 'Identification', 'Sexe',
          'Date acte', 'Type', 'Intervenant', 'Description', 'N° ordonnance'];

      String _fmtDate(String? s) {
        if (s == null || s.isEmpty) return '—';
        final dt = DateTime.tryParse(s);
        return dt != null ? fmt.format(dt) : s;
      }

      final rows = docsList.map((d) => [
        (d['animal_nom']    as String?) ?? '—',
        _espLabel((d['espece'] as String?) ?? ''),
        _fmtDate(d['date_naissance'] as String?),
        (d['identification'] as String?) ?? '—',
        (d['sexe']           as String?) ?? '—',
        _fmtDate(d['date_acte'] as String?),
        _typeFor(d['type_acte'] as String?).label,
        (d['intervenant']    as String?) ?? '—',
        (d['description']    as String?) ?? '—',
        (d['ordonnance_num'] as String?) ?? '—',
      ]).toList();

      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
            pw.Image(logo, width: 32, height: 32),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
              pw.Text('REGISTRE SANITAIRE',
                  style: pw.TextStyle(font: fontBold, fontSize: 12)),
              pw.Text('Édité le ${fmt.format(DateTime.now())}',
                  style: pw.TextStyle(font: font, fontSize: 8,
                      color: PdfColors.grey600)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 4),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(font: fontBold, fontSize: 7,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0C5C6C)),
            cellStyle: pw.TextStyle(font: font, fontSize: 6.5),
            cellAlignments: {
              for (var i = 0; i < headers.length; i++)
                i: pw.Alignment.centerLeft
            },
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F5F5)),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4, vertical: 3),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6), // Animal
              1: const pw.FlexColumnWidth(0.9), // Espèce
              2: const pw.FlexColumnWidth(0.9), // Né(e) le
              3: const pw.FlexColumnWidth(1.2), // Identification
              4: const pw.FlexColumnWidth(0.6), // Sexe
              5: const pw.FlexColumnWidth(0.9), // Date acte
              6: const pw.FlexColumnWidth(1.4), // Type
              7: const pw.FlexColumnWidth(1.4), // Intervenant
              8: const pw.FlexColumnWidth(2.4), // Description
              9: const pw.FlexColumnWidth(1.2), // N° ordonnance
            },
          ),
        ],
      ));

      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur export : $e',
                style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_planLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C))),
      );
    }
    if (!_hasRegistres) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F6),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0C5C6C),
          foregroundColor: Colors.white,
          title: const Text('Registre sanitaire',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔒', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text('Fonctionnalité Pro',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 22, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 8),
              const Text(
                'Le registre sanitaire est réservé aux éleveurs avec un plan payant.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AbonnementPage())),
                  icon: const Text('⚡', style: TextStyle(fontSize: 18)),
                  label: const Text('Voir les plans',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5C6C), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Registre sanitaire',
            style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _exportPdf,
              tooltip: 'Exporter PDF',
            ),
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                onPressed: _openFilterSheet,
                tooltip: 'Filtrer',
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                        border: Border.all(color: _teal, width: 1.5)),
                    child: Center(
                      child: Text('$_activeFilterCount',
                          style: const TextStyle(
                              fontFamily: 'Galey', fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _RegistreList(
        filterEspece: _filterEspece,
        filterType: _filterType,
        isAssociation: widget.isAssociation,
        assoAnimalIds: _assoAnimalIds,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouvel acte',
            style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, color: Colors.white)),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const _NouvelActePage())),
      ),
    );
  }
}

// ── Liste des actes ────────────────────────────────────────────────────────────

class _RegistreList extends StatelessWidget {
  final String? filterEspece;
  final String? filterType;
  final bool isAssociation;
  final Set<String> assoAnimalIds;
  const _RegistreList({this.filterEspece, this.filterType, this.isAssociation = false, this.assoAnimalIds = const {}});

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('registre_sanitaire')
          .stream(primaryKey: ['id'])
          .eq('uid_eleveur', _uid)
          .order('date_acte', ascending: false),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snap.data ?? [];
        if (isAssociation) {
          docs = docs.where((d) => d['profil_source'] == 'association').toList();
        } else {
          docs = docs.where((d) {
            final ps = d['profil_source'] as String?;
            return ps == null || ps == 'eleveur';
          }).toList();
        }
        if (filterEspece != null) {
          docs = docs.where((d) => d['espece'] == filterEspece).toList();
        }
        if (filterType != null) {
          docs = docs.where((d) => d['type_acte'] == filterType).toList();
        }
        final filtered = filterEspece != null || filterType != null;
        if (docs.isEmpty) return _EmptyState(filtered: filtered);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) => _ActeCard(
            doc: docs[i],
            onDelete: () => _confirmDelete(ctx, docs[i]),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet acte ?',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(
                      fontFamily: 'Galey', color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client
          .from('registre_sanitaire').delete().eq('id', doc['id']);
    }
  }
}

// ── Carte acte ─────────────────────────────────────────────────────────────────

class _ActeCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onDelete;
  const _ActeCard({required this.doc, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final data        = doc;
    final type        = _typeFor(data['type_acte'] as String?);
    final nom         = (data['animal_nom'] as String?) ?? '—';
    final espece      = (data['espece'] as String?) ?? '';
    final sexe        = (data['sexe'] as String?) ?? '';
    final intervenant = (data['intervenant'] as String?) ?? '';
    final ds          = data['date_acte'] as String?;
    final dateStr     = ds != null && ds.isNotEmpty
        ? (DateTime.tryParse(ds) != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(ds)) : ds)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDetail(context, data, type),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: type.color,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(type.icon, size: 22,
                    color: const Color(0xFF0C5C6C)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(nom,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 14, color: Color(0xFF1F2A2E)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(dateStr,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: Colors.grey.shade400)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: type.color,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(type.label,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0C5C6C))),
                  ),
                  if (espece.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(_espLabel(espece),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: Colors.grey.shade500)),
                  ],
                  if (sexe.isNotEmpty)
                    Text(' · $sexe',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: Colors.grey.shade500)),
                  if (intervenant.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('· $intervenant',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: Colors.grey.shade500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ]),
              ])),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> data,
      _ActeType type) {
    String _fmt(String? s) {
      if (s == null || s.isEmpty) return '—';
      final dt = DateTime.tryParse(s);
      return dt != null ? DateFormat('dd/MM/yyyy').format(dt) : s;
    }
    final dateStr = _fmt(data['date_acte'] as String?);
    final dnRaw   = data['date_naissance'] as String?;
    final dnStr   = (dnRaw != null && dnRaw.isNotEmpty) ? _fmt(dnRaw) : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: type.color,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(type.icon, size: 24,
                  color: const Color(0xFF0C5C6C)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['animalNom'] ?? '—',
                  style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 16)),
              Text(type.label,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: Colors.grey.shade500)),
            ])),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _detailRow('Date de l\'acte', dateStr),
          if (dnStr != null) _detailRow('Né(e) le', dnStr),
          if ((data['espece'] ?? '').isNotEmpty)
            _detailRow('Espèce', _espLabel(data['espece'] as String)),
          if ((data['sexe'] ?? '').isNotEmpty)
            _detailRow('Sexe', data['sexe'] as String),
          if ((data['identification'] ?? '').isNotEmpty)
            _detailRow('Identification', data['identification'] as String),
          if ((data['intervenant'] ?? '').isNotEmpty)
            _detailRow('Intervenant', data['intervenant'] as String),
          if ((data['description'] ?? '').isNotEmpty)
            _detailRow('Acte / description', data['description'] as String),
          if ((data['ordonnance_num'] ?? '').isNotEmpty)
            _detailRow('N° ordonnance', data['ordonnance_num'] as String),
        ]),
      ),
    );
  }

  static Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 145,
          child: Text(label,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600, color: Color(0xFF6F767B)))),
      Expanded(child: Text(value,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: Color(0xFF1F2A2E)))),
    ]),
  );
}

// ── État vide ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.health_and_safety_outlined, size: 56,
            color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Aucun acte pour ce filtre' : 'Aucun acte enregistré',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
              fontSize: 15, color: Color(0xFF1F2A2E)),
        ),
        const SizedBox(height: 4),
        if (!filtered)
          Text('Appuyez sur + pour saisir le premier acte.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: Colors.grey.shade400)),
      ]),
    );
  }
}

// ── Formulaire nouvel acte ─────────────────────────────────────────────────────

class _NouvelActePage extends StatefulWidget {
  const _NouvelActePage();

  @override
  State<_NouvelActePage> createState() => _NouvelActePageState();
}

class _NouvelActePageState extends State<_NouvelActePage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  // Animal sélectionné
  String?  _animalId;
  String   _animalNom      = '';
  String   _espece         = '';
  String?  _dateNaissanceStr;
  String   _identification = '';
  String   _sexe           = '';

  // Champs du formulaire
  DateTime? _dateActe;
  String?   _typeActe;
  final _intervenantCtrl  = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _autreTypeCtrl    = TextEditingController();
  final _ordonnanceCtrl   = TextEditingController();

  // Recherche animal
  List<Map<String, dynamic>> _animals = [];
  bool _loadingAnimals = false;
  final _searchCtrl = TextEditingController();

  bool _saving = false;

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadAnimals();
  }

  @override
  void dispose() {
    _intervenantCtrl.dispose();
    _descriptionCtrl.dispose();
    _autreTypeCtrl.dispose();
    _ordonnanceCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnimals() async {
    setState(() => _loadingAnimals = true);
    try {
      final rows = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece, sexe, identification, date_naissance, photo_url')
          .eq('uid_eleveur', _uid)
          .order('nom', ascending: true);
      if (mounted) setState(() => _animals = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingAnimals = false);
    }
  }

  void _selectAnimal(Map<String, dynamic> d) {
    setState(() {
      _animalId         = d['id'] as String?;
      _animalNom        = (d['nom'] as String?) ?? '';
      _espece           = (d['espece'] as String?) ?? '';
      _dateNaissanceStr = d['date_naissance'] as String?;
      _identification   = (d['identification'] as String?) ?? '';
      _sexe             = (d['sexe'] as String?) ?? '';
    });
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dateActe ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _dateActe = d);
  }

  String get _effectiveDescription {
    if (_typeActe == 'autre' && _autreTypeCtrl.text.trim().isNotEmpty) {
      return _autreTypeCtrl.text.trim();
    }
    return _descriptionCtrl.text.trim();
  }

  Future<void> _save() async {
    if (_animalId == null) {
      _snack('Veuillez sélectionner un animal'); return;
    }
    if (_dateActe == null) {
      _snack('Veuillez indiquer la date de l\'acte'); return;
    }
    if (_typeActe == null) {
      _snack('Veuillez choisir le type d\'acte'); return;
    }
    setState(() => _saving = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await Supabase.instance.client.from('registre_sanitaire').insert({
        'id':             id,
        'uid_eleveur':    _uid,
        if (User_Info.activeProfileId != null) 'eleveur_profile_id': User_Info.activeProfileId,
        'animal_nom':     _animalNom,
        'espece':         _espece,
        'date_naissance': _dateNaissanceStr,
        'identification': _identification,
        'sexe':           _sexe,
        'date_acte':      _dateActe!.toIso8601String(),
        'type_acte':      _typeActe,
        'intervenant':    _intervenantCtrl.text.trim(),
        'description':    _effectiveDescription,
        'ordonnance_num': _ordonnanceCtrl.text.trim(),
        'profil_source':  (User_Info.activeType == 'association' || User_Info.isAssociation) ? 'association' : 'eleveur',
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg,
            style: const TextStyle(fontFamily: 'Galey'))));
  }

  void _showAnimalPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final query    = _searchCtrl.text.trim().toLowerCase();
          final filtered = _animals.where((d) {
            return query.isEmpty ||
                (d['nom'] ?? '').toString().toLowerCase().contains(query) ||
                (d['espece'] ?? '').toString().toLowerCase().contains(query);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollCtrl) => Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(children: [
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 14),
                  const Text('Sélectionner un animal',
                      style: TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setLocal(() {}),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Nom ou espèce…',
                      hintStyle: const TextStyle(fontFamily: 'Galey',
                          color: Color(0xFF6F767B)),
                      prefixIcon: const Icon(Icons.search, size: 18,
                          color: Color(0xFF6F767B)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E7E2))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF0C5C6C), width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: _loadingAnimals
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(child: Text('Aucun animal trouvé',
                              style: TextStyle(fontFamily: 'Galey',
                                  color: Colors.grey.shade500)))
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final d = filtered[i];
                              final photoUrl = d['photo_url'] as String?;
                              final espece   = (d['espece'] ?? '') as String;
                              return Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: (photoUrl != null &&
                                            photoUrl.isNotEmpty)
                                        ? NetworkImage(photoUrl) : null,
                                    backgroundColor:
                                        const Color(0xFFE0F2F1),
                                    child: (photoUrl == null ||
                                            photoUrl.isEmpty)
                                        ? speciesIcon(espece, 16,
                                            const Color(0xFF0C5C6C))
                                        : null,
                                  ),
                                  title: Text(d['nom'] ?? '—',
                                      style: const TextStyle(
                                          fontFamily: 'Galey',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  subtitle: Text(
                                    [
                                      _espLabel(espece),
                                      if ((d['sexe'] ?? '').toString().isNotEmpty)
                                        d['sexe'],
                                    ].join(' · '),
                                    style: const TextStyle(
                                        fontFamily: 'Galey', fontSize: 12),
                                  ),
                                  onTap: () {
                                    _searchCtrl.clear();
                                    _selectAnimal(filtered[i]);
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dnStr = (_dateNaissanceStr != null && _dateNaissanceStr!.isNotEmpty)
        ? (DateTime.tryParse(_dateNaissanceStr!) != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(_dateNaissanceStr!))
            : _dateNaissanceStr)
        : null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Nouvel acte',
            style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 14, color: Colors.white)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

          // ── Animal ───────────────────────────────────────────────────────
          _sectionTitle('Animal concerné *'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showAnimalPicker,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2))],
                border: _animalId == null
                    ? Border.all(color: const Color(0xFFE4E7E2))
                    : Border.all(color: _green, width: 1.5),
              ),
              child: _animalId == null
                  ? Row(children: [
                      const Icon(Icons.pets_outlined, size: 20,
                          color: Color(0xFF6F767B)),
                      const SizedBox(width: 10),
                      Text('Sélectionner un animal',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                              color: Colors.grey.shade500)),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down,
                          color: Color(0xFF6F767B)),
                    ])
                  : Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(8)),
                        child: speciesIcon(_espece, 16, _teal),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_animalNom,
                            style: const TextStyle(fontFamily: 'Galey',
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          [
                            if (_espece.isNotEmpty) _espLabel(_espece),
                            if (_sexe.isNotEmpty) _sexe,
                            if (_identification.isNotEmpty) _identification,
                          ].join(' · '),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: Colors.grey.shade500),
                        ),
                      ])),
                      const Icon(Icons.swap_horiz, size: 18,
                          color: Color(0xFF6F767B)),
                    ]),
            ),
          ),
          if (dnStr != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Né(e) le $dnStr',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: Colors.grey.shade500)),
            ),
          ],

          const SizedBox(height: 20),

          // ── Date ─────────────────────────────────────────────────────────
          _sectionTitle('Date de l\'acte *'),
          const SizedBox(height: 8),
          _card([
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4E7E2))),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16,
                      color: Color(0xFF6F767B)),
                  const SizedBox(width: 10),
                  Text(
                    _dateActe != null
                        ? DateFormat('dd/MM/yyyy').format(_dateActe!)
                        : 'Choisir une date',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                        color: _dateActe != null
                            ? const Color(0xFF1F2A2E)
                            : Colors.grey.shade400),
                  ),
                ]),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Type d'acte (dropdown) ────────────────────────────────────────
          _sectionTitle('Type d\'acte *'),
          const SizedBox(height: 8),
          _card([
            DropdownButtonFormField<String>(
              value: _typeActe,
              isExpanded: true,
              hint: const Text('Choisir un type d\'acte',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: Color(0xFF6F767B))),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: Color(0xFF1F2A2E)),
              icon: const Icon(Icons.arrow_drop_down,
                  color: Color(0xFF6F767B)),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: _teal, width: 1.5)),
                isDense: true,
              ),
              selectedItemBuilder: (ctx) => _kActeTypes.map((t) =>
                  Row(children: [
                    Icon(t.icon, size: 15, color: const Color(0xFF0C5C6C)),
                    const SizedBox(width: 8),
                    Text(t.label,
                        style: const TextStyle(fontFamily: 'Galey',
                            fontSize: 13, color: Color(0xFF1F2A2E))),
                  ])).toList(),
              items: _kActeTypes.map((t) => DropdownMenuItem(
                value: t.value,
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: t.color,
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(t.icon, size: 14,
                        color: const Color(0xFF0C5C6C)),
                  ),
                  const SizedBox(width: 10),
                  Text(t.label,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontSize: 13)),
                ]),
              )).toList(),
              onChanged: (v) => setState(() {
                _typeActe = v;
                if (v != 'autre') _autreTypeCtrl.clear();
              }),
            ),
            // Champ libre pour "Autre"
            if (_typeActe == 'autre') ...[
              const SizedBox(height: 10),
              _field('Préciser le type d\'acte *', _autreTypeCtrl),
            ],
          ]),

          const SizedBox(height: 20),

          // ── Détails ───────────────────────────────────────────────────────
          _sectionTitle('Détails'),
          const SizedBox(height: 8),
          _card([
            _field('Intervenant (vétérinaire, ostéopathe…)',
                _intervenantCtrl),
            const SizedBox(height: 10),
            _field('Description / Acte réalisé', _descriptionCtrl,
                maxLines: 3),
            const SizedBox(height: 10),
            _field('N° ordonnance (si applicable)', _ordonnanceCtrl),
          ]),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer l\'acte',
                      style: TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 16, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey',
          fontWeight: FontWeight.w700, fontSize: 14,
          color: Color(0xFF1F2A2E)));

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: children),
  );

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1}) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: Color(0xFF6F767B)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}
