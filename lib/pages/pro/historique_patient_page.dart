// Historique d'un patient, vue réservée au vétérinaire : tableau des
// consultations de la clinique (comptes rendus structurés —
// migration_cr_structure.sql) : date · motif · poids · actes · prescription ;
// le CR complet au toucher. Ouvert depuis « Mes patients » et les cartes RDV
// de l'agenda. Miroir site : website/src/components/pro/HistoriquePatient.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/widgets/vet/consultation_widgets.dart';

const _teal = Color(0xFF0C5C6C);

class HistoriquePatientPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  const HistoriquePatientPage({super.key, required this.animalId, required this.animalNom});

  @override
  State<HistoriquePatientPage> createState() => _HistoriquePatientPageState();
}

class _HistoriquePatientPageState extends State<HistoriquePatientPage> {
  List<Map<String, dynamic>> _crs = [];
  Map<String, String> _noms = {};
  bool _loading = true;

  String get _pid {
    final p = AgendaContexte.profileId;
    if (p.isNotEmpty) return p;
    for (final x in User_Info.availableProfiles) {
      if (x['is_main'] == true) return x['id']?.toString() ?? '';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final rows = await Supabase.instance.client.from('comptes_rendus').select()
          .eq('animal_id', widget.animalId).eq('pro_profile_id', _pid)
          .order('created_at', ascending: false);
      final crs = List<Map<String, dynamic>>.from(rows as List);
      final cites = intervenantsCites(crs, const []);
      final noms = await chargerNomsIntervenants(profils: cites.profils, uids: cites.uids);
      if (mounted) setState(() { _crs = crs; _noms = noms; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String? _nom(dynamic profil, dynamic uid) => _noms[profil?.toString() ?? ''] ?? _noms[uid?.toString() ?? ''];

  /// Traçabilité : validateur + date de validation (horodatées côté serveur).
  String _valide(Map<String, dynamic> cr) {
    if (cr['statut'] == 'brouillon') return 'À valider';
    final qui = _nom(cr['valide_par_profile_id'], cr['valide_par_uid']);
    final le = DateTime.tryParse(cr['valide_le']?.toString() ?? '')?.toLocal();
    final t = [if (qui != null) qui, if (le != null) 'le ${fmtJourHeure(le)}'].join(' ');
    return t.isEmpty ? 'Oui' : t;
  }

  void _ouvrir(Map<String, dynamic> cr) => showModalBottomSheet(
    context: context, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false, initialChildSize: 0.6, maxChildSize: 0.92,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
        Text('Consultation du ${_date(cr['created_at']?.toString())}',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text((cr['contenu'] ?? '').toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.45)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const entete = TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _teal);
    const cellule = TextStyle(fontFamily: 'Galey', fontSize: 13);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: Text('Historique — ${widget.animalNom}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _crs.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24),
                  child: Text('Aucune consultation enregistrée pour ce patient.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey))))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE4E7E2))),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        headingRowHeight: 40,
                        dataRowMinHeight: 44, dataRowMaxHeight: 88,
                        columnSpacing: 18,
                        columns: const [
                          DataColumn(label: Text('Date', style: entete)),
                          DataColumn(label: Text('Motif', style: entete)),
                          DataColumn(label: Text('Poids', style: entete), numeric: true),
                          DataColumn(label: Text('Actes réalisés', style: entete)),
                          DataColumn(label: Text('Prescription', style: entete)),
                          DataColumn(label: Text('Rédigé par', style: entete)),
                          DataColumn(label: Text('Validé', style: entete)),
                        ],
                        rows: [
                          for (final cr in _crs) DataRow(
                            onSelectChanged: (_) => _ouvrir(cr),
                            cells: [
                              DataCell(Text(_date(cr['created_at']?.toString()), style: cellule.copyWith(fontWeight: FontWeight.w700))),
                              DataCell(SizedBox(width: 140, child: Text((cr['motif'] ?? '—').toString(), style: cellule, maxLines: 3))),
                              DataCell(Text(cr['poids'] != null ? '${cr['poids']} kg' : '—', style: cellule)),
                              DataCell(SizedBox(width: 200, child: Text(
                                  ((cr['actes'] as List?)?.join(', ') ?? '').isEmpty ? '—' : (cr['actes'] as List).join(', '),
                                  style: cellule, maxLines: 4))),
                              DataCell(SizedBox(width: 240, child: Text(
                                  (cr['prescription'] ?? '').toString().isEmpty ? '—' : cr['prescription'].toString(),
                                  style: cellule, maxLines: 4))),
                              DataCell(Text(_nom(cr['redige_par_profile_id'], cr['redige_par_uid']) ?? '—', style: cellule)),
                              DataCell(SizedBox(width: 150, child: Text(_valide(cr), style: cellule, maxLines: 3))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
