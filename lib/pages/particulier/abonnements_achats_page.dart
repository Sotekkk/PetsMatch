import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

class AchatPonctuel {
  final String id;
  final DateTime date;
  final String nom;
  final String type;
  final double montant;
  final String statut;
  final String? factureUrl;
  const AchatPonctuel({
    required this.id, required this.date, required this.nom, required this.type,
    required this.montant, required this.statut, this.factureUrl,
  });
}

class MouvementCredit {
  final DateTime date;
  final String motif;
  final int montant;
  const MouvementCredit({required this.date, required this.motif, required this.montant});
}

class LigneFacturation {
  final DateTime date;
  final String type;
  final String libelle;
  final double montant;
  final String? factureUrl;
  const LigneFacturation({
    required this.date, required this.type, required this.libelle,
    required this.montant, this.factureUrl,
  });
}

const _typeLabels = {
  'boost': 'Boost', 'personnalisation': 'Personnalisation',
  'pass': 'Pass', 'cadeau_virtuel': 'Cadeau virtuel',
  'abonnement': 'Abonnement', 'renouvellement': 'Renouvellement',
  'achat': 'Achat', 'pack_credits': 'Pack de crédits', 'remboursement': 'Remboursement',
};
const _statutLabels = {
  'paye': 'Payé', 'en_attente': 'En attente', 'rembourse': 'Remboursé', 'echoue': 'Échoué',
};
const _statutColors = {
  'paye': _green, 'en_attente': Color(0xFFE0A030),
  'rembourse': Color(0xFF6F767B), 'echoue': Color(0xFFE05C5C),
};

class AbonnementsAchatsPage extends StatefulWidget {
  const AbonnementsAchatsPage({super.key});

  @override
  State<AbonnementsAchatsPage> createState() => _AbonnementsAchatsPageState();
}

class _AbonnementsAchatsPageState extends State<AbonnementsAchatsPage> {
  final _supa = Supabase.instance.client;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  final List<AchatPonctuel> _achats = const [];
  List<MouvementCredit> _mouvementsCredits = const [];
  final List<LigneFacturation> _facturation = const [];
  int _soldeCredits = 0;
  int _creditsAchetes = 0;
  int _creditsUtilises = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _packs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _supa.from('credit_wallets').select().eq('uid', uid).maybeSingle(),
        _supa.from('credit_transactions').select().eq('uid', uid)
            .order('created_at', ascending: false).limit(50),
        _supa.from('credit_packs').select().eq('actif', true).order('ordre'),
      ]);

      final wallet = results[0] as Map<String, dynamic>?;
      final transactions = results[1] as List;
      final packs = results[2] as List;

      final mouvements = transactions.map((t) => MouvementCredit(
        date: DateTime.parse(t['created_at'] as String),
        motif: t['motif'] as String,
        montant: t['montant'] as int,
      )).toList();

      if (mounted) {
        setState(() {
          _soldeCredits    = wallet?['solde']         as int? ?? 0;
          _creditsAchetes  = wallet?['total_achete']  as int? ?? 0;
          _creditsUtilises = wallet?['total_utilise'] as int? ?? 0;
          _mouvementsCredits = mouvements;
          _packs = packs.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPacksSheet() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreditPacksSheet(
        packs: _packs,
        myUid: uid,
        onSuccess: _load,
      ),
    );
  }

  void _bientotDisponible(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: _dark,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Abonnements & achats',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              color: _teal,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                children: [
                  const _SectionTitle('Mon abonnement'),
                  const SizedBox(height: 10),
                  _buildAbonnementCard(),
                  const SizedBox(height: 28),

                  const _SectionTitle('Mes achats'),
                  const SizedBox(height: 10),
                  _buildAchatsSection(),
                  const SizedBox(height: 28),

                  const _SectionTitle('Mes crédits'),
                  const SizedBox(height: 10),
                  _buildCreditsSection(),
                  const SizedBox(height: 28),

                  const _SectionTitle('Facturation'),
                  const SizedBox(height: 10),
                  _buildFacturationSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildAbonnementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_teal, Color(0xFF5F9EAA)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🆓 Formule Découverte',
            style: TextStyle(color: Colors.white, fontFamily: 'Galey',
                fontWeight: FontWeight.w700, fontSize: 19)),
        const SizedBox(height: 4),
        const Text('Le profil particulier est gratuit — aucune facturation associée.',
            style: TextStyle(color: Colors.white70, fontFamily: 'Galey', fontSize: 13)),
        const SizedBox(height: 16),
        _abonnementInfoRow('Statut', 'Actif'),
        _abonnementInfoRow('Prix', '0 €'),
        _abonnementInfoRow('Périodicité', '—'),
        _abonnementInfoRow('Prochaine facturation', '—'),
        _abonnementInfoRow('Moyen de paiement', '—'),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => _bientotDisponible(
              'Les formules payantes pour les particuliers arrivent bientôt.'),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.info_outline, size: 16, color: Colors.white),
          label: const Text('En savoir plus sur les formules à venir',
              style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _abonnementInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 150, child: Text(label,
          style: const TextStyle(color: Colors.white60, fontFamily: 'Galey', fontSize: 12))),
      Text(value, style: const TextStyle(color: Colors.white, fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildAchatsSection() {
    if (_achats.isEmpty) {
      return const _EmptyCard(
        icon: Icons.shopping_bag_outlined,
        title: 'Aucun achat pour le moment',
        subtitle: 'Vos boosts, pass et autres achats ponctuels\napparaîtront ici.',
      );
    }
    return Column(children: _achats.map((a) => _AchatRow(achat: a)).toList());
  }

  Widget _buildCreditsSection() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Expanded(child: _creditStat('Solde actuel', _soldeCredits)),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          Expanded(child: _creditStat('Achetés', _creditsAchetes)),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          Expanded(child: _creditStat('Utilisés', _creditsUtilises)),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openPacksSheet,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Acheter des crédits',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
      const SizedBox(height: 14),
      if (_mouvementsCredits.isEmpty)
        const _EmptyCard(
          icon: Icons.history,
          title: 'Aucun mouvement de crédits',
          subtitle: 'L\'historique de vos crédits achetés et\nutilisés apparaîtra ici.',
        )
      else
        Column(children: _mouvementsCredits.map((m) => _CreditRow(mouvement: m)).toList()),
    ]);
  }

  Widget _creditStat(String label, int value) => Column(children: [
    Text('$value', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: _dark)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
  ]);

  Widget _buildFacturationSection() {
    if (_facturation.isEmpty) {
      return const _EmptyCard(
        icon: Icons.receipt_long_outlined,
        title: 'Aucune facture pour le moment',
        subtitle: 'Paiements d\'abonnement, achats ponctuels,\npacks de crédits et remboursements\napparaîtront ici au même endroit.',
      );
    }
    return Column(children: _facturation.map((f) => _FactureRow(ligne: f)).toList());
  }
}

// ── Sheet packs de crédits ────────────────────────────────────────────────────

class CreditPacksSheet extends StatefulWidget {
  final List<Map<String, dynamic>> packs;
  final String myUid;
  final VoidCallback onSuccess;
  const CreditPacksSheet({required this.packs, required this.myUid, required this.onSuccess});
  @override
  State<CreditPacksSheet> createState() => CreditPacksSheetState();
}

class CreditPacksSheetState extends State<CreditPacksSheet> {
  String? _loadingPackId;

  Future<void> _pay(Map<String, dynamic> pack) async {
    final packId = pack['id'] as String;
    setState(() => _loadingPackId = packId);
    try {
      // 1. Créer le PaymentIntent via Firebase Function
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('createCreditPaymentIntent');
      final result = await fn.call({
        'packId': packId,
        'uid': widget.myUid,
        'credits': pack['credits'],
        'prixEuros': pack['prix_euros'].toString(),
        'nom': pack['nom'],
      });
      final clientSecret = result.data['clientSecret'] as String;

      // 2. Initialiser le Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'PetsMatch',
          style: ThemeMode.dark,
        ),
      );

      // 3. Présenter le Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. Paiement réussi — créditer le wallet côté Flutter (immédiat)
      final supa = Supabase.instance.client;
      final credits = pack['credits'] as int;
      final walletRow = await supa.from('credit_wallets').select().eq('uid', widget.myUid).maybeSingle();
      final soldeActuel = (walletRow?['solde'] as int?) ?? 0;
      final totalActuel = (walletRow?['total_achete'] as int?) ?? 0;
      await Future.wait([
        supa.from('credit_wallets').upsert({
          'uid': widget.myUid,
          'solde': soldeActuel + credits,
          'total_achete': totalActuel + credits,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'uid'),
        supa.from('credit_transactions').insert({
          'uid': widget.myUid,
          'montant': credits,
          'motif': 'Achat pack ${pack['nom']}',
          'ref_id': packId,
        }),
      ]);

      if (mounted) Navigator.pop(context);
      widget.onSuccess();
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        // Annulé par l'utilisateur — silencieux
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Paiement échoué : ${e.error.localizedMessage}',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingPackId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 18),
          const Text('Acheter des crédits',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 19, color: _dark)),
          const SizedBox(height: 4),
          Text('Boostez vos posts et personnalisez votre profil.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 20),
          if (widget.packs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('Aucun pack disponible pour le moment.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))),
            )
          else
            ...widget.packs.map((p) => _PackCard(
              pack: p,
              loading: _loadingPackId == p['id'],
              onTap: _loadingPackId == null ? () => _pay(p) : null,
            )),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_outline, size: 13, color: _teal),
            const SizedBox(width: 6),
            Text('Paiement sécurisé · Stripe',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  final Map<String, dynamic> pack;
  final bool loading;
  final VoidCallback? onTap;
  const _PackCard({required this.pack, this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tag = pack['tag'] as String?;
    final credits = pack['credits'] as int;
    final prix = (pack['prix_euros'] as num).toStringAsFixed(2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: tag != null ? Border.all(color: _green, width: 2) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pack['nom'] as String,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
              if (tag != null)
                Text(tag, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (loading)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
          else ...[
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$credits crédits',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _teal)),
              Text('$prix €',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Widgets partagés ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark));
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(children: [
      Icon(icon, size: 40, color: Colors.grey.shade300),
      const SizedBox(height: 10),
      Text(title, style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
    ]),
  );
}

class _AchatRow extends StatelessWidget {
  final AchatPonctuel achat;
  const _AchatRow({required this.achat});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(achat.nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark)),
          const SizedBox(height: 2),
          Text('${_typeLabels[achat.type] ?? achat.type} · ${DateFormat('dd/MM/yyyy').format(achat.date)}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${achat.montant.toStringAsFixed(2)} €',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
        const SizedBox(height: 2),
        Text(_statutLabels[achat.statut] ?? achat.statut,
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                color: _statutColors[achat.statut] ?? Colors.grey)),
      ]),
      if (achat.factureUrl != null) ...[
        const SizedBox(width: 8),
        Icon(Icons.description_outlined, size: 18, color: Colors.grey.shade400),
      ],
    ]),
  );
}

class _CreditRow extends StatelessWidget {
  final MouvementCredit mouvement;
  const _CreditRow({required this.mouvement});

  @override
  Widget build(BuildContext context) {
    final positif = mouvement.montant >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mouvement.motif, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark)),
            const SizedBox(height: 2),
            Text(DateFormat('dd/MM/yyyy').format(mouvement.date),
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ),
        Text('${positif ? '+' : ''}${mouvement.montant}',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                color: positif ? _green : const Color(0xFFE05C5C))),
      ]),
    );
  }
}

class _FactureRow extends StatelessWidget {
  final LigneFacturation ligne;
  const _FactureRow({required this.ligne});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ligne.libelle, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark)),
          const SizedBox(height: 2),
          Text('${_typeLabels[ligne.type] ?? ligne.type} · ${DateFormat('dd/MM/yyyy').format(ligne.date)}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      Text('${ligne.montant.toStringAsFixed(2)} €',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
      if (ligne.factureUrl != null) ...[
        const SizedBox(width: 10),
        Icon(Icons.download_outlined, size: 18, color: _teal),
      ],
    ]),
  );
}
