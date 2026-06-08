import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

class PartnerSignupPage extends StatefulWidget {
  const PartnerSignupPage({super.key});

  @override
  State<PartnerSignupPage> createState() => _PartnerSignupPageState();
}

class _PartnerSignupPageState extends State<PartnerSignupPage> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  final _nomCtrl = TextEditingController();
  final _siretCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String _categorie = 'boutique';
  String _plan = 'starter';
  final List<String> _especesCibles = [];

  static const _categories = [
    ('boutique', 'Boutique & Accessoires', Icons.store_outlined),
    ('alimentation', 'Alimentation & Petfood', Icons.restaurant_outlined),
    ('artisan', 'Créateur artisanal', Icons.brush_outlined),
    ('assurance', 'Assurance animaux', Icons.shield_outlined),
  ];

  static const _especes = [
    ('chien', 'Chien 🐕'),
    ('chat', 'Chat 🐈'),
    ('equide', 'Équidé 🐴'),
    ('lapin', 'Lapin 🐇'),
    ('autre', 'Autre'),
  ];

  static const _plans = [
    ('starter', 'Starter', '29€/mois', 'Logo + nom + lien, listing basique'),
    ('visible', 'Visible', '59€/mois', 'Mise en avant + badge Vérifié + description'),
    ('premium', 'Premium', '99€/mois', 'Top catégorie + bannières + ciblage avancé'),
  ];

  @override
  void dispose() {
    _nomCtrl.dispose();
    _siretCtrl.dispose();
    _siteCtrl.dispose();
    _descCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_especesCibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez au moins une espèce cible'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _supabase.from('marketplace_partners').insert({
        'user_id': User_Info.uid,
        'nom': _nomCtrl.text.trim(),
        'siret': _siretCtrl.text.trim(),
        'site_url': _siteCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'contact_email': _emailCtrl.text.trim(),
        'categorie': _categorie,
        'plan': _plan,
        'especes_cibles': _especesCibles,
        'statut': 'en_attente',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande envoyée ✓ Nous reviendrons vers vous sous 48h'),
          backgroundColor: Color(0xFF6E9E57),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        title: const Text('Devenir partenaire',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intro
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6E9E57), Color(0xFF4A7A3D)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rejoignez notre réseau',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                    SizedBox(height: 6),
                    Text('Touchez des milliers d\'amoureux des animaux qualifiés. Votre demande sera examinée sous 48h.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _sectionTitle('Informations entreprise'),
              const SizedBox(height: 12),
              _field(_nomCtrl, 'Nom de l\'entreprise *', validator: _required),
              const SizedBox(height: 12),
              _field(_siretCtrl, 'SIRET', keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(_siteCtrl, 'Site web (URL) *', keyboardType: TextInputType.url, validator: _required),
              const SizedBox(height: 12),
              _field(_emailCtrl, 'Email de contact *',
                  keyboardType: TextInputType.emailAddress, validator: _required),
              const SizedBox(height: 12),
              _field(_descCtrl, 'Description courte', maxLines: 3),
              const SizedBox(height: 24),

              _sectionTitle('Catégorie'),
              const SizedBox(height: 12),
              ..._categories.map((cat) => _RadioTile(
                    value: cat.$1,
                    groupValue: _categorie,
                    icon: cat.$3,
                    label: cat.$2,
                    onChanged: (v) => setState(() => _categorie = v!),
                  )),
              const SizedBox(height: 24),

              _sectionTitle('Espèces ciblées *'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _especes.map((e) {
                  final sel = _especesCibles.contains(e.$1);
                  return FilterChip(
                    label: Text(e.$2,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            color: sel ? Colors.white : Colors.black87)),
                    selected: sel,
                    onSelected: (v) => setState(() {
                      if (v) _especesCibles.add(e.$1);
                      else _especesCibles.remove(e.$1);
                    }),
                    selectedColor: const Color(0xFF6E9E57),
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: sel ? const Color(0xFF6E9E57) : Colors.grey.shade300),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              _sectionTitle('Plan de visibilité'),
              const SizedBox(height: 12),
              ..._plans.map((p) => _PlanCard(
                    plan: p.$1,
                    titre: p.$2,
                    prix: p.$3,
                    desc: p.$4,
                    selected: _plan == p.$1,
                    onTap: () => setState(() => _plan = p.$1),
                  )),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6E9E57),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Envoyer ma demande'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15));

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType, int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ requis' : null;
}

// ── Widgets internes ──────────────────────────────────────────────────────────

class _RadioTile extends StatelessWidget {
  final String value, groupValue, label;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _RadioTile({required this.value, required this.groupValue, required this.icon, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final sel = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? const Color(0xFF6E9E57) : Colors.grey.shade300, width: sel ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: sel ? const Color(0xFF6E9E57) : Colors.grey),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: sel ? FontWeight.w600 : FontWeight.normal, fontSize: 14))),
            if (sel) const Icon(Icons.check_circle, color: Color(0xFF6E9E57), size: 18),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String plan, titre, prix, desc;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.titre, required this.prix, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFF6E9E57) : Colors.grey.shade300, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF6E9E57), borderRadius: BorderRadius.circular(20)),
                      child: Text(prix, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: Color(0xFF6E9E57), size: 22),
          ],
        ),
      ),
    );
  }
}
