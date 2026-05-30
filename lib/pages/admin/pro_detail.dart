import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kTeal = Color(0xFF0C5C6C);
const _kGreen = Color(0xFF6E9E57);

const _kCatLabels = <String, String>{
  '': '—',
  'sante': 'Santé',
  'veterinaire': 'Vétérinaire',
  'education': 'Éducation',
  'garde': 'Pension / Garde',
  'referencement': 'Référencement',
  'autre': 'Autre',
};

const _kEspeces = [
  'Chien', 'Chat', 'Lapin', 'Oiseau',
  'Reptile', 'Rongeur', 'Cheval', 'Autre',
];

class ProDetail extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> fireData;
  final Map<String, dynamic> supaRow;

  const ProDetail({
    super.key,
    required this.uid,
    required this.fireData,
    required this.supaRow,
  });

  @override
  State<ProDetail> createState() => _ProDetailState();
}

class _ProDetailState extends State<ProDetail> {
  final _supaClient = Supabase.instance.client;
  late Map<String, dynamic> _supaRow;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _supaRow = Map<String, dynamic>.from(widget.supaRow);
  }

  // ── Statut ────────────────────────────────────────────────────────────────

  Future<void> _setStatut(String statut) async {
    final labels = {
      'actif': 'Activer',
      'refuse': 'Refuser',
      'suspendu': 'Suspendre',
      'en_attente': 'Mettre en attente',
    };
    final colors = {
      'actif': Colors.green,
      'refuse': Colors.red,
      'suspendu': Colors.orange,
      'en_attente': Colors.blue,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF8F8F6),
        title: Text('${labels[statut] ?? statut} ce profil ?',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colors[statut] ?? _kTeal),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels[statut] ?? statut,
                style: const TextStyle(color: Colors.white, fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _supaClient
          .from('users')
          .update({'statut_pro': statut})
          .eq('uid', widget.uid);
      setState(() => _supaRow['statut_pro'] = statut);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Statut mis à jour : $statut',
                style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: colors[statut] ?? _kTeal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e',
                style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Édition rayon ─────────────────────────────────────────────────────────

  Future<void> _editRayon() async {
    final ctrl = TextEditingController(
        text: (_supaRow['rayon_intervention'] ?? 0).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF8F8F6),
        title: const Text("Rayon d'intervention (km)",
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixText: 'km',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kTeal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final val = int.tryParse(ctrl.text.trim()) ?? 0;
    try {
      await _supaClient
          .from('users')
          .update({'rayon_intervention': val})
          .eq('uid', widget.uid);
      setState(() => _supaRow['rayon_intervention'] = val);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Édition espèces ───────────────────────────────────────────────────────

  Future<void> _editEspeces() async {
    List<String> selected = List<String>.from(
        (_supaRow['especes_acceptees'] as List? ?? []));
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFFF8F8F6),
          title: const Text('Espèces acceptées',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kEspeces.map((e) {
              final sel = selected.contains(e);
              return FilterChip(
                label: Text(e,
                    style: TextStyle(
                        fontFamily: 'Galey',
                        color: sel ? Colors.white : Colors.black87)),
                selected: sel,
                onSelected: (_) => setS(() {
                  if (sel) { selected.remove(e); } else { selected.add(e); }
                }),
                backgroundColor: Colors.white,
                selectedColor: _kTeal,
                checkmarkColor: Colors.white,
                side: BorderSide(color: sel ? _kTeal : Colors.grey.shade300),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kTeal),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _supaClient
                      .from('users')
                      .update({'especes_acceptees': selected})
                      .eq('uid', widget.uid);
                  setState(() => _supaRow['especes_acceptees'] = selected);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enregistrer', style: TextStyle(color: Colors.white, fontFamily: 'Galey')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Suppression ───────────────────────────────────────────────────────────

  Future<void> _deleteUser() async {
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF8F8F6),
        title: const Text('⚠️ Supprimer ce profil ?',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                color: Colors.red)),
        content: Text(
          'Sera supprimé définitivement :\n\n'
          '• Compte Firebase Auth\n'
          '• Données personnelles\n'
          '• Profil pro\n\n'
          'Utilisateur : ${widget.fireData['email'] ?? widget.uid}',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuer →',
                style: TextStyle(color: Colors.white, fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final ctrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFFF8F8F6),
          title: const Text('Confirmation finale',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tapez SUPPRIMER pour confirmer :',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              onChanged: (_) => setS(() {}),
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  color: Colors.red),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFFFEBEE),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                hintText: 'SUPPRIMER',
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: ctrl.text == 'SUPPRIMER'
                      ? Colors.red
                      : Colors.grey.shade300),
              onPressed: ctrl.text == 'SUPPRIMER'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Supprimer définitivement',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Galey',
                      fontSize: 12)),
            ),
          ],
        ),
      ),
    );
    if (step2 != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _supaClient.functions
          .invoke('delete-user', body: {'uid': widget.uid});
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil supprimé.'),
            backgroundColor: Colors.green));
        Navigator.pop(context, 'deleted');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name =
        '${widget.fireData['firstname'] ?? ''} ${widget.fireData['lastname'] ?? ''}'
            .trim();
    final ppUrl = widget.fireData['profilePictureUrl'] ?? '';
    final statut = _supaRow['statut_pro']?.toString() ?? 'actif';
    final cat = _supaRow['cat_pro']?.toString() ?? '';
    final rayon = _supaRow['rayon_intervention'];
    final especes = (_supaRow['especes_acceptees'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final certifs = (_supaRow['certifications'] as List? ?? [])
        .map((e) => (e as Map?)?.values.join(' — ') ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final struct = _supaRow['name_elevage']?.toString() ?? '';
    final profession = _supaRow['profession_pro']?.toString() ?? '';

    final (statutColor, statutLabel) = switch (statut) {
      'refuse' => (Colors.red, 'Refusé'),
      'suspendu' => (Colors.orange, 'Suspendu'),
      'en_attente' => (Colors.blue, 'En attente'),
      _ => (Colors.green, 'Actif'),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Profil professionnel',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Colors.black)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: _saving ? null : _deleteUser,
          ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + nom
                    Center(
                      child: Column(children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: _kTeal,
                          backgroundImage:
                              ppUrl.isNotEmpty ? NetworkImage(ppUrl) : null,
                          child: ppUrl.isEmpty
                              ? const Icon(Icons.work,
                                  size: 48, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(name.isNotEmpty ? name : 'Nom inconnu',
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                fontSize: 20)),
                        if (struct.isNotEmpty)
                          Text(struct,
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 14,
                                  color: _kTeal)),
                        if (profession.isNotEmpty)
                          Text(profession,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey)),
                        Text(widget.fireData['email'] ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Badge statut
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: statutColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statutColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(statutLabel,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: statutColor)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions statut
                    _SectionTitle('Actions'),
                    Row(children: [
                      if (statut != 'actif')
                        Expanded(
                          child: _ActionBtn(
                            label: 'Activer',
                            icon: Icons.check_circle_outline,
                            color: Colors.green,
                            onTap: () => _setStatut('actif'),
                          ),
                        ),
                      if (statut != 'actif') const SizedBox(width: 8),
                      if (statut != 'suspendu')
                        Expanded(
                          child: _ActionBtn(
                            label: 'Suspendre',
                            icon: Icons.pause_circle_outline,
                            color: Colors.orange,
                            onTap: () => _setStatut('suspendu'),
                          ),
                        ),
                      if (statut != 'suspendu') const SizedBox(width: 8),
                      if (statut != 'refuse')
                        Expanded(
                          child: _ActionBtn(
                            label: 'Refuser',
                            icon: Icons.cancel_outlined,
                            color: Colors.red,
                            onTap: () => _setStatut('refuse'),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 24),

                    // Infos pro
                    _SectionTitle('Profil professionnel'),
                    _InfoRow(Icons.category_outlined, 'Catégorie',
                        _kCatLabels[cat] ?? (cat.isNotEmpty ? cat : '—')),
                    const SizedBox(height: 20),

                    // Rayon
                    _SectionTitle('Zone d\'intervention'),
                    _EditableRow(
                      icon: Icons.radar,
                      label: 'Rayon',
                      value: rayon != null ? '$rayon km' : '—',
                      onTap: _editRayon,
                    ),
                    const SizedBox(height: 20),

                    // Espèces
                    _SectionTitle('Espèces acceptées'),
                    InkWell(
                      onTap: _editEspeces,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: especes.isEmpty
                            ? Row(children: [
                                const Icon(Icons.pets,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                const Text('Aucune espèce — toucher pour éditer',
                                    style: TextStyle(
                                        fontFamily: 'Galey',
                                        fontSize: 13,
                                        color: Colors.grey)),
                                const Spacer(),
                                const Icon(Icons.edit,
                                    size: 16, color: Colors.grey),
                              ])
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ...especes.map((e) => _badge(e, _kTeal)),
                                  const Icon(Icons.edit,
                                      size: 16, color: Colors.grey),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Certifications
                    if (certifs.isNotEmpty) ...[
                      _SectionTitle('Certifications'),
                      ...certifs.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              const Icon(Icons.verified_outlined,
                                  size: 16, color: _kGreen),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(c,
                                      style: const TextStyle(
                                          fontFamily: 'Galey', fontSize: 13))),
                            ]),
                          )),
                      const SizedBox(height: 20),
                    ],

                    // Infos perso Firestore
                    _SectionTitle('Informations personnelles'),
                    _InfoRow(Icons.phone, 'Téléphone',
                        widget.fireData['phone_number'] ?? '—'),
                    _InfoRow(Icons.numbers, 'SIRET',
                        widget.fireData['siret'] ?? '—'),
                    _InfoRow(Icons.fingerprint, 'UID', widget.uid),
                    const SizedBox(height: 40),
                  ]),
            ),
    );
  }
}

// ─── Widgets helpers ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: _kGreen)),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == '—') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 14)),
          ]),
        ),
      ]),
    );
  }
}

class _EditableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _EditableRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: 14)),
              ]),
            ),
            const Icon(Icons.edit, size: 16, color: Colors.grey),
          ]),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: color)),
          ]),
        ),
      );
}

Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500)),
    );
