// Champs du formulaire de recherche de l'annuaire (métier, lieu, rayon,
// animaux pris en charge). Miroir site : src/components/annuaire/*.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/annuaire_filtres.dart';

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1F2A2E);

/// Champ « déroulant » : libellé au-dessus, valeur + chevron, ouvre un menu.
class AnnuaireSelectField extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool placeholder;
  final bool enabled;
  final VoidCallback onTap;

  const AnnuaireSelectField({
    super.key, required this.label, required this.value, required this.onTap,
    this.icon, this.placeholder = false, this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
      const SizedBox(height: 4),
      Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: placeholder ? Colors.grey.shade500 : _teal),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                      color: placeholder ? Colors.grey.shade600 : _dark))),
              Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey.shade500),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Étiquette supprimable (animal sélectionné).
class AnnuaireChipSupprimable extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const AnnuaireChipSupprimable({super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
            fontWeight: FontWeight.w700, color: _teal)),
        InkWell(
          onTap: onRemove,
          customBorder: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 14, color: _teal),
          ),
        ),
      ]),
    );
  }
}

Widget _sheetHandle() => Center(child: Container(width: 40, height: 4,
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))));

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: builder,
    );

// ── Animaux pris en charge ───────────────────────────────────────────────────

/// Menu « Animaux pris en charge » : cases à cocher, liste défilante,
/// Réinitialiser / Appliquer. Renvoie la sélection, ou null si fermé sans
/// appliquer.
Future<List<String>?> showAnimauxSheet(BuildContext context, List<String> initial) {
  var draft = [...initial];
  return _sheet<List<String>>(context, (ctx) => StatefulBuilder(
    builder: (ctx, setS) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sheetHandle(),
        const Text('Animaux pris en charge', style: TextStyle(fontFamily: 'Galey',
            fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
        Text('Plusieurs choix possibles', style: TextStyle(fontFamily: 'Galey',
            fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView(shrinkWrap: true, children: kGroupesEspeces.map((g) => CheckboxListTile(
              value: draft.contains(g.key),
              onChanged: (v) => setS(() => v == true ? draft.add(g.key) : draft.remove(g.key)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: _teal,
              title: Text(g.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
              subtitle: g.detail == null ? null
                  : Text(g.detail!, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
            )).toList()),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => setS(() => draft = []),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, draft),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      ]),
    ),
  ));
}

String resumeAnimaux(List<String> keys) {
  if (keys.isEmpty) return 'Toutes les espèces';
  if (keys.length == 1) {
    return kGroupesEspeces.firstWhere((g) => g.key == keys.first, orElse: () => kGroupesEspeces.first).label;
  }
  return '${keys.length} sélectionnés';
}

// ── Métier ───────────────────────────────────────────────────────────────────

Future<String?> showMetierSheet(BuildContext context, String current) {
  final groupes = <String>[];
  for (final m in kMetiers) {
    if (!groupes.contains(m.groupe)) groupes.add(m.groupe);
  }
  return _sheet<String>(context, (ctx) => DraggableScrollableSheet(
    expand: false, initialChildSize: 0.7, maxChildSize: 0.92,
    builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      _sheetHandle(),
      const Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Text('Métier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
      ),
      for (final g in groupes) ...[
        if (g.isNotEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 2),
          child: Text(g.toUpperCase(), style: TextStyle(fontFamily: 'Galey', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.grey.shade500)),
        ),
        for (final m in kMetiers.where((m) => m.groupe == g)) ListTile(
          dense: true,
          title: Text(m.label, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
              fontWeight: m.key == current ? FontWeight.w700 : FontWeight.normal,
              color: m.key == current ? _teal : _dark)),
          trailing: m.key == current ? const Icon(Icons.check_rounded, color: _teal, size: 18) : null,
          onTap: () => Navigator.pop(ctx, m.key),
        ),
      ],
    ]),
  ));
}

// ── Rayon ────────────────────────────────────────────────────────────────────

Future<int?> showRayonSheet(BuildContext context, int current) {
  return _sheet<int>(context, (ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sheetHandle(),
      const Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Text('Rayon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
      ),
      for (final r in kRayonsKm) ListTile(
        dense: true,
        title: Text('$r km', style: TextStyle(fontFamily: 'Galey', fontSize: 14,
            fontWeight: r == current ? FontWeight.w700 : FontWeight.normal,
            color: r == current ? _teal : _dark)),
        trailing: r == current ? const Icon(Icons.check_rounded, color: _teal, size: 18) : null,
        onTap: () => Navigator.pop(ctx, r),
      ),
    ]),
  ));
}

// ── Lieu ─────────────────────────────────────────────────────────────────────

/// Choix fait dans le menu Lieu ([lieu] null = toute la France).
class LieuChoix {
  final LieuRecherche? lieu;
  const LieuChoix(this.lieu);
}

/// Commune française (autocomplétion), « Autour de moi » ou « Toute la
/// France ». Renvoie null si fermé sans choisir.
Future<LieuChoix?> showLieuSheet(BuildContext context, {LieuRecherche? maPosition}) {
  return _sheet<LieuChoix>(context, (ctx) => _LieuSheet(maPosition: maPosition));
}

class _LieuSheet extends StatefulWidget {
  final LieuRecherche? maPosition;
  const _LieuSheet({this.maPosition});
  @override
  State<_LieuSheet> createState() => _LieuSheetState();
}

class _LieuSheetState extends State<_LieuSheet> {
  List<LieuRecherche> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _loading = true);
      final res = await chercherCommunes(v);
      if (mounted) setState(() { _suggestions = res; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sheetHandle(),
        const Text('Lieu', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
        const SizedBox(height: 10),
        TextField(
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ville ou code postal',
            prefixIcon: const Icon(Icons.location_on_outlined, color: _teal, size: 20),
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
          child: ListView(shrinkWrap: true, children: [
            if (widget.maPosition != null) ListTile(
              dense: true,
              leading: const Icon(Icons.my_location_rounded, color: _teal, size: 20),
              title: Text('Autour de moi${widget.maPosition!.ville != null ? ' (${widget.maPosition!.ville})' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal)),
              onTap: () => Navigator.pop(context, LieuChoix(widget.maPosition)),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.public_rounded, color: Colors.grey.shade600, size: 20),
              title: const Text('Toute la France', style: TextStyle(fontFamily: 'Galey')),
              onTap: () => Navigator.pop(context, const LieuChoix(null)),
            ),
            for (final s in _suggestions) ListTile(
              dense: true,
              leading: Icon(Icons.place_outlined, color: Colors.grey.shade500, size: 20),
              title: Text(s.label, style: const TextStyle(fontFamily: 'Galey')),
              onTap: () => Navigator.pop(context, LieuChoix(s)),
            ),
          ]),
        ),
      ]),
    );
  }
}
