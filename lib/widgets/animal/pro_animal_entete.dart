// En-tête commun des fiches animaux professionnelles (véto, ostéo, éducateur,
// pet-sitter, pension) : identité de l'animal + propriétaire avec actions
// rapides (appeler, message), contact d'urgence et personnes autorisées à
// déposer / récupérer l'animal. Remplace l'ancien onglet « Propriétaire ».
// Miroir site : components/animaux/ProAnimalEntete.tsx.
//
// Le propriétaire est résolu comme avant (_ProprietaireVetTab) : client du
// fichier clinique si l'animal a été créé par la clinique, sinon le profil
// qui a accordé l'accès au profil pro actif, sinon le client du dernier RDV
// (jamais is_main seul — multi-profils).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _muted = Color(0xFF6B7280);

class ProAnimalEntete extends StatefulWidget {
  final String animalId;
  /// Métier du viewer : 'garde' / 'pension' affichent les personnes autorisées.
  final String? catPro;
  /// Statut métier facultatif (ex. « En pension », « Suivi actif »).
  final String? statut;
  const ProAnimalEntete({super.key, required this.animalId, this.catPro, this.statut});

  @override
  State<ProAnimalEntete> createState() => _ProAnimalEnteteState();
}

class _Contact {
  final String nom, tel, lien;
  const _Contact(this.nom, this.tel, [this.lien = '']);
}

class _ProAnimalEnteteState extends State<ProAnimalEntete> {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _animal;
  String _ownerNom = '';
  String _ownerTel = '';
  String _ownerEmail = '';
  String _ownerAdresse = '';
  String? _ownerUid; // compte PetsMatch (messagerie) — null si client hors appli
  String _ownerSousTitre = '';
  List<_Contact> _urgence = [];
  List<_Contact> _autorises = [];
  bool _ouvert = false;
  bool _chat = false;

  bool get _avecAutorises => widget.catPro == 'garde' || widget.catPro == 'pension';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(ProAnimalEntete old) {
    super.didUpdateWidget(old);
    if (old.animalId != widget.animalId) _charger();
  }

  List<_Contact> _contacts(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final c in raw)
        if (c is Map && ((c['nom'] ?? '').toString().trim().isNotEmpty || (c['tel'] ?? '').toString().trim().isNotEmpty))
          _Contact((c['nom'] ?? '').toString().trim(), (c['tel'] ?? '').toString().trim(), (c['lien'] ?? '').toString().trim()),
    ];
  }

  String _join(List<dynamic> parts) =>
      parts.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).join(', ');

  Future<void> _charger() async {
    try {
      final a = await _supa.from('animaux').select().eq('id', widget.animalId).maybeSingle();
      if (a == null) return;
      final animal = Map<String, dynamic>.from(a);
      final urgence = _contacts(animal['contacts_urgence']);
      final autorises = _contacts(animal['personnes_autorisees']);

      // 1. Client du fichier du pro : celui de MON profil pour une fiche
      // rattachée (créée par un autre pro), sinon celui de la fiche.
      String? clientId;
      final pidActif = User_Info.activeProfileId;
      if (pidActif.isNotEmpty) {
        try {
          final l = await _supa.from('animaux_clients_pro').select('client_id')
              .eq('animal_id', widget.animalId).eq('pro_profile_id', pidActif).maybeSingle();
          clientId = l?['client_id']?.toString();
        } catch (_) {}
      }
      clientId ??= animal['client_clinique_id']?.toString();
      if (clientId != null) {
        final c = await _supa.from('clients_clinique').select().eq('id', clientId).maybeSingle();
        if (c != null) {
          if (!mounted) return;
          setState(() {
            _animal = animal; _urgence = urgence; _autorises = autorises;
            _ownerNom = '${c['prenom'] ?? ''} ${c['nom'] ?? ''}'.trim();
            _ownerTel = (c['telephone'] ?? '').toString();
            _ownerEmail = (c['email'] ?? '').toString();
            _ownerAdresse = _join([c['adresse'], '${c['code_postal'] ?? ''} ${c['ville'] ?? ''}']);
            _ownerUid = c['uid_lie']?.toString();
            _ownerSousTitre = c['uid_lie'] != null ? 'Client' : 'Client — hors PetsMatch';
          });
          return;
        }
      }

      // 2. Profil propriétaire : celui qui a accordé l'accès à mon profil, sinon client du dernier RDV.
      final pid = User_Info.activeProfileId;
      String? profilId;
      if (pid.isNotEmpty) {
        final g = await _supa.from('animal_access').select('granted_by_profile_id')
            .eq('animal_id', widget.animalId).eq('pro_profile_id', pid).maybeSingle();
        profilId = g?['granted_by_profile_id']?.toString();
        if (profilId == null || profilId.isEmpty) {
          final r = await _supa.from('rdv').select('client_profile_id').eq('animal_id', widget.animalId)
              .eq('pro_profile_id', pid).not('client_profile_id', 'is', null)
              .order('date_heure', ascending: false).limit(1).maybeSingle();
          profilId = r?['client_profile_id']?.toString();
        }
      }
      Map<String, dynamic>? prof;
      if (profilId != null && profilId.isNotEmpty) {
        prof = await _supa.from('user_profiles_complet').select().eq('id', profilId).maybeSingle();
      }
      final uid = (prof?['uid'] ?? animal['uid_proprietaire'] ?? animal['uid_eleveur'])?.toString();
      Map<String, dynamic>? user;
      if (uid != null && uid.isNotEmpty) {
        user = await _supa.from('users_complet').select().eq('uid', uid).maybeSingle();
      }
      String champ(Map<String, dynamic>? m, List<String> cles) {
        for (final k in cles) {
          final v = (m?[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
        return '';
      }
      final particulier = prof?['profile_type'] == 'particulier';
      final nomProf = particulier
          ? '${prof?['firstname'] ?? ''} ${prof?['lastname'] ?? ''}'.trim()
          : champ(prof, ['nom', 'name_elevage']);
      final nomUser = '${user?['firstname'] ?? ''} ${user?['lastname'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        _animal = animal; _urgence = urgence; _autorises = autorises;
        _ownerUid = uid;
        _ownerNom = nomProf.isNotEmpty ? nomProf : nomUser;
        _ownerTel = champ(prof, particulier ? ['telephone', 'phone_number'] : ['numero_elevage', 'telephone', 'phone_number'])
            .ifEmpty(champ(user, ['phone_number', 'numero_elevage', 'numeroElevage']));
        _ownerEmail = champ(prof, ['email_contact', 'email']).ifEmpty(champ(user, ['email']));
        _ownerAdresse = _join([
          champ(prof, particulier ? ['rue', 'adresse'] : ['rue_elevage', 'rue', 'adresse']),
          '${champ(prof, particulier ? ['code_postal'] : ['code_postal_elevage', 'code_postal'])} '
              '${champ(prof, particulier ? ['ville'] : ['ville_elevage', 'ville'])}',
        ]).ifEmpty(_join([champ(user, ['rue']), '${champ(user, ['code_postal'])} ${champ(user, ['ville'])}']));
        _ownerSousTitre = particulier || prof == null ? 'Propriétaire' : 'Propriétaire (professionnel)';
      });
    } catch (_) {}
  }

  String _age(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    final now = DateTime.now();
    var mois = (now.year - d.year) * 12 + now.month - d.month;
    if (now.day < d.day) mois--;
    if (mois < 1) return "moins d'1 mois";
    if (mois < 24) return '$mois mois';
    return '${mois ~/ 12} ans';
  }

  String _sexe(String? s) => switch ((s ?? '').toLowerCase()) {
        'male' || 'mâle' || 'm' => 'Mâle',
        'femelle' || 'f' => 'Femelle',
        _ => '',
      };

  Future<void> _appeler(String tel) => launchUrl(Uri.parse('tel:${tel.replaceAll(' ', '')}'));

  Future<void> _message() async {
    final uid = _ownerUid;
    if (uid == null || _chat) return;
    setState(() => _chat = true);
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: uid, categorie: 'services',
        myProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      );
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: convId, eleveurId: uid)));
      }
    } finally {
      if (mounted) setState(() => _chat = false);
    }
  }

  Widget _action(IconData ic, String tip, VoidCallback? onTap) => IconButton(
        tooltip: tip, onPressed: onTap, visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(backgroundColor: _teal.withValues(alpha: 0.08)),
        icon: Icon(ic, size: 18, color: onTap == null ? Colors.grey.shade400 : _teal),
      );

  Widget _ligne(IconData ic, String label, String valeur, {String? tel}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, size: 15, color: _muted),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label : ', style: const TextStyle(color: _muted)),
            TextSpan(text: valeur, style: const TextStyle(color: _ink)),
          ]), style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
          if (tel != null && tel.isNotEmpty)
            InkWell(onTap: () => _appeler(tel),
                child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.phone_outlined, size: 16, color: _teal))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = _animal;
    if (a == null) return const SizedBox(height: 4);
    final photo = (a['photo_url'] ?? '').toString();
    final identite = [
      (a['espece'] ?? '').toString(), (a['race'] ?? '').toString(),
      _sexe(a['sexe']?.toString()), _age(a['date_naissance']?.toString()),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final puce = (a['identification'] ?? '').toString().trim();
    final details = _ouvert && (_urgence.isNotEmpty || (_avecAutorises && _autorises.isNotEmpty) ||
        _ownerEmail.isNotEmpty || _ownerAdresse.isNotEmpty);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 46, height: 46, color: const Color(0xFFEEF5EA),
              child: photo.isNotEmpty
                  ? Image.network(photo, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.pets, color: _teal, size: 20))
                  : const Icon(Icons.pets, color: _teal, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text((a['nom'] ?? 'Animal').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15.5, color: _ink))),
              if ((widget.statut ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                  child: Text(widget.statut!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: _teal)),
                ),
              ],
            ]),
            if (identite.isNotEmpty)
              Text(identite, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
            if (puce.isNotEmpty)
              Text('Identification : $puce', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
          ])),
        ]),
        const Divider(height: 18, color: Color(0xFFEDEFF0)),
        Row(children: [
          const Icon(Icons.person_outline, size: 18, color: _teal),
          const SizedBox(width: 8),
          Expanded(child: InkWell(
            onTap: () => setState(() => _ouvert = !_ouvert),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_ownerNom.isNotEmpty ? _ownerNom : 'Propriétaire non renseigné', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
              Text([_ownerSousTitre, if (_ownerTel.isNotEmpty) _ownerTel].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
            ]),
          )),
          _action(Icons.phone_outlined, 'Appeler', _ownerTel.isEmpty ? null : () => _appeler(_ownerTel)),
          const SizedBox(width: 4),
          _action(Icons.chat_bubble_outline, 'Message', _ownerUid == null ? null : _message),
          IconButton(
            tooltip: _ouvert ? 'Masquer' : 'Coordonnées, urgence${_avecAutorises ? ', personnes autorisées' : ''}',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _ouvert = !_ouvert),
            icon: Icon(_ouvert ? Icons.expand_less : Icons.expand_more, color: _muted),
          ),
        ]),
        if (!_ouvert && _urgence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text("Contact d'urgence : ${_urgence.first.nom}${_urgence.first.tel.isNotEmpty ? ' · ${_urgence.first.tel}' : ''}",
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
          ),
        if (_ouvert)
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_ownerEmail.isNotEmpty) _ligne(Icons.mail_outline, 'E-mail', _ownerEmail),
              if (_ownerAdresse.isNotEmpty) _ligne(Icons.home_outlined, 'Adresse', _ownerAdresse),
              for (final c in _urgence)
                _ligne(Icons.emergency_outlined, "Contact d'urgence",
                    [c.nom, c.tel].where((s) => s.isNotEmpty).join(' · '), tel: c.tel),
              if (_avecAutorises)
                for (final c in _autorises)
                  _ligne(Icons.how_to_reg_outlined, 'Autorisé·e à déposer / récupérer',
                      [c.nom, if (c.lien.isNotEmpty) '(${c.lien})', c.tel].where((s) => s.isNotEmpty).join(' '), tel: c.tel),
              if (!details)
                const Padding(padding: EdgeInsets.only(top: 6),
                    child: Text('Aucune autre information transmise.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted))),
            ]),
          ),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String autre) => trim().isEmpty ? autre : this;
}
