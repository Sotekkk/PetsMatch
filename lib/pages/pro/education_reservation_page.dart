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
  // Délai minimum (h) imposé par le pro entre maintenant et le début du cours.
  int _delaiMinReservationH = 0;

  // Profil du pro consulté, résolu une fois pour toutes : si l'appelant n'a
  // pas passé proProfileId (lien sans profil précis), on retombe sur le
  // profil "is_main" de ce uid — sinon les requêtes créneaux/RDV filtrées
  // sur pro_profile_id='' ne retournaient jamais aucune ligne.
  String? _resolvedProfileId;

  // Trajet à domicile
  bool _domicile = false;
  bool _domicileChoiceMade = false;
  bool _geocodingDomicile = false;
  final _adresseDomicileCtrl = TextEditingController();
  String _origineDefaut = 'cabinet';
  double? _cabinetLat, _cabinetLng, _autreDomicileLat, _autreDomicileLng;
  double? _domicileLat, _domicileLng;

  // Chargement paresseux semaine par semaine — clé = date du lundi (yyyy-MM-dd).
  // Une semaine = ≤ 7 jours × ~40 créneaux 15 min = ~280 lignes, bien sous le
  // plafond PostgREST de 1000 (l'ancien fetch « 3 mois d'un coup » était tronqué
  // à 1000 → seules ~4 semaines visibles).
  final Map<String, List<Map<String, dynamic>>> _slotsByWeek = {};
  final Map<String, List<Map<String, dynamic>>> _rdvsByWeek = {};
  // Séances de groupe déjà créées (cours collectif) — clé = lundi (yyyy-MM-dd),
  // valeur = [{date_heure, coursId, capacite, inscrits}]. Chargé seulement
  // quand le cours choisi est de type 'collectif'.
  final Map<String, List<Map<String, dynamic>>> _coursByWeek = {};
  final Set<String> _loadingWeeks = {};
  DateTime? _probedFirstDate; // 1re date où le pro a une dispo (sondage léger)
  bool _probed = false;
  bool _probing = false;
  DateTime _weekStart = DateTime.now();
  static const int _joursSemaine = 7;

  // ⚠ Arithmétique de dates : toujours passer par le constructeur DateTime
  // (jamais `.add(Duration(days:))`) — un Duration est en heures exactes et
  // « saute » d'un jour au changement d'heure (dernier dimanche d'octobre),
  // ce qui bloquait la navigation semaine par semaine à cette date.
  DateTime _addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  String _weekKey(DateTime d) => _dateKey(_addDays(d, -(d.weekday - 1)));

  Map<String, dynamic>? _selectedSlot; // {date, heure_debut, heure_fin}

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    // Lundi de la semaine courante.
    _weekStart = _addDays(DateTime(today.year, today.month, today.day), -(today.weekday - 1));
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
    await _resolveProfileId();
    await _loadPrestations();
    await _loadWeek(_weekStart);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resolveProfileId() async {
    if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
      _resolvedProfileId = widget.proProfileId;
      return;
    }
    try {
      final row = await _supa.from('user_profiles').select('id')
          .eq('uid', widget.proUid).eq('is_main', true).maybeSingle();
      _resolvedProfileId = row?['id']?.toString();
    } catch (_) {}
  }

  Future<void> _loadPrestations() async {
    try {
      const cols = 'education_bilan_requis, delai_min_reservation_h, trajet_origine_defaut, autre_domicile_lat, autre_domicile_lng, latitude, longitude, lat, lng';
      final row = (widget.proProfileId != null && widget.proProfileId!.isNotEmpty)
          ? await _supa.from('user_profiles').select(cols).eq('id', widget.proProfileId!).maybeSingle()
          : await _supa.from('user_profiles').select(cols).eq('uid', widget.proUid).eq('is_main', true).maybeSingle();
      _educationBilanRequis = row?['education_bilan_requis'] as bool? ?? true;
      _delaiMinReservationH = (row?['delai_min_reservation_h'] as num?)?.toInt() ?? 0;
      _origineDefaut = row?['trajet_origine_defaut']?.toString() ?? 'cabinet';
      _autreDomicileLat = (row?['autre_domicile_lat'] as num?)?.toDouble();
      _autreDomicileLng = (row?['autre_domicile_lng'] as num?)?.toDouble();
      _cabinetLat = (row?['latitude'] as num?)?.toDouble() ?? (row?['lat'] as num?)?.toDouble();
      _cabinetLng = (row?['longitude'] as num?)?.toDouble() ?? (row?['lng'] as num?)?.toDouble();

      var q = _supa.from('prestations_education').select().eq('pro_uid', widget.proUid).eq('actif', true);
      if (_resolvedProfileId != null && _resolvedProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', _resolvedProfileId!);
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
    } catch (_) {/* liste vide si échec */}
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
      if (_resolvedProfileId != null && _resolvedProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', _resolvedProfileId!);
      }
      final rows = await q.limit(1);
      _isFirstTimeClient = (rows as List).isEmpty;
    } catch (_) {}
  }

  // Charge (une seule fois) les créneaux + RDV d'une semaine donnée.
  Future<void> _loadWeek(DateTime anyDayOfWeek) async {
    final wk = _weekKey(anyDayOfWeek);
    // Séances de groupe : rechargées dès qu'on choisit un cours collectif
    // (clé absente de _coursByWeek), indépendamment du cache créneaux/RDV.
    if (_isCollectif && !_coursByWeek.containsKey(wk)) {
      await _loadCoursWeek(wk);
    }
    if (_slotsByWeek.containsKey(wk) || _loadingWeeks.contains(wk)) return;
    _loadingWeeks.add(wk);
    if (mounted) setState(() {});
    final mp = wk.split('-');
    final monday = DateTime(int.parse(mp[0]), int.parse(mp[1]), int.parse(mp[2]));
    final sunday = _addDays(monday, 6);
    final profileId = _resolvedProfileId ?? '';

    try {
      final rows = await _supa.from('creneaux_pro')
          .select('date, heure_debut, heure_fin, type_prestation, domicile_ok, trajet_origine')
          .eq('pro_uid', widget.proUid)
          .eq('statut', 'disponible')
          .eq('pro_profile_id', profileId)
          .gte('date', _dateKey(monday))
          .lte('date', _dateKey(sunday))
          .order('date', ascending: true)
          .order('heure_debut', ascending: true);
      _slotsByWeek[wk] = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) { _slotsByWeek[wk] = []; }

    try {
      final rows = await _supa.from('rdv')
          .select('date_heure, duree_minutes, statut, lieu_lat, lieu_lng')
          .eq('pro_uid', widget.proUid)
          .eq('pro_profile_id', profileId)
          .inFilter('statut', ['confirme', 'demande'])
          .gte('date_heure', monday.toUtc().toIso8601String())
          .lte('date_heure', _addDays(sunday, 1).toUtc().toIso8601String());
      _rdvsByWeek[wk] = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) { _rdvsByWeek[wk] = []; }

    _loadingWeeks.remove(wk);
    if (mounted) setState(() {});
  }

  // Charge les séances de groupe (cours collectif) d'une semaine + le nombre
  // d'inscrits par séance — pour afficher « x/y places » sur chaque créneau
  // fixe et rattacher une réservation à la bonne séance.
  Future<void> _loadCoursWeek(String wk) async {
    final mp = wk.split('-');
    final monday = DateTime(int.parse(mp[0]), int.parse(mp[1]), int.parse(mp[2]));
    final sunday = _addDays(monday, 6);
    final profileId = _resolvedProfileId ?? '';
    try {
      final rows = await _supa.from('cours_collectifs')
          .select('id, date_heure, capacite_max')
          .eq('pro_uid', widget.proUid)
          .eq('pro_profile_id', profileId)
          .neq('statut', 'annule')
          .gte('date_heure', monday.toUtc().toIso8601String())
          .lte('date_heure', _addDays(sunday, 1).toUtc().toIso8601String());
      final cours = List<Map<String, dynamic>>.from(rows as List);
      final ids = cours.map((c) => c['id'].toString()).toList();
      final counts = <String, int>{};
      if (ids.isNotEmpty) {
        final parts = await _supa.from('cours_collectifs_participants')
            .select('cours_id').inFilter('cours_id', ids).neq('statut', 'annule');
        for (final p in parts as List) {
          final cid = p['cours_id'].toString();
          counts[cid] = (counts[cid] ?? 0) + 1;
        }
      }
      _coursByWeek[wk] = cours.map((c) => <String, dynamic>{
        'date_heure': c['date_heure'],
        'coursId': c['id'].toString(),
        'capacite': (c['capacite_max'] as num?)?.toInt() ?? 6,
        'inscrits': counts[c['id'].toString()] ?? 0,
      }).toList();
    } catch (_) { _coursByWeek[wk] = []; }
    if (mounted) setState(() {});
  }

  // Sondage léger : 1re date (≥ aujourd'hui) où le pro a une dispo compatible
  // avec le type de cours choisi (collectif ⇔ créneaux collectif ; sinon
  // créneaux individuels, à domicile si demandé). 1 ligne → pas de plafond.
  Future<DateTime?> _firstAvailableDate({required bool domicileOnly}) async {
    final profileId = _resolvedProfileId ?? '';
    try {
      var q = _supa.from('creneaux_pro')
          .select('date')
          .eq('pro_uid', widget.proUid)
          .eq('statut', 'disponible')
          .eq('pro_profile_id', profileId)
          .gte('date', _dateKey(DateTime.now()));
      if (_isCollectif) {
        q = q.eq('type_prestation', 'collectif');
      } else {
        q = q.or('type_prestation.is.null,type_prestation.neq.collectif');
      }
      if (domicileOnly && !_isCollectif) q = q.eq('domicile_ok', true);
      final rows = await q.order('date', ascending: true).limit(1);
      if ((rows as List).isEmpty) return null;
      final p = (rows.first['date'] as String).split('-');
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) { return null; }
  }

  // Positionne le calendrier sur la 1re semaine réservable si la semaine
  // affichée est plus tôt / vide, puis charge cette semaine.
  Future<void> _goToFirstAvailableWeek() async {
    if (_probing) return;
    _probing = true;
    final first = await _firstAvailableDate(domicileOnly: _domicile);
    _probing = false;
    _probed = true;
    _probedFirstDate = first;
    if (!mounted) return;
    if (first != null) {
      final mondayNorm = _addDays(first, -(first.weekday - 1));
      if (mondayNorm.isAfter(_weekStart)) {
        setState(() => _weekStart = mondayNorm);
      } else {
        setState(() {});
      }
      await _loadWeek(_weekStart);
    } else {
      setState(() {});
    }
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _duration => (_selectedPrestation?['duree_minutes'] as num?)?.toInt() ?? 60;

  // Cours collectif : créneaux fixes bout à bout + inscription à une séance
  // de groupe (capacité / liste d'attente) au lieu d'un RDV 1-pour-1.
  bool get _isCollectif => _selectedPrestation?['type'] == 'collectif';

  // Créneaux intelligents : fusion des plages creneaux_pro disponibles,
  // découpées à la durée du cours choisi. Calculé pour la SEULE semaine
  // affichée (créneaux/RDV chargés semaine par semaine).
  //  - Cours INDIVIDUEL : créneaux glissants (pas de 15 min), moins les RDV
  //    déjà posés, filtre trajet à domicile — comme rdv_booking_page.dart.
  //  - Cours COLLECTIF : créneaux FIXES bout à bout (pas = durée), à partir
  //    des plages `type_prestation == 'collectif'` uniquement ; chaque
  //    créneau porte les places restantes de la séance de groupe existante.
  Map<String, List<Map<String, dynamic>>> get _smartSlotsByDate {
    if (_selectedPrestation == null) return {};
    final wk = _weekKey(_weekStart);
    final weekSlots = _slotsByWeek[wk] ?? const [];
    final weekRdvs = _rdvsByWeek[wk] ?? const [];
    final weekCours = _coursByWeek[wk] ?? const [];
    if (weekSlots.isEmpty) return {};
    final isCollectif = _isCollectif;
    final duration = _duration;
    final step = isCollectif ? duration : 15;
    final now = DateTime.now();
    // Heure minimale réservable : maintenant + délai imposé par le pro
    // (repli 30 min si aucun délai). Gère le multi-jours.
    final earliestBookable = _delaiMinReservationH > 0
        ? now.add(Duration(hours: _delaiMinReservationH))
        : now.add(const Duration(minutes: 30));

    final creneauxByDate = <String, List<({int startMin, int endMin, String? origine})>>{};
    for (final slot in weekSlots) {
      final slotCollectif = slot['type_prestation'] == 'collectif';
      if (isCollectif != slotCollectif) continue;
      if (!isCollectif && _domicile && slot['domicile_ok'] != true) continue;
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
      final rdvsDuJour = weekRdvs.where((rdv) {
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
      final dp = date.split('-');
      final dayDate = DateTime(int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]));
      for (final window in windows) {
        for (int t = window.startMin; t + duration <= window.endMin; t += step) {
          if (dayDate.add(Duration(minutes: t)).isBefore(earliestBookable)) continue;

          if (!isCollectif) {
            final overlaps = blocked.any((b) => t < b.endMin && t + duration > b.startMin);
            if (overlaps) continue;
            if (_domicile && _domicileLat != null && _domicileLng != null) {
              if (!_trajetOk(t, t + duration, window.origine, rdvsDuJour)) continue;
            }
          }

          final h = t ~/ 60, m = t % 60;
          final eh = (t + duration) ~/ 60, em = (t + duration) % 60;
          final entry = <String, dynamic>{
            'date': date,
            'heure_debut': '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00',
            'heure_fin': '${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}:00',
          };
          if (isCollectif) {
            // Rattache ce créneau fixe à la séance de groupe existante (même
            // instant) pour afficher les places restantes.
            final capaciteDefaut = (_selectedPrestation?['capacite_max'] as num?)?.toInt() ?? 6;
            Map<String, dynamic>? match;
            for (final c in weekCours) {
              final cdh = DateTime.tryParse(c['date_heure']?.toString() ?? '')?.toLocal();
              if (cdh != null && cdh.year == dayDate.year && cdh.month == dayDate.month
                  && cdh.day == dayDate.day && cdh.hour == h && cdh.minute == m) {
                match = c;
                break;
              }
            }
            final capacite = (match?['capacite'] as int?) ?? capaciteDefaut;
            final inscrits = (match?['inscrits'] as int?) ?? 0;
            entry['coursId'] = match?['coursId'];
            entry['capacite'] = capacite;
            entry['inscrits'] = inscrits;
            entry['complet'] = inscrits >= capacite;
          }
          available.add(entry);
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
      _probed = false;
      _probedFirstDate = null;
    });
    _goToFirstAvailableWeek(); // re-sonde avec le filtre domicile
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adresse introuvable — les créneaux à domicile ne pourront pas être filtrés par trajet.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _shiftWeek(int days) {
    setState(() => _weekStart = _addDays(_weekStart, days));
    _loadWeek(_weekStart);
  }

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
          _recapLine('Lieu', (_isCollectif || !_domicile)
              ? ((prestation['lieu_adresse']?.toString().trim().isNotEmpty ?? false)
                  ? prestation['lieu_adresse'].toString()
                  : 'Chez le professionnel')
              : 'À domicile — ${_adresseDomicileCtrl.text.trim()}'),
          if (_isCollectif)
            _recapLine('Places', '${slot['inscrits']}/${slot['capacite']}'
                '${slot['complet'] == true ? ' — liste d\'attente' : ''}'),
          const SizedBox(height: 12),
          if (_isFirstTimeClient) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x0C7B5EA7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x267B5EA7)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Première fois avec ce professionnel',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                const SizedBox(height: 8),
                TextField(controller: _notesCtrl, maxLines: 3, style: const TextStyle(fontFamily: 'Galey'),
                    decoration: const InputDecoration(
                      labelText: 'Décrivez brièvement votre besoin',
                      helperText: 'Visible par le professionnel — facultatif mais utile',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                      filled: true, fillColor: Colors.white,
                    )),
              ]),
            ),
          ] else
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
    if (confirm == true) {
      if (_isCollectif) {
        await _inscrireCollectif(dateHeure);
      } else {
        await _submit(dateHeure);
      }
    }
  }

  // Nom à afficher au pro : celui de la personne (le pro veut pouvoir
  // appeler / reconnaître le client), pas le nom d'élevage.
  String get _clientDisplayName {
    final n = '${User_Info.firstname} ${User_Info.lastname}'.trim();
    if (n.isNotEmpty && n != 'none none') return n;
    if (User_Info.nameElevage.isNotEmpty) return User_Info.nameElevage;
    return 'Un client';
  }

  // Réservation d'un cours collectif = inscription à une séance de groupe.
  // Réutilise le patron de service_detail_page.dart _inscrireAuCours :
  // find-or-create de la séance, comptage capacité → 'demande' ou
  // 'en_attente' (liste d'attente), notif au pro.
  Future<void> _inscrireCollectif(DateTime dateHeure) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final prestation = _selectedPrestation;
    if (uid == null || prestation == null) return;
    setState(() => _saving = true);
    try {
      final profileId = _resolvedProfileId ?? '';
      final utc = dateHeure.toUtc().toIso8601String();

      String? coursId = _selectedSlot?['coursId']?.toString();
      if (coursId == null) {
        final existing = await _supa.from('cours_collectifs').select('id')
            .eq('pro_uid', widget.proUid)
            .eq('pro_profile_id', profileId)
            .eq('date_heure', utc)
            .neq('statut', 'annule')
            .limit(1);
        if ((existing as List).isNotEmpty) {
          coursId = existing.first['id'].toString();
        } else {
          final created = await _supa.from('cours_collectifs').insert({
            'pro_uid': widget.proUid,
            'pro_profile_id': profileId,
            'prestation_id': prestation['id'],
            'titre': prestation['nom']?.toString() ?? 'Cours collectif',
            'date_heure': utc,
            'duree_minutes': _duration,
            'capacite_max': (prestation['capacite_max'] as num?)?.toInt() ?? 6,
            if (prestation['lieu_adresse']?.toString().trim().isNotEmpty ?? false)
              'lieu': prestation['lieu_adresse'],
            if (prestation['lieu_lat'] != null) 'lieu_lat': prestation['lieu_lat'],
            if (prestation['lieu_lng'] != null) 'lieu_lng': prestation['lieu_lng'],
            'statut': 'planifie',
          }).select('id').single();
          coursId = created['id'].toString();
        }
      }

      final current = await _supa.from('cours_collectifs_participants')
          .select('id').eq('cours_id', coursId).neq('statut', 'annule');
      final capacite = (_selectedSlot?['capacite'] as int?)
          ?? (prestation['capacite_max'] as num?)?.toInt() ?? 6;
      final complet = (current as List).length >= capacite;

      await _supa.from('cours_collectifs_participants').insert({
        'cours_id': coursId,
        'client_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'client_profile_id': User_Info.activeProfileId,
        if (_selectedAnimal?['id'] != null) 'animal_id': _selectedAnimal!['id'].toString(),
        if ((prestation['prix'] as num?) != null) 'prix': prestation['prix'],
        'statut': complet ? 'en_attente' : 'demande',
      });

      final dateStr = DateFormat('dd/MM à HH:mm').format(dateHeure);
      final animalNom = _selectedAnimal?['nom']?.toString() ?? 'son animal';
      await _supa.from('notifications').insert({
        'uid': widget.proUid,
        'type': 'cours_collectif_inscription',
        'title': 'Demande d\'inscription — ${prestation['nom']}',
        'body': '$_clientDisplayName souhaite inscrire $animalNom au cours du $dateStr — en attente de votre confirmation.',
        if (profileId.isNotEmpty) 'profile_id': profileId,
        'data': <String, dynamic>{'coursId': coursId},
        'read': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            complet
                ? 'Demande envoyée — vous êtes en liste d\'attente (séance complète).'
                : 'Demande envoyée — en attente de confirmation du professionnel.',
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          backgroundColor: complet ? Colors.orange : const Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
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
        'pro_profile_id': _resolvedProfileId ?? '',
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
        // Lieu propre au cours (parc…) si pas à domicile
        if (!_domicile && (_selectedPrestation?['lieu_adresse']?.toString().trim().isNotEmpty ?? false))
          'lieu': _selectedPrestation!['lieu_adresse'],
        if (!_domicile && _selectedPrestation?['lieu_lat'] != null) 'lieu_lat': _selectedPrestation!['lieu_lat'],
        if (!_domicile && _selectedPrestation?['lieu_lng'] != null) 'lieu_lng': _selectedPrestation!['lieu_lng'],
        'statut': 'demande',
      });

      final clientName = _clientDisplayName;
      final dateStr = DateFormat('dd/MM à HH:mm').format(dateHeure);
      await _supa.from('notifications').insert({
        'uid': widget.proUid,
        'type': 'rdv_demande',
        'title': 'Nouvelle demande de RDV',
        'body': '$clientName souhaite un cours "${_selectedPrestation!['nom']}" le $dateStr',
        if (_resolvedProfileId != null && _resolvedProfileId!.isNotEmpty) 'profile_id': _resolvedProfileId,
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
              onTap: () {
                setState(() {
                  _selectedPrestation = p;
                  _domicile = false;
                  // Collectif : jamais à domicile → pas d'étape de choix.
                  _domicileChoiceMade = p['type'] == 'collectif' || p['domicile_ok'] != true;
                  _domicileLat = null;
                  _domicileLng = null;
                  _adresseDomicileCtrl.clear();
                  _coursByWeek.clear(); // dépend du cours choisi
                  _probed = false;
                  _probedFirstDate = null;
                });
                _goToFirstAvailableWeek();
              },
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
                    Text('${p['duree_minutes']} min'
                        '${(p['prix'] as num?) != null ? ' · ${(p['prix'] as num).toStringAsFixed(0)} €' : ''}'
                        '${p['type'] == 'collectif' ? ' · en groupe (max ${(p['capacite_max'] as num?)?.toInt() ?? 6})' : ''}',
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
            onPressed: () {
              setState(() { _domicile = false; _domicileChoiceMade = true; _probed = false; _probedFirstDate = null; });
              _goToFirstAvailableWeek();
            },
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
    final days = List.generate(_joursSemaine, (i) => _addDays(_weekStart, i));
    final today = DateTime.now();
    final weekLoading = _loadingWeeks.contains(_weekKey(_weekStart)) || _probing;
    // Le sondage a fini et n'a rien trouvé → le pro n'a aucune dispo publiée.
    final aucuneDispo = _probed && _probedFirstDate == null && !weekLoading;
    // On ne montre que les jours qui ont au moins un créneau du type choisi.
    final visibleDays = days.where((d) => (smartSlots[_dateKey(d)] ?? []).isNotEmpty).toList();
    final semaineVide = !aucuneDispo && !weekLoading && visibleDays.isEmpty;
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
      if (weekLoading)
        const LinearProgressIndicator(minHeight: 2)
      else if (aucuneDispo)
        Container(
          width: double.infinity,
          color: Colors.orange.shade50,
          padding: const EdgeInsets.all(12),
          child: Text('Ce professionnel n\'a pas encore publié de disponibilités pour ce type de cours.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade800)),
        )
      else if (semaineVide)
        Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.06),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: Text('Rien de disponible cette semaine.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color))),
            TextButton(
              onPressed: _goToFirstAvailableWeek,
              child: Text('Voir les prochaines dispos ›',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
        ),
      Expanded(
        child: visibleDays.isEmpty
            ? const SizedBox.shrink()
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: visibleDays.length,
          itemBuilder: (_, i) {
            final day = visibleDays[i];
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
                Wrap(spacing: 8, runSpacing: 8, children: slots.map((s) {
                  final heure = (s['heure_debut'] as String).substring(0, 5);
                  final complet = s['complet'] == true;
                  final hasPlaces = s.containsKey('capacite');
                  return OutlinedButton(
                    onPressed: () => _pickSlot(s),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: complet ? Colors.orange.shade800 : color,
                      side: BorderSide(color: complet ? Colors.orange.shade300 : color),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                      if (hasPlaces)
                        Text(complet ? 'complet' : '${s['inscrits']}/${s['capacite']} pl.',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                color: complet ? Colors.orange.shade700 : Colors.grey.shade500)),
                    ]),
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
