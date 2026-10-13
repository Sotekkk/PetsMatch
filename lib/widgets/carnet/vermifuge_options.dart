// Vermifuge du carnet : traitement sur plusieurs jours avec rappel à chaque
// prise (même mécanique que les traitements : rappel_* + Cloud Function
// sendTraitementReminders) et saisie pour plusieurs animaux d'un coup.
// Utilisé par le carnet éleveur / association (animal_fiche.dart) et
// particulier (animal_fiche_particulier.dart). Miroir site :
// website/src/components/animaux/VermifugeOptions.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xFF6E9E57);

class OptionsVermifuge {
  int dureeJours = 1;
  bool rappel = false;
  final List<String> heures = [];
  final Set<String> autresAnimaux = {};

  /// Colonnes « prises » à enregistrer sur la ligne vermifuges.
  Map<String, dynamic> colonnes(DateTime debut) => {
        'duree_jours': dureeJours,
        'rappel_actif': rappel && heures.isNotEmpty,
        if (rappel && heures.isNotEmpty) ...{
          'rappel_frequence_jours': 1,
          'rappel_duree_jours': dureeJours,
          'rappel_fin': debut.add(Duration(days: dureeJours - 1)).toIso8601String(),
          'rappel_heures': heures,
        },
      };

  String? get erreur => rappel && heures.isEmpty ? 'Ajoutez au moins une heure de rappel.' : null;
}

/// Durée du traitement + rappels de prise.
class PrisesVermifugeSection extends StatefulWidget {
  final OptionsVermifuge options;
  const PrisesVermifugeSection({super.key, required this.options});

  @override
  State<PrisesVermifugeSection> createState() => _PrisesVermifugeSectionState();
}

class _PrisesVermifugeSectionState extends State<PrisesVermifugeSection> {
  late final _duree = TextEditingController(text: '${widget.options.dureeJours}');

  @override
  void dispose() {
    _duree.dispose();
    super.dispose();
  }

  Future<void> _ajouterHeure() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (!widget.options.heures.contains(s)) setState(() { widget.options.heures..add(s)..sort(); });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.options;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F8F6), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E7E2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Durée du traitement', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          SizedBox(width: 56, child: TextFormField(
            controller: _duree, keyboardType: TextInputType.number, textAlign: TextAlign.center,
            onChanged: (v) => setState(() => o.dureeJours = (int.tryParse(v) ?? 1).clamp(1, 60)),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder()),
          )),
          const SizedBox(width: 8),
          Text(o.dureeJours > 1 ? 'jours' : 'jour', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ]),
        Row(children: [
          const Expanded(child: Text('Rappel à chaque prise',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
          Switch(value: o.rappel, activeThumbColor: _green, onChanged: (v) => setState(() => o.rappel = v)),
        ]),
        if (o.rappel) ...[
          Text(o.dureeJours > 1 ? 'Chaque jour pendant ${o.dureeJours} jours, aux heures suivantes :' : 'Le jour de la prise, à :',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in o.heures)
              Chip(label: Text(h, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onDeleted: () => setState(() => o.heures.remove(h)),
                  backgroundColor: _green.withValues(alpha: 0.12)),
            ActionChip(avatar: const Icon(Icons.add, size: 16),
                label: const Text('Ajouter une heure', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: _ajouterHeure),
          ]),
        ],
      ]),
    );
  }
}

/// « Appliquer aussi à » : autres animaux présents du même propriétaire
/// (même profil, même espèce).
class AutresAnimauxSection extends StatefulWidget {
  final String animalId;
  final OptionsVermifuge options;
  const AutresAnimauxSection({super.key, required this.animalId, required this.options});

  @override
  State<AutresAnimauxSection> createState() => _AutresAnimauxSectionState();
}

class _AutresAnimauxSectionState extends State<AutresAnimauxSection> {
  List<Map<String, dynamic>> _animaux = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final supa = Supabase.instance.client;
    try {
      final moi = await supa.from('animaux_proprietes').select('profile_id_proprio, uid_proprio')
          .eq('animal_id', widget.animalId).isFilter('date_fin', null).limit(1).maybeSingle();
      final animal = await supa.from('animaux').select('espece').eq('id', widget.animalId).maybeSingle();
      if (moi == null) return;
      var q = supa.from('animaux_proprietes').select('animal_id').isFilter('date_fin', null);
      q = moi['profile_id_proprio'] != null
          ? q.eq('profile_id_proprio', moi['profile_id_proprio'])
          : q.eq('uid_proprio', moi['uid_proprio']);
      final liens = await q;
      final ids = {for (final l in liens as List) l['animal_id'].toString()}..remove(widget.animalId);
      if (ids.isEmpty) return;
      var qa = supa.from('animaux').select('id, nom, espece, statut').inFilter('id', ids.toList());
      if (animal?['espece'] != null) qa = qa.eq('espece', animal!['espece']);
      final rows = await qa.order('nom');
      if (mounted) {
        setState(() => _animaux = List<Map<String, dynamic>>.from((rows as List).where((a) =>
            !const ['sorti', 'decede'].contains(a['statut']))));
      }
    } catch (_) {}
  }

  /// Liste déroulante (feuille) avec recherche et cases à cocher — lisible
  /// même avec beaucoup d'animaux.
  Future<void> _ouvrirListe() async {
    final sel = {...widget.options.autresAnimaux};
    var recherche = '';
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final q = recherche.trim().toLowerCase();
        final liste = q.isEmpty ? _animaux
            : _animaux.where((a) => (a['nom']?.toString() ?? '').toLowerCase().contains(q)).toList();
        final tous = liste.isNotEmpty && liste.every((a) => sel.contains(a['id'].toString()));
        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
          builder: (ctx, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(children: [
                const Expanded(child: Text('Appliquer aussi à', style: TextStyle(fontFamily: 'Galey',
                    fontSize: 18, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => Navigator.pop(ctx, sel),
                    child: Text('Valider (${sel.length})', style: const TextStyle(fontFamily: 'Galey',
                        fontSize: 15, fontWeight: FontWeight.w700, color: _green))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                onChanged: (v) => ss(() => recherche = v),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Rechercher un animal', prefixIcon: const Icon(Icons.search),
                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            CheckboxListTile(
              value: tous, activeColor: _green, controlAffinity: ListTileControlAffinity.leading,
              title: Text(q.isEmpty ? 'Tout sélectionner' : 'Sélectionner les résultats',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700)),
              onChanged: (v) => ss(() {
                for (final a in liste) {
                  v == true ? sel.add(a['id'].toString()) : sel.remove(a['id'].toString());
                }
              }),
            ),
            const Divider(height: 1),
            Expanded(child: ListView(controller: sc, children: [
              for (final a in liste)
                CheckboxListTile(
                  value: sel.contains(a['id'].toString()), activeColor: _green,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(a['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
                  onChanged: (v) => ss(() => v == true ? sel.add(a['id'].toString()) : sel.remove(a['id'].toString())),
                ),
              if (liste.isEmpty)
                const Padding(padding: EdgeInsets.all(24),
                    child: Text('Aucun animal trouvé.', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey'))),
            ])),
          ]),
        );
      }),
    );
    if (res != null && mounted) {
      setState(() => widget.options.autresAnimaux..clear()..addAll(res));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_animaux.isEmpty) return const SizedBox.shrink();
    final sel = widget.options.autresAnimaux;
    final noms = [for (final a in _animaux) if (sel.contains(a['id'].toString())) a['nom']?.toString() ?? 'Animal'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Appliquer aussi à', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      InkWell(
        onTap: _ouvrirListe,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            sel.isEmpty ? 'Aucun autre animal' : '${sel.length} ${sel.length > 1 ? 'autres animaux' : 'autre animal'} : ${noms.join(', ')}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: sel.isEmpty ? Colors.grey.shade600 : const Color(0xFF1F2A2E)),
          ),
        ),
      ),
    ]);
  }
}
