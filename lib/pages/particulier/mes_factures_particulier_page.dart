import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FactureDetailPage;

/// « Mes Factures » côté particulier — factures REÇUES d'un pro (garde,
/// toilettage, véto, éducateur…), à ne pas confondre avec `FacturationPage`
/// (factures ÉMISES, filtrées par uid_eleveur/profile_id). Ici on filtre par
/// client_uid/client_profile_id — colonnes déjà renseignées à la création
/// (facturation.dart _save()).
class MesFacturesParticulierPage extends StatefulWidget {
  const MesFacturesParticulierPage({super.key});

  @override
  State<MesFacturesParticulierPage> createState() => _MesFacturesParticulierPageState();
}

class _MesFacturesParticulierPageState extends State<MesFacturesParticulierPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);
  static const _dark = Color(0xFF1F2A2E);

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // YYYY-MM-DD → DD/MM/YYYY
  static String _isoToFr(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length < 10) return s;
    final p = s.substring(0, 10).split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : s;
  }

  // Même correspondance snake_case → camelCase que facturation.dart _supaToUi
  // — FactureDetailPage attend ce format, dupliqué ici (symboles privés à
  // facturation.dart, non réutilisables depuis un autre fichier).
  static Map<String, dynamic> _toUi(Map<String, dynamic> r) => {
    'id':                 r['id'],
    'numeroFacture':      r['numero_facture'],
    'numeroAffichage':    r['numero_affichage'],
    'typeFacture':        r['type_facture'],
    'pdfUrl':             r['pdf_url'],
    'dateFacture':        _isoToFr(r['date_facture']),
    'datePrestation':     _isoToFr(r['date_prestation']),
    'dateEcheance':       _isoToFr(r['date_echeance']),
    'lignes':             r['lignes'] ?? [],
    'totalHT':            r['total_ht'],
    'totalTVA':           r['total_tva'],
    'totalTTC':           r['total_ttc'],
    'regimeTVA':          r['regime_tva'],
    'nomClient':          r['nom_client'],
    'prenomClient':       r['prenom_client'],
    'emailClient':        r['email_client'],
    'telephoneClient':    r['telephone_client'],
    'rueClient':          r['rue_client'],
    'cpClient':           r['cp_client'],
    'villeClient':        r['ville_client'],
    'paysClient':         r['pays_client'],
    'siretClient':        r['siret_client'],
    'tvaClient':          r['tva_client'],
    'nomEmetteur':        r['nom_emetteur'],
    'rueEmetteur':        r['rue_emetteur'],
    'cpEmetteur':         r['cp_emetteur'],
    'villeEmetteur':      r['ville_emetteur'],
    'paysEmetteur':       r['pays_emetteur'],
    'telEmetteur':        r['tel_emetteur'],
    'siretEmetteur':      r['siret_emetteur'],
    'tvaEmetteur':        r['tva_emetteur'],
    'formeJuridiqueEmetteur': r['forme_juridique_emetteur'],
    'capitalEmetteur':    r['capital_emetteur'],
    'rcsEmetteur':        r['rcs_emetteur'],
    'rmEmetteur':         r['rm_emetteur'],
    'emailEmetteur':      r['email_emetteur'],
    'modePaiement':       r['mode_paiement'],
    'delaiPaiement':      r['delai_paiement'],
    'conditionsEscompte': r['conditions_escompte'],
    'noteComplementaire': r['note_complementaire'],
    'statut':             r['statut'],
  };

  static String numAff(Map<String, dynamic> d) {
    final a = d['numeroAffichage']?.toString() ?? '';
    if (a.trim().isNotEmpty) return a;
    final n = d['numeroFacture'];
    return n == null ? '—' : n.toString();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final supa = Supabase.instance.client;
    final activePid = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;

    final rows = activePid != null
        ? await supa.from('factures').select()
            .eq('client_profile_id', activePid).order('created_at', ascending: false)
        : await supa.from('factures').select()
            .eq('client_uid', uid).order('created_at', ascending: false);
    return (rows as List).map((r) => _toUi(Map<String, dynamic>.from(r))).toList();
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes Factures',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }
          final docs = snap.data ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('Aucune facture reçue', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 16)),
              ]),
            );
          }
          return RefreshIndicator(
            color: _green,
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = docs[i];
                final statut = d['statut'] ?? 'emise';
                final statutColor = statut == 'payee' ? _green : statut == 'annulee' ? Colors.red : const Color(0xFFE9A825);
                final statutLabel = statut == 'payee' ? 'Payée' : statut == 'annulee' ? 'Annulée' : 'Émise';
                final total = (d['totalTTC'] ?? 0.0).toStringAsFixed(2);
                return GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => FactureDetailPage(data: d, docId: d['id'].toString()),
                    ));
                    _refresh();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.receipt_outlined, color: _green, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Facture n° ${numAff(d)}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
                        const SizedBox(height: 2),
                        Text(d['nomEmetteur'] ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                        Text(d['dateFacture'] ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$total €', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: statutColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(statutLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: statutColor, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
