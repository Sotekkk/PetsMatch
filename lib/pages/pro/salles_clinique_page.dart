import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';

/// Types de salle et motifs de RDV vétérinaire — partagés avec la prise de
/// RDV (rdv_booking_page.dart) et le contrôle en base (pm_rdv_controle_clinique,
/// migration_clinique_rdv.sql). Miroir site : website/src/lib/salles-clinique.ts.
const kTypesSalle = <(String, String)>[
  ('consultation', 'Consultation'),
  ('chirurgie', 'Bloc opératoire'),
  ('imagerie', 'Imagerie / radiologie'),
  ('soins', 'Soins / hospitalisation'),
];
const kMotifsVeto = <(String, String)>[
  ('consultation', 'Consultation'),
  ('vaccination', 'Vaccination'),
  ('bilan', 'Bilan annuel'),
  ('urgence', 'Urgence'),
  ('chirurgie', 'Chirurgie'),
  ('autre', 'Autre'),
];
String libelleTypeSalle(String t) =>
    kTypesSalle.firstWhere((x) => x.$1 == t, orElse: () => (t, t)).$2;

/// Clinique : salles (typées) et type de salle occupé par chaque motif.
/// Sans salle déclarée, la prise de RDV ne tient compte que des praticiens.
class SallesCliniquePage extends StatefulWidget {
  const SallesCliniquePage({super.key});

  @override
  State<SallesCliniquePage> createState() => _SallesCliniquePageState();
}

class _SallesCliniquePageState extends State<SallesCliniquePage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _salles = [];
  Map<String, String> _parMotif = {};
  /// Les clients peuvent choisir leur vétérinaire à la réservation.
  bool _choixPraticien = true;
  bool _loading = true;

  String get _pid => AgendaContexte.profileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final s = await _supa.from('salles_clinique').select()
          .eq('clinique_profile_id', _pid).order('ordre').order('created_at');
      final p = await _supa.from('user_profiles_complet').select('salles_par_motif, rdv_choix_praticien').eq('id', _pid).maybeSingle();
      _choixPraticien = p?['rdv_choix_praticien'] as bool? ?? true;
      final m = <String, String>{};
      if (p?['salles_par_motif'] is Map) {
        (p!['salles_par_motif'] as Map).forEach((k, v) => m[k.toString()] = v.toString());
      }
      if (mounted) setState(() { _salles = List<Map<String, dynamic>>.from(s as List); _parMotif = m; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _err(e); }
    }
  }

  void _err(Object e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Erreur : $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  Future<void> _editerSalle([Map<String, dynamic>? salle]) async {
    final nomCtrl = TextEditingController(text: salle?['nom'] as String? ?? '');
    var type = salle?['type_salle'] as String? ?? 'consultation';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(salle == null ? 'Nouvelle salle' : 'Modifier la salle',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nomCtrl, autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom (ex. Consultation 1, Bloc)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: [for (final t in kTypesSalle) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setD(() => type = v ?? type),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    ));
    if (ok != true || nomCtrl.text.trim().isEmpty) return;
    try {
      if (salle == null) {
        await _supa.from('salles_clinique').insert({
          'clinique_profile_id': _pid, 'nom': nomCtrl.text.trim(), 'type_salle': type,
          'ordre': _salles.length,
        });
      } else {
        await _supa.from('salles_clinique').update({'nom': nomCtrl.text.trim(), 'type_salle': type})
            .eq('id', salle['id']);
      }
      _load();
    } catch (e) { _err(e); }
  }

  Future<void> _basculer(Map<String, dynamic> salle) async {
    try {
      await _supa.from('salles_clinique').update({'actif': !(salle['actif'] as bool? ?? true)}).eq('id', salle['id']);
      _load();
    } catch (e) { _err(e); }
  }

  Future<void> _supprimer(Map<String, dynamic> salle) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Supprimer la salle ?'),
      content: Text('« ${salle['nom']} » sera retirée. Les RDV déjà attribués à cette salle la perdent.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    try {
      await _supa.from('salles_clinique').delete().eq('id', salle['id']);
      _load();
    } catch (e) { _err(e); }
  }

  Future<void> _majMotif(String motif, String type) async {
    final m = {..._parMotif, motif: type};
    setState(() => _parMotif = m);
    try {
      await _supa.from('user_profiles').update({'salles_par_motif': m}).eq('id', _pid);
    } catch (e) { _err(e); }
  }

  @override
  Widget build(BuildContext context) {
    final typesPresents = {for (final s in _salles) if (s['actif'] != false) s['type_salle'] as String};
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: const Text('Salles & motifs', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () => _editerSalle(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Ajouter une salle', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
              Text('Un RDV en ligne n\'est proposé que si un vétérinaire ET une salle du bon type sont libres. '
                  'Sans salle déclarée, seuls les vétérinaires comptent.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Les clients peuvent choisir leur vétérinaire',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(_choixPraticien
                      ? '« Peu importe » ou un vétérinaire précis, au choix du client.'
                      : 'Le premier vétérinaire libre est attribué automatiquement.',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  value: _choixPraticien,
                  onChanged: (v) async {
                    setState(() => _choixPraticien = v);
                    try {
                      await _supa.from('user_profiles').update({'rdv_choix_praticien': v}).eq('id', _pid);
                    } catch (e) { _err(e); }
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text('Salles', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              if (_salles.isEmpty)
                Text('Aucune salle déclarée.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
              for (final s in _salles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.meeting_room_outlined,
                        color: s['actif'] == false ? Colors.grey : _teal),
                    title: Text(s['nom'] as String? ?? '', style: TextStyle(fontFamily: 'Galey',
                        decoration: s['actif'] == false ? TextDecoration.lineThrough : null)),
                    subtitle: Text(libelleTypeSalle(s['type_salle'] as String? ?? 'consultation')
                        + (s['actif'] == false ? ' · désactivée' : '')),
                    onTap: () => _editerSalle(s),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'actif' ? _basculer(s) : _supprimer(s),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'actif', child: Text(s['actif'] == false ? 'Réactiver' : 'Désactiver')),
                        const PopupMenuItem(value: 'suppr', child: Text('Supprimer')),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text('Salle occupée par motif', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Les visites à domicile n\'occupent aucune salle.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              for (final m in kMotifsVeto)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: Text(m.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600))),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        initialValue: _parMotif[m.$1] ?? 'consultation',
                        isDense: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: [
                          for (final t in kTypesSalle)
                            DropdownMenuItem(value: t.$1, child: Text(
                              t.$2 + (_salles.isNotEmpty && !typesPresents.contains(t.$1) ? ' ⚠' : ''),
                              overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) { if (v != null) _majMotif(m.$1, v); },
                      ),
                    ),
                  ]),
                ),
              if (_salles.isNotEmpty && kMotifsVeto.any((m) => !typesPresents.contains(_parMotif[m.$1] ?? 'consultation')))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('⚠ Aucune salle active de ce type : ces RDV ne pourront pas être pris en ligne.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade800)),
                ),
            ]),
    );
  }
}
