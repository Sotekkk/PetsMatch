import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/animal_picker_sheet.dart';
import 'package:PetsMatch/main.dart' show User_Info;

class RdvBookingPage extends StatefulWidget {
  final String proUid;
  final String proName;
  final Color categoryColor;
  final bool isPension;
  final bool isVet;
  final bool isAssociation;
  final bool isGarde;
  final String? preselectedAnimalId;
  final String? proProfileId; // user_profiles.id si profil secondaire
  final Map<String, dynamic>? visiteAnimal; // animal de l'association à visiter (id, nom, espece, photo_url)

  const RdvBookingPage({
    super.key,
    required this.proUid,
    required this.proName,
    required this.categoryColor,
    this.isPension = false,
    this.isVet = false,
    this.isAssociation = false,
    this.isGarde = false,
    this.preselectedAnimalId,
    this.proProfileId,
    this.visiteAnimal,
  });

  @override
  State<RdvBookingPage> createState() => _RdvBookingPageState();
}

class _RdvBookingPageState extends State<RdvBookingPage> {
  static const _bg = Color(0xFFF8F8F8);

  // Common
  bool _loadingData = true;
  bool _saving = false;
  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>? _selectedAnimal;
  final _notesCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();

  // Créneaux (tous les pros)
  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> _existingRdvs = [];
  String? _selectedDateKey;
  Map<String, dynamic>? _selectedSlot;
  // Garde : RDV récurrent (visites/promenades hebdomadaires)
  bool _recurrent = false;
  int _occurrences = 4;
  static const _occurrenceChoices = [4, 8, 12];
  // Pension-specific
  String? _selectedMotif;
  bool? _premiereVisite;

  static const _pensionMotifs = [
    ('visite',  'Visite de la pension',  Icons.tour_outlined),
    ('arrivee', 'Arrivée de l\'animal',  Icons.login_outlined),
    ('depart',  'Départ de l\'animal',   Icons.logout_outlined),
    ('autre',   'Autre',                 Icons.more_horiz_outlined),
  ];

  static const _vetMotifs = [
    ('consultation', 'Consultation',  Icons.medical_services_outlined),
    ('vaccination',  'Vaccination',   Icons.medication_outlined),
    ('bilan',        'Bilan annuel',  Icons.assignment_outlined),
    ('urgence',      'Urgence',       Icons.warning_amber_outlined),
    ('chirurgie',    'Chirurgie',     Icons.healing_outlined),
    ('autre',        'Autre',         Icons.more_horiz_outlined),
  ];

  String? _selectedVetMotif;
  int _selectedVetDuration = 30;

  // Durées et motifs dynamiques (chargés depuis le profil du pro)
  Map<String, int> _dureesMotifs = {};
  String _catPro = '';
  String? _selectedMotifKey; // pour les pros autres que vet/pension

  // Éducateur : un nouveau client ne peut réserver qu'un bilan tant qu'il
  // n'a pas eu de séance confirmée avec ce pro (sauf si le pro désactive
  // cette exigence dans son profil).
  bool _educationBilanRequis = true;
  bool _isFirstTimeEducationClient = false;

  static const _motifLabels = <String, String>{
    'consultation': 'Consultation', 'vaccination': 'Vaccination',
    'bilan': 'Bilan annuel', 'urgence': 'Urgence', 'chirurgie': 'Chirurgie',
    'visite': 'Visite', 'arrivee': 'Arrivée', 'depart': 'Départ',
    'promenade_30min': 'Promenade 30 min', 'promenade_1h': 'Promenade 1h',
    'promenade_2h': 'Promenade 2h', 'garde_journee': 'Garde journée',
    'cours_individuel': 'Cours individuel', 'cours_collectif': 'Cours collectif',
    'evaluation': 'Évaluation', 'bain': 'Bain',
    'toilettage_complet': 'Toilettage complet', 'coupe': 'Coupe',
    'seance': 'Séance', 'visite_adoption': 'Visite pour adoption', 'autre': 'Autre',
  };
  static const _motifIcons = <String, IconData>{
    'consultation': Icons.medical_services_outlined,
    'vaccination': Icons.medication_outlined,
    'bilan': Icons.assignment_outlined,
    'urgence': Icons.warning_amber_outlined,
    'chirurgie': Icons.healing_outlined,
    'visite': Icons.tour_outlined,
    'arrivee': Icons.login_outlined,
    'depart': Icons.logout_outlined,
    'promenade_30min': Icons.directions_walk_outlined,
    'promenade_1h': Icons.directions_walk_outlined,
    'promenade_2h': Icons.directions_walk,
    'garde_journee': Icons.home_outlined,
    'cours_individuel': Icons.school_outlined,
    'cours_collectif': Icons.groups_outlined,
    'evaluation': Icons.quiz_outlined,
    'bain': Icons.bathtub_outlined,
    'toilettage_complet': Icons.content_cut_outlined,
    'coupe': Icons.content_cut_outlined,
    'seance': Icons.self_improvement_outlined,
    'visite_adoption': Icons.favorite_border,
    'autre': Icons.more_horiz_outlined,
  };
  static const _defaultDureesByCatPro = <String, Map<String, int>>{
    'veterinaire': {'consultation': 30, 'vaccination': 20, 'bilan': 45, 'urgence': 60, 'chirurgie': 120, 'autre': 30},
    'pension':     {'visite': 30, 'arrivee': 60, 'depart': 30, 'autre': 30},
    'garde':       {'promenade_30min': 30, 'promenade_1h': 60, 'promenade_2h': 120, 'garde_journee': 480, 'autre': 60},
    'education':   {'cours_individuel': 60, 'cours_collectif': 90, 'evaluation': 45, 'autre': 60},
    'toilettage':  {'bain': 45, 'toilettage_complet': 90, 'coupe': 60, 'autre': 60},
    'sante':       {'consultation': 45, 'seance': 60, 'autre': 60},
  };

  // Durée sélectionnée selon le motif choisi
  int get _selectedDuration {
    if (widget.isVet && _selectedVetMotif != null && _selectedVetMotif != 'autre') {
      return _dureesMotifs[_selectedVetMotif] ?? _selectedVetDuration;
    }
    if (widget.isPension && _selectedMotif != null && _selectedMotif != 'autre') {
      return _dureesMotifs[_selectedMotif] ?? 30;
    }
    if (_selectedMotifKey != null && _selectedMotifKey != 'autre') {
      return _dureesMotifs[_selectedMotifKey] ?? 30;
    }
    return _dureesMotifs['autre'] ?? 30;
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h$m' : '${h}h';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _motifCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAnimaux(),
      _loadProProfile(),
      _loadAvailableSlots(),
    ]);
    if (mounted) setState(() => _loadingData = false);
  }

  Future<void> _loadProProfile() async {
    if (widget.isAssociation) {
      _dureesMotifs = {'visite_adoption': 30, 'autre': 30};
      _selectedMotifKey = 'visite_adoption';
      return;
    }
    try {
      // Profil secondaire (pension, éducateur…) → user_profiles ; sinon
      // compte principal → users. Sans cette distinction, cat_pro et
      // durees_motifs d'un profil secondaire ne sont jamais résolus (on lit
      // toujours le profil principal, potentiellement d'un autre type).
      final row = (widget.proProfileId != null && widget.proProfileId!.isNotEmpty)
          ? await Supabase.instance.client
              .from('user_profiles')
              .select('durees_motifs, profile_type, cat_pro, education_bilan_requis')
              .eq('id', widget.proProfileId!)
              .maybeSingle()
          : await Supabase.instance.client
              .from('users')
              .select('durees_motifs, cat_pro')
              .eq('uid', widget.proUid)
              .maybeSingle();
      if (row != null && mounted) {
        _catPro = row['profile_type']?.toString() ?? row['cat_pro']?.toString() ?? '';
        if (row['durees_motifs'] is Map) {
          _dureesMotifs = Map<String, int>.from(
            (row['durees_motifs'] as Map).map((k, v) =>
                MapEntry(k.toString(), (v as num?)?.toInt() ?? 30)));
        }
        if (_dureesMotifs.isEmpty) {
          final cat = _catPro.isNotEmpty ? _catPro
              : widget.isVet ? 'veterinaire'
              : widget.isPension ? 'pension' : '';
          _dureesMotifs = Map<String, int>.from(
              _defaultDureesByCatPro[cat] ?? {'consultation': 30, 'autre': 30});
        }
        _educationBilanRequis = row['education_bilan_requis'] as bool? ?? true;
        if (_catPro == 'education') await _checkFirstTimeEducationClient();
      }
    } catch (_) {}
  }

  // Un client est "nouveau" s'il n'a jamais eu de séance confirmée/terminée
  // avec ce pro — tant que le pro exige un bilan préalable, ses choix de
  // motif sont alors restreints à l'évaluation seule.
  Future<void> _checkFirstTimeEducationClient() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      var q = Supabase.instance.client.from('rdv').select('id')
          .eq('client_uid', uid).eq('pro_uid', widget.proUid)
          .inFilter('statut', ['confirme', 'termine']);
      if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', widget.proProfileId!);
      }
      final rows = await q.limit(1);
      _isFirstTimeEducationClient = (rows as List).isEmpty;
      if (_educationBilanRequis && _isFirstTimeEducationClient && _dureesMotifs.containsKey('evaluation')) {
        _dureesMotifs = {'evaluation': _dureesMotifs['evaluation'] ?? 45};
        _selectedMotifKey = 'evaluation';
      }
    } catch (_) {}
  }

  // ── Animal loading ────────────────────────────────────────────────────────────

  Future<void> _loadAnimaux() async {
    if (widget.isAssociation) {
      _selectedAnimal = widget.visiteAnimal;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final supa = Supabase.instance.client;
      final pid = User_Info.activeProfileId;
      // Scopé au profil actif du client réservant le RDV (pas tout le compte
      // Firebase) — sinon un compte multi-profil (ex. particulier + éleveur)
      // voit les animaux de tous ses profils au lieu du seul profil courant.
      var directQ = supa
          .from('animaux')
          .select('id, nom, espece, race, photo_url')
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid');
      if (pid.isNotEmpty) directQ = directQ.eq('profile_id', pid);
      final directRows = await directQ;
      final direct = List<Map<String, dynamic>>.from((directRows as List).map((e) => Map<String, dynamic>.from(e as Map)));

      // animaux_proprietes = source de vérité pour la propriété actuelle
      // (notamment après une cession — animaux.uid_proprietaire n'est pas
      // mis à jour lors d'une cession, seul animaux_proprietes l'est).
      var ownQ = supa.from('animaux_proprietes')
          .select('animal_id')
          .eq('uid_proprio', uid)
          .isFilter('date_fin', null);
      if (pid.isNotEmpty) ownQ = ownQ.eq('profile_id_proprio', pid);
      final ownRows = await ownQ;
      final cessionIds = (ownRows as List).map((r) => r['animal_id']?.toString()).whereType<String>().toSet();

      final missingIds = cessionIds.difference(direct.map((a) => a['id']?.toString() ?? '').toSet());
      List<Map<String, dynamic>> viaCession = [];
      if (missingIds.isNotEmpty) {
        final rows2 = await supa.from('animaux')
            .select('id, nom, espece, race, photo_url')
            .inFilter('id', missingIds.toList());
        viaCession = List<Map<String, dynamic>>.from((rows2 as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }

      final rows = [...direct, ...viaCession]..sort((a, b) => (a['nom']?.toString() ?? '').compareTo(b['nom']?.toString() ?? ''));
      if (mounted) {
        _animaux = rows;
        // Pré-sélection animal si fourni
        if (widget.preselectedAnimalId != null) {
          _selectedAnimal = _animaux.where(
              (a) => a['id']?.toString() == widget.preselectedAnimalId).firstOrNull;
        }
      }
    } catch (_) {}
  }

  // ── Créneaux disponibles (tous les pros) ─────────────────────────────────────

  Future<void> _loadAvailableSlots() async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      final maxDt = DateTime(now.year, now.month + 3, now.day);
      final maxDate = '${maxDt.year}-${maxDt.month.toString().padLeft(2,'0')}-${maxDt.day.toString().padLeft(2,'0')}';
      final profileId = widget.proProfileId ?? '';
      final results = await Future.wait([
        Supabase.instance.client
            .from('creneaux_pro')
            .select('date, heure_debut, heure_fin, type_prestation')
            .eq('pro_uid', widget.proUid)
            .eq('statut', 'disponible')
            .eq('pro_profile_id', profileId)
            .gte('date', today)
            .lte('date', maxDate)
            .order('date')
            .order('heure_debut')
            .limit(1000),
        Supabase.instance.client
            .from('rdv')
            .select('date_heure, duree_minutes, statut')
            .eq('pro_uid', widget.proUid)
            .eq('pro_profile_id', profileId)
            .inFilter('statut', ['confirme', 'demande'])
            .gte('date_heure', now.toUtc().toIso8601String()),
      ]);

      if (mounted) {
        _availableSlots = (results[0] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _existingRdvs = (results[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
  }

  // Créneaux intelligents : 15 min d'intervalle, en tenant compte des RDVs existants
  Map<String, List<Map<String, dynamic>>> get _smartSlotsByDate {
    final duration = _selectedDuration;
    if (_availableSlots.isEmpty) return {};

    // Pour aujourd'hui, on ne propose que les créneaux futurs (+ 30 min de marge)
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final nowMinutes = now.hour * 60 + now.minute + 30; // marge 30 min

    // 1. Grouper les creneaux_pro par date
    // Un créneau marqué "collectif" par un éducateur est réservé à ses cours
    // collectifs (planifiés séparément) — non proposé ici pour un RDV individuel.
    final creneauxByDate = <String, List<({int startMin, int endMin})>>{};
    for (final slot in _availableSlots) {
      if (_catPro == 'education' && slot['type_prestation'] == 'collectif') continue;
      final date = slot['date'] as String;
      final sp = (slot['heure_debut'] as String).split(':');
      final ep = (slot['heure_fin']   as String).split(':');
      final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      creneauxByDate.putIfAbsent(date, () => []).add((startMin: s, endMin: e));
    }

    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in creneauxByDate.entries) {
      final date = entry.key;
      final slots = entry.value..sort((a, b) => a.startMin.compareTo(b.startMin));

      // 2. Fusionner les créneaux consécutifs en fenêtres continues
      final windows = <({int startMin, int endMin})>[];
      for (final s in slots) {
        if (windows.isNotEmpty && s.startMin <= windows.last.endMin) {
          windows[windows.length - 1] = (
            startMin: windows.last.startMin,
            endMin: s.endMin > windows.last.endMin ? s.endMin : windows.last.endMin,
          );
        } else {
          windows.add(s);
        }
      }

      // 3. Intervals bloqués par les RDVs existants pour ce jour
      final blocked = <({int startMin, int endMin})>[];
      for (final rdv in _existingRdvs) {
        final dh = DateTime.tryParse(rdv['date_heure'] as String? ?? '')?.toLocal();
        if (dh == null) continue;
        final rdvDate = '${dh.year}-${dh.month.toString().padLeft(2,'0')}-${dh.day.toString().padLeft(2,'0')}';
        if (rdvDate != date) continue;
        final rdvDuree = (rdv['duree_minutes'] as num?)?.toInt() ?? 30;
        final rdvStart = dh.hour * 60 + dh.minute;
        blocked.add((startMin: rdvStart, endMin: rdvStart + rdvDuree));
      }

      // 4. Générer les créneaux disponibles (pas de 15 min)
      final available = <Map<String, dynamic>>[];
      for (final window in windows) {
        for (int t = window.startMin; t + duration <= window.endMin; t += 15) {
          // Pour aujourd'hui : ignorer les créneaux déjà passés (+ 30 min de marge)
          if (date == todayKey && t < nowMinutes) continue;
          final overlaps = blocked.any((b) => t < b.endMin && t + duration > b.startMin);
          if (!overlaps) {
            final h = t ~/ 60;
            final m = t % 60;
            final eh = (t + duration) ~/ 60;
            final em = (t + duration) % 60;
            available.add({
              'date': date,
              'heure_debut': '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:00',
              'heure_fin':   '${eh.toString().padLeft(2,'0')}:${em.toString().padLeft(2,'0')}:00',
            });
          }
        }
      }
      if (available.isNotEmpty) result[date] = available;
    }
    return result;
  }

  List<String> get _availableDates => _smartSlotsByDate.keys.toList()..sort();

  // ── Récurrence (garde uniquement) ────────────────────────────────────────────
  // Vérifie que TOUS les créneaux de 15 min nécessaires à la durée sont marqués
  // disponibles pour cette date, et qu'aucun RDV existant ne chevauche.
  bool _isDateSlotAvailable(DateTime date, String heureDebut, int durationMin) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final startParts = heureDebut.split(':');
    final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMin = startMin + durationMin;

    final freeSet = <int>{};
    for (final slot in _availableSlots) {
      if (slot['date'] != dateStr) continue;
      final sp = (slot['heure_debut'] as String).split(':');
      freeSet.add(int.parse(sp[0]) * 60 + int.parse(sp[1]));
    }
    for (var m = startMin; m < endMin; m += 15) {
      if (!freeSet.contains(m)) return false;
    }

    for (final rdv in _existingRdvs) {
      final dh = DateTime.tryParse(rdv['date_heure'] as String? ?? '')?.toLocal();
      if (dh == null) continue;
      if (dh.year != date.year || dh.month != date.month || dh.day != date.day) continue;
      final rdvStart = dh.hour * 60 + dh.minute;
      final rdvEnd = rdvStart + ((rdv['duree_minutes'] as num?)?.toInt() ?? 30);
      if (startMin < rdvEnd && endMin > rdvStart) return false;
    }
    return true;
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Validation créneau (tous les pros)
    if (_selectedSlot == null) {
      _snack('Veuillez sélectionner un créneau disponible', color: Colors.orange); return;
    }

    // Validation motif selon type
    if (widget.isPension) {
      if (_selectedMotif == null) {
        _snack('Veuillez choisir le motif du rendez-vous', color: Colors.orange); return;
      }
      if (_selectedMotif == 'autre' && _notesCtrl.text.trim().isEmpty) {
        _snack('Précisez le motif dans le champ "Autre"', color: Colors.orange); return;
      }
    } else if (widget.isVet) {
      if (_selectedVetMotif == null) {
        _snack('Veuillez choisir le motif de la consultation', color: Colors.orange); return;
      }
      if (_selectedVetMotif == 'autre' && _motifCtrl.text.trim().isEmpty) {
        _snack('Précisez le motif dans le champ "Autre"', color: Colors.orange); return;
      }
    } else if (_dureesMotifs.isNotEmpty) {
      // Pros avec motifs dynamiques
      if (_selectedMotifKey == null) {
        _snack('Veuillez choisir le type de prestation', color: Colors.orange); return;
      }
      if (_selectedMotifKey == 'autre' && _motifCtrl.text.trim().isEmpty) {
        _snack('Précisez le motif dans le champ "Autre"', color: Colors.orange); return;
      }
    } else {
      if (_motifCtrl.text.trim().isEmpty) {
        _snack('Veuillez indiquer le motif du rendez-vous', color: Colors.orange); return;
      }
    }

    setState(() => _saving = true);
    try {
      // Tous les pros : créneau sélectionné depuis creneaux_pro
      final slotDate = DateTime.parse(_selectedSlot!['date'] as String);
      final heureDebut = (_selectedSlot!['heure_debut'] as String).split(':');
      final dateHeure = DateTime(slotDate.year, slotDate.month, slotDate.day,
          int.parse(heureDebut[0]), int.parse(heureDebut[1])).toUtc();

      final String motif;
      if (widget.isPension) {
        motif = _selectedMotif == 'autre'
            ? _notesCtrl.text.trim()
            : _pensionMotifs.firstWhere((m) => m.$1 == _selectedMotif).$2;
      } else if (widget.isVet) {
        motif = _selectedVetMotif == 'autre'
            ? _motifCtrl.text.trim()
            : _vetMotifs.firstWhere((m) => m.$1 == _selectedVetMotif).$2;
      } else if (_selectedMotifKey != null && _selectedMotifKey != 'autre') {
        motif = _motifLabels[_selectedMotifKey] ?? _selectedMotifKey!;
      } else {
        motif = _motifCtrl.text.trim();
      }

      final animalId = _selectedAnimal?['id']?.toString();
      final dureeToSend = _selectedDuration;

      // Récurrence (garde uniquement) : une série hebdomadaire à partir du
      // créneau choisi, en ne retenant que les dates réellement disponibles
      // (créneaux du pro + absence de conflit avec un RDV existant).
      final occurrenceDates = <DateTime>[slotDate];
      if (widget.isGarde && _recurrent) {
        for (var i = 1; i < _occurrences; i++) {
          final d = slotDate.add(Duration(days: 7 * i));
          if (_isDateSlotAvailable(d, (_selectedSlot!['heure_debut'] as String), dureeToSend)) {
            occurrenceDates.add(d);
          }
        }
      }

      final heureDebutStr = _selectedSlot!['heure_debut'] as String;
      final rows = occurrenceDates.map((d) {
        final hp = heureDebutStr.split(':');
        final dh = DateTime(d.year, d.month, d.day, int.parse(hp[0]), int.parse(hp[1])).toUtc();
        return {
          'pro_uid':        widget.proUid,
          'pro_profile_id': widget.proProfileId ?? '',
          'client_uid': uid,
          if (User_Info.activeProfileId.isNotEmpty) 'client_profile_id': User_Info.activeProfileId,
          if (animalId != null && animalId.isNotEmpty) 'animal_id': animalId,
          'date_heure': dh.toIso8601String(),
          'motif':      motif,
          if (widget.isPension && _premiereVisite != null) 'premiere_visite': _premiereVisite,
          if (_notesCtrl.text.trim().isNotEmpty && (widget.isPension ? _selectedMotif != 'autre' : true))
            'notes_client': _notesCtrl.text.trim(),
          'duree_minutes': dureeToSend,
          'statut': 'demande',
        };
      }).toList();

      await Supabase.instance.client.from('rdv').insert(rows);

      // Notification in-app (cloche) pour le pro
      try {
        final clientName = FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true
            ? FirebaseAuth.instance.currentUser!.displayName!
            : 'Un client';
        final dateStr = _formatDate(dateHeure.toLocal());
        final isSerie = rows.length > 1;
        await Supabase.instance.client.from('notifications').insert({
          'uid':   widget.proUid,
          'type':  'rdv_demande',
          'title': isSerie ? 'Nouvelle série de RDV récurrents' : 'Nouvelle demande de RDV',
          'body':  isSerie
              ? '$clientName souhaite ${rows.length} RDV récurrents à partir du $dateStr — motif : $motif'
              : '$clientName souhaite un RDV le $dateStr — motif : $motif',
          if ((widget.proProfileId ?? '').isNotEmpty) 'profile_id': widget.proProfileId,
          'data':  <String, dynamic>{
            'client_uid': uid,
            if (_selectedAnimal != null) 'animal_nom': _selectedAnimal!['nom']?.toString() ?? '',
          },
          'read':  false,
        });

        // Push FCM via Cloud Function
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyProNewRdv')
            .call({
              'proUid':     widget.proUid,
              'clientName': clientName,
              'dateStr':    dateStr,
              'motif':      motif,
            });
      } catch (_) {}

      if (mounted) {
        if (widget.isGarde && _recurrent && rows.length < _occurrences) {
          _snack('${rows.length}/$_occurrences RDV créés — certaines dates n\'étaient pas disponibles.',
              color: widget.categoryColor);
        } else if (rows.length > 1) {
          _snack('${rows.length} demandes de RDV envoyées !', color: widget.categoryColor);
        } else {
          _snack('Demande de RDV envoyée !', color: widget.categoryColor);
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Erreur : $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Prendre un RDV',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loadingData
          ? Center(child: CircularProgressIndicator(color: widget.categoryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProBanner(),
                  const SizedBox(height: 20),
                  ..._buildMotifSection(),
                  const SizedBox(height: 20),
                  ..._buildSlotPicker(),
                  if (widget.isGarde && _selectedSlot != null) ...[
                    const SizedBox(height: 20),
                    _buildRecurrenceSection(),
                  ],
                  const SizedBox(height: 20),
                  _buildAnimalSection(),
                  const SizedBox(height: 20),
                  _buildNotesSection(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 8),
                  Center(child: Text(
                    widget.isPension
                        ? 'La pension vous confirmera l\'heure exacte de votre RDV.'
                        : widget.isVet
                            ? 'Le vétérinaire confirmera votre rendez-vous.'
                            : widget.isAssociation
                                ? 'L\'association confirmera votre rendez-vous de visite.'
                                : 'Le professionnel confirmera votre rendez-vous.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildProBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: widget.categoryColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: widget.categoryColor.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Icon(widget.isPension ? Icons.home_work_outlined
          : widget.isVet ? Icons.medical_services_outlined
          : widget.isAssociation ? Icons.favorite_border
          : Icons.person_outlined,
          color: widget.categoryColor, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.proName,
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 15, color: widget.categoryColor))),
    ]),
  );

  // ── Motif section (varie selon type de pro) ──────────────────────────────────

  List<Widget> _buildMotifSection() {
    if (widget.isPension) return _buildPensionMotif();
    if (widget.isVet) return _buildVetMotif();
    // Pour les autres pros : motifs dynamiques si configurés, sinon champ libre
    return _buildDynamicMotif();
  }

  // ── Slot picker (commun à tous les pros) ─────────────────────────────────────

  List<Widget> _buildSlotPicker() => [
    _sectionTitle('Choisir un créneau *'),
    const SizedBox(height: 10),
    _buildSlotSelector(),
  ];

  // ── Pension motif ─────────────────────────────────────────────────────────────

  List<Widget> _buildPensionMotif() => [
    _sectionTitle('Motif du rendez-vous *'),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8, runSpacing: 8,
      children: _pensionMotifs.map((m) {
        final sel = _selectedMotif == m.$1;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedMotif = m.$1;
            if (m.$1 != 'autre') _notesCtrl.clear();
            _selectedSlot = null; // recalcul des créneaux selon durée du motif
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? widget.categoryColor : Colors.white,
              border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
              boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                  blurRadius: 6, offset: const Offset(0, 2))] : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.$3, size: 16, color: sel ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(m.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : const Color(0xFF1E2025))),
            ]),
          ),
        );
      }).toList(),
    ),
    if (_selectedMotif == 'autre') ...[
      const SizedBox(height: 10),
      TextField(
        controller: _notesCtrl,
        maxLines: 2,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _inputDecoration('Précisez le motif…'),
      ),
    ],
    const SizedBox(height: 20),

    // Première visite
    _sectionTitle('Avez-vous déjà visité cette pension ?'),
    const SizedBox(height: 10),
    Row(children: [
      for (final v in [(true, 'Première visite'), (false, 'Déjà venu·e')]) ...[
        GestureDetector(
          onTap: () => setState(() => _premiereVisite = v.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _premiereVisite == v.$1 ? widget.categoryColor : Colors.white,
              border: Border.all(color: _premiereVisite == v.$1
                  ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(v.$2, style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                color: _premiereVisite == v.$1 ? Colors.white : const Color(0xFF1E2025))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ]),
    const SizedBox(height: 20),

  ];

  Widget _buildSlotSelector() {
    final dates = _availableDates;
    if (dates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E7E2)),
        ),
        child: Center(child: Column(children: [
          Icon(Icons.event_busy_outlined, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Aucun créneau disponible pour le moment',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Contactez le professionnel pour plus d\'informations',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
        ])),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontal date chips
        SizedBox(
          height: 68,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            itemBuilder: (_, i) {
              final dateStr = dates[i];
              final date = DateTime.tryParse(dateStr);
              if (date == null) return const SizedBox.shrink();
              final sel = _selectedDateKey == dateStr;
              final slotsCount = _smartSlotsByDate[dateStr]?.length ?? 0;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedDateKey = dateStr;
                  _selectedSlot = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? widget.categoryColor : Colors.white,
                    border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                        blurRadius: 6, offset: const Offset(0, 2))] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_weekdayShort(date),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: sel ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500)),
                    Text('${date.day}/${date.month}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : const Color(0xFF1E2025))),
                    Text('$slotsCount crén.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                            color: sel ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade400)),
                  ]),
                ),
              );
            },
          ),
        ),

        // Slots for selected date
        if (_selectedDateKey != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(_formatDateLong(DateTime.parse(_selectedDateKey!)),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 13, color: Color(0xFF1E2025)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.categoryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('⏱ ${_durationLabel(_selectedDuration)}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w600, color: widget.categoryColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: (_smartSlotsByDate[_selectedDateKey!] ?? []).map((slot) {
              final sel = _selectedSlot != null &&
                  _selectedSlot!['date'] == slot['date'] &&
                  _selectedSlot!['heure_debut'] == slot['heure_debut'];
              final debut = (slot['heure_debut'] as String).substring(0, 5);
              return GestureDetector(
                onTap: () => setState(() => _selectedSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? widget.categoryColor : Colors.white,
                    border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                        blurRadius: 6, offset: const Offset(0, 2))] : [],
                  ),
                  child: Text(debut,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : const Color(0xFF1E2025))),
                ),
              );
            }).toList(),
          ),
          if ((_smartSlotsByDate[_selectedDateKey!] ?? []).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Aucun créneau disponible pour cette durée (${_durationLabel(_selectedDuration)}) ce jour.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade700),
              ),
            ),
        ] else ...[
          const SizedBox(height: 10),
          Text('Sélectionnez une date pour voir les créneaux disponibles',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
        ],
      ],
    );
  }

  // ── Vet motif ─────────────────────────────────────────────────────────────────

  List<Widget> _buildVetMotif() => [
    _sectionTitle('Motif de la consultation *'),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8, runSpacing: 8,
      children: _vetMotifs.map((m) {
        final sel = _selectedVetMotif == m.$1;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedVetMotif = m.$1;
            // Auto-remplir la durée depuis la config du pro
            if (_dureesMotifs.containsKey(m.$1)) {
              _selectedVetDuration = _dureesMotifs[m.$1]!;
            }
            if (m.$1 != 'autre') _motifCtrl.clear();
            _selectedSlot = null; // recalcul des créneaux
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? widget.categoryColor : Colors.white,
              border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
              boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                  blurRadius: 6, offset: const Offset(0, 2))] : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.$3, size: 16, color: sel ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(m.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : const Color(0xFF1E2025))),
            ]),
          ),
        );
      }).toList(),
    ),
    if (_selectedVetMotif == 'autre') ...[
      const SizedBox(height: 10),
      TextField(
        controller: _motifCtrl,
        maxLines: 2,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _inputDecoration('Précisez le motif de la consultation…'),
      ),
    ],
    const SizedBox(height: 20),
    _sectionTitle('Première visite ?'),
    const SizedBox(height: 10),
    Row(children: [
      for (final v in [(true, 'Première visite'), (false, 'Déjà patient·e')]) ...[
        GestureDetector(
          onTap: () => setState(() => _premiereVisite = v.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _premiereVisite == v.$1 ? widget.categoryColor : Colors.white,
              border: Border.all(color: _premiereVisite == v.$1
                  ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(v.$2, style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                color: _premiereVisite == v.$1 ? Colors.white : const Color(0xFF1E2025))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ]),
  ];

  // ── Motifs dynamiques (tous pros hors vet/pension) ───────────────────────────

  List<Widget> _buildDynamicMotif() {
    if (_dureesMotifs.isEmpty) return _buildStandardMotif();
    return [
      _sectionTitle('Type de prestation *'),
      if (_catPro == 'education' && _educationBilanRequis && _isFirstTimeEducationClient) ...[
        const SizedBox(height: 6),
        Text('Premier rendez-vous avec ce professionnel : un bilan est requis avant de réserver un cours.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      ],
      const SizedBox(height: 10),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: _dureesMotifs.entries.map((e) {
          final sel = _selectedMotifKey == e.key;
          final label = _motifLabels[e.key] ?? e.key;
          final icon  = _motifIcons[e.key] ?? Icons.more_horiz_outlined;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedMotifKey = e.key;
              if (e.key != 'autre') _motifCtrl.clear();
              _selectedSlot = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? widget.categoryColor : Colors.white,
                border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                borderRadius: BorderRadius.circular(22),
                boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                    blurRadius: 6, offset: const Offset(0, 2))] : [],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: sel ? Colors.white : Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : const Color(0xFF1E2025))),
                const SizedBox(width: 6),
                Text(_durationLabel(e.value),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: sel ? Colors.white.withValues(alpha: 0.75) : Colors.grey.shade400)),
              ]),
            ),
          );
        }).toList(),
      ),
      if (_selectedMotifKey == 'autre') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _motifCtrl,
          maxLines: 2,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: _inputDecoration('Précisez le motif…'),
        ),
      ],
    ];
  }

  // ── Standard motif (fallback) ─────────────────────────────────────────────────

  List<Widget> _buildStandardMotif() => [
    _sectionTitle('Motif du rendez-vous *'),
    const SizedBox(height: 8),
    TextField(
      controller: _motifCtrl,
      maxLines: 3,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: _inputDecoration('Décrivez la raison de votre demande de RDV…'),
    ),
  ];

  // ── Récurrence (garde uniquement) ────────────────────────────────────────────

  Widget _buildRecurrenceSection() {
    final color = widget.categoryColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.repeat, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text('Répéter ce RDV chaque semaine',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: color))),
          Switch(
            value: _recurrent,
            activeThumbColor: color,
            onChanged: (v) => setState(() => _recurrent = v),
          ),
        ]),
        if (_recurrent) ...[
          const SizedBox(height: 4),
          Text('Idéal pour une promenade ou une visite régulière avec le même client.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: _occurrenceChoices.map((n) {
            final selected = _occurrences == n;
            return ChoiceChip(
              label: Text('$n semaines', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: selected ? Colors.white : color)),
              selected: selected,
              onSelected: (_) => setState(() => _occurrences = n),
              selectedColor: color,
              backgroundColor: color.withValues(alpha: 0.08),
              showCheckmark: false,
            );
          }).toList()),
        ],
      ]),
    );
  }

  // ── Animal & notes sections ───────────────────────────────────────────────────

  Widget _buildAnimalSection() {
    final color = widget.categoryColor;
    if (widget.isAssociation) {
      if (_selectedAnimal == null) return const SizedBox.shrink();
      final photoUrl = _selectedAnimal!['photo_url'] as String? ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Animal à visiter'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: 0.06),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoUrl.isNotEmpty
                      ? Image.network(photoUrl, width: 36, height: 36, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 15))))
                      : const Center(child: Text('🐾', style: TextStyle(fontSize: 15))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_selectedAnimal!['nom']?.toString() ?? '—',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                  if ((_selectedAnimal!['espece']?.toString() ?? '').isNotEmpty)
                    Text(_selectedAnimal!['espece'].toString(),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888))),
                ]),
              ),
            ]),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Pour quel animal ?'),
        const SizedBox(height: 8),
        if (_animaux.isEmpty)
          Text('Aucun animal enregistré dans votre profil.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))
        else
          GestureDetector(
            onTap: () async {
              final result = await AnimalPickerSheet.pickOne(
                context,
                preloaded: _animaux,
                current: _selectedAnimal,
                accentColor: color,
              );
              if (mounted) setState(() => _selectedAnimal = result);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: Row(children: [
                if (_selectedAnimal != null) ...[
                  Builder(builder: (_) {
                    final photoUrl = _selectedAnimal!['photo_url'] as String? ?? '';
                    return Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: photoUrl.isNotEmpty
                            ? Image.network(photoUrl, width: 32, height: 32, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 14))))
                            : const Center(child: Text('🐾', style: TextStyle(fontSize: 14))),
                      ),
                    );
                  }),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(_selectedAnimal!['nom']?.toString() ?? '—',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                      if ((_selectedAnimal!['espece']?.toString() ?? '').isNotEmpty)
                        Text(_selectedAnimal!['espece'].toString(),
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888))),
                    ]),
                  ),
                ] else ...[
                  Icon(Icons.pets_outlined, color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Choisir un animal…',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)),
                  ),
                ],
                Icon(Icons.expand_more, color: Colors.grey.shade500, size: 20),
              ]),
            ),
          ),
        if (_selectedAnimal != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _selectedAnimal = null),
            child: Text('Supprimer la sélection',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500, decoration: TextDecoration.underline)),
          ),
        ],
      ],
    );
  }

  Widget _buildNotesSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Notes (optionnel)'),
      const SizedBox(height: 8),
      if (widget.isPension && _selectedMotif == 'autre') const SizedBox.shrink()
      else TextField(
        controller: _notesCtrl,
        maxLines: 2,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _inputDecoration(widget.isPension
            ? 'Informations complémentaires pour la pension…'
            : widget.isVet
                ? 'Informations complémentaires pour le vétérinaire…'
                : 'Informations complémentaires…'),
      ),
    ],
  );

  Widget _buildSubmitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _saving ? null : _submit,
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: _saving
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Envoyer la demande',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 13, color: Color(0xFF1E2025)));

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.categoryColor, width: 1.5)),
    contentPadding: const EdgeInsets.all(14),
  );

  String _weekdayShort(DateTime d) {
    const j = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return j[d.weekday - 1];
  }

  String _formatDate(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois  = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} ${d.year}';
  }

  String _formatDateLong(DateTime d) {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    const mois  = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                   'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]}';
  }
}

