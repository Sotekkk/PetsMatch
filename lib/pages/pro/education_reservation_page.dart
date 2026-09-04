import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/animal_picker_sheet.dart';
import 'package:PetsMatch/utils/geocoding_helper.dart';

// Vitesse moyenne heuristique (à vol d'oiseau, pas d'API Directions payante)
// + marge de sécurité — même principe que pro_agenda.dart _travelWarningsToday(),
// mais utilisé ici pour FILTRER les créneaux proposés (pas juste avertir après coup).
const int _kVitesseTrajetKmh = 30;
const int _kMargeTrajetMin = 15;

/// Calendrier de réservation "intelligent" pour l'éducateur/comportementaliste
/// — remplace le flux RDV générique (motif fixe + un jour à la fois) pour
/// `cat_pro == 'education'` : la famille choisit un cours dans le catalogue
/// du pro (`prestations_education`), puis un créneau dans une vraie vue
/// semaine. Les autres catégories de pro continuent d'utiliser
/// `RdvBookingPage`, inchangé.
class EducationReservationPage extends StatefulWidget {
  final String proUid;
  final String proName;
  final Color categoryColor;
  final String? proProfileId;
  final String? preselectedAnimalId;

  const EducationReservationPage({
    super.key,
    required this.proUid,
    required this.proName,
    required this.categoryColor,
    this.proProfileId,
    this.preselectedAnimalId,
  });

  @override
  State<EducationReservationPage> createState() => _EducationReservationPageState();
}

class _EducationReservationPageState extends State<EducationReservationPage> {
  static const _bg = Color(0xFFF8F8F8);
  final _supa = Supabase.instance.client;
  final _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _prestations = [];
  Map<String, dynamic>? _selectedPrestation;
  Map<String, dynamic>? _selectedAnimal;

  bool _educationBilanRequis = true;
  bool _isFirstTimeClient = false;

  // Trajet à domicile
  bool _domicile = false;
  bool _domicileChoiceMade = false;
  bool _geocodingDomicile = false;
  final _adresseDomicileCtrl = TextEditingController();
  String _origineDefaut = 'cabinet';
  double? _cabinetLat, _cabinetLng, _autreDomicileLat, _autreDomicileLng;
  double? _domicileLat, _domicileLng;

  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> _existingRdvs = [];
  DateTime _weekStart = DateTime.now();
  static const int _joursSemaine = 7;

  Map<String, dynamic>? _selectedSlot; // {date, heure_debut, heure_fin}

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    // Lundi de la semaine courante.
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    if (widget.preselectedAnimalId != null) {
      _loadPreselectedAnimal();
    }
    _init();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _adresseDomicileCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreselectedAnimal() async {
    try {
      final row = await _supa.from('animaux').select('id, nom, espece, race, photo_url')
          .eq('id', widget.preselectedAnimalId!).maybeSingle();
      if (mounted && row != null) setState(() => _selectedAnimal = row);
    } catch (_) {}
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    await Future.wait([_loadPrestations(), _loadAvailableSlots()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPrestations() async {
    try {
      const cols = 'education_bilan_requis, trajet_origine_defaut, autre_domicile_lat, autre_domicile_lng, latitude, longitude, lat, lng';
      final row = (widget.proProfileId != null && widget.proProfileId!.isNotEmpty)
          ? await _supa.from('user_profiles').select(cols).eq('id', widget.proProfileId!).maybeSingle()
          : await _supa.from('user_profiles').select(cols).eq('uid', widget.proUid).eq('is_main', true).maybeSingle();
      _educationBilanRequis = row?['education_bilan_requis'] as bool? ?? true;
      _origineDefaut = row?['trajet_origine_defaut']?.toString() ?? 'cabinet';
      _autreDomicileLat = (row?['autre_domicile_lat'] as num?)?.toDouble();
      _autreDomicileLng = (row?['autre_domicile_lng'] as num?)?.toDouble();
      _cabinetLat = (row?['latitude'] as num?)?.toDouble() ?? (row?['lat'] as num?)?.toDouble();
      _cabinetLng = (row?['longitude'] as num?)?.toDouble() ?? (row?['lng'] as num?)?.toDouble();

      var q = _supa.from('prestations_education').select().eq('pro_uid', widget.proUid).eq('actif', true);
      if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', widget.proProfileId!);
      }
      final rows = await q.order('ordre').order('created_at');
      var all = List<Map<String, dynamic>>.from(rows as List);

      await _checkFirstTimeClient();

      // Nouvelle famille + bilan exigé → ne proposer que les cours marqués
      // "nécessite un bilan" (s'il en existe au moins un configuré).
      if (_educationBilanRequis && _isFirstTimeClient) {
        final bilans = all.where((p) => p['bilan_requis'] == true).toList();
        if (bilans.isNotEmpty) all = bilans;
      }

      if (mounted) setState(() => _prestations = all);
    } catch (_) {}
  }

  // Un client est "nouveau" s'il n'a jamais eu de séance confirmée/terminée
  // avec ce pro — même mécanisme que rdv_booking_page.dart
  // _checkFirstTimeEducationClient(), généralisé au catalogue personnalisé.
  Future<void> _checkFirstTimeClient() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      var q = _supa.from('rdv').select('id')
          .eq('client_uid', uid).eq('pro_uid', widget.proUid)
          .inFilter('statut', ['confirme', 'termine']);
      if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', widget.proProfileId!);
      }
      final rows = await q.limit(1);
      _isFirstTimeClient = (rows as List).isEmpty;
    } catch (_) {}
  }

  Future<void> _loadAvailableSlots() async {
    try {
      final now = DateTime.now();
      final today = _dateKey(now);
      final maxDt = DateTime(now.year, now.month + 3, now.day);
      final maxDate = _dateKey(maxDt);
      final profileId = widget.proProfileId ?? '';
      final results = await Future.wait([
        _supa.from('creneaux_pro')
            .select('date, heure_debut, heure_fin, type_prestation, domicile_ok, trajet_origine')
            .eq('pro_uid', widget.proUid)
            .eq('statut', 'disponible')
            .eq('pro_profile_id', profileId)
            .gte('date', today)
            .lte('date', maxDate)
            .order('date')
            .order('heure_debut')
            .limit(1000),
        _supa.from('rdv')
            .select('date_heure, duree_minutes, statut, lieu_lat, lieu_lng')
            .eq('pro_uid', widget.proUid)
            .eq('pro_profile_id', profileId)
            .inFilter('statut', ['confirme', 'demande'])
            .gte('date_heure', now.toUtc().toIso8601String()),
      ]);
      if (mounted) {
        _availableSlots = List<Map<String, dynamic>>.from(results[0] as List);
        _existingRdvs = List<Map<String, dynamic>>.from(results[1] as List);
      }
    } catch (_) {}
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _duration => (_selectedPrestation?['duree_minutes'] as num?)?.toInt() ?? 60;

  // Créneaux intelligents : fusion des plages creneaux_pro disponibles, moins
  // les RDV déjà posés, découpés à la durée du cours choisi — même algorithme
  // que rdv_booking_page.dart _smartSlotsByDate (créneaux "collectif" exclus,
  // marge de 30 min pour aujourd'hui).
  Map<String, List<Map<String, dynamic>>> get _smartSlotsByDate {
    if (_availableSlots.isEmpty || _selectedPrestation == null) return {};
    final duration = _duration;
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final nowMinutes = now.hour * 60 + now.minute + 30;

    final creneauxByDate = <String, List<({int startMin, int endMin, String? origine})>>{};
    for (final slot in _availableSlots) {
      if (slot['type_prestation'] == 'collectif') continue;
      if (_domicile && slot['domicile_ok'] != true) continue;
      final date = slot['date'] as String;
      final sp = (slot['heure_debut'] as String).split(':');
      final ep = (slot['heure_fin'] as String).split(':');
      final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      creneauxByDate.putIfAbsent(date, () => []).add((startMin: s, endMin: e, origine: slot['trajet_origine']?.toString()));
    }

    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in creneauxByDate.entries) {
      final date = entry.key;
      final slots = entry.value..sort((a, b) => a.startMin.compareTo(b.startMin));

      final windows = <({int startMin, int endMin, String? origine})>[];
      for (final s in slots) {
        if (windows.isNotEmpty && s.startMin <= windows.last.endMin) {
          windows[windows.length - 1] = (
            startMin: windows.last.startMin,
            endMin: s.endMin > windows.last.endMin ? s.endMin : windows.last.endMin,
            origine: windows.last.origine,
          );
        } else {
          windows.add(s);
        }
      }

      // RDV existants ce jour-là, triés — utilisés pour bloquer les créneaux
      // ET, en mode domicile, comme points de chaînage pour le trajet.
      final rdvsDuJour = _existingRdvs.where((rdv) {
        final dh = DateTime.tryParse(rdv['date_heure'] as String? ?? '')?.toLocal();
        return dh != null && _dateKey(dh) == date;
      }).map((rdv) {
        final dh = DateTime.parse(rdv['date_heure'] as String).toLocal();
        final duree = (rdv['duree_minutes'] as num?)?.toInt() ?? 30;
        final start = dh.hour * 60 + dh.minute;
        return (
          startMin: start, endMin: start + duree,
          lat: (rdv['lieu_lat'] as num?)?.toDouble(), lng: (rdv['lieu_lng'] as num?)?.toDouble(),
        );
      }).toList()
        ..sort((a, b) => a.startMin.compareTo(b.startMin));

      final blocked = rdvsDuJour.map((r) => (startMin: r.startMin, endMin: r.endMin)).toList();

      final available = <Map<String, dynamic>>[];
      for (final window in windows) {
        for (int t = window.startMin; t + duration <= window.endMin; t += 15) {
          if (date == todayKey && t < nowMinutes) continue;
          final overlaps = blocked.any((b) => t < b.endMin && t + duration > b.startMin);
          if (overlaps) continue;

          if (_domicile && _domicileLat != null && _domicileLng != null) {
            if (!_trajetOk(t, t + duration, window.origine, rdvsDuJour)) continue;
          }

          final h = t ~/ 60, m = t % 60;
          final eh = (t + duration) ~/ 60, em = (t + duration) % 60;
          available.add({
            'date': date,
            'heure_debut': '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00',
            'heure_fin': '${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}:00',
          });
        }
      }
      if (available.isNotEmpty) result[date] = available;
    }
    return result;
  }

  // Vérifie qu'il reste assez de temps pour le trajet avant/après ce créneau
  // à domicile — origine = le RDV précédent ce jour-là s'il est géocodé,
  // sinon l'origine du créneau (ou le défaut du pro) ; heuristique
  // _kVitesseTrajetKmh + marge _kMargeTrajetMin.
  bool _trajetOk(int startMin, int endMin, String? origineCreneau,
      List<({int startMin, int endMin, double? lat, double? lng})> rdvsDuJour) {
    final origine = origineCreneau ?? _origineDefaut;
    final baseLat = origine == 'autre_domicile' ? _autreDomicileLat : _cabinetLat;
    final baseLng = origine == 'autre_domicile' ? _autreDomicileLng : _cabinetLng;

    ({int endMin, double? lat, double? lng})? precedent;
    ({int startMin, double? lat, double? lng})? suivant;
    for (final r in rdvsDuJour) {
      if (r.endMin <= startMin) precedent = (endMin: r.endMin, lat: r.lat, lng: r.lng);
      if (r.startMin >= endMin && suivant == null) suivant = (startMin: r.startMin, lat: r.lat, lng: r.lng);
    }

    final avantLat = precedent?.lat ?? baseLat;
    final avantLng = precedent?.lng ?? baseLng;
    final avantFin = precedent?.endMin ?? 0;
    if (avantLat != null && avantLng != null) {
      final distKm = GeocodingHelper.distanceKm(avantLat, avantLng, _domicileLat!, _domicileLng!);
      final trajetMin = (distKm / _kVitesseTrajetKmh * 60).ceil() + _kMargeTrajetMin;
      if (startMin - avantFin < trajetMin) return false;
    }

    if (suivant != null && suivant.lat != null && suivant.lng != null) {
      final distKm = GeocodingHelper.distanceKm(_domicileLat!, _domicileLng!, suivant.lat!, suivant.lng!);
      final trajetMin = (distKm / _kVitesseTrajetKmh * 60).ceil() + _kMargeTrajetMin;
      if (suivant.startMin - endMin < trajetMin) return false;
    }
    return true;
  }

  Future<void> _geocoderDomicile() async {
    final adresse = _adresseDomicileCtrl.text.trim();
    if (adresse.isEmpty) return;
    setState(() => _geocodingDomicile = true);
    final geo = await GeocodingHelper.geocode(adresse);
    if (!mounted) return;
    setState(() {
      _domicileLat = geo?.lat;
      _domicileLng = geo?.lng;
      _geocodingDomicile = false;
      _domicileChoiceMade = true;
    });
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adresse introuvable — les créneaux à domicile ne pourront pas être filtrés par trajet.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _shiftWeek(int days) => setState(() => _weekStart = _weekStart.add(Duration(days: days)));

  Future<void> _pickSlot(Map<String, dynamic> slot) async {
    if (_selectedAnimal == null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final animal = await AnimalPickerSheet.pickOne(
        context,
        uid: uid,
        profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        accentColor: widget.categoryColor,
      );
      if (animal == null || !mounted) return;
      setState(() => _selectedAnimal = animal);
    }
    setState(() => _selectedSlot = slot);
    await _confirmSheet();
  }

  Future<void> _confirmSheet() async {
    final slot = _selectedSlot;
    final prestation = _selectedPrestation;
    if (slot == null || prestation == null) return;
    final d = DateTime.parse(slot['date'] as String);
    final hp = (slot['heure_debut'] as String).split(':');
    final dateHeure = DateTime(d.year, d.month, d.day, int.parse(hp[0]), int.parse(hp[1]));

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Confirmer la réservation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: widget.categoryColor)),
          const SizedBox(height: 12),
          _recapLine('Cours', prestation['nom']?.toString() ?? ''),
          _recapLine('Avec', widget.proName),
          _recapLine('Animal', _selectedAnimal?['nom']?.toString() ?? '—'),
          _recapLine('Date', DateFormat('EEEE d MMMM à HH:mm', 'fr_FR').format(dateHeure)),
          _recapLine('Durée', '$_duration min'),
          if ((prestation['prix'] as num?) != null)
            _recapLine('Prix', '${(prestation['prix'] as num).toStringAsFixed(0)} €'),
          _recapLine('Lieu', _domicile ? 'À domicile — ${_adresseDomicileCtrl.text.trim()}' : 'Chez le professionnel'),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Message pour le pro (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Confirmer la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
    if (confirm == true) await _submit(dateHeure);
  }

  Widget _recapLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 70, child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))),
      Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );

  Future<void> _submit(DateTime dateHeure) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _supa.from('rdv').insert({
        'pro_uid': widget.proUid,
        'pro_profile_id': widget.proProfileId ?? '',
        'client_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'client_profile_id': User_Info.activeProfileId,
        if (_selectedAnimal?['id'] != null) 'animal_id': _selectedAnimal!['id'].toString(),
        'date_heure': dateHeure.toUtc().toIso8601String(),
        'duree_minutes': _duration,
        'motif': _selectedPrestation!['nom']?.toString() ?? 'Cours',
        if (_notesCtrl.text.trim().isNotEmpty) 'notes_client': _notesCtrl.text.trim(),
        if (_domicile && _adresseDomicileCtrl.text.trim().isNotEmpty) 'lieu': _adresseDomicileCtrl.text.trim(),
        if (_domicile && _domicileLat != null) 'lieu_lat': _domicileLat,
        if (_domicile && _domicileLng != null) 'lieu_lng': _domicileLng,
        'statut': 'demande',
      });

      final composedName = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage
          : '${User_Info.firstname} ${User_Info.lastname}'.trim();
      final clientName = (composedName.isNotEmpty && composedName != 'none none') ? composedName : 'Un client';
      final dateStr = DateFormat('dd/MM à HH:mm').format(dateHeure);
      await _supa.from('notifications').insert({
        'uid': widget.proUid,
        'type': 'rdv_demande',
        'title': 'Nouvelle demande de RDV',
        'body': '$clientName souhaite un cours "${_selectedPrestation!['nom']}" le $dateStr',
        if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) 'profile_id': widget.proProfileId,
        'data': <String, dynamic>{'client_uid': uid},
        'read': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande de cours envoyée !', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57), behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() { _saving = false; _selectedSlot = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.categoryColor;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text('Réserver — ${widget.proName}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: color))
          : _prestations.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ce professionnel n\'a pas encore configuré de cours à réserver en ligne.',
                      textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600)),
                ))
              : _selectedPrestation == null
                  ? _buildCoursStep(color)
                  : !_domicileChoiceMade
                      ? _buildDomicileStep(color)
                      : _buildSemaineStep(color),
    );
  }

  Widget _buildCoursStep(Color color) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choisissez un cours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: color)),
        if (_isFirstTimeClient && _educationBilanRequis)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Première réservation : un bilan préalable peut être requis.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade700)),
          ),
        const SizedBox(height: 12),
        ..._prestations.map((p) => GestureDetector(
              onTap: () => setState(() {
                _selectedPrestation = p;
                _domicile = false;
                _domicileChoiceMade = p['domicile_ok'] != true; // pas de choix à faire si le cours ne le propose pas
                _domicileLat = null;
                _domicileLng = null;
                _adresseDomicileCtrl.clear();
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                    if ((p['description'] as String?)?.isNotEmpty == true)
                      Text(p['description'] as String, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                    Text('${p['duree_minutes']} min${(p['prix'] as num?) != null ? ' · ${(p['prix'] as num).toStringAsFixed(0)} €' : ''}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  ])),
                  Icon(Icons.chevron_right, color: color),
                ]),
              ),
            )),
      ],
    );
  }

  Widget _buildDomicileStep(Color color) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selectedPrestation = null),
          icon: Icon(Icons.arrow_back, size: 16, color: color),
          label: Text(_selectedPrestation!['nom']?.toString() ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color)),
        ),
        const SizedBox(height: 8),
        Text('Ce cours peut avoir lieu à domicile', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: color)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => setState(() { _domicile = false; _domicileChoiceMade = true; }),
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Chez le professionnel', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => setState(() => _domicile = true),
            style: ElevatedButton.styleFrom(backgroundColor: _domicile ? color : Colors.grey.shade300, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text('À domicile', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _domicile ? Colors.white : Colors.black54)),
          )),
        ]),
        if (_domicile) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _adresseDomicileCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'Galey'),
            decoration: const InputDecoration(labelText: 'Votre adresse', hintText: 'Numéro, rue, ville', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Text('Seuls les créneaux compatibles avec le trajet du professionnel seront proposés.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _geocodingDomicile || _adresseDomicileCtrl.text.trim().isEmpty ? null : _geocoderDomicile,
            style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _geocodingDomicile
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Voir les créneaux', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ],
      ],
    );
  }

  Widget _buildSemaineStep(Color color) {
    final smartSlots = _smartSlotsByDate;
    final days = List.generate(_joursSemaine, (i) => _weekStart.add(Duration(days: i)));
    final today = DateTime.now();
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.white,
        child: Row(children: [
          TextButton.icon(
            onPressed: () => setState(() => _selectedPrestation = null),
            icon: Icon(Icons.arrow_back, size: 16, color: color),
            label: Text(_selectedPrestation!['nom']?.toString() ?? '', overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftWeek(-7)),
          Text(DateFormat('MMM yyyy', 'fr_FR').format(_weekStart), style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftWeek(7)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: days.length,
          itemBuilder: (_, i) {
            final day = days[i];
            final key = _dateKey(day);
            final slots = smartSlots[key] ?? [];
            final isPast = day.isBefore(DateTime(today.year, today.month, today.day));
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('EEEE d MMMM', 'fr_FR').format(day),
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
                        color: isPast ? Colors.grey.shade400 : Colors.black87)),
                const SizedBox(height: 8),
                if (slots.isEmpty)
                  Text('Aucun créneau disponible', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400))
                else
                  Wrap(spacing: 8, runSpacing: 8, children: slots.map((s) {
                    final heure = (s['heure_debut'] as String).substring(0, 5);
                    return OutlinedButton(
                      onPressed: () => _pickSlot(s),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                        side: BorderSide(color: color),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                    );
                  }).toList()),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
