import 'package:PetsMatch/pages/petfriends/petfriend_chat_page.dart';
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
  final String? uid;
  final List<Map<String, dynamic>> animaux;
  final bool loading;
  final Future<void> Function() onChanged;

  const SuiviCessionsTab({
    super.key,
    required this.uid,
    required this.animaux,
    required this.loading,
    required this.onChanged,
  });

  @override
  State<SuiviCessionsTab> createState() => _SuiviCessionsTabState();
}

class _SuiviCessionsTabState extends State<SuiviCessionsTab> {
  final _supa = Supabase.instance.client;
  bool _nonFaitesOnly = false;
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

  Future<void> _loadAnnivSetting() async {
    try {
      final row = await _supa.from('user_profiles')
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

  List<Map<String, dynamic>> get _sterilList {
    var list = _cedes.where((a) => a['sterilisation_requise'] == true).toList();
    if (_nonFaitesOnly) {
      list = list.where((a) =>
          a['sterilise'] != true || a['sterilisation_validee'] != true).toList();
    }
    list.sort((a, b) {
      final da = _parseDate(a['sterilisation_echeance']);
      final db = _parseDate(b['sterilisation_echeance']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

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
          title: const Text('Valider la stérilisation',
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
                child: const Text('Valider', style: TextStyle(color: _green, fontFamily: 'Galey', fontWeight: FontWeight.w700))),
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
        final acqProfile = await _supa.from('user_profiles')
            .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
        await _supa.from('notifications').insert({
          'uid':   acqUid,
          'type':  'sterilisation_validee',
          'title': '✅ Stérilisation validée — ${a['nom'] ?? 'Animal'}',
          'body':  'L\'éleveur a validé la stérilisation de ${a['nom'] ?? 'votre animal'}. Merci !',
          if (acqProfile?['id'] != null) 'profile_id': acqProfile!['id'],
          'data':  {'animalId': a['id']},
          'read':  false,
        });
      }
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Stérilisation validée'), backgroundColor: _green));
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

  Future<void> _envoyerVoeux(Map<String, dynamic> a) async {
    final acqUid = a['uid_acquereur'] as String?;
    if (acqUid == null || acqUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('L\'acquéreur n\'a pas de compte PetsMatch.')));
      return;
    }
    final nom = a['nom'] as String? ?? 'votre compagnon';
    final ctrl = TextEditingController(
        text: 'Joyeux anniversaire $nom ! 🎂 Toute l\'équipe pense à lui aujourd\'hui.');
    final envoyer = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎂 Envoyer mes vœux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Envoyer', style: TextStyle(color: _teal, fontFamily: 'Galey'))),
        ],
      ),
    );
    if (envoyer != true) return;
    setState(() => _wishing = a['id'] as String);
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: acqUid,
        categorie: 'contact-elevage',
      );
      await _taguerConversation(convId, acqUid, await _profilAcquereur(a, acqUid));
      await _supa.from('messages').insert({
        'conversation_id': convId,
        'sender_id':       widget.uid,
        'text':            ctrl.text.trim(),
        'msg_type':        'text',
        'is_read':         false,
      });
      final conv = await _supa.from('conversations')
          .select('participants, unread_count')
          .eq('id', convId).maybeSingle();
      if (conv != null) {
        final members = List<String>.from(
            (conv['participants'] as List?)?.map((e) => e.toString()) ?? []);
        final unread = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
        for (final u in members) {
          if (u != widget.uid) unread[u] = (unread[u] as int? ?? 0) + 1;
        }
        await _supa.from('conversations').update({
          'last_message': ctrl.text.trim(),
          'unread_count': unread,
          'updated_at':   DateTime.now().toIso8601String(),
          'deleted_for':  {},
        }).eq('id', convId);
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PetFriendChatPage(
          conversationId: convId,
          convNom: a['destinataire_nom'] as String? ?? 'Message',
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _wishing = null);
    }
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

  /// Coordonnées de l'acquéreur. Priorité : **profil particulier** de l'acquéreur
  /// s'il est utilisateur PetsMatch (données à jour, qu'il maîtrise) → contrat
  /// signé → ligne `cessions`. `put` conserve la 1re valeur non vide.
  /// Retourne { prenom, nom, tel, email, adresse }.
  Future<Map<String, String>> _contactAcquereur(Map<String, dynamic> a) async {
    final out = <String, String>{};
    void put(String k, dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && (out[k] == null || out[k]!.isEmpty)) out[k] = s;
    }
    String joinNonEmpty(Iterable parts, String sep) => parts
        .where((e) => (e ?? '').toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .join(sep);

    final acqUid = (a['uid_acquereur'] ?? '').toString();
    if (acqUid.isNotEmpty) {
      try {
        final p = await _supa.from('user_profiles')
            .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
            .eq('uid', acqUid)
            .eq('profile_type', 'particulier')
            .maybeSingle();
        if (p != null) {
          put('prenom', p['firstname']);
          put('nom', p['lastname']);
          put('tel', p['phone_number']);
          put('email', p['email_contact']);
          put('adresse', p['adresse'] ??
              joinNonEmpty([p['rue'], p['code_postal'], p['ville']], ' '));
        }
      } catch (_) {}
    }

    try {
      final doc = await _supa.from('documents_animaux')
          .select('metadata')
          .eq('animal_id', a['id'])
          .inFilter('type', ['contrat_vente', 'certificat_cession'])
          .order('created_at', ascending: false)
          .limit(1).maybeSingle();
      final m = (doc?['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
      put('prenom', m['acquereur_prenom']);
      put('nom', m['acquereur_nom_famille'] ?? m['acquereur_nom']);
      put('tel', m['acquereur_tel']);
      put('email', m['acquereur_email']);
      put('adresse', joinNonEmpty([
        m['acquereur_adresse'],
        joinNonEmpty([m['acquereur_cp'], m['acquereur_ville']], ' '),
      ], ', '));
    } catch (_) {}

    try {
      final c = await _supa.from('cessions')
          .select('prenom_acquereur, nom_acquereur, tel_acquereur, email_acquereur, adresse_acquereur')
          .eq('animal_id', a['id'])
          .order('created_at', ascending: false)
          .limit(1).maybeSingle();
      if (c != null) {
        put('prenom', c['prenom_acquereur']);
        put('nom', c['nom_acquereur']);
        put('tel', c['tel_acquereur']);
        put('email', c['email_acquereur']);
        put('adresse', c['adresse_acquereur']);
      }
    } catch (_) {}

    put('nom', a['destinataire_nom']);
    return out;
  }

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
      final part = await _supa.from('user_profiles')
          .select('id').eq('uid', acqUid).eq('profile_type', 'particulier').maybeSingle();
      if (part?['id'] != null) return part!['id'] as String;
      final main = await _supa.from('user_profiles')
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
      final elevP = await _supa.from('user_profiles')
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
  Future<void> _relanceInApp(Map<String, dynamic> a, String acqUid, String texte) async {
    if (acqUid == (widget.uid ?? '')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('L\'acquéreur est votre propre compte : la relance in-app '
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
      await _supa.from('messages').insert({
        'conversation_id': convId,
        'sender_id':       widget.uid,
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
          if (u != widget.uid) unread[u] = (unread[u] as int? ?? 0) + 1;
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
      await _supa.from('notifications').insert({
        'uid':   acqUid,
        'type':  'sterilisation_relance',
        'title': '✂️ Rappel stérilisation — ${a['nom'] ?? 'votre animal'}',
        'body':  texte.length > 140 ? '${texte.substring(0, 137)}…' : texte,
        if (acqProfileId != null) 'profile_id': acqProfileId,
        'data':  {'animalId': a['id']},
        'read':  false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Relance envoyée dans l\'application ✅'), backgroundColor: _green));
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
      c = await _contactAcquereur(a);
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
                  _relanceInApp(a, acqUid, ctrl.text.trim());
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

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    final steril = _sterilList;
    final anniv = _anniversaires;
    if (_cedes.isEmpty) {
      return _emptyState('Aucun animal cédé pour le moment.',
          'Vous retrouverez ici le suivi de stérilisation et les anniversaires de vos chiots cédés.');
    }
    return RefreshIndicator(
      onRefresh: widget.onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Stérilisation ──
          Row(children: [
            const Text('✂️  Stérilisation',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
            const Spacer(),
            if (_sterilRequiseCount > 0)
              GestureDetector(
                onTap: () => setState(() => _nonFaitesOnly = !_nonFaitesOnly),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _nonFaitesOnly ? _teal : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_nonFaitesOnly ? Icons.check_circle : Icons.filter_alt_outlined,
                        size: 14, color: _nonFaitesOnly ? Colors.white : Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('Non faite',
                        style: TextStyle(fontSize: 11, fontFamily: 'Galey',
                            color: _nonFaitesOnly ? Colors.white : Colors.grey.shade700)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (steril.isEmpty)
            _hint(_nonFaitesOnly
                ? 'Toutes les stérilisations demandées sont faites et validées. 🎉'
                : 'Aucune condition de stérilisation sur vos cessions.')
          else
            ...steril.map(_sterilCard),

          const SizedBox(height: 26),

          // ── Anniversaires ──
          const Text('🎂  Anniversaires',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
          const SizedBox(height: 6),
          if (_annivLoaded)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: _green,
                title: const Text('Message d\'anniversaire automatique',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: _dark)),
                subtitle: const Text('Envoie chaque année un message de vœux aux acquéreurs qui ont l\'appli.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _annivAuto,
                onChanged: _toggleAnnivAuto,
              ),
            ),
          if (anniv.isEmpty)
            _hint('Aucun anniversaire dans les 60 prochains jours.')
          else
            ...anniv.map(_annivCard),
        ],
      ),
    );
  }

  int get _sterilRequiseCount =>
      _cedes.where((a) => a['sterilisation_requise'] == true).length;

  Widget _sterilCard(Map<String, dynamic> a) {
    final ech = _parseDate(a['sterilisation_echeance']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final done = a['sterilise'] == true;
    final validee = a['sterilisation_validee'] == true;
    final enRetard = ech != null && ech.isBefore(today) && !validee;
    final days = ech?.difference(today).inDays;

    late final String chipLabel;
    late final Color chipColor;
    if (validee) {
      chipLabel = '✅ Validée'; chipColor = _green;
    } else if (done) {
      chipLabel = '🟡 Déclarée · à valider'; chipColor = Colors.orange.shade700;
    } else if (enRetard) {
      chipLabel = 'En retard de ${-days!} j'; chipColor = Colors.red.shade600;
    } else {
      chipLabel = '⏳ À faire'; chipColor = Colors.grey.shade600;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(a),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['nom'] as String? ?? 'Sans nom',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
            const SizedBox(height: 2),
            Text([
              if ((a['destinataire_nom'] as String?)?.isNotEmpty == true) a['destinataire_nom'],
              if ((a['race'] as String?)?.isNotEmpty == true) a['race'],
            ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: chipColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(chipLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: chipColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(enRetard ? Icons.warning_amber_rounded : Icons.event_outlined,
              size: 14, color: enRetard ? Colors.red.shade600 : Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(
            ech != null
                ? (validee
                    ? 'Échéance : ${DateFormat('dd/MM/yyyy').format(ech)}'
                    : enRetard
                        ? 'Devait être fait avant le ${DateFormat('dd/MM/yyyy').format(ech)}'
                        : 'Avant le ${DateFormat('dd/MM/yyyy').format(ech)}${days != null ? ' · dans $days j' : ''}')
                : 'Échéance non définie',
            style: TextStyle(fontSize: 11, color: enRetard ? Colors.red.shade700 : Colors.grey.shade700),
          ),
        ]),
        if (!validee) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _validating == a['id'] ? null : () => _valider(a),
                icon: _validating == a['id']
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined, size: 16),
                label: Text(done ? 'Valider' : 'Certificat reçu',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _relancing == a['id'] ? null : () => _relancer(a),
                icon: _relancing == a['id']
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                    : const Icon(Icons.campaign_outlined, size: 16),
                label: const Text('Relancer la famille',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _annivCard(Map<String, dynamic> a) {
    final days = a['_annivDays'] as int;
    final age = a['_annivAge'] as int;
    final aujourdHui = days == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: aujourdHui ? _green.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aujourdHui ? _green.withValues(alpha: 0.4) : Colors.grey.shade200),
      ),
      child: Row(children: [
        _avatar(a),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['nom'] as String? ?? 'Sans nom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
          const SizedBox(height: 2),
          Text(
            aujourdHui
                ? '🎉 Aujourd\'hui · $age an${age > 1 ? 's' : ''}'
                : 'Dans $days j · aura $age an${age > 1 ? 's' : ''}',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                color: aujourdHui ? _green : Colors.grey.shade600,
                fontWeight: aujourdHui ? FontWeight.w700 : FontWeight.w400),
          ),
        ])),
        if ((a['uid_acquereur'] as String?)?.isNotEmpty == true)
          TextButton.icon(
            onPressed: _wishing == a['id'] ? null : () => _envoyerVoeux(a),
            icon: _wishing == a['id']
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cake_outlined, size: 16),
            label: const Text('Vœux', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: _teal),
          ),
      ]),
    );
  }

  Widget _avatar(Map<String, dynamic> a) {
    final url = a['photo_url'] as String?;
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        image: (url != null && url.isNotEmpty)
            ? DecorationImage(image: CachedNetworkImageProvider(url), fit: BoxFit.cover)
            : null,
      ),
      child: (url == null || url.isEmpty)
          ? const Icon(Icons.pets, size: 20, color: _teal)
          : null,
    );
  }

  Widget _hint(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(msg, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      );

  Widget _emptyState(String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pets_outlined, size: 48, color: Color(0xFFB0B8C1)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          ]),
        ),
      );
}
