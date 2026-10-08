// Salles de la clinique vétérinaire : choix du lieu d'un RDV (à domicile ou
// salle, avec disponibilité sur le créneau) et réservation ponctuelle d'une
// salle (radio, opération…). Données : pm_salles_dispo / occupations_salle
// (migration_salles_occupation_direct.sql). Miroir site :
// website/src/components/rdv/SallesClinique.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal = Color(0xFF0C5C6C);
const _muted = Color(0xFF6F767B);

/// Valeurs du champ Lieu : [kLieuAuto] (salle choisie automatiquement),
/// [kLieuDomicile], sinon id de salle.
const kLieuAuto = 'auto';
const kLieuDomicile = 'domicile';

class SalleDispo {
  final String id, nom, type;
  final bool libre;
  const SalleDispo(this.id, this.nom, this.type, this.libre);
}

Future<List<SalleDispo>> chargerSallesDispo(String profileId, DateTime debut, int dureeMinutes,
    {String? exclureRdv}) async {
  try {
    final rows = await Supabase.instance.client.rpc('pm_salles_dispo', params: {
      'p_pro_profile_id': profileId,
      'p_debut': debut.toUtc().toIso8601String(),
      'p_fin': debut.add(Duration(minutes: dureeMinutes)).toUtc().toIso8601String(),
      'p_exclure_rdv': exclureRdv,
    });
    return [
      for (final r in rows as List)
        SalleDispo(r['id'] as String, (r['nom'] as String?) ?? 'Salle',
            (r['type_salle'] as String?) ?? 'consultation', r['libre'] == true),
    ];
  } catch (_) {
    // pm_salles_dispo indisponible (migration_salles_occupation_direct.sql
    // pas encore passée) : liste des salles sans la disponibilité.
    try {
      final rows = await Supabase.instance.client.from('salles_clinique')
          .select('id, nom, type_salle').eq('clinique_profile_id', profileId).eq('actif', true).order('ordre');
      return [
        for (final r in rows as List)
          SalleDispo(r['id'] as String, (r['nom'] as String?) ?? 'Salle',
              (r['type_salle'] as String?) ?? 'consultation', true),
      ];
    } catch (_) {
      return const [];
    }
  }
}

String libelleTypeSalle(String t) => switch (t) {
  'consultation' => 'Consultation',
  'chirurgie' => 'Chirurgie',
  'imagerie' => 'Imagerie',
  'hospitalisation' => 'Hospitalisation',
  _ => t.isEmpty ? '' : '${t[0].toUpperCase()}${t.substring(1)}',
};

/// Champ « Lieu » : à domicile ou une salle, disponibilité recalculée quand
/// le créneau change. N'affiche rien si la clinique n'a pas de salle.
class LieuSalleField extends StatefulWidget {
  final String profileId;
  final DateTime debut;
  final int dureeMinutes;
  final String? exclureRdv;
  final String value;
  final ValueChanged<String> onChanged;
  const LieuSalleField({super.key, required this.profileId, required this.debut, required this.dureeMinutes,
      this.exclureRdv, required this.value, required this.onChanged});

  @override
  State<LieuSalleField> createState() => _LieuSalleFieldState();
}

class _LieuSalleFieldState extends State<LieuSalleField> {
  List<SalleDispo>? _salles;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(LieuSalleField old) {
    super.didUpdateWidget(old);
    if (old.debut != widget.debut || old.dureeMinutes != widget.dureeMinutes) _charger();
  }

  Future<void> _charger() async {
    final s = await chargerSallesDispo(widget.profileId, widget.debut, widget.dureeMinutes,
        exclureRdv: widget.exclureRdv);
    if (mounted) setState(() => _salles = s);
  }

  @override
  Widget build(BuildContext context) {
    final salles = _salles;
    if (salles == null) return const LinearProgressIndicator(minHeight: 2, color: _teal);
    if (salles.isEmpty) return const SizedBox.shrink();
    final valeur = widget.value == kLieuAuto || widget.value == kLieuDomicile || salles.any((s) => s.id == widget.value)
        ? widget.value : kLieuAuto;
    return DropdownButtonFormField<String>(
      value: valeur,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Lieu', border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem(value: kLieuAuto, child: Text('Automatique (salle du praticien)')),
        const DropdownMenuItem(value: kLieuDomicile, child: Text('🏠 À domicile')),
        for (final s in salles) DropdownMenuItem(
          value: s.id,
          enabled: s.libre || s.id == widget.value,
          child: Text('${s.nom} · ${libelleTypeSalle(s.type)}${s.libre ? '' : ' — occupée'}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: s.libre ? null : Colors.grey)),
        ),
      ],
      onChanged: (v) { if (v != null) widget.onChanged(v); },
    );
  }
}

/// Réservation ponctuelle d'une salle (radio, échographie, opération…).
/// [praticiens] : id '' = titulaire. Renvoie true si la salle a été réservée.
Future<bool> reserverSalleSheet(BuildContext context, {
  required String profileId,
  required List<SalleDispo> salles,
  required List<({String id, String nom})> praticiens,
  String? salleId,
  String? praticienParDefaut,
  DateTime? debutParDefaut,
  String? rdvId,
  String? uid,
}) async {
  if (salles.isEmpty) return false;
  var salle = salleId ?? salles.first.id;
  var praticien = praticienParDefaut ?? (praticiens.isNotEmpty ? praticiens.first.id : '');
  var maintenant = debutParDefaut == null;
  var debut = debutParDefaut ?? DateTime.now();
  var duree = 30;
  var motif = 'Radio / imagerie';
  String? erreur;
  var saving = false;
  const motifs = ['Radio / imagerie', 'Échographie', 'Chirurgie', 'Consultation', 'Soins', 'Autre'];
  const durees = [15, 30, 45, 60, 90, 120, 180];

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
      Widget chip(String label, bool sel, VoidCallback onTap) => ChoiceChip(
        label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: sel ? Colors.white : Colors.black87)),
        selected: sel, selectedColor: _teal, showCheckmark: false, onSelected: (_) => onTap(),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Réserver une salle', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Radio pendant une consultation, opération programmée… La salle est bloquée pour tous.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: salle, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Salle', border: OutlineInputBorder()),
            items: [for (final s in salles) DropdownMenuItem(value: s.id, child: Text('${s.nom} · ${libelleTypeSalle(s.type)}'))],
            onChanged: (v) => setM(() => salle = v ?? salle),
          ),
          const SizedBox(height: 12),
          const Text('Pour', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600, color: _muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in motifs) chip(m, motif == m, () => setM(() => motif = m))]),
          const SizedBox(height: 12),
          Row(children: [
            chip('Maintenant', maintenant, () => setM(() { maintenant = true; debut = DateTime.now(); })),
            const SizedBox(width: 6),
            chip(maintenant ? 'Plus tard…' : '${debut.day.toString().padLeft(2, '0')}/${debut.month.toString().padLeft(2, '0')} '
                '${debut.hour.toString().padLeft(2, '0')}:${debut.minute.toString().padLeft(2, '0')}', !maintenant, () async {
              final d = await showDatePicker(context: ctx, initialDate: debut,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d == null || !ctx.mounted) return;
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(debut));
              if (t == null) return;
              setM(() { maintenant = false; debut = DateTime(d.year, d.month, d.day, t.hour, t.minute); });
            }),
          ]),
          const SizedBox(height: 12),
          const Text('Durée', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600, color: _muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in durees) chip(d < 60 ? '$d min' : d % 60 == 0 ? '${d ~/ 60} h' : '${d ~/ 60}h${d % 60}', duree == d, () => setM(() => duree = d)),
          ]),
          if (praticiens.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: praticiens.any((p) => p.id == praticien) ? praticien : praticiens.first.id, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vétérinaire', border: OutlineInputBorder()),
              items: [for (final p in praticiens) DropdownMenuItem(value: p.id, child: Text(p.nom))],
              onChanged: (v) => setM(() => praticien = v ?? praticien),
            ),
          ],
          if (erreur != null) ...[
            const SizedBox(height: 10),
            Text(erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.red)),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: saving ? null : () async {
              setM(() { saving = true; erreur = null; });
              final d0 = maintenant ? DateTime.now() : debut;
              try {
                await Supabase.instance.client.from('occupations_salle').insert({
                  'clinique_profile_id': profileId,
                  'salle_id': salle,
                  'debut': d0.toUtc().toIso8601String(),
                  'fin': d0.add(Duration(minutes: duree)).toUtc().toIso8601String(),
                  'motif': motif,
                  if (praticien.isNotEmpty) 'praticien_profile_id': praticien,
                  if (rdvId != null) 'rdv_id': rdvId,
                  if (uid != null) 'cree_par_uid': uid,
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on PostgrestException catch (e) {
                setM(() { saving = false; erreur = e.code == 'P0001' ? e.message : 'Réservation impossible (${e.message}).'; });
              } catch (e) {
                setM(() { saving = false; erreur = 'Réservation impossible.'; });
              }
            },
            child: saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Réserver la salle', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ])),
      );
    }),
  );
  return ok == true;
}
