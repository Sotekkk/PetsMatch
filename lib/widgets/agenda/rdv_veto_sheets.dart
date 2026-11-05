// Élevage : créer un RDV vétérinaire à venir depuis l'agenda, et le valider
// (date réelle, animaux réellement vus). Miroir site : components/agenda/RdvVetoModals.tsx.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/rdv_veto.dart';
import 'package:PetsMatch/widgets/rattachement_picker.dart';

const _teal = Color(0xFF0C5C6C);
const _style = TextStyle(fontFamily: 'Galey', fontSize: 14);
const _label = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal);

InputDecoration _deco(String hint) => InputDecoration(
      hintText: hint, hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9E9E9E)),
      isDense: true, filled: true, fillColor: const Color(0xFFF8F8F6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _teal.withValues(alpha: 0.2))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    );

/// Date et heure d'un RDV à venir : deux boutons (date à partir d'aujourd'hui, heure).
class ChoixDateHeureRdv extends StatelessWidget {
  final DateTime? date;
  final TimeOfDay? heure;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeOfDay> onHeure;
  const ChoixDateHeureRdv({super.key, required this.date, required this.heure, required this.onDate, required this.onHeure});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final n = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: date ?? n.add(const Duration(days: 1)),
                firstDate: DateTime(n.year, n.month, n.day), lastDate: n.add(const Duration(days: 730)),
                locale: const Locale('fr'), helpText: 'Date du RDV');
            if (d != null) onDate(d);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(date == null ? 'Date *' : DateFormat('dd/MM/yyyy').format(date!), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: heure ?? const TimeOfDay(hour: 9, minute: 0), helpText: 'Heure du RDV');
            if (t != null) onHeure(t);
          },
          icon: const Icon(Icons.schedule_outlined, size: 15),
          label: Text(heure == null ? 'Heure *' : '${heure!.hour.toString().padLeft(2, '0')}h${heure!.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
        )),
      ]);
}

/// Renvoie true si le RDV a été ajouté à l'agenda.
Future<bool> showNouveauRdvVeto(BuildContext context, {required String uid, required String? profileId, DateTime? jour}) async {
  final r = await showModalBottomSheet<bool>(
    context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _NouveauRdvVeto(uid: uid, profileId: profileId, jour: jour),
  );
  return r ?? false;
}

class _NouveauRdvVeto extends StatefulWidget {
  final String uid;
  final String? profileId;
  final DateTime? jour;
  const _NouveauRdvVeto({required this.uid, required this.profileId, this.jour});
  @override
  State<_NouveauRdvVeto> createState() => _NouveauRdvVetoState();
}

class _NouveauRdvVetoState extends State<_NouveauRdvVeto> {
  final _cabinet = TextEditingController(), _motif = TextEditingController(), _notes = TextEditingController();
  DateTime? _date;
  TimeOfDay? _heure;
  List<Map<String, dynamic>>? _dispo;
  List<String> _ids = [];
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    if (widget.jour != null && widget.jour!.isAfter(DateTime(n.year, n.month, n.day, 23, 59))) _date = widget.jour;
    animauxPresentsElevage(widget.profileId).then((l) { if (mounted) setState(() => _dispo = l); })
        .catchError((_) { if (mounted) setState(() => _dispo = []); });
  }

  @override
  void dispose() { _cabinet.dispose(); _motif.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _choisirAnimaux() async {
    final res = await showRattachementSheet(context,
        titre: 'Animaux concernés', recherche: 'Rechercher un animal…',
        items: [for (final a in _dispo ?? const <Map<String, dynamic>>[])
          ItemRattachement(a['id'].toString(), (a['nom'] ?? '').toString(),
              (a['espece'] ?? '').toString().isEmpty ? 'Autre' : a['espece'].toString(),
              detail: (a['race'] ?? a['espece'])?.toString())],
        initial: _ids);
    if (res != null && mounted) setState(() => _ids = res);
  }

  /// Portées : cocher une portée sélectionne tous ses membres présents.
  Future<void> _choisirPortees() async {
    final portees = porteesDepuis(_dispo ?? const []);
    final dejaEntieres = [for (final p in portees) if (p.membres.every((a) => _ids.contains(a['id'].toString()))) p.id];
    final res = await showRattachementSheet(context,
        titre: 'Portées concernées', recherche: 'Rechercher une portée (nom de la mère)…',
        items: [for (final p in portees)
          ItemRattachement(p.id, p.label, (p.membres.first['espece'] ?? '').toString().isEmpty ? 'Autre' : p.membres.first['espece'].toString(),
              detail: '${p.membres.length} ${p.membres.length > 1 ? 'petits' : 'petit'} présent${p.membres.length > 1 ? 's' : ''}')],
        initial: dejaEntieres);
    if (res == null || !mounted) return;
    setState(() {
      final ids = {..._ids};
      for (final p in portees) {
        final membres = p.membres.map((a) => a['id'].toString());
        if (res.contains(p.id)) { ids.addAll(membres); } else if (dejaEntieres.contains(p.id)) { ids.removeAll(membres); }
      }
      _ids = ids.toList();
    });
  }

  Future<void> _enregistrer() async {
    setState(() { _enCours = true; _erreur = null; });
    final d = _date, h = _heure;
    final e = await creerRdvVeto(
      uid: widget.uid, profileId: widget.profileId, cabinet: _cabinet.text, motif: _motif.text, notes: _notes.text,
      dateHeure: d == null || h == null ? null : DateTime(d.year, d.month, d.day, h.hour, h.minute),
      animaux: [for (final a in _dispo ?? const <Map<String, dynamic>>[]) if (_ids.contains(a['id'].toString())) a],
    );
    if (!mounted) return;
    if (e == null) { Navigator.pop(context, true); return; }
    setState(() { _enCours = false; _erreur = e; });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('RDV vétérinaire à venir', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 14),
          const Text('Cabinet vétérinaire *', style: _label),
          const SizedBox(height: 6),
          TextField(controller: _cabinet, style: _style, textCapitalization: TextCapitalization.words, decoration: _deco('Nom du cabinet')),
          const SizedBox(height: 12),
          ChoixDateHeureRdv(date: _date, heure: _heure,
              onDate: (d) => setState(() => _date = d), onHeure: (t) => setState(() => _heure = t)),
          const SizedBox(height: 12),
          const Text('Motif', style: _label),
          const SizedBox(height: 6),
          TextField(controller: _motif, style: _style, decoration: _deco('Vaccins, contrôle de portée…')),
          const SizedBox(height: 12),
          const Text('Animaux concernés *', style: _label),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _dispo == null ? null : _choisirAnimaux,
              style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
              child: Text(_dispo == null ? 'Chargement…' : 'Choisir des animaux', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            )),
            if (porteesDepuis(_dispo ?? const []).isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(
                onPressed: _choisirPortees,
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
                child: const Text('Choisir une portée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
            ],
          ]),
          if (_dispo != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _dispo!.isEmpty ? 'Aucun animal présent dans cet élevage.'
                  : _ids.isEmpty ? 'Aucun animal sélectionné.'
                  : '${_ids.length} ${_ids.length > 1 ? 'animaux sélectionnés' : 'animal sélectionné'}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 12),
          const Text('Notes', style: _label),
          const SizedBox(height: 6),
          TextField(controller: _notes, style: _style, maxLines: 2, decoration: _deco('')),
          const SizedBox(height: 10),
          Text('Le RDV apparaît dans votre agenda. Le carnet et le registre sont remplis quand vous le validez.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.red))),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _enCours ? null : _enregistrer,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
            child: Text(_enCours ? 'Enregistrement…' : 'Ajouter à l’agenda', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ])),
      );
}

/// Récapitulatif de validation. Renvoie true si le RDV a été validé.
Future<bool> showValiderRdvVeto(BuildContext context, Map<String, dynamic> tache) async {
  final r = await showModalBottomSheet<bool>(
    context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ValiderRdvVeto(tache: tache),
  );
  return r ?? false;
}

class _ValiderRdvVeto extends StatefulWidget {
  final Map<String, dynamic> tache;
  const _ValiderRdvVeto({required this.tache});
  @override
  State<_ValiderRdvVeto> createState() => _ValiderRdvVetoState();
}

class _ValiderRdvVetoState extends State<_ValiderRdvVeto> {
  late DateTime _date;
  List<Map<String, dynamic>>? _animaux;
  final _coches = <String>{};
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final prevu = DateTime.tryParse(widget.tache['date']?.toString() ?? '');
    _date = prevu != null && !prevu.isAfter(n) ? prevu : n;
    _charger();
  }

  Future<void> _charger() async {
    final t = widget.tache;
    final brut = t['animaux_ids'];
    final ids = brut is List && brut.isNotEmpty
        ? [for (final x in brut) x.toString()]
        : [if (t['animal_id'] != null) t['animal_id'].toString()];
    final noms = <String, String>{};
    if (ids.isNotEmpty) {
      try {
        for (final a in await Supabase.instance.client.from('animaux').select('id, nom').inFilter('id', ids) as List) {
          noms[a['id'].toString()] = a['nom']?.toString() ?? '';
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _animaux = [for (final id in ids) {'id': id, 'nom': noms[id] ?? 'Animal'}];
      _coches.addAll(ids);
    });
  }

  Future<void> _valider() async {
    setState(() { _enCours = true; _erreur = null; });
    final e = await validerRdvVeto(widget.tache, _date,
        [for (final a in _animaux ?? const <Map<String, dynamic>>[]) if (_coches.contains(a['id'])) a],
        profilActif: User_Info.activeProfileId);
    if (!mounted) return;
    if (e == null) { Navigator.pop(context, true); return; }
    setState(() { _enCours = false; _erreur = e; });
  }

  @override
  Widget build(BuildContext context) {
    final motif = widget.tache['rdv_veto_motif']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Valider le RDV vétérinaire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 8),
        Text('${widget.tache['rdv_veto_cabinet'] ?? ''}${motif.isEmpty ? '' : ' · $motif'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        const Text('Date réelle de la visite', style: _label),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final n = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(n.year - 2), lastDate: n, locale: const Locale('fr'));
            if (d != null) setState(() => _date = d);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(DateFormat('dd/MM/yyyy').format(_date), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
        ),
        const SizedBox(height: 12),
        Text('Animaux vus (${_coches.length})', style: _label),
        if (_animaux == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: _teal)))
        else
          for (final a in _animaux!)
            CheckboxListTile(
              dense: true, contentPadding: EdgeInsets.zero, activeColor: _teal,
              controlAffinity: ListTileControlAffinity.leading,
              value: _coches.contains(a['id']),
              onChanged: (v) => setState(() { if (v == true) { _coches.add(a['id'].toString()); } else { _coches.remove(a['id']); } }),
              title: Text(a['nom']?.toString() ?? 'Animal', style: _style),
            ),
        const SizedBox(height: 6),
        Text('Une visite vétérinaire est ajoutée au carnet de chaque animal coché et au registre sanitaire.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.red))),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _enCours || _animaux == null ? null : _valider,
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
          child: Text(_enCours ? 'Validation…' : 'Valider pour ${_coches.length} ${_coches.length > 1 ? 'animaux' : 'animal'}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ])),
    );
  }
}
