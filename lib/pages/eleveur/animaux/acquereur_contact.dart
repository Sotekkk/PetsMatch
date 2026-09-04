import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal  = Color(0xFF0C5C6C);
const _dark  = Color(0xFF1F2A2E);

/// Coordonnées de l'acquéreur d'un animal cédé. Priorité : **profil
/// particulier** PetsMatch de l'acquéreur (à jour, qu'il maîtrise) → contrat
/// signé (`documents_animaux`) → ligne `cessions` → `destinataire_nom` de
/// secours. `put` conserve la 1re valeur non vide trouvée.
/// Retourne `{ prenom, nom, tel, email, adresse }` (clés absentes si vides).
Future<Map<String, String>> fetchContactAcquereur(
    SupabaseClient supa, Map<String, dynamic> animal) async {
  final out = <String, String>{};
  void put(String k, dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isNotEmpty && (out[k] == null || out[k]!.isEmpty)) out[k] = s;
  }
  String joinNonEmpty(Iterable parts, String sep) => parts
      .where((e) => (e ?? '').toString().trim().isNotEmpty)
      .map((e) => e.toString().trim())
      .join(sep);

  final acqUid = (animal['uid_acquereur'] ?? '').toString();
  if (acqUid.isNotEmpty) {
    try {
      final p = await supa.from('user_profiles')
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

  put('nom', animal['destinataire_nom']);
  return out;
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
/// besoin de le recontacter.
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
    Map<String, String> c;
    try {
      c = await fetchContactAcquereur(Supabase.instance.client, widget.animal);
    } catch (_) {
      c = {};
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!context.mounted) return;

    final nom = widget.animal['nom'] as String? ?? 'l\'animal';
    final nomComplet = [c['prenom'], c['nom']]
        .where((e) => (e ?? '').isNotEmpty).join(' ');
    final tel = c['tel'] ?? '';
    final email = c['email'] ?? '';
    final adresse = c['adresse'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('Coordonnées — $nom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
          const SizedBox(height: 12),
          if (nomComplet.isEmpty && tel.isEmpty && email.isEmpty && adresse.isEmpty)
            Text('Aucune coordonnée enregistrée pour cet animal.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))
          else ...[
            if (nomComplet.isNotEmpty) _line(Icons.person_outline, nomComplet),
            if (tel.isNotEmpty) _line(Icons.phone_outlined, tel),
            if (email.isNotEmpty) _line(Icons.mail_outline, email),
            if (adresse.isNotEmpty) _line(Icons.home_outlined, adresse),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (tel.isNotEmpty)
                _actionBtn('Appeler', const Icon(Icons.call_outlined, size: 16, color: _teal), _teal,
                    () => _openUri(context, Uri(scheme: 'tel', path: _telDigits(tel)))),
              if (tel.isNotEmpty)
                _actionBtn('WhatsApp', const FaIcon(FontAwesomeIcons.whatsapp, size: 15, color: Color(0xFF25D366)), const Color(0xFF25D366),
                    () => _openUri(context, Uri.parse('https://wa.me/${_waPhone(tel)}'))),
              if (email.isNotEmpty)
                _actionBtn('Email', const Icon(Icons.email_outlined, size: 16, color: Color(0xFFEA4335)), const Color(0xFFEA4335),
                    () => _openUri(context, Uri.parse('mailto:$email'))),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _dark))),
        ]),
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
