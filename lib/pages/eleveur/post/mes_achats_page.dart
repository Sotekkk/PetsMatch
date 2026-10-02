import 'package:PetsMatch/main.dart' show User_Info;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';

// « Achats & crédits » — tout ce qui a été payé, accessible depuis
// Administratif (tous les profils pro) et depuis Mes annonces. Miroir de
// website/src/app/mes-achats/page.tsx.
//  • Boosts / options d'annonces : achats_ponctuels, scopés au profil de
//    l'annonce boostée (un compte élevage + association ne mélange pas).
//  • Crédits Pets Social : porte-monnaie global du compte (credit_wallets),
//    achats de packs = credit_transactions positives.
//  • Abonnement : renvoi vers la page d'abonnement du profil ([abonnement]).
class MesAchatsPage extends StatefulWidget {
  /// Page « Mon abonnement » du profil courant (null : pas d'abonnement,
  /// ex. association).
  final Widget? abonnement;
  const MesAchatsPage({super.key, this.abonnement});
  @override
  State<MesAchatsPage> createState() => _MesAchatsPageState();
}

class _MesAchatsPageState extends State<MesAchatsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _ink = Color(0xFF1F2A2E);

  List<Map<String, dynamic>> _achats = [];
  List<Map<String, dynamic>> _packsAchetes = [];
  int _solde = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final supa = Supabase.instance.client;
    try {
      final res = await Future.wait<dynamic>([
        supa.from('achats_ponctuels')
            .select('id, annonce_id, statut, date_achat, date_expiration, produits_ponctuels(label, prix, description)')
            .eq('uid', uid)
            .order('date_achat', ascending: false),
        supa.from('credit_wallets').select('solde').eq('uid', uid).maybeSingle(),
        supa.from('credit_transactions').select('motif, montant, created_at')
            .eq('uid', uid).gt('montant', 0)
            .order('created_at', ascending: false).limit(50),
      ]);
      // Multi-profil : un boost appartient au profil de l'annonce boostée —
      // ne pas montrer les achats de l'élevage côté association (et inverse).
      final achats = List<Map<String, dynamic>>.from(res[0] as List);
      final annonceIds = achats.map((a) => a['annonce_id']).whereType<Object>().map((e) => e.toString()).toSet().toList();
      final profilParAnnonce = <String, String?>{};
      if (annonceIds.isNotEmpty) {
        final ann = await supa.from('annonces').select('id, profile_id').inFilter('id', annonceIds);
        for (final r in ann as List) {
          profilParAnnonce[r['id'].toString()] = r['profile_id']?.toString();
        }
      }
      final actif = User_Info.activeProfileId;
      achats.removeWhere((a) {
        final pid = profilParAnnonce[a['annonce_id']?.toString()];
        return actif.isNotEmpty && pid != null && pid != actif;
      });
      final wallet = res[1] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _achats = achats;
          _solde = (wallet?['solde'] as num?)?.toInt() ?? 0;
          _packsAchetes = List<Map<String, dynamic>>.from(res[2] as List);
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

  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      );

  Widget _titre(String t, {String? sous}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)),
          if (sous != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sous, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            ),
        ]),
      );

  Widget _vide(String t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card,
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
      );

  Widget _achatBoost(Map<String, dynamic> a) {
    final produit = a['produits_ponctuels'] as Map<String, dynamic>?;
    final label = produit?['label']?.toString() ?? 'Achat';
    final prix = (produit?['prix'] as num?)?.toDouble();
    final statut = a['statut']?.toString() ?? '';
    final meta = _statutMeta[statut] ?? (label: statut, color: Colors.grey);
    final dateAchat = DateTime.tryParse(a['date_achat']?.toString() ?? '');
    final annonceId = a['annonce_id']?.toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(label,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: meta.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(meta.label,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: meta.color)),
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
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _teal)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Achats & crédits',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              color: _teal,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                children: [
                  if (widget.abonnement != null) ...[
                    _titre('Abonnement'),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: const Icon(Icons.workspace_premium_outlined, color: _teal),
                        title: const Text('Mon abonnement',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _ink)),
                        subtitle: const Text('Formule, échéances et factures d\'abonnement',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: _teal),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.abonnement!)),
                      ),
                    ),
                  ],
                  _titre('Boosts et options d\'annonces', sous: 'Achats liés aux annonces de ce profil'),
                  if (_achats.isEmpty) _vide('Aucun achat pour le moment.')
                  else
                    for (final a in _achats) ...[_achatBoost(a), const SizedBox(height: 10)],
                  _titre('Crédits Pets Social', sous: 'Partagés entre tous les profils de votre compte'),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _card,
                    child: Row(children: [
                      const Icon(Icons.toll_outlined, color: _green),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Solde actuel',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: _ink))),
                      Text('$_solde crédit${_solde > 1 ? 's' : ''}',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _green)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  if (_packsAchetes.isEmpty) _vide('Aucun achat de crédits.')
                  else
                    for (final t in _packsAchetes) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: _card,
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t['motif']?.toString() ?? 'Achat de crédits',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _ink)),
                            const SizedBox(height: 4),
                            Text(DateTime.tryParse(t['created_at']?.toString() ?? '') != null
                                    ? DateFormat('dd/MM/yyyy').format(DateTime.parse(t['created_at'].toString()).toLocal())
                                    : '',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
                          ])),
                          Text('+${t['montant']}',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _green)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}
