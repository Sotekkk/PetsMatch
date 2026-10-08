// Briques du formulaire de prise de rendez-vous, communes à toutes les
// professions : la page du métier fournit ses motifs, ses intervenants et ses
// textes (rien de vétérinaire ici). Utilisées d'abord par le formulaire
// vétérinaire (rdv_booking_page.dart). Miroir site :
// website/src/components/rdv/RdvForm.tsx.

import 'package:flutter/material.dart';

const _ink = Color(0xFF1E2025);
const _muted = Color(0xFF6F767B);
const _line = Color(0xFFE4E7E2);
const _font = 'Galey';

/// Motif / prestation proposé au client.
class RdvOption {
  final String key;
  final String label;
  final IconData icon;
  final String? description;
  /// Petite info à droite (ex. durée « 30 min »).
  final String? badge;
  const RdvOption({required this.key, required this.label, required this.icon, this.description, this.badge});
}

/// Intervenant (vétérinaire, employé…) ; `id` '*' = « Peu importe ».
class RdvIntervenant {
  final String id;
  final String nom;
  final String? sousTitre;
  final String? photoUrl;
  const RdvIntervenant({required this.id, required this.nom, this.sousTitre, this.photoUrl});
}

/// Titre de section numéroté.
class RdvSection extends StatelessWidget {
  final int? etape;
  final String titre;
  final String? sousTitre;
  final Color color;
  final Widget child;
  const RdvSection({super.key, this.etape, required this.titre, this.sousTitre, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (etape != null) ...[
          Container(
            width: 22, height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text('$etape', style: TextStyle(fontFamily: _font, fontSize: 11.5,
                fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(titre, style: const TextStyle(fontFamily: _font, fontSize: 15,
            fontWeight: FontWeight.w700, color: _ink))),
      ]),
      if (sousTitre != null) ...[
        const SizedBox(height: 3),
        Padding(
          padding: EdgeInsets.only(left: etape != null ? 32 : 0),
          child: Text(sousTitre!, style: const TextStyle(fontFamily: _font, fontSize: 12, color: _muted)),
        ),
      ],
      const SizedBox(height: 12),
      child,
    ]);
  }
}

/// Cartes de sélection compactes, sur deux colonnes quand la place le permet.
class RdvChoiceGrid extends StatelessWidget {
  final List<RdvOption> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Color color;
  const RdvChoiceGrid({super.key, required this.options, required this.selected, required this.onSelect, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final cols = c.maxWidth >= 340 ? 2 : 1;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final o in options) SizedBox(width: w, child: _ChoiceCard(
          option: o, selected: o.key == selected, color: color, onTap: () => onSelect(o.key))),
      ]);
    });
  }
}

class _ChoiceCard extends StatelessWidget {
  final RdvOption option;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ChoiceCard({required this.option, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : _line, width: selected ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(option.icon, size: 18, color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: _font, fontSize: 13.5, fontWeight: FontWeight.w700,
                        color: selected ? color : _ink))),
                if (option.badge != null)
                  Text(option.badge!, style: const TextStyle(fontFamily: _font, fontSize: 10.5, color: _muted)),
              ]),
              if (option.description != null) ...[
                const SizedBox(height: 2),
                Text(option.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: _font, fontSize: 11.5, height: 1.25, color: _muted)),
              ],
            ])),
          ]),
        ),
      ),
    );
  }
}

/// Deux choix courts côte à côte (ex. « Première visite » / « Déjà patient »).
class RdvSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelect;
  final Color color;
  const RdvSegmented({super.key, required this.options, required this.selected, required this.onSelect, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        for (final o in options) Expanded(child: GestureDetector(
          onTap: () => onSelect(o.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected == o.$1 ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected == o.$1 ? color.withValues(alpha: 0.5) : Colors.transparent),
              boxShadow: selected == o.$1
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                  : const [],
            ),
            child: Text(o.$2, style: TextStyle(fontFamily: _font, fontSize: 13,
                fontWeight: FontWeight.w600, color: selected == o.$1 ? color : _muted)),
          ),
        )),
      ]),
    );
  }
}

/// Liste d'intervenants avec avatar (photo ou icône neutre).
class RdvIntervenantList extends StatelessWidget {
  final List<RdvIntervenant> intervenants;
  final String selected;
  final ValueChanged<String> onSelect;
  final Color color;
  const RdvIntervenantList({super.key, required this.intervenants, required this.selected, required this.onSelect, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final p in intervenants) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(p.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.id == selected ? color.withValues(alpha: 0.06) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.id == selected ? color : _line, width: p.id == selected ? 1.5 : 1),
              ),
              child: Row(children: [
                _Avatar(photoUrl: p.photoUrl, color: color, tous: p.id == '*'),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nom, style: TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w700,
                      color: p.id == selected ? color : _ink)),
                  if (p.sousTitre != null)
                    Text(p.sousTitre!, style: const TextStyle(fontFamily: _font, fontSize: 11.5, color: _muted)),
                ])),
                _Radio(selected: p.id == selected, color: color),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final Color color;
  final bool tous;
  const _Avatar({required this.photoUrl, required this.color, required this.tous});

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(tous ? Icons.groups_outlined : Icons.person_outline, size: 20, color: color);
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl ?? '').isNotEmpty
          ? Image.network(photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
          : fallback,
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  final Color color;
  const _Radio({required this.selected, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: 20, height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: selected ? color : const Color(0xFFC9CDC7), width: selected ? 6 : 1.5),
    ),
  );
}

/// Champ déroulant (ex. choix de l'animal) : vignette + titre + sous-titre.
class RdvSelectField extends StatelessWidget {
  final Widget? leading;
  final String? titre;
  final String? sousTitre;
  final String placeholder;
  final VoidCallback onTap;
  const RdvSelectField({super.key, this.leading, this.titre, this.sousTitre, required this.placeholder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(child: titre == null
                ? Text(placeholder, style: const TextStyle(fontFamily: _font, fontSize: 14, color: _muted))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titre!, style: const TextStyle(fontFamily: _font, fontSize: 14,
                        fontWeight: FontWeight.w700, color: _ink)),
                    if (sousTitre != null && sousTitre!.isNotEmpty)
                      Text(sousTitre!, style: const TextStyle(fontFamily: _font, fontSize: 11.5, color: _muted)),
                  ])),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
          ]),
        ),
      ),
    );
  }
}

/// Bandeau de dates compactes, navigation par flèches (sans barre de
/// défilement). `dates` au format AAAA-MM-JJ ; `disponible` grise une date
/// sans créneau pour la durée choisie.
class RdvDateStrip extends StatefulWidget {
  final List<String> dates;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Color color;
  final bool Function(String date)? disponible;
  const RdvDateStrip({super.key, required this.dates, required this.selected, required this.onSelect, required this.color, this.disponible});

  @override
  State<RdvDateStrip> createState() => _RdvDateStripState();
}

class _RdvDateStripState extends State<RdvDateStrip> {
  final _ctrl = ScrollController();
  static const _w = 54.0, _gap = 8.0;
  bool _debut = true, _fin = false;

  static const _jours = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
  static const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_maj);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maj());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _maj() {
    if (!_ctrl.hasClients) return;
    final p = _ctrl.position;
    final d = p.pixels <= 1, f = p.pixels >= p.maxScrollExtent - 1;
    if (d != _debut || f != _fin) setState(() { _debut = d; _fin = f; });
  }

  void _defiler(int sens) {
    if (!_ctrl.hasClients) return;
    final p = _ctrl.position;
    final cible = (p.pixels + sens * (p.viewportDimension - _w)).clamp(0.0, p.maxScrollExtent);
    _ctrl.animateTo(cible, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Widget _fleche(IconData icon, bool actif, int sens) => SizedBox(
    width: 30,
    child: IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: actif ? () => _defiler(sens) : null,
      icon: Icon(icon, size: 22, color: actif ? _ink : const Color(0xFFCDD1CB)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Row(children: [
      _fleche(Icons.chevron_left_rounded, !_debut, -1),
      Expanded(child: SizedBox(
        height: 70,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView.separated(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            itemCount: widget.dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (_, i) {
              final key = widget.dates[i];
              final d = DateTime.tryParse(key);
              if (d == null) return const SizedBox.shrink();
              final sel = key == widget.selected;
              final dispo = widget.disponible?.call(key) ?? true;
              return GestureDetector(
                onTap: () => widget.onSelect(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: _w,
                  decoration: BoxDecoration(
                    color: sel ? c : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? c : _line),
                  ),
                  child: Opacity(
                    opacity: dispo || sel ? 1 : 0.4,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_jours[d.weekday - 1], style: TextStyle(fontFamily: _font, fontSize: 10,
                          letterSpacing: 0.4, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white.withValues(alpha: 0.85) : _muted)),
                      const SizedBox(height: 2),
                      Text('${d.day}', style: TextStyle(fontFamily: _font, fontSize: 18,
                          fontWeight: FontWeight.w800, color: sel ? Colors.white : _ink)),
                      Text(_mois[d.month - 1], style: TextStyle(fontFamily: _font, fontSize: 10,
                          color: sel ? Colors.white.withValues(alpha: 0.85) : _muted)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      )),
      _fleche(Icons.chevron_right_rounded, !_fin, 1),
    ]);
  }
}

/// Horaires disponibles, groupés Matin / Après-midi / Soir.
/// `horaires` : clés « HH:MM » triées.
class RdvTimeGrid extends StatelessWidget {
  final List<String> horaires;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Color color;
  const RdvTimeGrid({super.key, required this.horaires, required this.selected, required this.onSelect, required this.color});

  @override
  Widget build(BuildContext context) {
    final groupes = <String, List<String>>{'Matin': [], 'Après-midi': [], 'Soir': []};
    for (final h in horaires) {
      final heure = int.tryParse(h.split(':').first) ?? 0;
      groupes[heure < 12 ? 'Matin' : heure < 18 ? 'Après-midi' : 'Soir']!.add(h);
    }
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final cols = c.maxWidth >= 420 ? 5 : 4;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final g in groupes.entries) if (g.value.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 2),
            child: Text(g.key, style: const TextStyle(fontFamily: _font, fontSize: 11.5,
                fontWeight: FontWeight.w600, color: _muted)),
          ),
          Wrap(spacing: gap, runSpacing: gap, children: [
            for (final h in g.value) GestureDetector(
              onTap: () => onSelect(h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: h == selected ? color : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: h == selected ? color : _line),
                ),
                child: Text(h, style: TextStyle(fontFamily: _font, fontSize: 13.5,
                    fontWeight: FontWeight.w700, color: h == selected ? Colors.white : _ink)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
        ],
      ]);
    });
  }
}

/// Champ de texte libre, discret.
class RdvTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Color color;
  final int minLines;
  const RdvTextArea({super.key, required this.controller, required this.hint, required this.color, this.minLines = 3});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: minLines,
    maxLines: 6,
    textCapitalization: TextCapitalization.sentences,
    style: const TextStyle(fontFamily: _font, fontSize: 14, height: 1.35),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: _font, fontSize: 13, color: Color(0xFF9AA09C)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: 1.5)),
    ),
  );
}

/// Récapitulatif avant validation : lignes (icône, libellé, valeur).
class RdvRecap extends StatelessWidget {
  final List<(IconData, String, String)> lignes;
  final Color color;
  const RdvRecap({super.key, required this.lignes, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Récapitulatif', style: TextStyle(fontFamily: _font, fontSize: 13.5,
            fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 8),
        for (final l in lignes) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(l.$1, size: 16, color: color),
            const SizedBox(width: 10),
            SizedBox(width: 92, child: Text(l.$2, style: const TextStyle(fontFamily: _font, fontSize: 12.5, color: _muted))),
            Expanded(child: Text(l.$3, style: const TextStyle(fontFamily: _font, fontSize: 13,
                fontWeight: FontWeight.w600, color: _ink))),
          ]),
        ),
      ]),
    );
  }
}

/// Bouton principal du formulaire.
class RdvPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final Color color;
  const RdvPrimaryButton({super.key, required this.label, required this.onPressed, required this.color, this.loading = false});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 15.5)),
    ),
  );
}
