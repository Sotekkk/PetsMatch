import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/services/profile_service.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/pro/animal_fiche_pension_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/config.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _orange = Color(0xFFE65100);

  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_uid.isEmpty) return;
    try {
      final data = await _supa
          .from('notifications')
          .select()
          .eq('uid', _uid)
          .order('created_at', ascending: false)
          .limit(200);
      final currentType = _currentProfileType;
      final filtered = (data as List).where((n) {
        final pt = (n['profile_type'] as String?) ?? '';
        return pt.isEmpty || pt == currentType;
      }).toList();
      if (mounted) setState(() {
        _notifs = List<Map<String, dynamic>>.from(filtered);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteNotif(Map<String, dynamic> notif) async {
    try {
      await _supa.from('notifications').delete().eq('id', notif['id']);
      if (mounted) setState(() => _notifs.removeWhere((n) => n['id'] == notif['id']));
    } catch (_) {}
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer toutes les notifications ?', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final ids = _notifs.map((n) => n['id']).toList();
      if (ids.isNotEmpty) {
        await _supa.from('notifications').delete().inFilter('id', ids);
      }
      if (mounted) setState(() => _notifs.clear());
    } catch (_) {}
  }

  Future<void> _markRead(Map<String, dynamic> notif) async {
    if (notif['read'] == true) return;
    try {
      await _supa.from('notifications').update({'read': true}).eq('id', notif['id']);
      if (mounted) setState(() {
        final idx = _notifs.indexWhere((n) => n['id'] == notif['id']);
        if (idx != -1) _notifs[idx] = {..._notifs[idx], 'read': true};
      });
    } catch (_) {}
  }

  Future<void> _handleTap(Map<String, dynamic> notif) async {
    await _markRead(notif);

    // Vérifier si la notif appartient à un profil différent du profil actif
    final notifProfileType = notif['profile_type'] as String?;
    if (notifProfileType != null && notifProfileType.isNotEmpty &&
        notifProfileType != _currentProfileType) {
      final ok = await _confirmProfileSwitch(notifProfileType);
      if (ok) await _switchToProfileType(notifProfileType);
      return; // after switch, user starts fresh from BottomNav home
    }

    final type = notif['type'] as String?;
    final data = notif['data'];
    String? alerteId;
    String? annonceId;
    int?    bebeIndex;
    if (data is Map) {
      alerteId  = data['alerteId']  as String?;
      annonceId = data['annonceId'] as String?;
      final raw = data['bebeIndex'];
      bebeIndex = raw is int ? raw : (raw is num ? raw.toInt() : null);
    }

    if (!mounted) return;

    // RDV notifications → pages agenda
    if (type == 'rdv_demande' || type == 'rdv_annule_client' || type == 'rdv_contre_proposition') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProAgendaPage()));
      return;
    }
    if (type == 'rdv_confirme' || type == 'rdv_refuse' || type == 'rdv_annule') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaPage()));
      return;
    }

    if (type == 'vet_access_demande') {
      final vetId     = data is Map ? data['vet_id']    as String? : null;
      final vetNom    = data is Map ? (data['vet_nom']  as String? ?? '') : '';
      final isClinic  = data is Map ? (data['is_clinic'] as bool? ?? false) : false;
      final animalId  = data is Map ? data['animal_id'] as String? : null;
      final animalNom = data is Map ? (data['animal_nom'] as String? ?? 'votre animal') : 'votre animal';
      if (vetId != null && animalId != null) {
        await _showVetAccesDialog(
          vetId: vetId,
          vetNom: vetNom,
          isClinic: isClinic,
          animalId: animalId,
          animalNom: animalNom,
        );
      }
      return;
    }
    if (type == 'sante_vet') {
      final animalId = data is Map ? (data['animalId'] as String?) : null;
      if (animalId != null) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AnimalFichePage(
            animalId: animalId,
            readOnly: true,
            initialTabIndex: 2, // Santé tab in owner mode (0=Identité, 1=Repro, 2=Santé)
          ),
        ));
      }
      return;
    }
    if (type == 'vet_access_reponse') {
      final approved = data is Map ? data['approved'] as bool? : null;
      if (approved == true) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => const VetPatientsPage(),
        ));
      }
      return;
    }
    if (type == 'pension_acces') {
      final pensionUid = data is Map ? data['pensionUid'] as String? : null;
      final pensionNom = data is Map ? data['pensionNom'] as String? : null;
      final animalId   = data is Map ? data['animalId']   as String? : null;
      final animalNom  = data is Map ? data['animalNom']  as String? : null;
      if (pensionUid != null && animalId != null) {
        await _showPensionAccesDialog(
          pensionUid: pensionUid,
          pensionNom: pensionNom ?? 'La pension',
          animalId: animalId,
          animalNom: animalNom ?? 'votre animal',
        );
      }
      return;
    }
    if (type == 'pension_acces_reponse') {
      final animalId  = data is Map ? data['animalId']  as String? : null;
      final animalNom = data is Map ? data['animalNom'] as String? : null;
      final approved  = data is Map ? data['approved']  as bool?   : null;
      if (approved == true && animalId != null) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AnimalFichePensionPage(
            animalId: animalId,
            animalNom: animalNom,
          ),
        ));
      }
      return;
    }
    // Notifications contrats — ouvre le lien de signature dans le navigateur
    if (type == 'contrat_saillie_invite' ||
        type == 'contrat_signe_eleveur' ||
        type == 'contrat_signe_complet') {
      final url = data is Map ? data['url'] as String? : null;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    // Notifications contrats côté éleveur — ouvre la page Mes Contrats dans l'app
    if (type == 'contrat_signe_acquereur' || type == 'contrat_refuse' || type == 'contrat_expire') {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const ContratReservationPage(),
      ));
      return;
    }
    // Cession — signature demandée à l'acquéreur → ouvrir le lien de signature
    if (type == 'cession_signature_demandee') {
      final signingUrl = data is Map ? data['signingUrl'] as String? : null;
      final token      = data is Map ? data['token']      as String? : null;
      final url = signingUrl ?? (token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null);
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    // Cession confirmée côté acquéreur → voir dans Mes Animaux
    if (type == 'cession_confirmee') {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const MesAnimauxPage(),
      ));
      return;
    }
    // Cession révoquée → juste marquer lue (déjà fait)
    if (type == 'cession_revoquee') return;
    if (type == 'annonce_expiration' && annonceId != null) {
      // Charger les données de l'annonce depuis Supabase pour ouvrir directement l'édition
      final supa = Supabase.instance.client;
      final res = await supa.from('annonces').select().eq('id', annonceId).maybeSingle();
      if (!mounted) return;
      if (res != null) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreateAnnoncePage(
            annonceId: annonceId,
            initialData: Map<String, dynamic>.from(res),
          ),
        ));
      }
      return;
    }
    if (type == 'alerte_perdu') {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimauxPerdusPage(initialAlertId: alerteId),
      ));
    } else if (type == 'like' && annonceId != null) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnnoncesFeedPage(
          initialAnnonceId: annonceId,
          initialBebeIndex: bebeIndex,
        ),
      ));
    } else if (type == 'chaleur') {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const MesAnimauxPage(),
      ));
    } else if (type == 'employee_invite') {
      final eleveurUid = data is Map ? data['eleveurUid'] as String? : null;
      final eleveurNom = data is Map ? (data['eleveurNom'] as String? ?? 'Mon employeur') : 'Mon employeur';
      if (eleveurUid != null) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => EmployeurDetailPage(
            eleveurUid: eleveurUid,
            eleveurNom: eleveurNom,
          ),
        ));
      }
    } else if (type == 'tache') {
      final eleveurUid = data is Map ? data['eleveurUid'] as String? : null;
      if (eleveurUid != null) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => EmployeurDetailPage(
            eleveurUid: eleveurUid,
            eleveurNom: 'Mon employeur',
          ),
        ));
      } else {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => const MesEmployeursPage(),
        ));
      }
    }
  }

  // ── Helpers profil ────────────────────────────────────────────────────────

  static String _profileTypeLabel(String type) => switch (type) {
    'particulier'      => 'Particulier',
    'eleveur'          => 'Éleveur',
    'veterinaire'      => 'Vétérinaire',
    'sante'            => 'Santé animale',
    'education'        => 'Éducation',
    'garde'            => 'Garde',
    'pension'          => 'Pension',
    'toilettage'       => 'Toilettage',
    'photographe'      => 'Photographe',
    'marechal_ferrant' => 'Maréchal-ferrant',
    _                  => type,
  };

  static String _profileTypeEmoji(String type) => switch (type) {
    'particulier'      => '👤',
    'eleveur'          => '🐾',
    'veterinaire'      => '🏥',
    'sante'            => '💆',
    'education'        => '🧠',
    'garde'            => '🏠',
    'pension'          => '🏨',
    'toilettage'       => '✂️',
    'photographe'      => '📷',
    'marechal_ferrant' => '🔨',
    _                  => '👤',
  };

  Widget _profileBadge(String type) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: _teal.withAlpha(18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _teal.withAlpha(38)),
    ),
    child: Text(
      '${_profileTypeEmoji(type)} ${_profileTypeLabel(type)}',
      style: const TextStyle(
        fontFamily: 'Galey', fontSize: 10, color: _teal, fontWeight: FontWeight.w600),
    ),
  );

  String get _currentProfileType {
    if (User_Info.catPro.isNotEmpty) return User_Info.catPro;
    if (User_Info.isAssociation) return 'association';
    if (User_Info.isElevage) return 'eleveur';
    return 'particulier';
  }

  Future<void> _switchToProfileType(String profileType) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (profileType == User_Info.primaryType) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) User_Info.updateUserInfo(doc.data()!);
      } catch (_) {}
    } else {
      final profiles = await ProfileService.loadProfiles(uid);
      final match = profiles.firstWhere(
        (p) => p['profile_type'] == profileType,
        orElse: () => {},
      );
      if (match.isNotEmpty) User_Info.applyProfile(match);
    }

    if (mounted) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => BottomNav()), (_) => false);
    }
  }

  Future<bool> _confirmProfileSwitch(String profileType) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Text(_profileTypeEmoji(profileType), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Changer de profil ?',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
            content: Text(
              'Cette notification concerne votre profil ${_profileTypeLabel(profileType)}.\n\nBasculer vers ce profil ?',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text('Basculer — ${_profileTypeLabel(profileType)}',
                    style: const TextStyle(fontFamily: 'Galey'))),
            ],
          ),
        ) ??
        false;
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('dd/MM/yyyy', 'fr').format(dt);
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'alerte_perdu':  return Icons.location_searching;
      case 'message':       return Icons.chat_bubble_outline;
      case 'like':          return Icons.favorite;
      case 'chaleur':       return Icons.spa;
      case 'tache':         return Icons.task_alt;
      case 'employee_invite': return Icons.handshake_outlined;
      case 'vet_access_demande':       return Icons.medical_services_outlined;
      case 'vet_access_reponse':       return Icons.check_circle_outline;
      case 'pension_acces':          return Icons.home_work_outlined;
      case 'pension_acces_reponse':  return Icons.check_circle_outline;
      case 'rdv_demande':            return Icons.event_note_outlined;
      case 'rdv_confirme':           return Icons.event_available_outlined;
      case 'rdv_refuse':             return Icons.event_busy_outlined;
      case 'rdv_annule':
      case 'rdv_annule_client':      return Icons.cancel_outlined;
      case 'rdv_contre_proposition': return Icons.edit_calendar_outlined;
      default:                       return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'alerte_perdu':  return _orange;
      case 'message':       return _teal;
      case 'like':          return Colors.redAccent;
      case 'chaleur':       return const Color(0xFFE91E8C);
      case 'tache':         return const Color(0xFF6E9E57);
      case 'employee_invite': return const Color(0xFF0C5C6C);
      case 'vet_access_demande':       return const Color(0xFF26A69A);
      case 'vet_access_reponse':       return const Color(0xFF6E9E57);
      case 'pension_acces':          return const Color(0xFF7B5EA7);
      case 'pension_acces_reponse':  return const Color(0xFF6E9E57);
      case 'rdv_demande':
      case 'rdv_contre_proposition': return _teal;
      case 'rdv_confirme':           return const Color(0xFF6E9E57);
      case 'rdv_refuse':
      case 'rdv_annule':
      case 'rdv_annule_client':      return Colors.redAccent;
      default:                       return Colors.grey;
    }
  }

  Future<void> _showPensionAccesDialog({
    required String pensionUid,
    required String pensionNom,
    required String animalId,
    required String animalNom,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Demande d\'accès à la fiche de $animalNom',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          '$pensionNom souhaite consulter la fiche de $animalNom (santé, alimentation, comportement) en lecture seule.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0C5C6C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Autoriser', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    final newStatut = result ? 'approved' : 'refused';

    try {
      await _supa
          .from('pension_acces')
          .update({'statut': newStatut})
          .eq('pro_uid', pensionUid)
          .eq('animal_id', animalId);

      // Notification retour à la pension
      await _supa.from('notifications').insert({
        'uid':   pensionUid,
        'type':  'pension_acces_reponse',
        'title': result
            ? 'Accès accordé pour $animalNom'
            : 'Demande refusée pour $animalNom',
        'body': result
            ? 'Le propriétaire vous a autorisé à consulter la fiche de $animalNom.'
            : 'Le propriétaire a refusé votre demande pour $animalNom.',
        'data':  {'animalId': animalId, 'animalNom': animalNom, 'approved': result},
        'read':  false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result
              ? 'Accès accordé à $pensionNom'
              : 'Demande refusée'),
          backgroundColor: result ? const Color(0xFF6E9E57) : Colors.red,
        ));
      }
    } catch (_) {}
  }

  Future<void> _showVetAccesDialog({
    required String vetId,
    required String vetNom,
    required bool isClinic,
    required String animalId,
    required String animalNom,
  }) async {
    final displayNom = vetNom.isNotEmpty
        ? (isClinic ? vetNom : 'Dr. $vetNom')
        : 'Un vétérinaire';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.medical_services_outlined, color: Color(0xFF26A69A), size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Demande d\'accès vétérinaire',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        content: Text(
          '$displayNom souhaite accéder au carnet de santé de $animalNom '
          '(identité, santé, repro) en lecture seule.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Autoriser', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    try {
      if (result) {
        await _supa.from('vet_access_grants').update({
          'status': 'active',
          'granted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('vet_id', vetId).eq('animal_id', animalId);
      } else {
        await _supa.from('vet_access_grants').update({
          'status': 'revoked',
          'revoked_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('vet_id', vetId).eq('animal_id', animalId);
      }

      // Notification retour au vétérinaire
      await _supa.from('notifications').insert({
        'uid':   vetId,
        'type':  'vet_access_reponse',
        'title': result ? 'Accès accordé — $animalNom' : 'Demande refusée — $animalNom',
        'body':  result
            ? 'Le propriétaire vous a autorisé à consulter la fiche de $animalNom.'
            : 'Le propriétaire a refusé votre demande pour $animalNom.',
        'data':  <String, dynamic>{'animal_id': animalId, 'animal_nom': animalNom, 'approved': result},
        'read':  false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result ? 'Accès accordé à $displayNom' : 'Demande refusée',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: result ? const Color(0xFF26A69A) : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Notifications',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          if (_notifs.isNotEmpty)
            TextButton(
              onPressed: _deleteAll,
              child: const Text('Tout supprimer',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _fetch,
              color: _teal,
              child: _notifs.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_none, size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('Aucune notification',
                                  style: TextStyle(
                                      fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _notifs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final n = _notifs[i];
                        final isRead = n['read'] == true;
                        final type = n['type'] as String?;

                        return Dismissible(
                          key: ValueKey(n['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red.shade400,
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteNotif(n),
                          child: InkWell(
                          onTap: () => _handleTap(n),
                          child: Container(
                            color: isRead ? Colors.transparent : _teal.withAlpha(12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _colorFor(type).withAlpha(20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_iconFor(type), color: _colorFor(type), size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n['title'] as String? ?? '',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                              fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(n['body'] as String? ?? '',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 13,
                                              color: Colors.grey.shade600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(_timeAgo(n['created_at'] as String?),
                                                style: TextStyle(
                                                    fontFamily: 'Galey',
                                                    fontSize: 11,
                                                    color: Colors.grey.shade400)),
                                          ),
                                          if ((n['profile_type'] as String?)?.isNotEmpty == true) ...[
                                            const SizedBox(width: 6),
                                            _profileBadge(n['profile_type'] as String),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 6, left: 6),
                                    decoration: const BoxDecoration(
                                      color: _teal,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ));
                      },
                    ),
            ),
    );
  }
}

/// Streams the unread notification count from Supabase for the badge.
class NotifBadge extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  const NotifBadge({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  @override
  State<NotifBadge> createState() => _NotifBadgeState();
}

class _NotifBadgeState extends State<NotifBadge> with WidgetsBindingObserver {
  static const _green = Color(0xFF6E9E57);
  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  int _unread = 0;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUnread();
    _subscribe();
    User_Info.profileNotifier.addListener(_onProfileChange);
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _fetchUnread());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    User_Info.profileNotifier.removeListener(_onProfileChange);
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onProfileChange() => _fetchUnread();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetchUnread();
  }

  String get _currentBadgeProfileType {
    if (User_Info.catPro.isNotEmpty) return User_Info.catPro;
    if (User_Info.isAssociation) return 'association';
    if (User_Info.isElevage) return 'eleveur';
    return 'particulier';
  }

  Future<void> _fetchUnread() async {
    if (_uid.isEmpty) return;
    try {
      final data = await _supa
          .from('notifications')
          .select('id, profile_type')
          .eq('uid', _uid)
          .eq('read', false);
      final currentType = _currentBadgeProfileType;
      final count = (data as List).where((n) {
        final pt = (n['profile_type'] as String?) ?? '';
        return pt.isEmpty || pt == currentType;
      }).length;
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  void _subscribe() {
    if (_uid.isEmpty) return;
    // Sans filtre : les DELETE ne transmettent pas uid sans REPLICA IDENTITY FULL.
    // On re-fetch à chaque changement ; _fetchUnread() filtre déjà par uid.
    _channel = _supa
        .channel('notif_badge_$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _fetchUnread(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  widget.active ? widget.activeIcon : widget.icon,
                  color: widget.active ? _green : Colors.grey,
                  size: 24,
                ),
                if (_unread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text(
                        _unread > 99 ? '99+' : '$_unread',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Alertes',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Galey',
                  color: widget.active ? _green : Colors.grey,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}
