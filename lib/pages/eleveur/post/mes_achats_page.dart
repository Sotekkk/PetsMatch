import 'package:PetsMatch/main.dart' show User_Info;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';

// Historique des achats ponctuels (boosts, annonce supplémentaire…) —
// miroir de website/src/app/mes-achats/page.tsx, même table achats_ponctuels
// jointe à produits_ponctuels (label/prix).
class MesAchatsPage extends StatefulWidget {
  const MesAchatsPage({super.key});
  @override
  State<MesAchatsPage> createState() => _MesAchatsPageState();
}

class _MesAchatsPageState extends State<MesAchatsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _achats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final rows = await Supabase.instance.client
          .from('achats_ponctuels')
          .select('id, annonce_id, statut, date_achat, date_expiration, produits_ponctuels(label, prix, description)')
          .eq('uid', uid)
          .order('date_achat', ascending: false);
      // Multi-profil : un boost appartient au profil de l'annonce boostée —
      // ne pas montrer les achats de l'élevage côté association (et inverse).
      final achats = List<Map<String, dynamic>>.from(rows as List);
      final annonceIds = achats.map((a) => a['annonce_id']).whereType<Object>().map((e) => e.toString()).toSet().toList();
      final profilParAnnonce = <String, String?>{};
      if (annonceIds.isNotEmpty) {
        final ann = await Supabase.instance.client.from('annonces')
            .select('id, profile_id').inFilter('id', annonceIds);
        for (final r in ann as List) {
          profilParAnnonce[r['id'].toString()] = r['profile_id']?.toString();
        }
      }
      final actif = User_Info.activeProfileId;
      achats.removeWhere((a) {
        final pid = profilParAnnonce[a['annonce_id']?.toString()];
        return actif.isNotEmpty && pid != null && pid != actif;
      });
      if (mounted) {
        setState(() {
          _achats = achats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const Map<String, ({String label, Color color})> _statutMeta = {
    'paye':       (label: 'Payé', color: _green),
    'rembourse':  (label: 'Remboursé', color: Colors.redAccent),
    'en_attente': (label: 'En attente', color: Colors.orange),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes achats',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _achats.isEmpty
              ? Center(
                  child: Text('Aucun achat pour le moment.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _achats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final a = _achats[i];
                    final produit = a['produits_ponctuels'] as Map<String, dynamic>?;
                    final label = produit?['label']?.toString() ?? 'Achat';
                    final prix = (produit?['prix'] as num?)?.toDouble();
                    final statut = a['statut']?.toString() ?? '';
                    final meta = _statutMeta[statut] ?? (label: statut, color: Colors.grey);
                    final dateAchat = DateTime.tryParse(a['date_achat']?.toString() ?? '');
                    final annonceId = a['annonce_id']?.toString();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(
                                child: Text(label,
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                        fontSize: 14, color: Color(0xFF1F2A2E)),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: meta.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: Text(meta.label,
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                        fontWeight: FontWeight.w600, color: meta.color)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text(dateAchat != null ? DateFormat('dd/MM/yyyy').format(dateAchat.toLocal()) : '',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
                            if (annonceId != null) ...[
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => AnnonceDetailPage(annonceId: annonceId))),
                                child: const Text('Voir l\'annonce concernée →',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
                              ),
                            ],
                          ]),
                        ),
                        if (prix != null)
                          Text('${prix.toStringAsFixed(2)} €',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                  fontSize: 14, color: _teal)),
                      ]),
                    );
                  },
                ),
    );
  }
}
