import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/acquereur_contact.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show AnimalFichePage;
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

/// Onglet « Suivi » de Mes Animaux : suivi des chiots cédés — condition de
/// stérilisation (rappels, validation) + anniversaires à venir.
class SuiviCessionsTab extends StatefulWidget {
  /// uid du gérant principal (propriétaire réel de l'élevage) — sert à
  /// résoudre le réglage anniv. auto et le profil éleveur à taguer.
  final String? uid;
  /// uid Firebase réel de la personne connectée — sert pour l'identité des
  /// messages envoyés (sender_id, garde-fou « vous ne pouvez pas vous
  /// contacter vous-même »). Différent de [uid] pour un cogérant.
  final String? myUid;
  final List<Map<String, dynamic>> animaux;
  final bool loading;
  final Future<void> Function() onChanged;

  const SuiviCessionsTab({
    super.key,
    required this.uid,
    this.myUid,
    required this.animaux,
    required this.loading,
    required this.onChanged,
  });

  @override
  State<SuiviCessionsTab> createState() => _SuiviCessionsTabState();
}

class _SuiviCessionsTabState extends State<SuiviCessionsTab> {
  final _supa = Supabase.instance.client;
  // Recherche + filtres (par défaut : dossiers à suivre)
  final _qCtrl = TextEditingController();
  String _q = '';
  String _statutFiltre = 'a_suivre';   // a_suivre | tous | a_faire | retard | recu
  String _echeanceFiltre = 'toutes';   // toutes | depassees | 30j
  String? _validating;
  String? _wishing;
  String? _relancing;

  bool _annivAuto = false;
  bool _annivLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAnnivSetting();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnnivSetting() async {
    try {
      final row = await _supa.from('user_profiles_complet')
          .select('cession_anniv_auto')
          .eq('uid', widget.uid ?? '')
          .eq('is_main', true)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _annivAuto = row?['cession_anniv_auto'] == true;
          _annivLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _annivLoaded = true);
    }
  }

  Future<void> _toggleAnnivAuto(bool v) async {
    setState(() => _annivAuto = v);
    try {
      await _supa.from('user_profiles')
          .update({'cession_anniv_auto': v})
          .eq('uid', widget.uid ?? '')
          .eq('is_main', true);
    } catch (e) {
      if (mounted) {
        setState(() => _annivAuto = !v);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  List<Map<String, dynamic>> get _cedes => widget.animaux
      .where((a) => (a['statut'] as String?) == 'sorti')
      .toList();

  /// Animaux cédés avec date de naissance, triés par prochain anniversaire (≤ 60 j).
  List<Map<String, dynamic>> get _anniversaires {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = <(Map<String, dynamic>, int, int)>[];
    for (final a in _cedes) {
      final dn = _parseDate(a['date_naissance']);
      if (dn == null) continue;
      var next = DateTime(today.year, dn.month, dn.day);
      if (next.isBefore(today)) next = DateTime(today.year + 1, dn.month, dn.day);
      final days = next.difference(today).inDays;
      if (days > 60) continue;
      final age = next.year - dn.year;
      list.add((a, days, age));
    }
    list.sort((x, y) => x.$2.compareTo(y.$2));
    return list.map((e) => {...e.$1, '_annivDays': e.$2, '_annivAge': e.$3}).toList();
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null || (raw is String && raw.isEmpty)) return null;
    return DateTime.tryParse(raw.toString());
  }

  Future<void> _valider(Map<String, dynamic> a) async {
    final nom = a['nom'] as String? ?? 'l\'animal';
    // L'éleveur peut valider dès qu'il a reçu le certificat vétérinaire, même si
    // le propriétaire n'a pas déclaré la stérilisation dans l'appli.
    final dejaDeclaree = a['sterilise'] == true;
    if (!dejaDeclaree) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Enregistrer le certificat',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          content: Text(
              'Confirmez-vous avoir reçu le certificat de stérilisation vétérinaire '
              'pour $nom ?\n\nLa stérilisation sera marquée comme faite et validée, '
              'et le propriétaire en sera informé.',
              style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Enregistrer', style: TextStyle(color: _teal, fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _validating = a['id'] as String);
    try {
      await _supa.from('animaux').update({
        'sterilisation_validee': true,
        'sterilise': true,
      }).eq('id', a['id']);
      // Ligne cession éventuelle (workflow appli)
      try {
        await _supa.from('cessions')
            .update({
              'sterilisation_validee': true,
              'sterilisation_validee_at': DateTime.now().toIso8601String(),
            })
            .eq('animal_id', a['id'])
            .eq('sterilisation_requise', true);
      } catch (_) {}
      // Notifier l'acquéreur
      final acqUid = a['uid_acquereur'] as String?;
      if (acqUid != null && acqUid.isNotEmpty) {
        final acqProfile = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
        await _supa.from('notifications').insert({
          'uid':   acqUid,
          'type':  'sterilisation_validee',
          'title': 'Stérilisation validée — ${a['nom'] ?? 'Animal'}',
          'body':  'L\'éleveur a validé la stérilisation de ${a['nom'] ?? 'votre animal'}. Merci !',
          if (acqProfile?['id'] != null) 'profile_id': acqProfile!['id'],
          'data':  {'animalId': a['id']},
          'read':  false,
        });
      }
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Certificat enregistré : stérilisation validée'), backgroundColor: _green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _validating = null);
    }
  }

  /// Envoi des vœux d'anniversaire — mêmes canaux que « Relancer la famille » :
  /// Application, WhatsApp, SMS, Email. Fonctionne même sans compte PetsMatch
  /// (les coordonnées viennent du contrat / de la fiche cession / de la
  /// correction manuelle, cf. [[project_cession_sterilisation]]).
  Future<void> _envoyerVoeux(Map<String, dynamic> a) async {
    setState(() => _wishing = a['id'] as String);
    Map<String, String> c;
    try {
      c = (await fetchContactAcquereur(_supa, a)).data;
    } catch (e) {
      if (mounted) {
        setState(() => _wishing = null);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
      return;
    }
    if (mounted) setState(() => _wishing = null);
    if (!mounted) return;

    final nom = a['nom'] as String? ?? 'votre compagnon';
    final prenom = c['prenom'] ?? '';
    final salut = prenom.isNotEmpty ? 'Bonjour $prenom,\n\n' : '';
    final ctrl = TextEditingController(
        text: '${salut}Joyeux anniversaire $nom ! Toute l\'équipe pense à lui aujourd\'hui.');

    final acqUid = (a['uid_acquereur'] ?? '').toString();
    final tel = c['tel'] ?? '';
    final email = c['email'] ?? '';
    final nomComplet = [c['prenom'], c['nom']]
        .where((e) => (e ?? '').isNotEmpty).join(' ');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18, right: 18, top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('Envoyer mes vœux — $nom',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (nomComplet.isNotEmpty) _contactLine(Icons.person_outline, nomComplet),
                if (tel.isNotEmpty)
                  _contactLine(Icons.phone_outlined, tel, onTap: () => _openUri(Uri(scheme: 'tel', path: _telDigits(tel)))),
                if (email.isNotEmpty) _contactLine(Icons.mail_outline, email),
                if ((c['adresse'] ?? '').isNotEmpty) _contactLine(Icons.home_outlined, c['adresse']!),
                if (nomComplet.isEmpty && tel.isEmpty && email.isEmpty && (c['adresse'] ?? '').isEmpty)
                  Text('Aucune coordonnée connue pour cet animal.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl, maxLines: 6, minLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 14),
            Text('ENVOYER VIA',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (acqUid.isNotEmpty)
                _canalBtn('Application', const Icon(Icons.notifications_active_outlined, size: 16, color: _teal), _teal, () {
                  Navigator.pop(ctx);
                  _envoyerInApp(a, acqUid, ctrl.text.trim(),
                      notifType: 'message',
                      notifTitre: '${User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : "Votre éleveur"}');
                }),
              if (tel.isNotEmpty)
                _canalBtn('WhatsApp', const FaIcon(FontAwesomeIcons.whatsapp, size: 15, color: Color(0xFF25D366)), const Color(0xFF25D366), () {
                  Navigator.pop(ctx);
                  _openUri(Uri.parse('https://wa.me/${_waPhone(tel)}?text=${Uri.encodeComponent(ctrl.text.trim())}'));
                }),
              if (tel.isNotEmpty)
                _canalBtn('SMS', const Icon(Icons.sms_outlined, size: 16, color: Color(0xFF6E9E57)), const Color(0xFF6E9E57), () {
                  Navigator.pop(ctx);
                  _openUri(Uri.parse('sms:${_telDigits(tel)}?body=${Uri.encodeComponent(ctrl.text.trim())}'));
                }),
              if (email.isNotEmpty)
                _canalBtn('Email', const Icon(Icons.email_outlined, size: 16, color: Color(0xFFEA4335)), const Color(0xFFEA4335), () {
                  Navigator.pop(ctx);
                  final subj = Uri.encodeComponent('Joyeux anniversaire $nom');
                  final body = Uri.encodeComponent(ctrl.text.trim());
                  _openUri(Uri.parse('mailto:$email?subject=$subj&body=$body'));
                }),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Relance famille (stérilisation) ─────────────────────────────────────────

  /// Téléphone au format international sans « + » pour wa.me (France par défaut).
  String _waPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = '33${d.substring(1)}';
    return d;
  }

  String _telDigits(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _openUri(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossible d\'ouvrir : ${uri.scheme}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Profil de l'acquéreur auquel rattacher la relance : celui qui détient
  /// l'animal cédé (`animaux.profile_id_acquereur`), sinon son profil
  /// particulier, sinon son profil principal. C'est ce profil-là qui verra la
  /// conversation ET la notification (cohérence indispensable).
  Future<String?> _profilAcquereur(Map<String, dynamic> a, String acqUid) async {
    final direct = '${a['profile_id_acquereur'] ?? ''}';
    if (direct.isNotEmpty) return direct;
    try {
      final part = await _supa.from('user_profiles_complet')
          .select('id').eq('uid', acqUid).eq('profile_type', 'particulier').maybeSingle();
      if (part?['id'] != null) return part!['id'] as String;
      final main = await _supa.from('user_profiles_complet')
          .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
      return main?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Tague la conversation `pro_profile_id` (éleveur) + `consumer_profile_id`
  /// (profil de l'acquéreur qui détient l'animal). Sans ça, la liste /messages
  /// masque la conversation à l'acquéreur.
  Future<void> _taguerConversation(String convId, String acqUid, String? acqProfileId) async {
    try {
      final elevP = await _supa.from('user_profiles_complet')
          .select('id').eq('uid', widget.uid ?? '').eq('profile_type', 'eleveur').maybeSingle();
      final conv = await _supa.from('conversations')
          .select('pro_profile_id, consumer_profile_id, categorie, deleted_for').eq('id', convId).maybeSingle();
      final patch = <String, dynamic>{};
      if ('${conv?['pro_profile_id'] ?? ''}'.isEmpty && elevP?['id'] != null) {
        patch['pro_profile_id'] = elevP!['id'];
      }
      if ('${conv?['consumer_profile_id'] ?? ''}'.isEmpty && acqProfileId != null) {
        patch['consumer_profile_id'] = acqProfileId;
      }
      if ('${conv?['categorie'] ?? ''}'.isEmpty || conv?['categorie'] == 'elevage') {
        patch['categorie'] = 'contact-elevage';
      }
      // Réafficher la conversation si l'acquéreur l'avait supprimée.
      if ((conv?['deleted_for'] as Map?)?.isNotEmpty == true) patch['deleted_for'] = {};
      if (patch.isNotEmpty) {
        await _supa.from('conversations').update(patch).eq('id', convId);
      }
    } catch (_) {}
  }

  /// Relance « in-app » : message dans la conversation + notification.
  /// Envoi in-app générique (message dans la conversation élevage + notif),
  /// réutilisé par le canal « Application » de `_relancer` et `_envoyerVoeux`.
  Future<void> _envoyerInApp(
    Map<String, dynamic> a,
    String acqUid,
    String texte, {
    required String notifType,
    required String notifTitre,
  }) async {
    if (acqUid == (widget.myUid ?? widget.uid ?? '')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('L\'acquéreur est votre propre compte : le message in-app '
              'ne peut pas s\'afficher. Testez avec un autre compte, ou par '
              'WhatsApp / SMS / Email.'),
          duration: Duration(seconds: 6),
        ));
      }
      return;
    }
    try {
      final acqProfileId = await _profilAcquereur(a, acqUid);
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: acqUid, categorie: 'contact-elevage',
      );
      await _taguerConversation(convId, acqUid, acqProfileId);
      final senderUid = widget.myUid ?? widget.uid;
      await _supa.from('messages').insert({
        'conversation_id': convId,
        'sender_id':       senderUid,
        'text':            texte,
        'msg_type':        'text',
        'is_read':         false,
      });
      final conv = await _supa.from('conversations')
          .select('participants, unread_count').eq('id', convId).maybeSingle();
      if (conv != null) {
        final members = List<String>.from(
            (conv['participants'] as List?)?.map((e) => e.toString()) ?? []);
        final unread = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
        for (final u in members) {
          if (u != senderUid) unread[u] = (unread[u] as int? ?? 0) + 1;
        }
        await _supa.from('conversations').update({
          'last_message': texte,
          'unread_count': unread,
          'updated_at':   DateTime.now().toIso8601String(),
          // Un nouveau message fait réapparaître la conversation si le
          // destinataire l'avait supprimée de sa liste.
          'deleted_for':  {},
        }).eq('id', convId);
      }
      // Un simple message est déjà notifié par le trigger trg_notify_new_message ;
      // seule la relance (type dédié) mérite sa propre notif.
      if (notifType != 'message') await _supa.from('notifications').insert({
        'uid':   acqUid,
        'type':  notifType,
        'title': notifTitre,
        'body':  texte.length > 140 ? '${texte.substring(0, 137)}…' : texte,
        if (acqProfileId != null) 'profile_id': acqProfileId,
        'data':  {'animalId': a['id']},
        'read':  false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message envoyé dans l\'application.'), backgroundColor: _green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _relancer(Map<String, dynamic> a) async {
    setState(() => _relancing = a['id'] as String);
    Map<String, String> c;
    try {
      c = (await fetchContactAcquereur(_supa, a)).data;
    } catch (e) {
      if (mounted) {
        setState(() => _relancing = null);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
      return;
    }
    if (mounted) setState(() => _relancing = null);
    if (!mounted) return;

    final nom = a['nom'] as String? ?? 'l\'animal';
    final ech = _parseDate(a['sterilisation_echeance']);
    final echStr = ech != null ? DateFormat('dd/MM/yyyy').format(ech) : null;
    final done = a['sterilise'] == true;
    final prenom = c['prenom'] ?? '';
    final salut = prenom.isNotEmpty ? 'Bonjour $prenom,' : 'Bonjour,';
    final defaut = done
        ? '$salut\n\nLa stérilisation de $nom a bien été déclarée. Pourriez-vous '
          'nous transmettre le certificat vétérinaire afin que nous puissions la '
          'valider ? Merci beaucoup.'
        : '$salut\n\nPetit rappel concernant la stérilisation de $nom'
          '${echStr != null ? ', à réaliser avant le $echStr' : ''}. '
          'Merci de nous transmettre le certificat vétérinaire une fois '
          'l\'intervention réalisée. Bien à vous.';
    final ctrl = TextEditingController(text: defaut);

    final acqUid = (a['uid_acquereur'] ?? '').toString();
    final tel = c['tel'] ?? '';
    final email = c['email'] ?? '';
    final nomComplet = [c['prenom'], c['nom']]
        .where((e) => (e ?? '').isNotEmpty).join(' ');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18, right: 18, top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('Relancer la famille — $nom',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (nomComplet.isNotEmpty) _contactLine(Icons.person_outline, nomComplet),
                if (tel.isNotEmpty)
                  _contactLine(Icons.phone_outlined, tel, onTap: () => _openUri(Uri(scheme: 'tel', path: _telDigits(tel)))),
                if (email.isNotEmpty) _contactLine(Icons.mail_outline, email),
                if ((c['adresse'] ?? '').isNotEmpty) _contactLine(Icons.home_outlined, c['adresse']!),
                if (nomComplet.isEmpty && tel.isEmpty && email.isEmpty && (c['adresse'] ?? '').isEmpty)
                  Text('Aucune coordonnée dans le contrat.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl, maxLines: 6, minLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 14),
            Text('ENVOYER VIA',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (acqUid.isNotEmpty)
                _canalBtn('Application', const Icon(Icons.notifications_active_outlined, size: 16, color: _teal), _teal, () {
                  Navigator.pop(ctx);
                  _envoyerInApp(a, acqUid, ctrl.text.trim(),
                      notifType: 'sterilisation_relance',
                      notifTitre: 'Rappel stérilisation — ${a['nom'] ?? 'votre animal'}');
                }),
              if (tel.isNotEmpty)
                _canalBtn('WhatsApp', const FaIcon(FontAwesomeIcons.whatsapp, size: 15, color: Color(0xFF25D366)), const Color(0xFF25D366), () {
                  Navigator.pop(ctx);
                  _openUri(Uri.parse('https://wa.me/${_waPhone(tel)}?text=${Uri.encodeComponent(ctrl.text.trim())}'));
                }),
              if (tel.isNotEmpty)
                _canalBtn('SMS', const Icon(Icons.sms_outlined, size: 16, color: Color(0xFF6E9E57)), const Color(0xFF6E9E57), () {
                  Navigator.pop(ctx);
                  _openUri(Uri.parse('sms:${_telDigits(tel)}?body=${Uri.encodeComponent(ctrl.text.trim())}'));
                }),
              if (email.isNotEmpty)
                _canalBtn('Email', const Icon(Icons.email_outlined, size: 16, color: Color(0xFFEA4335)), const Color(0xFFEA4335), () {
                  Navigator.pop(ctx);
                  final subj = Uri.encodeComponent('Stérilisation de $nom — rappel');
                  final body = Uri.encodeComponent(ctrl.text.trim());
                  _openUri(Uri.parse('mailto:$email?subject=$subj&body=$body'));
                }),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _contactLine(IconData icon, String value, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: TextStyle(
            fontSize: 12.5,
            color: onTap != null ? _teal : _dark,
            fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400))),
      ]),
    );
    return onTap != null ? InkWell(onTap: onTap, child: row) : row;
  }

  Widget _canalBtn(String label, Widget icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: color)),
        ]),
      ),
    );
  }

  // ── Dossiers de stérilisation ─────────────────────────────────────────────────
  // Délais calculés depuis l'échéance contractuelle enregistrée (jamais un âge
  // type). « Certificat reçu » = validé par l'éleveur ; une échéance passée ne
  // vaut jamais stérilisation réalisée.

  String _statut(Map<String, dynamic> a) {
    if (a['sterilisation_validee'] == true) return 'recu';
    final j = _jours(a);
    return j != null && j < 0 ? 'retard' : 'a_faire';
  }

  int? _jours(Map<String, dynamic> a) {
    final ech = _parseDate(a['sterilisation_echeance']);
    if (ech == null) return null;
    final now = DateTime.now();
    return DateTime(ech.year, ech.month, ech.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  List<Map<String, dynamic>> get _dossiers =>
      _cedes.where((a) => a['sterilisation_requise'] == true).toList();

  List<Map<String, dynamic>> get _dossiersFiltres {
    final q = _q.trim().toLowerCase();
    const rang = {'retard': 0, 'a_faire': 1, 'recu': 2};
    final list = _dossiers.where((a) {
      final s = _statut(a);
      if (_statutFiltre == 'a_suivre' && s == 'recu') return false;
      if (_statutFiltre != 'a_suivre' && _statutFiltre != 'tous' && s != _statutFiltre) return false;
      final j = _jours(a);
      if (_echeanceFiltre == 'depassees' && !(j != null && j < 0)) return false;
      if (_echeanceFiltre == '30j' && !(j != null && j >= 0 && j <= 30)) return false;
      if (q.isNotEmpty && ![a['nom'], a['destinataire_nom'], a['race']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q))) return false;
      return true;
    }).toList();
    list.sort((x, y) {
      final r = rang[_statut(x)]!.compareTo(rang[_statut(y)]!);
      if (r != 0) return r;
      final jx = _jours(x), jy = _jours(y);
      if (jx == null && jy == null) return 0;
      if (jx == null) return 1;
      if (jy == null) return -1;
      return jx.compareTo(jy);
    });
    return list;
  }

  bool get _filtresActifs => _q.isNotEmpty || _statutFiltre != 'a_suivre' || _echeanceFiltre != 'toutes';

  InputDecoration _deco(String hint, {Widget? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.grey.shade500),
    prefixIcon: prefix,
    isDense: true,
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _teal, width: 1.5)),
  );

  Widget _menu(String label, String valeur, List<(String, String)> items, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: valeur,
      key: ValueKey('$label$valeur'),
      isExpanded: true,
      decoration: _deco(label),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: _dark),
      items: [for (final it in items) DropdownMenuItem(value: it.$1, child: Text(it.$2, overflow: TextOverflow.ellipsis))],
      onChanged: (v) { if (v != null) onChanged(v); },
    );

  Widget _compteur(String label, int n, IconData icone, Color fond, Color teinte) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
            child: Icon(icone, size: 17, color: teinte)),
        const SizedBox(width: 8),
        Text('$n', style: const TextStyle(fontFamily: 'Galey', fontSize: 20, fontWeight: FontWeight.w800, color: _dark)),
      ]),
      const SizedBox(height: 6),
      Text(label, maxLines: 2, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600, height: 1.2)),
    ]),
  ));

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }
    if (_cedes.isEmpty) {
      return _emptyState('Aucun animal cédé',
          'Le suivi des stérilisations et les anniversaires de vos animaux cédés apparaîtront ici.');
    }
    final dossiers = _dossiers;
    final liste = _dossiersFiltres;
    final anniv = _anniversaires;
    final nbRetard = dossiers.where((a) => _statut(a) == 'retard').length;
    return RefreshIndicator(
      onRefresh: widget.onChanged,
      color: _teal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text('Suivi des stérilisations',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _dark)),
          const SizedBox(height: 2),
          Text('Échéances, certificats et relances des familles.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Row(children: [
            _compteur('À suivre', dossiers.where((a) => _statut(a) != 'recu').length,
                Icons.schedule, const Color(0xFFE8F4F6), _teal),
            const SizedBox(width: 8),
            _compteur('Échéances dépassées', nbRetard,
                Icons.priority_high, const Color(0xFFFDECEC), const Color(0xFFDC2626)),
            const SizedBox(width: 8),
            _compteur('Certificats reçus', dossiers.where((a) => _statut(a) == 'recu').length,
                Icons.description_outlined, const Color(0xFFEAF2E5), const Color(0xFF4D7A3C)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _qCtrl,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _deco('Rechercher un animal ou une famille',
                prefix: Icon(Icons.search, size: 20, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _menu('Statut', _statutFiltre, const [
              ('a_suivre', 'À suivre'), ('tous', 'Tous'), ('a_faire', 'À faire'), ('retard', 'En retard'), ('recu', 'Certificat reçu'),
            ], (v) => setState(() => _statutFiltre = v))),
            const SizedBox(width: 8),
            Expanded(child: _menu('Échéance', _echeanceFiltre, const [
              ('toutes', 'Toutes les échéances'), ('depassees', 'Dépassées'), ('30j', '30 prochains jours'),
            ], (v) => setState(() => _echeanceFiltre = v))),
          ]),
          const SizedBox(height: 12),
          if (dossiers.isEmpty)
            _hint('Aucune condition de stérilisation sur vos cessions.')
          else if (liste.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
              child: Column(children: [
                const Text('Aucun suivi ne correspond à vos filtres', textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
                if (_filtresActifs)
                  TextButton(
                    onPressed: () => setState(() { _qCtrl.clear(); _q = ''; _statutFiltre = 'a_suivre'; _echeanceFiltre = 'toutes'; }),
                    child: const Text('Réinitialiser les filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
                  ),
              ]),
            )
          else
            ...liste.map(_sterilCard),

          const SizedBox(height: 28),
          const Text('Anniversaires',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _dark)),
          const SizedBox(height: 2),
          Text('Animaux cédés fêtant leur anniversaire dans les 60 prochains jours.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          if (_annivLoaded)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeThumbColor: _teal,
              title: const Text('Message d\'anniversaire automatique',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5, color: _dark)),
              subtitle: Text('Envoie chaque année un message de vœux aux acquéreurs qui ont l\'application.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
              value: _annivAuto,
              onChanged: _toggleAnnivAuto,
            ),
          if (anniv.isEmpty)
            _hint('Aucun anniversaire dans les 60 prochains jours.')
          else
            ...anniv.map(_annivCard),
        ],
      ),
    );
  }

  Widget _badge(String statut) {
    final (label, fond, texte) = switch (statut) {
      'recu' => ('Certificat reçu', const Color(0xFFEAF2E5), const Color(0xFF4D7A3C)),
      'retard' => ('En retard', const Color(0xFFFDECEC), const Color(0xFFB91C1C)),
      _ => ('À faire', const Color(0xFFF1F3F4), const Color(0xFF4B5A60)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: texte)),
    );
  }

  void _menuDossier(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(a['nom'] as String? ?? 'Animal',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark))),
          ListTile(
            title: const Text('Coordonnées de la famille', style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: _dark)),
            onTap: () { Navigator.pop(ctx); afficherContactAcquereur(context, a); },
          ),
          ListTile(
            title: const Text('Ouvrir la fiche', style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: _dark)),
            onTap: () { Navigator.pop(ctx); _ouvrirFiche(a); },
          ),
        ]),
      )),
    );
  }

  void _ouvrirFiche(Map<String, dynamic> a) {
    final id = a['id'] as String?;
    if (id == null) return;
    // Animal cédé : la fiche s'ouvre en lecture seule (elle n'est plus à l'élevage)
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(animalId: id, initialData: a, readOnly: true),
    ));
  }

  Future<void> _voirCertificat(Map<String, dynamic> a) async {
    String? le;
    try {
      final r = await _supa.from('cessions').select('sterilisation_validee_at')
          .eq('animal_id', a['id']).not('sterilisation_validee_at', 'is', null).limit(1).maybeSingle();
      final d = _parseDate(r?['sterilisation_validee_at']);
      if (d != null) le = DateFormat('dd/MM/yyyy').format(d.toLocal());
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Certificat de stérilisation — ${a['nom'] ?? 'Animal'}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
          const SizedBox(height: 10),
          Text('Certificat reçu${le != null ? ' le $le' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF4D7A3C))),
          const SizedBox(height: 4),
          Text('La stérilisation a été validée à réception du certificat vétérinaire. Aucun fichier n\'est joint dans PetsMatch : '
              'les documents de l\'animal se trouvent dans sa fiche, onglet Administratif.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _ouvrirFiche(a); },
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                  minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Ouvrir la fiche', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(foregroundColor: _dark, side: BorderSide(color: Colors.grey.shade400),
                  minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            )),
          ]),
        ]),
      )),
    );
  }

  Widget _sterilCard(Map<String, dynamic> a) {
    final ech = _parseDate(a['sterilisation_echeance']);
    final statut = _statut(a);
    final j = _jours(a);
    final declaree = a['sterilise'] == true;
    final enCours = _validating == a['id'] || _relancing == a['id'];
    final race = (a['race'] as String?) ?? '';
    final famille = (a['destinataire_nom'] as String?) ?? '';
    final delai = statut == 'recu' || j == null ? null
        : j < 0 ? 'Dépassée de ${-j} jour${-j > 1 ? 's' : ''}'
        : j == 0 ? 'Aujourd\'hui' : 'Dans $j jour${j > 1 ? 's' : ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _ouvrirFiche(a),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _avatar(a),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: a['nom'] as String? ?? 'Sans nom',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: _dark)),
                  if (race.isNotEmpty) TextSpan(text: ' · $race', style: TextStyle(color: Colors.grey.shade600)),
                ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                Text(famille.isNotEmpty ? famille : 'Famille non renseignée', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                const SizedBox(height: 1),
                Text.rich(TextSpan(children: [
                  TextSpan(text: ech != null ? DateFormat('dd/MM/yyyy').format(ech) : 'Échéance non renseignée'),
                  if (delai != null) TextSpan(text: ' · $delai',
                      style: TextStyle(color: statut == 'retard' ? const Color(0xFFB91C1C) : null)),
                ]), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                if (declaree && statut != 'recu')
                  Text('Stérilisation déclarée par la famille',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ])),
              const SizedBox(width: 8),
              _badge(statut),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
          child: Row(children: [
            if (statut == 'recu')
              OutlinedButton(
                onPressed: () => _voirCertificat(a),
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                    minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Voir le certificat', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
              )
            else ...[
              Flexible(child: OutlinedButton(
                onPressed: enCours ? null : () => _valider(a),
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal),
                    minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _validating == a['id']
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                    : const Text('Certificat', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
              )),
              TextButton(
                onPressed: enCours ? null : () => _relancer(a),
                style: TextButton.styleFrom(foregroundColor: _teal, minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: _relancing == a['id']
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                    : const Text('Relancer', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Autres actions',
              icon: const Icon(Icons.more_horiz, color: Color(0xFF4B5A60)),
              onPressed: () => _menuDossier(a),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _annivCard(Map<String, dynamic> a) {
    final days = a['_annivDays'] as int;
    final age = a['_annivAge'] as int;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Row(children: [
        _avatar(a),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['nom'] as String? ?? 'Sans nom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
          Text(days == 0
                  ? 'Aujourd\'hui · $age an${age > 1 ? 's' : ''}'
                  : 'Dans $days jour${days > 1 ? 's' : ''} · aura $age an${age > 1 ? 's' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ])),
        TextButton(
          onPressed: _wishing == a['id'] ? null : () => _envoyerVoeux(a),
          style: TextButton.styleFrom(foregroundColor: _teal, minimumSize: const Size(0, 40)),
          child: _wishing == a['id']
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
              : const Text('Envoyer mes vœux', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Autres actions',
          icon: const Icon(Icons.more_horiz, color: Color(0xFF4B5A60)),
          onPressed: () => _menuDossier(a),
        ),
      ]),
    );
  }

  /// Photo de l'animal ou emplacement neutre (absente / erreur de chargement).
  Widget _avatar(Map<String, dynamic> a) {
    final url = a['photo_url'] as String?;
    const vide = ColoredBox(color: Color(0xFFEDF2F2),
        child: Center(child: Icon(Icons.image_outlined, size: 20, color: Color(0xFF8B9FA1))));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 44, height: 44,
        child: url == null || url.isEmpty ? vide
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(color: Color(0xFFEDF2F2)),
                errorWidget: (_, __, ___) => vide)),
    );
  }

  Widget _hint(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(msg, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
      );

  Widget _emptyState(String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          ]),
        ),
      );
}
