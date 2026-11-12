// Moyens de paiement acceptés par un pro (user_profiles.moyens_paiement),
// cochés dans son profil ; affichés sur sa fiche, à la prise de RDV et dans le
// RDV / séjour du client (avec le RIB si virement — RPC pm_rib_pro, réservée
// aux clients du pro). Miroir site : lib/moyens-paiement.ts + MoyensPaiement.tsx.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kMoyensPaiement = [
  (value: 'especes', label: 'Espèces'),
  (value: 'cheque', label: 'Chèque'),
  (value: 'cb', label: 'Carte bancaire'),
  (value: 'virement', label: 'Virement'),
];

List<String> moyensPaiement(Object? v) => v is List
    ? [for (final x in v) if (kMoyensPaiement.any((m) => m.value == x.toString())) x.toString()]
    : const [];

String libelleMoyens(Object? v) {
  final l = moyensPaiement(v);
  return [for (final m in kMoyensPaiement) if (l.contains(m.value)) m.label].join(', ');
}

/// RDV / séjour du client : moyens du pro, et son RIB s'il accepte le virement.
class MoyensPaiementDuPro extends StatefulWidget {
  final String? proProfileId;
  const MoyensPaiementDuPro({super.key, required this.proProfileId});
  @override
  State<MoyensPaiementDuPro> createState() => _MoyensPaiementDuProState();
}

class _MoyensPaiementDuProState extends State<MoyensPaiementDuPro> {
  String _libelle = '';
  Map<String, dynamic>? _rib;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final id = widget.proProfileId;
    if (id == null || id.isEmpty) return;
    try {
      final supa = Supabase.instance.client;
      final p = await supa.from('user_profiles_complet').select('moyens_paiement').eq('id', id).maybeSingle();
      final moyens = p?['moyens_paiement'];
      Map<String, dynamic>? rib;
      if (moyensPaiement(moyens).contains('virement')) {
        final r = await supa.rpc('pm_rib_pro', params: {'p_pro_profile_id': id});
        final l = r is List ? r : const [];
        if (l.isNotEmpty && (l.first['iban'] ?? '').toString().isNotEmpty) rib = Map<String, dynamic>.from(l.first as Map);
      }
      if (mounted) setState(() { _libelle = libelleMoyens(moyens); _rib = rib; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_libelle.isEmpty) return const SizedBox.shrink();
    const st = TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF4B5563));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Paiement accepté : $_libelle', style: st),
        if (_rib != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF7FAF8), borderRadius: BorderRadius.circular(8)),
            child: SelectableText(
              'RIB pour le virement${(_rib!['titulaire'] ?? '').toString().isNotEmpty ? ' — ${_rib!['titulaire']}' : ''}\n'
              'IBAN ${_rib!['iban']}${(_rib!['bic'] ?? '').toString().isNotEmpty ? '\nBIC ${_rib!['bic']}' : ''}',
              style: st.copyWith(fontSize: 12),
            ),
          ),
      ]),
    );
  }
}
