// Pet-sitting — après l'acceptation d'une demande (un passage ou une série) :
// contrat de garde pré-rempli à faire signer, facture au choix (maintenant /
// acompte / après la prestation) et, si le client remet ses clés, enregistrement
// de la clé. Miroir site : components/garde/ApresAcceptationGardeModal.tsx.
// Scopé au profil pet-sitter actif (pro_profile_id) — jamais l'uid seul.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/pro/garde_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/garde_facture_helper.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne;

const _teal = Color(0xFF0C5C6C);

/// Montant de la prestation : forfait choisi, sinon tarif × passages
/// (+ animal supplémentaire × animaux en plus × passages). Prix HT.
class GardeChiffrage {
  final List<FacturePrefillLigne> lignes;
  final double totalHT;
  const GardeChiffrage(this.lignes, this.totalHT);
}

int _nbAnimaux(Map<String, dynamic> r) {
  final ids = r['animaux_ids'];
  return ids is List && ids.isNotEmpty ? ids.length : 1;
}

String _periode(List<Map<String, dynamic>> rdvs) {
  final d = [for (final r in rdvs) DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal()]
      .whereType<DateTime>().toList()..sort();
  if (d.isEmpty) return '';
  final f = DateFormat('dd/MM/yyyy', 'fr_FR');
  return d.length == 1 ? 'le ${f.format(d.first)}' : 'du ${f.format(d.first)} au ${f.format(d.last)}';
}

Future<GardeChiffrage> chiffrerGarde(List<Map<String, dynamic>> rdvs) async {
  final first = rdvs.first;
  final n = rdvs.length;
  final animaux = _nbAnimaux(first);
  final noms = (first['_animal_nom'] ?? first['animal_nom_manuel'] ?? '').toString();
  final forfaitId = first['forfait_id']?.toString();
  if (forfaitId != null && forfaitId.isNotEmpty) {
    try {
      final f = await Supabase.instance.client.from('forfaits_garde')
          .select('nom, prix, nb_visites').eq('id', forfaitId).maybeSingle();
      final prix = (f?['prix'] as num?)?.toDouble() ?? 0;
      if (f != null && prix > 0) {
        return GardeChiffrage([
          FacturePrefillLigne(designation: 'Forfait ${f['nom']}${noms.isNotEmpty ? ' — $noms' : ''}',
              description: _periode(rdvs), prixHT: prix, quantite: 1, tauxTVA: 20),
        ], prix);
      }
    } catch (_) {}
  }
  final prix = await gardeTarif(first);
  final lignes = <FacturePrefillLigne>[
    FacturePrefillLigne(
      designation: '${(first['motif'] ?? 'Prestation').toString()}${noms.isNotEmpty ? ' — $noms' : ''}',
      description: _periode(rdvs), prixHT: prix, quantite: n.toDouble(), tauxTVA: 20),
  ];
  var total = prix * n;
  if (animaux > 1) {
    final supp = await _tarifAnimalSupp();
    if (supp > 0) {
      lignes.add(FacturePrefillLigne(designation: 'Animal supplémentaire', prixHT: supp,
          quantite: ((animaux - 1) * n).toDouble(), tauxTVA: 20));
      total += supp * (animaux - 1) * n;
    }
  }
  return GardeChiffrage(lignes, total);
}

Future<double> _tarifAnimalSupp() async {
  final pid = User_Info.activeProfileId;
  if (pid.isEmpty) return 0;
  try {
    final p = await Supabase.instance.client.from('user_profiles_complet')
        .select('tarifs_garde').eq('id', pid).maybeSingle();
    final tg = p?['tarifs_garde'];
    if (tg is Map) return (tg['animal_supplementaire'] as num?)?.toDouble() ?? 0;
  } catch (_) {}
  return 0;
}

Future<bool> _premiumOuProposer(BuildContext context, String quoi) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final plan = await PlanService.getGardePlanCode(uid);
  if (plan == 'premium') return true;
  if (!context.mounted) return false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$quoi — Plan Premium requis', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Text('$quoi est disponible avec l\'abonnement Premium.', style: const TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const GardeAbonnementPage()));
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
          child: const Text('👑 Voir les plans', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        ),
      ],
    ),
  );
  return false;
}

/// Contrat de prestation du client (un par profil pet-sitter + client),
/// pré-rempli avec la prestation acceptée, puis ouvert pour signature.
Future<void> ouvrirContratGardeDepuisRdv(BuildContext context, List<Map<String, dynamic>> rdvs,
    {double? totalHT}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final pid = User_Info.activeProfileId;
  final first = rdvs.first;
  final clientUid = first['client_uid']?.toString();
  if (uid == null || pid.isEmpty || clientUid == null) return;
  if (!await _premiumOuProposer(context, 'La signature de contrats')) return;
  final supa = Supabase.instance.client;
  final noms = (first['_animal_nom'] ?? first['animal_nom_manuel'] ?? '').toString();
  final dates = [for (final r in rdvs) DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal()]
      .whereType<DateTime>().toList()..sort();
  final acces = accesLogementLabel(first['acces_logement']?.toString());
  final prestation = [
    (first['motif'] ?? 'Prestation').toString(),
    if (rdvs.length > 1) '${rdvs.length} passages ${_periode(rdvs)}',
  ].join(' — ');
  final notes = [
    if ((first['lieu']?.toString() ?? '').isNotEmpty) 'Lieu de prise en charge : ${first['lieu']}',
    if (acces.isNotEmpty) 'Accès au logement : $acces',
    if ((first['notes_client']?.toString() ?? '').trim().isNotEmpty) 'Consignes : ${first['notes_client'].toString().trim()}',
  ].join('\n');
  final total = totalHT ?? (await chiffrerGarde(rdvs)).totalHT;
  final details = <String, dynamic>{
    'prestation': prestation,
    if (dates.isNotEmpty) 'date_prestation': dates.first.toIso8601String().substring(0, 10),
    if (total > 0) 'tarif': total.toStringAsFixed(2),
    if (notes.isNotEmpty) 'notes': notes,
    if ((first['lieu']?.toString() ?? '').isNotEmpty) 'client_adresse': first['lieu'].toString(),
  };
  try {
    final existing = await supa.from('documents_animaux')
        .select('id, token, statut, metadata')
        .eq('uid_eleveur', uid).eq('pro_profile_id', pid)
        .eq('type', 'contrat_garde').eq('metadata->>client_uid', clientUid)
        .order('created_at', ascending: false).limit(1).maybeSingle();
    String? token = existing?['token'] as String?;
    final signe = (existing?['statut']?.toString() ?? '').startsWith('signe');
    if (token == null || signe) {
      // Nouveau contrat (aucun, ou le précédent est déjà signé : nouvelle prestation).
      final row = await supa.from('documents_animaux').insert({
        'uid_eleveur': uid,
        'pro_profile_id': pid,
        'type': 'contrat_garde',
        'titre': 'Contrat de prestation — ${first['_client_name'] ?? 'Client'}',
        'statut': 'en_attente',
        if ((first['animal_id']?.toString() ?? '').isNotEmpty) 'animal_id': first['animal_id'],
        'metadata': {
          'client_nom': first['_client_name'] ?? 'Client',
          'client_uid': clientUid,
          if ((first['client_profile_id']?.toString() ?? '').isNotEmpty) 'client_profile_id': first['client_profile_id'],
          if (noms.isNotEmpty) 'animal_nom': noms,
          if (noms.isNotEmpty) 'animal_noms': noms.split(' + '),
          ...details,
        },
      }).select('token').single();
      token = row['token'] as String?;
    } else {
      final meta = Map<String, dynamic>.from((existing!['metadata'] as Map?) ?? {})..addAll(details);
      if (noms.isNotEmpty) {
        final l = List<String>.from((meta['animal_noms'] as List?) ?? const []);
        for (final n in noms.split(' + ')) {
          if (!l.contains(n)) l.add(n);
        }
        meta['animal_noms'] = l;
        meta['animal_nom'] ??= noms;
      }
      await supa.from('documents_animaux').update({'metadata': meta}).eq('id', existing['id']);
    }
    if (token != null && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token!)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contrat : $e')));
    }
  }
}

/// Facture maintenant (totale) ou acompte (30 % par défaut, modifiable).
Future<void> facturerGardeAcceptee(BuildContext context, List<Map<String, dynamic>> rdvs,
    {required bool acompte}) async {
  if (!await _premiumOuProposer(context, 'La facturation')) return;
  final c = await chiffrerGarde(rdvs);
  if (!context.mounted) return;
  final first = rdvs.first;
  final lignes = acompte
      ? [FacturePrefillLigne(
          designation: 'Acompte — ${(first['motif'] ?? 'Prestation').toString()}',
          description: _periode(rdvs), prixHT: double.parse((c.totalHT * 0.3).toStringAsFixed(2)), tauxTVA: 20)]
      : c.lignes;
  await Navigator.push(context, MaterialPageRoute(
    builder: (_) => CreerFacturePage(
      clientNom: gardeClientNom(first),
      clientEmail: (first['_client_email'] ?? first['client_email_manuel'])?.toString(),
      clientTel: (first['_client_tel'] ?? first['client_tel_manuel'])?.toString(),
      lignesPrefill: lignes,
      typeFacture: acompte ? 'acompte' : null,
      // Acompte : les passages restent « à facturer » (solde ensuite).
      sourceRdvId: acompte ? null : first['id']?.toString(),
      sourceRdvIds: acompte ? const [] : [for (final r in rdvs) r['id']?.toString() ?? ''].where((s) => s.isNotEmpty).toList(),
      sourceAnimalId: first['animal_id']?.toString(),
      clientUid: first['client_uid']?.toString(),
      clientProfileId: first['client_profile_id']?.toString(),
    ),
  ));
}

Future<void> _enregistrerCle(BuildContext context, Map<String, dynamic> rdv) async {
  final ctrl = TextEditingController(text: 'Clé du logement');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enregistrer la clé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Description (ex. clé porte d\'entrée + badge)')),
        const SizedBox(height: 8),
        Text('Aucun code d\'accès n\'est enregistré ici.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer', style: TextStyle(color: _teal, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  final desc = ctrl.text.trim();
  ctrl.dispose();
  if (ok != true) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await Supabase.instance.client.from('cles_clients').insert({
      'pro_uid': uid,
      'pro_profile_id': User_Info.activeProfileId,
      if (rdv['animal_id'] != null) 'animal_id': rdv['animal_id'],
      'owner_uid': rdv['client_uid'],
      if (rdv['client_profile_id'] != null) 'owner_profile_id': rdv['client_profile_id'],
      'description': desc.isEmpty ? 'Clé du logement' : desc,
      'date_recuperation': DateTime.now().toIso8601String().substring(0, 10),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clé enregistrée dans « Gestion des clés »')));
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clé : $e')));
  }
}

/// Feuille « Demande acceptée — et maintenant ? » (pet-sitter).
Future<void> apresAcceptationGarde(BuildContext context, List<Map<String, dynamic>> rdvs) async {
  if (rdvs.isEmpty || !context.mounted) return;
  final first = rdvs.first;
  final remiseCles = first['acces_logement'] == 'remise_cles';
  final c = await chiffrerGarde(rdvs);
  if (!context.mounted) return;
  // Tarifs saisis par le pet-sitter (TVA selon son régime, appliquée sur la facture).
  String eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  Widget tuile(IconData ic, String titre, String sous, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(backgroundColor: _teal.withValues(alpha: 0.1), child: Icon(ic, color: _teal, size: 20)),
        title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(sous, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Demande acceptée ✓', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _teal)),
          const SizedBox(height: 2),
          Text('${first['_animal_nom'] ?? ''} · ${first['_client_name'] ?? ''}${rdvs.length > 1 ? ' · ${rdvs.length} passages' : ''}'
              '${c.totalHT > 0 ? ' · ${eur(c.totalHT)}' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          const Text('Contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
          tuile(Icons.draw_outlined, 'Envoyer le contrat de garde', 'Pré-rempli : prestation, dates, lieu, accès, tarif', () {
            Navigator.pop(ctx);
            ouvrirContratGardeDepuisRdv(context, rdvs, totalHT: c.totalHT);
          }),
          const SizedBox(height: 4),
          const Text('Facturation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
          tuile(Icons.receipt_long_outlined, 'Facturer maintenant',
              c.totalHT > 0 ? 'Paiement d\'avance — ${eur(c.totalHT)}' : 'Paiement d\'avance (tarif à compléter)', () {
            Navigator.pop(ctx);
            facturerGardeAcceptee(context, rdvs, acompte: false);
          }),
          tuile(Icons.savings_outlined, 'Demander un acompte',
              c.totalHT > 0 ? '30 % — ${eur(c.totalHT * 0.3)} (modifiable)' : 'Montant à saisir', () {
            Navigator.pop(ctx);
            facturerGardeAcceptee(context, rdvs, acompte: true);
          }),
          tuile(Icons.schedule_outlined, 'Facturer après la prestation',
              'Depuis le registre ou le RDV une fois terminé', () => Navigator.pop(ctx)),
          if (remiseCles) ...[
            const SizedBox(height: 4),
            const Text('Clés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
            tuile(Icons.vpn_key_outlined, 'Enregistrer la clé du client', 'Le client vous remet ses clés', () {
              Navigator.pop(ctx);
              _enregistrerCle(context, first);
            }),
          ],
        ]),
      ),
    ),
  );
}
