import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal  = Color(0xFF0C5C6C);
const _dark  = Color(0xFF1F2A2E);

/// Adresse complète d'un profil : `adresse` (souvent la rue seule, sinon
/// [rue]) + code postal + ville, sans répéter ce qu'elle contient déjà.
String adresseComplete(dynamic adresse, dynamic cp, dynamic ville, {dynamic rue}) {
  var r = (adresse ?? '').toString().trim();
  if (r.isEmpty) r = (rue ?? '').toString().trim();
  final low = r.toLowerCase();
  final suite = [cp, ville]
      .map((e) => (e ?? '').toString().trim())
      .where((e) => e.isNotEmpty && !low.contains(e.toLowerCase()))
      .join(' ');
  return [r, suite].where((e) => e.isNotEmpty).join(', ');
}

/// Coordonnées de l'acquéreur d'un animal cédé + indique si elles peuvent être
/// corrigées à la main (`editable` = aucun compte PetsMatch actif derrière —
/// sinon c'est le propriétaire lui-même qui maîtrise ses données).
class AcquereurContact {
  final Map<String, String> data; // prenom, nom, tel, email, adresse
  final bool editable;
  const AcquereurContact(this.data, this.editable);
  String get prenom => data['prenom'] ?? '';
  String get nom => data['nom'] ?? '';
  String get tel => data['tel'] ?? '';
  String get email => data['email'] ?? '';
  String get adresse => data['adresse'] ?? '';
  bool get isEmpty => data.isEmpty;
}

/// Coordonnées de l'acquéreur d'un animal cédé. Priorité : **profil
/// particulier** PetsMatch de l'acquéreur (à jour, qu'il maîtrise) → **saisie
/// manuelle de l'éleveur** (`animaux.acquereur_contact_manuel`, uniquement si
/// pas de profil PetsMatch actif) → contrat signé (`documents_animaux`) →
/// ligne `cessions` (cessions faites dans l'app) → réservation et certificat
/// d'engagement (seules traces du téléphone / email pour les cessions faites
/// sur le site avant qu'elles remplissent `acquereur_contact_manuel`) →
/// `destinataire_nom` / `destinataire_adresse` de secours. `put` conserve la 1re
/// valeur non vide trouvée.
Future<AcquereurContact> fetchContactAcquereur(
    SupabaseClient supa, Map<String, dynamic> animal) async {
  final out = <String, String>{};
  final cpRe = RegExp(r'\b\d{5}\b');
  void put(String k, dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return;
    final cur = out[k] ?? '';
    // Adresse : une source plus loin peut avoir l'adresse complète (code
    // postal + ville) alors que la première n'a que la rue → on la préfère.
    if (cur.isEmpty || (k == 'adresse' && !cpRe.hasMatch(cur) && cpRe.hasMatch(s))) out[k] = s;
  }
  String joinNonEmpty(Iterable parts, String sep) => parts
      .where((e) => (e ?? '').toString().trim().isNotEmpty)
      .map((e) => e.toString().trim())
      .join(sep);

  var hasLiveProfile = false;
  final acqUid = (animal['uid_acquereur'] ?? '').toString();
  if (acqUid.isNotEmpty) {
    try {
      final p = await supa.from('user_profiles_complet')
          .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
          .eq('uid', acqUid)
          .eq('profile_type', 'particulier')
          .maybeSingle();
      if (p != null) {
        hasLiveProfile = true;
        put('prenom', p['firstname']);
        put('nom', p['lastname']);
        put('tel', p['phone_number']);
        put('email', p['email_contact']);
        put('adresse', adresseComplete(p['adresse'], p['code_postal'], p['ville'], rue: p['rue']));
      }
    } catch (_) {}
  }

  // Pas de compte PetsMatch actif derrière l'acquéreur → priorité à la
  // correction manuelle de l'éleveur (info reçue par tél./mail hors appli).
  if (!hasLiveProfile) {
    try {
      final row = await supa.from('animaux')
          .select('acquereur_contact_manuel')
          .eq('id', animal['id'])
          .maybeSingle();
      final manuel = row?['acquereur_contact_manuel'];
      if (manuel is Map) {
        put('prenom', manuel['prenom']);
        put('nom', manuel['nom']);
        put('tel', manuel['tel']);
        put('email', manuel['email']);
        put('adresse', manuel['adresse']);
      }
    } catch (_) {}
  }

  try {
    final doc = await supa.from('documents_animaux')
        .select('metadata')
        .eq('animal_id', animal['id'])
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
    final c = await supa.from('cessions')
        .select('prenom_acquereur, nom_acquereur, tel_acquereur, email_acquereur, adresse_acquereur')
        .eq('animal_id', animal['id'])
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

  try {
    final r = await supa.from('reservations_animaux')
        .select()
        .eq('animal_id', animal['id']).neq('statut', 'annulee')
        .order('created_at', ascending: false)
        .limit(1).maybeSingle();
    if (r != null) {
      // Ancien format : `nom` = nom complet, à ne reprendre que s'il est
      // accompagné d'un prénom séparé (sinon « Prénom Prénom Nom »).
      if ((r['prenom'] ?? '').toString().trim().isNotEmpty) {
        put('prenom', r['prenom']);
        put('nom', r['nom']);
      }
      put('tel', r['tel']);
      put('email', r['email']);
      put('adresse', r['adresse']);
    }
  } catch (_) {}

  try {
    final ce = await supa.from('certificats_engagement')
        .select('acquereur_prenom, acquereur_nom, acquereur_telephone, acquereur_email, acquereur_adresse')
        .eq('animal_id', animal['id'])
        .order('created_at', ascending: false)
        .limit(1).maybeSingle();
    if (ce != null) {
      put('prenom', ce['acquereur_prenom']);
      put('nom', ce['acquereur_nom']);
      put('tel', ce['acquereur_telephone']);
      put('email', ce['acquereur_email']);
      put('adresse', ce['acquereur_adresse']);
    }
  } catch (_) {}

  put('nom', animal['destinataire_nom']);
  if (!cpRe.hasMatch(out['adresse'] ?? '')) {
    try {
      final an = await supa.from('animaux')
          .select('destinataire_adresse').eq('id', animal['id']).maybeSingle();
      put('adresse', an?['destinataire_adresse']);
    } catch (_) {}
  }
  // Les cessions de l'app stockent le nom complet dans `nom_acquereur` :
  // évite « Leslie Leslie de Mesquita » quand le prénom vient d'ailleurs.
  final pre = (out['prenom'] ?? '').toLowerCase();
  final nomC = out['nom'] ?? '';
  if (pre.isNotEmpty && nomC.toLowerCase().startsWith('$pre ')) {
    out['nom'] = nomC.substring(pre.length).trim();
  }
  return AcquereurContact(out, !hasLiveProfile);
}

/// Enregistre la correction manuelle de l'éleveur (uniquement pertinent quand
/// l'acquéreur n'a pas de compte PetsMatch actif).
Future<void> saveContactAcquereurManuel(
    SupabaseClient supa, String animalId, Map<String, String> data) {
  return supa.from('animaux')
      .update({'acquereur_contact_manuel': data})
      .eq('id', animalId);
}

String _waPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '33${d.substring(1)}';
  return d;
}

String _telDigits(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

Future<void> _openUri(BuildContext context, Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir : ${uri.scheme}')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }
}

/// Bouton icône compact « coordonnées » : au tap, charge et affiche les
/// coordonnées du nouveau propriétaire d'un animal cédé (nom, téléphone,
/// email, adresse) + actions rapides (appeler, WhatsApp, email). À poser sur
/// n'importe quelle carte animal (Anciens, Suivi…) — on sait jamais si on a
/// besoin de le recontacter. Si l'acquéreur n'a pas (ou plus) de compte
/// PetsMatch actif, les coordonnées sont modifiables (info reçue autrement).
/// Ouvre la fiche « Coordonnées » de la famille (même feuille que le bouton),
/// depuis un menu d'actions.
Future<void> afficherContactAcquereur(BuildContext context, Map<String, dynamic> animal) async {
  AcquereurContact c;
  try {
    c = await fetchContactAcquereur(Supabase.instance.client, animal);
  } catch (_) {
    c = const AcquereurContact({}, false);
  }
  if (!context.mounted) return;
  // ignore: invalid_use_of_protected_member
  await _ContactAcquereurButtonState()._showSheet(context, animal, c);
}

class ContactAcquereurButton extends StatefulWidget {
  final Map<String, dynamic> animal;
  final Color color;
  final double size;
  const ContactAcquereurButton({
    super.key, required this.animal, this.color = _teal, this.size = 18,
  });

  @override
  State<ContactAcquereurButton> createState() => _ContactAcquereurButtonState();
}

class _ContactAcquereurButtonState extends State<ContactAcquereurButton> {
  bool _loading = false;

  Future<void> _open() async {
    setState(() => _loading = true);
    AcquereurContact c;
    try {
      c = await fetchContactAcquereur(Supabase.instance.client, widget.animal);
    } catch (_) {
      c = const AcquereurContact({}, false);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!context.mounted) return;
    await _showSheet(context, widget.animal, c);
  }

  Future<void> _showSheet(BuildContext context, Map<String, dynamic> animal, AcquereurContact initial) async {
    var c = initial;
    var editing = false;
    final nom = animal['nom'] as String? ?? 'l\'animal';
    final prenomCtrl = TextEditingController(text: c.prenom);
    final nomCtrl = TextEditingController(text: c.nom);
    final telCtrl = TextEditingController(text: c.tel);
    final emailCtrl = TextEditingController(text: c.email);
    final adresseCtrl = TextEditingController(text: c.adresse);
    var saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                Expanded(child: Text('Coordonnées — $nom',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark))),
                if (c.editable && !editing)
                  TextButton.icon(
                    onPressed: () => setSheet(() => editing = true),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                  ),
              ]),
              if (c.editable) ...[
                const SizedBox(height: 2),
                Text(
                  editing
                      ? 'Le propriétaire n\'a pas (ou plus) de compte actif — corrigez si vous avez une info plus récente.'
                      : 'Propriétaire sans compte actif : coordonnées modifiables si besoin.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
              const SizedBox(height: 12),
              if (editing) ...[
                _field(prenomCtrl, 'Prénom'),
                const SizedBox(height: 8),
                _field(nomCtrl, 'Nom'),
                const SizedBox(height: 8),
                _field(telCtrl, 'Téléphone', keyboardType: TextInputType.phone),
                const SizedBox(height: 8),
                _field(emailCtrl, 'Email', keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 8),
                _field(adresseCtrl, 'Adresse'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: saving ? null : () => setSheet(() => editing = false),
                    child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(
                    onPressed: saving ? null : () async {
                      setSheet(() => saving = true);
                      final data = {
                        'prenom': prenomCtrl.text.trim(),
                        'nom': nomCtrl.text.trim(),
                        'tel': telCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'adresse': adresseCtrl.text.trim(),
                      }..removeWhere((_, v) => v.isEmpty);
                      try {
                        await saveContactAcquereurManuel(Supabase.instance.client, animal['id'] as String, data);
                        c = AcquereurContact(data, true);
                        setSheet(() { editing = false; saving = false; });
                      } catch (e) {
                        setSheet(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                    child: saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  )),
                ]),
              ] else ...[
                if (c.isEmpty)
                  Text('Aucune coordonnée enregistrée pour cet animal.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))
                else ...[
                  if ([c.prenom, c.nom].where((e) => e.isNotEmpty).isNotEmpty)
                    _line(Icons.person_outline, [c.prenom, c.nom].where((e) => e.isNotEmpty).join(' ')),
                  if (c.tel.isNotEmpty) _line(Icons.phone_outlined, c.tel,
                      onTap: () => _openUri(context, Uri(scheme: 'tel', path: _telDigits(c.tel)))),
                  if (c.email.isNotEmpty) _line(Icons.mail_outline, c.email,
                      onTap: () => _openUri(context, Uri.parse('mailto:${c.email}'))),
                  if (c.adresse.isNotEmpty) _line(Icons.home_outlined, c.adresse,
                      onTap: () => _openUri(context, Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': c.adresse}))),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    if (c.tel.isNotEmpty)
                      _actionBtn('Appeler', const Icon(Icons.call_outlined, size: 16, color: _teal), _teal,
                          () => _openUri(context, Uri(scheme: 'tel', path: _telDigits(c.tel)))),
                    if (c.tel.isNotEmpty)
                      _actionBtn('WhatsApp', const FaIcon(FontAwesomeIcons.whatsapp, size: 15, color: Color(0xFF25D366)), const Color(0xFF25D366),
                          () => _openUri(context, Uri.parse('https://wa.me/${_waPhone(c.tel)}'))),
                    if (c.email.isNotEmpty)
                      _actionBtn('Email', const Icon(Icons.email_outlined, size: 16, color: Color(0xFFEA4335)), const Color(0xFFEA4335),
                          () => _openUri(context, Uri.parse('mailto:${c.email}'))),
                  ]),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
    prenomCtrl.dispose(); nomCtrl.dispose(); telCtrl.dispose();
    emailCtrl.dispose(); adresseCtrl.dispose();
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  /// Ligne de coordonnée ; avec [onTap] elle est cliquable (appel, email,
  /// itinéraire) et affichée en couleur de lien.
  Widget _line(IconData icon, String value, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 15, color: onTap != null ? _teal : Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(child: Text(value, style: TextStyle(fontSize: 13,
                color: onTap != null ? _teal : _dark,
                fontWeight: onTap != null ? FontWeight.w600 : FontWeight.normal))),
          ]),
        ),
      );

  Widget _actionBtn(String label, Widget icon, Color color, VoidCallback onTap) => InkWell(
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
            icon, const SizedBox(width: 7),
            Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: color)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _loading ? null : _open,
      icon: _loading
          ? SizedBox(width: widget.size - 2, height: widget.size - 2,
              child: CircularProgressIndicator(strokeWidth: 2, color: widget.color))
          : Icon(Icons.contact_phone_outlined, size: widget.size, color: widget.color),
      tooltip: 'Coordonnées du propriétaire',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
