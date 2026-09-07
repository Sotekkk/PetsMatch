import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Palette (identique au reste des pages particulier — cf. mes_contrats_page.dart) ──
const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

// ── Modèles génériques ──────────────────────────────────────────────────────────
// Le profil particulier est gratuit par conception (cf. commentaire dans
// onboarding_theme.dart : « Les profils gratuits (particulier, association)
// n'ont pas d'abonnement »). Il n'existe donc aujourd'hui aucune table Supabase
// ni aucun modèle de paiement pour un abonnement, un achat ponctuel ou des
// crédits côté particulier — ces classes ne servent qu'à préparer l'affichage
// (structure volontairement générique) pour le jour où ces fonctionnalités
// seront réellement activées. Tant que ce n'est pas le cas, les listes qui
// les utilisent restent vides et l'UI l'assume clairement (états vides),
// plutôt que d'inventer des données.

/// Un achat ponctuel (boost, personnalisation, pass, cadeau virtuel…).
class AchatPonctuel {
  final String id;
  final DateTime date;
  final String nom;
  final String type; // 'boost' | 'personnalisation' | 'pass' | 'cadeau_virtuel' | ...
  final double montant;
  final String statut; // 'paye' | 'en_attente' | 'rembourse' | 'echoue'
  final String? factureUrl;
  const AchatPonctuel({
    required this.id, required this.date, required this.nom, required this.type,
    required this.montant, required this.statut, this.factureUrl,
  });
}

/// Une ligne de l'historique des mouvements de crédits.
class MouvementCredit {
  final DateTime date;
  final String motif;
  final int montant; // positif = crédité, négatif = débité
  const MouvementCredit({required this.date, required this.motif, required this.montant});
}

/// Une ligne de l'historique de facturation unifié (abonnement, achat, pack
/// de crédits, remboursement…).
class LigneFacturation {
  final DateTime date;
  final String type; // 'abonnement' | 'renouvellement' | 'achat' | 'pack_credits' | 'remboursement'
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
  'paye': _green, 'en_attente': Color(0xFFE0A030), 'rembourse': Color(0xFF6F767B), 'echoue': Color(0xFFE05C5C),
};

class AbonnementsAchatsPage extends StatefulWidget {
  const AbonnementsAchatsPage({super.key});

  @override
  State<AbonnementsAchatsPage> createState() => _AbonnementsAchatsPageState();
}

class _AbonnementsAchatsPageState extends State<AbonnementsAchatsPage> {
  // Aucune source de données réelle pour l'instant (voir commentaire plus
  // haut) — listes vides, prêtes à être remplacées par une requête Supabase
  // dès qu'une table dédiée existera, sans changer le reste de la page.
  final List<AchatPonctuel> _achats = const [];
  final List<MouvementCredit> _mouvementsCredits = const [];
  final List<LigneFacturation> _facturation = const [];
  static const int _soldeCredits = 0;
  static const int _creditsAchetes = 0;
  static const int _creditsUtilises = 0;

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
      body: ListView(
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
    );
  }

  // ── 1. Mon abonnement ──────────────────────────────────────────────────────
  // Profil particulier = gratuit aujourd'hui (aucune formule payante n'existe
  // encore). On affiche donc honnêtement l'état « Gratuit » plutôt que
  // d'inventer un prix ou une date de facturation — les boutons Gérer /
  // Changer / Résilier n'ont pas de sens tant qu'il n'y a rien à gérer.
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

  // ── 2. Mes achats ────────────────────────────────────────────────────────
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

  // ── 3. Mes crédits ───────────────────────────────────────────────────────
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
          onPressed: () => _bientotDisponible('L\'achat de crédits n\'est pas encore disponible.'),
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

  // ── 4. Facturation ───────────────────────────────────────────────────────
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
