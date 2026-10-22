// Composants communs de la gestion des annonces (« Mes annonces » de tous les
// profils qui publient : élevage, association, particulier, matériel des
// pros). Purement visuels : chaque liste garde ses données, statuts, droits,
// quotas et actions. Miroir site : components/annonces/GestionAnnonces.tsx.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _vert = Color(0xFF6E9E57);

/// Action d'une annonce (bouton principal ou entrée du menu « … »).
class GestionAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;
  /// Mise en avant (ex. annonce déjà boostée).
  final bool actif;
  const GestionAction(this.label, this.icon, this.onTap, {this.danger = false, this.actif = false});
}

/// Teintes des puces de statut (point coloré).
const kTeintesStatut = <String, (Color, Color)>{
  'vert': (Color(0xFF2F7D3A), Color(0xFFEAF5EC)),
  'ambre': (Color(0xFFB45309), Color(0xFFFEF3C7)),
  'bleu': (Color(0xFF1D4ED8), Color(0xFFEFF6FF)),
  'gris': (Color(0xFF6B7280), Color(0xFFF3F4F6)),
  'rouge': (Color(0xFFB91C1C), Color(0xFFFEF2F2)),
  'teal': (Color(0xFF0C5C6C), Color(0xFFE8F4F6)),
};

Widget puceStatut(String texte, String teinte) {
  final t = kTeintesStatut[teinte] ?? kTeintesStatut['gris']!;
  return DashPuce(texte, fg: t.$1, bg: t.$2, point: true);
}

Widget puceType(String texte) => DashPuce(texte, fg: const Color(0xFF41525A), bg: const Color(0xFFF3F6F5));

/// Correspondance de recherche (insensible à la casse et aux accents).
bool correspondRecherche(String recherche, List<String?> champs) {
  String n(String s) {
    const avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const sans = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final b = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final i = avec.indexOf(c);
      b.write(i >= 0 ? sans[i] : c);
    }
    return b.toString();
  }
  final q = n(recherche.trim());
  if (q.isEmpty) return true;
  return champs.any((c) => c != null && n(c).contains(q));
}

/// En-tête : nombre d'annonces et bouton « Publier une annonce ».
class GestionEntete extends StatelessWidget {
  final int total;
  final VoidCallback onPublier;
  const GestionEntete({super.key, required this.total, required this.onPublier});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Mes annonces', style: TextStyle(fontFamily: 'Galey', fontSize: 22,
              fontWeight: FontWeight.w700, color: kDashInk)),
          Text('$total annonce${total > 1 ? 's' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)),
        ])),
        ElevatedButton.icon(
          onPressed: onPublier,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Publier une annonce',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]);
}

/// Bandeau de quota : « 1 / 3 annonces actives », barre, lien « Gérer ».
class GestionBandeauQuota extends StatelessWidget {
  final int actives;
  /// -1 = illimité.
  final int max;
  final String formule;
  final bool changerFormule;
  final VoidCallback onGerer;
  const GestionBandeauQuota({super.key, required this.actives, required this.max,
      required this.formule, required this.onGerer, this.changerFormule = false});

  @override
  Widget build(BuildContext context) {
    final illimite = max == -1;
    final atteinte = !illimite && actives >= max;
    final pct = illimite ? 1.0 : (max > 0 ? (actives / max).clamp(0.0, 1.0) : 1.0);
    return InkWell(
      onTap: onGerer,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: atteinte ? const Color(0xFFFEF2F2) : const Color(0xFFF1F6EE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: atteinte ? const Color(0xFFFECACA) : const Color(0xFFDCE8D5)),
        ),
        child: Row(children: [
          if (!illimite) ...[
            SizedBox(width: 56, child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct, minHeight: 6,
                  backgroundColor: Colors.white, color: atteinte ? Colors.red.shade300 : _vert),
            )),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text.rich(TextSpan(children: [
            if (illimite) ...[
              TextSpan(text: 'Formule $formule · '),
              const TextSpan(text: 'annonces illimitées', style: TextStyle(fontWeight: FontWeight.w700)),
            ] else ...[
              TextSpan(text: '$actives / $max', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' annonces actives · $formule'),
            ],
            if (atteinte) const TextSpan(text: '  Limite atteinte',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
          ]), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashInk))),
          const SizedBox(width: 8),
          Text(changerFormule ? 'Changer de formule' : 'Gérer',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
          const Icon(Icons.chevron_right, size: 18, color: _teal),
        ]),
      ),
    );
  }
}

/// Champ de recherche des annonces.
class GestionRecherche extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const GestionRecherche({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: kDashInk),
        decoration: InputDecoration(
          hintText: 'Rechercher une annonce, une race…',
          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: kDashMuted),
          prefixIcon: const Icon(Icons.search, color: kDashMuted, size: 20),
          isDense: true, filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal)),
        ),
      );
}

/// Menu « … » : actions secondaires, en feuille du bas.
Future<void> ouvrirMenuActions(BuildContext context, String titre, List<GestionAction> actions) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: kDashInk)),
          ),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? const Color(0xFFDC2626) : a.actif ? const Color(0xFFB45309) : kDashInk),
              title: Text(a.label, style: TextStyle(fontFamily: 'Galey', fontSize: 14.5, fontWeight: FontWeight.w600,
                  color: a.danger ? const Color(0xFFDC2626) : a.actif ? const Color(0xFFB45309) : kDashInk)),
              onTap: a.onTap == null ? null : () { Navigator.pop(ctx); a.onTap!(); },
            ),
        ]),
      )),
    );

/// Carte d'une annonce : photo, infos, bouton « … », actions principales.
class GestionCarteAnnonce extends StatelessWidget {
  final Widget photo;
  final String titre;
  final String? sousTitre;
  final List<Widget> etiquettes;
  final String? prix;
  final List<(IconData, String)> indicateurs;
  /// Une ou deux actions affichées en boutons (la première pleine).
  final List<GestionAction> principales;
  final List<GestionAction> menu;
  final VoidCallback? onTap;
  final String? note;
  const GestionCarteAnnonce({super.key, required this.photo, required this.titre, this.sousTitre,
      this.etiquettes = const [], this.prix, this.indicateurs = const [],
      this.principales = const [], this.menu = const [], this.onTap, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDashBorder),
        boxShadow: kDashOmbre,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 92, height: 92, child: photo),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: kDashInk)),
              if (sousTitre != null && sousTitre!.isNotEmpty)
                Text(sousTitre!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: kDashMuted)),
              if (etiquettes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: etiquettes),
              ],
              if (prix != null && prix!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(prix!, style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: kDashInk)),
              ],
              if (indicateurs.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  for (final i in indicateurs)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i.$1, size: 14, color: kDashMuted),
                      const SizedBox(width: 4),
                      Text(i.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
                    ]),
                ]),
              ],
            ])),
            if (menu.isNotEmpty)
              SizedBox(
                width: 36, height: 36,
                child: OutlinedButton(
                  onPressed: () => ouvrirMenuActions(context, titre, menu),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero, foregroundColor: kDashInk,
                    side: const BorderSide(color: kDashBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Icon(Icons.more_horiz, size: 20),
                ),
              ),
          ]),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
        ],
        for (var i = 0; i < principales.length; i++) ...[
          SizedBox(height: i == 0 ? 12 : 8),
          _Bouton(a: principales[i], plein: i == 0),
        ],
      ]),
    );
  }
}

class _Bouton extends StatelessWidget {
  final GestionAction a;
  final bool plein;
  const _Bouton({required this.a, required this.plein});

  @override
  Widget build(BuildContext context) {
    final couleur = a.danger ? const Color(0xFFDC2626) : _teal;
    final texte = Text(a.label, textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14));
    final forme = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return plein
        ? ElevatedButton.icon(
            onPressed: a.onTap, icon: Icon(a.icon, size: 18), label: texte,
            style: ElevatedButton.styleFrom(backgroundColor: couleur, foregroundColor: Colors.white,
                elevation: 0, minimumSize: const Size.fromHeight(44), shape: forme))
        : OutlinedButton.icon(
            onPressed: a.onTap, icon: Icon(a.icon, size: 18), label: texte,
            style: OutlinedButton.styleFrom(foregroundColor: couleur, side: BorderSide(color: couleur.withValues(alpha: 0.6)),
                minimumSize: const Size.fromHeight(44), shape: forme));
  }
}

/// Rubrique (Animaux, Matériel & équipements) : en-tête sobre, compteur,
/// repliable. Le contenu reste monté (il charge et compte ses annonces).
class GestionRubrique extends StatefulWidget {
  final String titre;
  final IconData icon;
  /// null = en cours de chargement.
  final int? nombre;
  final Widget child;
  const GestionRubrique({super.key, required this.titre, required this.icon, required this.nombre, required this.child});

  @override
  State<GestionRubrique> createState() => _GestionRubriqueState();
}

class _GestionRubriqueState extends State<GestionRubrique> {
  bool _ouvert = true;

  @override
  Widget build(BuildContext context) {
    final vide = widget.nombre == 0;
    final visible = _ouvert && !vide;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: vide ? null : () => setState(() => _ouvert = !_ouvert),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
            child: Row(children: [
              Icon(widget.icon, size: 20, color: kDashInk),
              const SizedBox(width: 10),
              Text(widget.titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 15,
                  fontWeight: FontWeight.w700, color: kDashInk)),
              const Spacer(),
              Text(vide ? 'Aucune annonce'
                  : widget.nombre != null ? '${widget.nombre} annonce${widget.nombre! > 1 ? 's' : ''}' : '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: kDashMuted)),
              if (!vide) ...[
                const SizedBox(width: 6),
                Icon(_ouvert ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: kDashMuted),
              ],
            ]),
          ),
        ),
        Offstage(offstage: !visible, child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: widget.child,
        )),
      ]),
    );
  }
}

/// Message d'état vide, au même style.
class GestionVide extends StatelessWidget {
  final IconData icon;
  final String texte;
  const GestionVide({super.key, required this.icon, required this.texte});

  @override
  Widget build(BuildContext context) => DashCarte(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: Color(0xFFE8F4F6), shape: BoxShape.circle),
            child: Icon(icon, color: _teal, size: 21),
          ),
          const SizedBox(height: 10),
          Text(texte, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: kDashMuted)),
        ]),
      );
}

/// Boost d'une annonce d'animal : point d'entrée unique, menu « … » de « Mes
/// annonces ». Le paiement in-app est interdit (commission Apple/Google) : il
/// se finalise sur le site, qui ouvre directement les offres (?boost=<id>).
/// Offres, durées et paiement inchangés.
Future<void> ouvrirBoostAnnonce(BuildContext context,
    {required String annonceId, String? boostUntil, bool association = false}) {
  final until = boostUntil != null ? DateTime.tryParse(boostUntil) : null;
  final actif = until != null && until.isAfter(DateTime.now());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.bolt, color: Color(0xFFB45309), size: 22),
          const SizedBox(width: 8),
          Text(actif ? 'Prolonger le boost' : 'Booster l\'annonce',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: kDashInk)),
        ]),
        const SizedBox(height: 8),
        Text(
          actif
              ? 'Votre annonce est mise en avant jusqu\'au '
                  '${DateFormat('dd/MM/yyyy à HH:mm').format(until.toLocal())}. '
                  'Vous pouvez prolonger la mise en avant sur le site.'
              : 'Un boost place votre annonce en tête des résultats de recherche '
                  'et dans le fil. Le paiement se fait sur le site, en quelques secondes.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF41525A), height: 1.4),
        ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(ctx);
            final page = association ? 'association/annonces' : 'mes-annonces';
            await launchUrl(Uri.parse('$kSiteBaseUrl/$page?boost=$annonceId'), mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(actif ? 'Prolonger sur le site' : 'Booster sur le site',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )),
        Center(child: TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Plus tard', style: TextStyle(fontFamily: 'Galey', color: kDashMuted)),
        )),
      ]),
    )),
  );
}
