// Présentation commune des menus latéraux professionnels (éleveur, métiers,
// association, menu des pages de services). Purement visuel : chaque menu
// garde ses rubriques, son ordre, ses destinations et ses conditions.
import 'package:flutter/material.dart';

const kMenuTeal = Color(0xFF0C5C6C);
const kMenuTexte = Color(0xFF1F2A2E);
const kMenuFondActif = Color(0xFFE8F4F6);
const kMenuRouge = Color(0xFFC0392B);

/// Thème des menus : séparateurs fins et en retrait.
ThemeData themeMenuPro(BuildContext context) => Theme.of(context).copyWith(
  dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1, space: 17, indent: 20, endIndent: 20),
);

Widget _badge(String label) => Container(
  margin: const EdgeInsets.only(left: 8),
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.35)),
  ),
  child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
);

/// Entrée de premier niveau.
class MenuProItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final String badgeLabel;
  final bool active;
  /// Enveloppe l'icône (ex. pastille de notification existante).
  final Widget Function(Widget icone)? enveloppeIcone;

  const MenuProItem({
    super.key, required this.icon, required this.label, required this.onTap,
    this.locked = false, this.badgeLabel = 'Pro', this.active = false, this.enveloppeIcone,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = locked ? Colors.grey.shade400 : active ? kMenuTeal : kMenuTexte;
    final icone = Icon(icon, size: 22, color: locked ? Colors.grey.shade400 : kMenuTeal);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: active ? kMenuFondActif : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                SizedBox(width: 24, child: Center(child: enveloppeIcone != null ? enveloppeIcone!(icone) : icone)),
                const SizedBox(width: 14),
                Flexible(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: couleur))),
                if (locked) _badge(badgeLabel),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rubrique dépliable (même comportement : fermée par défaut sauf indication).
class MenuProSection extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;
  final bool initiallyExpanded;

  const MenuProSection({super.key, required this.icon, required this.label, required this.children, this.initiallyExpanded = false});

  @override
  State<MenuProSection> createState() => _MenuProSectionState();
}

class _MenuProSectionState extends State<MenuProSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                SizedBox(width: 24, child: Center(child: Icon(widget.icon, size: 22, color: kMenuTeal))),
                const SizedBox(width: 14),
                Expanded(child: Text(widget.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 15,
                    fontWeight: FontWeight.w500, color: kMenuTexte))),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: Colors.grey.shade500),
                ),
              ]),
            ),
          ),
        ),
      ),
      AnimatedCrossFade(
        firstChild: const SizedBox(width: double.infinity),
        secondChild: Container(
          // Sous-menus : retrait + filet vertical discret
          margin: const EdgeInsets.fromLTRB(45, 0, 10, 6),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
        ),
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 200),
      ),
    ]);
  }
}

/// Sous-menu : texte seul, traitement discret.
class MenuProSubItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final String badgeLabel;
  final bool active;
  /// Pastille de notification existante, conservée à droite du libellé.
  final Widget? indicateur;

  const MenuProSubItem({
    super.key, required this.label, required this.onTap,
    this.locked = false, this.badgeLabel = 'Pro', this.active = false, this.indicateur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: active ? kMenuFondActif : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Flexible(child: Text(label, maxLines: 2, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: locked ? Colors.grey.shade400 : active ? kMenuTeal : const Color(0xFF3F4B50)))),
                if (indicateur != null) ...[const SizedBox(width: 8), indicateur!],
                if (locked) _badge(badgeLabel),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lien secondaire discret (ex. CGU & Confidentialité).
class MenuProLienDiscret extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const MenuProLienDiscret({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(children: [
          SizedBox(width: 24, child: Center(child: Icon(icon, size: 20, color: Colors.grey.shade500))),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.grey.shade600)),
        ]),
      ),
    ),
  );
}

/// Déconnexion en rouge discret.
class MenuProDeconnexion extends StatelessWidget {
  final VoidCallback onTap;
  const MenuProDeconnexion({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(children: [
          SizedBox(width: 24, child: Center(child: Icon(Icons.logout_rounded, size: 22, color: kMenuRouge))),
          SizedBox(width: 14),
          Text('Déconnexion', style: TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w600, color: kMenuRouge)),
        ]),
      ),
    ),
  );
}
