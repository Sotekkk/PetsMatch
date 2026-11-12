import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/utils/rdv_veto.dart';
import 'package:PetsMatch/widgets/agenda/rdv_veto_sheets.dart' show ChoixDateHeureRdv;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show poserRappelAgendaSoin;

// Types d'actes (mirror de registre_sanitaire.dart)
const _kActes = [
  (value: 'vermifuge',       label: 'Vermifuge',           icon: Icons.bug_report_outlined,        color: Color(0xFFFFF8E1)),
  (value: 'vaccination',     label: 'Vaccination',          icon: Icons.vaccines_outlined,          color: Color(0xFFE8F5E9)),
  (value: 'antiparasitaire', label: 'Antiparasitaire',      icon: Icons.pest_control_outlined,      color: Color(0xFFFFF3E0)),
  (value: 'traitement',      label: 'Traitement',           icon: Icons.medication_outlined,        color: Color(0xFFE0F2F1)),
  (value: 'visite',          label: 'Visite vétérinaire',   icon: Icons.medical_services_outlined,  color: Color(0xFFE3F2FD)),
  (value: 'rdv_veto',        label: 'RDV vétérinaire à venir', icon: Icons.event_outlined,          color: Color(0xFFE3F2FD)),
  (value: 'osteopathie',     label: 'Ostéopathie',          icon: Icons.self_improvement_outlined,  color: Color(0xFFF3E5F5)),
  (value: 'chirurgie',       label: 'Chirurgie',            icon: Icons.healing_outlined,           color: Color(0xFFFFEBEE)),
  (value: 'autre',           label: 'Autre',                icon: Icons.more_horiz,                 color: Color(0xFFF5F5F5)),
];

typedef _Acte = ({String value, String label, IconData icon, Color color});

/// Fréquence du soin → prochain rappel (date du soin + fréquence, modifiable).
/// Miroir site : PorteeSoinModal (ajouterFrequence).
const _kFreqRapides = [
  (label: '1 semaine', n: 1, u: 'semaines'), (label: '1 mois', n: 1, u: 'mois'),
  (label: '3 mois', n: 3, u: 'mois'), (label: '6 mois', n: 6, u: 'mois'), (label: '1 an', n: 12, u: 'mois'),
];
DateTime ajouterFrequence(DateTime d, int n, String u) {
  if (u == 'mois') {
    final r = DateTime(d.year, d.month + n, d.day);
    // 31 janvier + 1 mois : dernier jour de février, pas le 3 mars.
    return r.day != d.day ? DateTime(r.year, r.month, 0) : r;
  }
  return DateTime(d.year, d.month, d.day + n * (u == 'semaines' ? 7 : 1));
}
String libelleFrequence(int n, String u) =>
    u == 'mois' && n == 12 ? '1 an' : '$n ${u == 'mois' ? 'mois' : n > 1 ? u : u.substring(0, u.length - 1)}';

/// Soins avec prochain rappel (carnet de chaque animal + un rappel d'agenda pour le groupe).
const _kLibelleRappel = {'vaccination': 'Rappel vaccin', 'vermifuge': 'Rappel vermifuge', 'antiparasitaire': 'Rappel antiparasitaire'};

class PorteeSoinSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  /// Employé : propriétaire de l'élevage (RDV vétérinaire inscrit à son agenda).
  final String? eleveurUid;

  /// Ouvert depuis l'accueil éleveur (rappel du carnet) : titre, soin, produit,
  /// prochain rappel et animaux concernés préremplis ; les autres restent proposés.
  final String? titre;
  final String? acteInitial;
  final String? produitInitial;
  final DateTime? rappelInitial;
  final Set<String>? selectionInitiale;
  /// Ligne d'information sous les animaux (ex. soin déjà inscrit au carnet).
  final String? info;
  const PorteeSoinSheet({super.key, required this.animals, this.eleveurUid,
      this.titre, this.acteInitial, this.produitInitial, this.rappelInitial, this.selectionInitiale, this.info});

  /// Ouvre le bottom sheet et retourne true si des soins ont été enregistrés.
  static Future<bool> show(BuildContext context, List<Map<String, dynamic>> animals, {String? eleveurUid,
      String? titre, String? acteInitial, String? produitInitial, DateTime? rappelInitial, Set<String>? selectionInitiale, String? info}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PorteeSoinSheet(animals: animals, eleveurUid: eleveurUid, titre: titre, acteInitial: acteInitial,
          produitInitial: produitInitial, rappelInitial: rappelInitial, selectionInitiale: selectionInitiale, info: info),
    );
    return result ?? false;
  }

  @override
  State<PorteeSoinSheet> createState() => _PorteeSoinSheetState();
}

class _PorteeSoinSheetState extends State<PorteeSoinSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  _Acte _selectedActe = _kActes.first; // vermifuge par défaut
  DateTime _date = DateTime.now();
  DateTime? _dateRappel;
  bool get _avecRappel => _kLibelleRappel.containsKey(_selectedActe.value);
  // RDV vétérinaire à venir : date et heure dans le futur.
  DateTime? _dateRdv;
  TimeOfDay? _heureRdv;
  bool get _estRdv => _selectedActe.value == 'rdv_veto';
  bool get _estVisite => _selectedActe.value == 'visite';
  final _intervenantCtrl  = TextEditingController();
  final _freqCtrl         = TextEditingController();
  String _freqU = 'mois';
  int get _freqN => int.tryParse(_freqCtrl.text.trim()) ?? 0;
  void _majRappelDepuisFrequence() {
    if (_freqN > 0) _dateRappel = ajouterFrequence(_date, _freqN, _freqU);
  }
  final _descriptionCtrl  = TextEditingController();
  final _dosageCtrl       = TextEditingController();
  final _notesCtrl        = TextEditingController();
  final _ordonnanceCtrl   = TextEditingController();
  /// Vaccination : n° de lot (comme le carnet ; repris dans les annonces).
  final _lotCtrl          = TextEditingController();
  bool _saving = false;
  String? _error;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.selectionInitiale ?? (widget.animals.map((a) => a['id']?.toString() ?? '').toSet()..remove(''));
    if (widget.acteInitial != null) {
      _selectedActe = _kActes.firstWhere((a) => a.value == widget.acteInitial, orElse: () => _kActes.first);
    }
    if (widget.produitInitial != null) _descriptionCtrl.text = widget.produitInitial!;
    _dateRappel = widget.rappelInitial;
  }

  Future<void> _pickRappel() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateRappel ?? _date.add(const Duration(days: 30)),
      firstDate: _date.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3 * 365)),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: _teal)), child: child!),
    );
    if (picked != null) setState(() => _dateRappel = picked);
  }

  @override
  void dispose() {
    _intervenantCtrl.dispose();
    _freqCtrl.dispose();
    _descriptionCtrl.dispose();
    _dosageCtrl.dispose();
    _notesCtrl.dispose();
    _ordonnanceCtrl.dispose();
    _lotCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _teal),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _date = picked; _majRappelDepuisFrequence(); });
  }

  /// RDV à venir : tâche d'agenda ; carnet et registre à la validation.
  Future<void> _saveRdv() async {
    setState(() { _saving = true; _error = null; });
    final choisis = [for (final a in widget.animals) if (_selectedIds.contains(a['id']?.toString())) a];
    final premier = choisis.isNotEmpty ? choisis.first : const <String, dynamic>{};
    final proprio = widget.eleveurUid ?? premier['uid_eleveur']?.toString() ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final profil = (premier['profile_id']?.toString() ?? '').isNotEmpty ? premier['profile_id'].toString() : User_Info.activeProfileId;
    final d = _dateRdv, h = _heureRdv;
    final err = await creerRdvVeto(
      uid: proprio, profileId: profil, animaux: choisis, cabinet: _intervenantCtrl.text,
      motif: _descriptionCtrl.text, notes: _notesCtrl.text,
      dateHeure: d == null || h == null ? null : DateTime(d.year, d.month, d.day, h.hour, h.minute),
    );
    if (!mounted) return;
    if (err != null) { setState(() { _saving = false; _error = err; }); return; }
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('RDV ajouté à l\u2019agenda. Validez-le après la visite pour remplir le carnet et le registre.', style: TextStyle(fontFamily: 'Galey')),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _save() async {
    if (_estRdv) return _saveRdv();
    if (_descriptionCtrl.text.trim().isEmpty) {
      setState(() => _error = _estVisite ? 'Veuillez renseigner le motif.' : 'Veuillez renseigner le produit / la description.');
      return;
    }
    if (_estVisite && _intervenantCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez le nom du cabinet vétérinaire.');
      return;
    }
    final rappel = _avecRappel ? _dateRappel : null;
    if (rappel != null && !DateTime(rappel.year, rappel.month, rappel.day).isAfter(DateTime(_date.year, _date.month, _date.day))) {
      setState(() => _error = 'Le prochain rappel doit être après la date du soin.');
      return;
    }
    final rappelTxt = rappel == null ? null : DateFormat('yyyy-MM-dd').format(rappel);
    setState(() { _saving = true; _error = null; });
    final supa        = Supabase.instance.client;
    final type        = _selectedActe.value;
    final desc        = _descriptionCtrl.text.trim();
    final dosage      = _dosageCtrl.text.trim();
    // « Administré par » vide : la personne connectée.
    final interv      = _intervenantCtrl.text.trim().isNotEmpty ? _intervenantCtrl.text.trim() : moiIntervenant();
    final frequence   = _freqN > 0 ? libelleFrequence(_freqN, _freqU) : '';
    final notes       = _notesCtrl.text.trim();
    final dateIso     = _date.toIso8601String();
    int success = 0;
    for (final animal in widget.animals) {
      final id = animal['id']?.toString() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      try {
        final entryId = DateTime.now().microsecondsSinceEpoch.toString();
        // Écriture dans la table spécifique (lue par le carnet de santé de la fiche)
        switch (type) {
          case 'vermifuge':
            await supa.from('vermifuges').insert({
              'id': entryId, 'animal_id': id,
              'produit': desc, 'date': dateIso, 'source': 'owner',
              if (rappelTxt != null) 'date_rappel': rappelTxt,
              if (dosage.isNotEmpty) 'dosage': dosage,
              if (notes.isNotEmpty) 'notes': notes,
            });
          case 'vaccination':
            await supa.from('vaccinations').insert({
              'id': entryId, 'animal_id': id,
              'vaccin': desc, 'veterinaire': interv, 'date': dateIso, 'source': 'owner',
              if (_lotCtrl.text.trim().isNotEmpty) 'lot': _lotCtrl.text.trim(),
              if (rappelTxt != null) 'date_rappel': rappelTxt,
            });
          case 'antiparasitaire':
            await supa.from('antiparasitaires').insert({
              'id': entryId, 'animal_id': id,
              'produit': desc, 'type': 'autre', 'date': dateIso, 'source': 'owner',
              if (rappelTxt != null) 'date_rappel': rappelTxt,
              if (frequence.isNotEmpty) 'frequence': frequence,
              if (notes.isNotEmpty) 'notes': notes,
            });
          case 'visite':
          case 'osteopathie':
            await supa.from('visites').insert({
              'id': entryId, 'animal_id': id,
              'motif': type == 'osteopathie' ? 'Autre' : 'Consultation',
              'veterinaire': interv, 'date': dateIso,
              'diagnostic': type == 'osteopathie' ? 'Ostéopathie — $desc' : desc,
              if (notes.isNotEmpty) 'notes': notes,
              'source': 'owner',
            });
          default: // traitement, chirurgie, autre
            await supa.from('traitements').insert({
              'id': entryId, 'animal_id': id,
              'nom': desc, 'type': type == 'chirurgie' ? 'autre' : 'medicament',
              'date': dateIso, 'source': 'owner',
              if (notes.isNotEmpty) 'notes': notes,
            });
        }
        // Log consolidé dans registre_sanitaire (ostéopathie : la ligne visites l'inscrit déjà).
        if (type != 'osteopathie') await RegistreHelper.writeActe(
          animalId:     id,
          typeActe:     type,
          dateActe:     _date,
          intervenant:  interv,
          description:  desc,
          ordonnanceNum: _ordonnanceCtrl.text.trim(),
        );
        success++;
      } catch (_) {}
    }
    // Prochain rappel : un seul événement d'agenda pour les animaux traités ensemble.
    final traites = [for (final a in widget.animals) if (_selectedIds.contains(a['id']?.toString())) a['id'].toString()];
    if (success > 0 && rappel != null && traites.isNotEmpty) {
      await poserRappelAgendaSoin(animalId: traites.first, autres: traites.skip(1).toList(), dateRappel: rappel,
          titre: '${_kLibelleRappel[type]} — $desc');
    }
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, success > 0);
      if (success > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$success soin${success > 1 ? 's' : ''} enregistré${success > 1 ? 's' : ''} dans le registre.',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Titre
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.medical_services_outlined, color: _teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.titre ?? 'Soin pour la portée', style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
                Text('${_selectedIds.length}/${widget.animals.length} ${widget.animals.length > 1 ? 'animaux' : 'animal'} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context, false),
              padding: EdgeInsets.zero,
            ),
          ]),

          const SizedBox(height: 4),

          // Noms des animaux — tap pour désélectionner
          Wrap(spacing: 6, runSpacing: 4, children: widget.animals.map((a) {
            final id  = a['id']?.toString() ?? '';
            final nom = (a['nom'] as String?) ?? '?';
            final sel = _selectedIds.contains(id);
            return GestureDetector(
              onTap: () {
                if (id.isEmpty) return;
                setState(() {
                  if (sel) _selectedIds.remove(id);
                  else _selectedIds.add(id);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sel ? _teal.withOpacity(0.12) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? _teal.withOpacity(0.35) : Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(nom, style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12,
                    color: sel ? _teal : Colors.grey,
                    decoration: sel ? TextDecoration.none : TextDecoration.lineThrough,
                  )),
                  if (!sel) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 10, color: Colors.grey.shade400),
                  ],
                ]),
              ),
            );
          }).toList()),
          if (widget.info != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
              child: Text(widget.info!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _green)),
            ),
          ],

          const SizedBox(height: 20),

          // Sélecteur type d'acte
          const Text('Type de soin', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _kActes.map((a) {
            final sel = _selectedActe.value == a.value;
            return GestureDetector(
              onTap: () => setState(() { _selectedActe = a; _dosageCtrl.clear(); }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? _teal : a.color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? _teal : Colors.transparent, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(a.icon, size: 14, color: sel ? Colors.white : _teal),
                  const SizedBox(width: 5),
                  Text(a.label, style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : const Color(0xFF1F2A2E),
                  )),
                ]),
              ),
            );
          }).toList()),

          const SizedBox(height: 18),

          // Date
          Text(_estRdv ? 'Date et heure du RDV *' : 'Date du soin', style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          if (_estRdv)
            ChoixDateHeureRdv(date: _dateRdv, heure: _heureRdv,
                onDate: (d) => setState(() => _dateRdv = d), onHeure: (t) => setState(() => _heureRdv = t))
          else
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: _teal),
                const SizedBox(width: 8),
                Text(fmt.format(_date), style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
              ]),
            ),
          ),

          const SizedBox(height: 14),

          // Produit / description
          Text(_estRdv ? 'Motif (optionnel)' : _estVisite ? 'Motif *' : 'Produit / description *', style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: _estRdv || _estVisite ? 'Ex : vaccins, contrôle de portée' : 'Ex : Milbemax®, 1 comprimé par chiot',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          // Vaccination : n° de lot.
          if (_selectedActe.value == 'vaccination') ...[
            const SizedBox(height: 14),
            const Text('N° de lot', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
            const SizedBox(height: 6),
            TextField(
              controller: _lotCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: "Numéro inscrit sur l'étiquette du vaccin",
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
                filled: true, fillColor: const Color(0xFFF8F8F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],

          // Prochain rappel (vaccin, vermifuge, antiparasitaire).
          if (_avecRappel) ...[
            const SizedBox(height: 14),
            const Text('Fréquence (optionnel)', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in _kFreqRapides)
                ChoiceChip(
                  label: Text(f.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  selected: _freqN == f.n && _freqU == f.u,
                  selectedColor: _teal.withValues(alpha: 0.18),
                  onSelected: (_) => setState(() {
                    _freqCtrl.text = '${f.n}'; _freqU = f.u; _majRappelDepuisFrequence();
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 100, child: TextField(
                controller: _freqCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(_majRappelDepuisFrequence),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Nombre', isDense: true, filled: true, fillColor: const Color(0xFFF8F8F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _freqU,
                isDense: true,
                decoration: InputDecoration(
                  filled: true, fillColor: const Color(0xFFF8F8F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'jours', child: Text('jour(s)', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                  DropdownMenuItem(value: 'semaines', child: Text('semaine(s)', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                  DropdownMenuItem(value: 'mois', child: Text('mois', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
                ],
                onChanged: (v) => setState(() { _freqU = v ?? 'mois'; _majRappelDepuisFrequence(); }),
              )),
            ]),
            const SizedBox(height: 14),
            const Text('Prochain rappel (optionnel)', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickRappel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF8F8F6), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _teal.withValues(alpha: 0.2))),
                child: Row(children: [
                  const Icon(Icons.event_repeat_outlined, size: 16, color: _teal),
                  const SizedBox(width: 8),
                  Text(_dateRappel == null ? 'Aucun' : DateFormat('dd/MM/yyyy').format(_dateRappel!), style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                  const Spacer(),
                  if (_dateRappel != null)
                    GestureDetector(onTap: () => setState(() => _dateRappel = null),
                        child: const Icon(Icons.close, size: 18, color: Color(0xFF9E9E9E)))
                  else
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text('Inscrit au carnet de chaque animal, avec un rappel dans l\'agenda.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
          ],

          // Dosage (visible pour vermifuge et antiparasitaire)
          if (_selectedActe.value == 'vermifuge') ...[
            const SizedBox(height: 14),
            const Text(
              'Dosage (optionnel)',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _dosageCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex : 1 cp / 5 kg',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
                filled: true, fillColor: const Color(0xFFF8F8F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _teal, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Administré par (optionnel)
          Text(_estRdv || _estVisite ? 'Cabinet vétérinaire *' : 'Administré par (optionnel)', style: const TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _intervenantCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: _estRdv || _estVisite ? 'Nom du cabinet'
                  : moiIntervenant().isNotEmpty ? 'Laissé vide : ${moiIntervenant()}' : 'Éleveur, Dr. Dupont, …',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          const SizedBox(height: 14),

          // Notes (optionnel)
          const Text('Notes (optionnel)', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Observations, réactions, …',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          const SizedBox(height: 14),

          // N° ordonnance (optionnel)
          const Text('N° ordonnance (optionnel)', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _ordonnanceCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'ORD-2024-XXXXX',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!, style: const TextStyle(fontFamily: 'Galey',
                  fontSize: 13, color: Color(0xFFB71C1C))),
            ),
          ],

          const SizedBox(height: 20),

          // Bouton enregistrer
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_saving || _selectedIds.isEmpty) ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                _saving ? 'Enregistrement…' : 'Enregistrer pour ${_selectedIds.length} ${_selectedIds.length > 1 ? 'animaux' : 'animal'}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
