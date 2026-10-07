import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';

/// Clinique vétérinaire — comptes rendus rédigés par un(e) ASV, en attente
/// de validation (migration_clinique_equipe.sql). Scopé au profil clinique
/// (AgendaContexte.profileId : profil actif du gérant, ou clinique ouverte
/// par un employé vétérinaire). Ouvrir un CR → page CR, bouton « Valider ».
class CrAValiderPage extends StatefulWidget {
  const CrAValiderPage({super.key});

  @override
  State<CrAValiderPage> createState() => _CrAValiderPageState();
}

class _CrAValiderPageState extends State<CrAValiderPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _crs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = AgendaContexte.profileId;
      if (pid.isEmpty) {
        setState(() { _crs = []; _loading = false; });
        return;
      }
      final rows = List<Map<String, dynamic>>.from(await _supa.from('comptes_rendus')
          .select('id, animal_id, owner_uid, rdv_id, contenu, created_at, redige_par_profile_id')
          .eq('pro_profile_id', pid).eq('statut', 'brouillon')
          .order('created_at', ascending: false) as List);
      // Noms : animaux + rédacteurs.
      final animalIds = rows.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();
      final auteurIds = rows.map((r) => r['redige_par_profile_id']?.toString()).whereType<String>().toSet().toList();
      final animaux = <String, String>{};
      final auteurs = <String, String>{};
      if (animalIds.isNotEmpty) {
        for (final a in await _supa.from('animaux').select('id, nom').inFilter('id', animalIds) as List) {
          animaux[a['id'].toString()] = (a['nom'] as String?) ?? '';
        }
      }
      if (auteurIds.isNotEmpty) {
        for (final p in await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom').inFilter('id', auteurIds) as List) {
          final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          auteurs[p['id'].toString()] = n.isNotEmpty ? n : ((p['nom'] as String?) ?? '');
        }
      }
      for (final r in rows) {
        r['_animal'] = animaux[r['animal_id']?.toString()] ?? 'Animal';
        r['_auteur'] = auteurs[r['redige_par_profile_id']?.toString()] ?? '';
      }
      if (mounted) setState(() { _crs = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Comptes rendus à valider',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _crs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.task_alt, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun compte rendu en attente',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey.shade500)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _crs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final cr = _crs[i];
                      final date = DateTime.tryParse(cr['created_at']?.toString() ?? '')?.toLocal();
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => CompteRenduPage(
                              animalId: cr['animal_id']?.toString(),
                              ownerUid: cr['owner_uid']?.toString(),
                              clientName: cr['_animal'] as String,
                              categoryColor: _teal,
                            ),
                          ));
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const Icon(Icons.pets, size: 16, color: _teal),
                              const SizedBox(width: 6),
                              Expanded(child: Text(cr['_animal'] as String,
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                              if (date != null)
                                Text('${date.day}/${date.month}/${date.year}',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                            ]),
                            if ((cr['_auteur'] as String).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Rédigé par ${cr['_auteur']}',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                            ],
                            const SizedBox(height: 6),
                            Text(cr['contenu']?.toString() ?? '', maxLines: 3, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
