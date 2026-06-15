import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:PetsMatch/services/planning_service.dart';

// ════════════════════════════════════════════════════════════════════════════════
// PAGE FORMULAIRE TEMPLATE
// ════════════════════════════════════════════════════════════════════════════════

class PlanTemplateFormPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const PlanTemplateFormPage({super.key, this.existing});
  @override
  State<PlanTemplateFormPage> createState() => _PlanTemplateFormPageState();
}

class _PlanTemplateFormPageState extends State<PlanTemplateFormPage> {
  static const _green = Color(0xFF0C5C6C);

  final _nomCtrl         = TextEditingController();
  final _descCtrl        = TextEditingController();
  final _lieuNettCtrl    = TextEditingController();

  String _type          = 'sanitaire';
  String _espece        = '';
  String _cibleType     = 'individuel';
  String _refEvent      = 'manuel';
  bool   _saving        = false;

  static const _lieuxNettoyage = [
    'Chatterie n°1', 'Chatterie n°2', 'Chenil', 'Chenil n°1', 'Chenil n°2',
    'Cuisine', 'Salle de soins', 'Salle de quarantaine', 'Box', 'Jardin', 'Couloir',
  ];

  final List<_EtapeCtrl> _etapes = [];

  static const _types = [
    ('sanitaire',     '💊', 'Sanitaire'),
    ('nettoyage',     '🧹', 'Nettoyage'),
    ('promenade',     '🦮', 'Promenade'),
    ('socialisation', '🐾', 'Socialisation'),
  ];

  static const _especes = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

  // Cible : qui est concerné
  static const _cibles = [
    ('individuel',  '🐾', 'Animal individuel',      'Sélection manuelle à l\'application'),
    ('cheptel',     '🏡', 'Tout le cheptel',        'Tous les animaux de l\'espèce'),
    ('males',       '♂',  'Mâles',                  'Tous les mâles de l\'espèce'),
    ('femelles',    '♀',  'Femelles',               'Toutes les femelles de l\'espèce'),
    ('gestantes',   '🤰', 'Femelles gestantes',     'Relativement à la date de mise bas'),
    ('allaitantes', '🤱', 'Femelles allaitantes',   'Femelles en nurserie / avec bébés (< 8 sem.)'),
    ('bebes',       '🍼', 'Bébés / Jeunes',         'Selon l\'âge en semaines'),
  ];

  // Événement de référence pour J0
  static const _refEvents = [
    ('manuel',        '📅', 'Date choisie',        'Vous choisissez la date J0 à l\'application'),
    ('saillie',       '💑', 'Date de saillie',     'J0 = date de la saillie'),
    ('mise_bas',      '🍼', 'Date de mise bas',    'J0 = date de mise bas (avant ou après)'),
    ('naissance',     '🐣', 'Date de naissance',   'J0 = date de naissance de l\'animal'),
    ('age_semaines',  '📆', 'Âge en semaines',     'Déclenche à un âge précis du bébé'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nomCtrl.text      = e['nom'] ?? '';
      _descCtrl.text     = e['description'] ?? '';
      _lieuNettCtrl.text = e['lieu'] ?? '';
      _type      = e['type']            ?? 'sanitaire';
      _espece    = e['espece']          ?? '';
      _cibleType = e['cible_type']      ?? 'individuel';
      _refEvent  = e['reference_event'] ?? 'manuel';
      final etapesData = e['plan_template_etapes'];
      if (etapesData is List) {
        for (final et in etapesData) {
          _etapes.add(_EtapeCtrl.fromData(Map<String, dynamic>.from(et)));
        }
      }
    }
    if (_etapes.isEmpty) _addEtape();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _descCtrl.dispose();
    _lieuNettCtrl.dispose();
    for (final e in _etapes) { e.dispose(); }
    super.dispose();
  }

  void _addEtape() => setState(() => _etapes.add(_EtapeCtrl()));
  void _removeEtape(int i) {
    setState(() { _etapes[i].dispose(); _etapes.removeAt(i); });
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      _snack('Le nom est requis'); return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final etapesData = _etapes.map((e) => e.toMap(isBebes: _cibleType == 'bebes')).toList();
      final lieuNett = _lieuNettCtrl.text.trim().isEmpty ? null : _lieuNettCtrl.text.trim();
      if (widget.existing != null) {
        await PlanningService.updateTemplate(
          templateId:     widget.existing!['id'] as String,
          nom:            _nomCtrl.text.trim(),
          espece:         _espece.isEmpty ? null : _espece,
          description:    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          lieu:           lieuNett,
          cibleType:      _type == 'nettoyage' ? 'cheptel' : _cibleType,
          referenceEvent: _type == 'nettoyage' ? 'manuel' : _refEvent,
          etapes:         etapesData,
        );
      } else {
        await PlanningService.createTemplate(
          uid:            uid,
          nom:            _nomCtrl.text.trim(),
          type:           _type,
          espece:         _espece.isEmpty ? null : _espece,
          description:    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          lieu:           lieuNett,
          cibleType:      _type == 'nettoyage' ? 'cheptel' : _cibleType,
          referenceEvent: _type == 'nettoyage' ? 'manuel' : _refEvent,
          etapes:         etapesData,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erreur : $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: Text(
          isEdit ? 'Modifier le protocole' : 'Nouveau protocole',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ── Informations générales ──
          _Card(children: [
            _SectionTitle('Informations générales'),
            _Field(controller: _nomCtrl, label: 'Nom du protocole *', hint: 'ex: Vermifuge portée standard chien'),
            const SizedBox(height: 10),
            _Field(controller: _descCtrl, label: 'Description (optionnel)', hint: 'Notes sur ce protocole', maxLines: 2),
          ]),
          const SizedBox(height: 12),

          // ── Type de protocole ── (seulement à la création)
          if (!isEdit) ...[
            _Card(children: [
              _SectionTitle('Type de protocole'),
              Wrap(spacing: 8, runSpacing: 6, children: _types.map((t) {
                final active = _type == t.$1;
                return _Chip(emoji: t.$2, label: t.$3, active: active, onTap: () => setState(() => _type = t.$1));
              }).toList()),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Nettoyage : lieu physique ──
          if (_type == 'nettoyage') ...[
            _Card(children: [
              _SectionTitle('Lieu à nettoyer'),
              const _InfoBox('Indiquez le lieu concerné par ce protocole de nettoyage.'),
              const SizedBox(height: 8),
              // Chips raccourci
              Wrap(spacing: 6, runSpacing: 6, children: _lieuxNettoyage.map((l) {
                return GestureDetector(
                  onTap: () => setState(() => _lieuNettCtrl.text = l),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _lieuNettCtrl.text == l ? _green : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _lieuNettCtrl.text == l ? _green : Colors.grey.shade300),
                    ),
                    child: Text(l, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _lieuNettCtrl.text == l ? Colors.white : Colors.grey.shade700)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 10),
              _Field(controller: _lieuNettCtrl, label: 'Ou écrivez le lieu', hint: 'ex: Nurserie, Salle de traite…'),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Espèce + Qui est ciblé (hors nettoyage) ──
          if (_type != 'nettoyage') ...[
            _Card(children: [
              _SectionTitle('Qui est concerné ?'),
              const _InfoBox('Définissez qui sera automatiquement ciblé quand vous appliquez ce protocole.'),
              const SizedBox(height: 10),
              _DropField(
                label: 'Espèce cible',
                value: _espece,
                items: _especes.map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? 'Toutes espèces' : e, style: const TextStyle(fontFamily: 'Galey')))).toList(),
                onChanged: (v) => setState(() => _espece = v ?? ''),
              ),
              const SizedBox(height: 10),
              ...(_cibles.map((c) => _RadioTile(
                emoji: c.$1,
                title: c.$3,
                subtitle: c.$4,
                selected: _cibleType == c.$1,
                onTap: () => setState(() {
                  _cibleType = c.$1;
                  if (c.$1 == 'gestantes') { _refEvent = 'mise_bas'; }
                  else if (c.$1 == 'bebes') { _refEvent = 'age_semaines'; }
                  else if (c.$1 == 'individuel') { _refEvent = 'manuel'; }
                }),
              ))),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Référence temporelle (J0) — hors nettoyage et bébés ──
          if (_type != 'nettoyage' && _cibleType != 'bebes') ...[
            _Card(children: [
              _SectionTitle('Événement de référence (J0)'),
              const _InfoBox('Tous les offsets de vos étapes seront calculés depuis cet événement.'),
              const SizedBox(height: 8),
              ...(_refEventsFor(_cibleType).map((r) => _RadioTile(
                emoji: r.$2,
                title: r.$3,
                subtitle: r.$4,
                selected: _refEvent == r.$1,
                onTap: () => setState(() => _refEvent = r.$1),
              ))),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Étapes ──
          _Card(children: [
            Row(children: [
              const Expanded(child: _SectionTitle('Étapes du protocole')),
              Text('${_etapes.length} étape${_etapes.length > 1 ? 's' : ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 8),
            ..._etapes.asMap().entries.map((entry) => _EtapeCard(
              index: entry.key,
              ctrl: entry.value,
              cibleType: _cibleType,
              refEvent: _refEvent,
              onRemove: _etapes.length > 1 ? () => _removeEtape(entry.key) : null,
              onChanged: () => setState(() {}),
            )),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _addEtape,
              icon: const Icon(Icons.add, size: 16, color: _green),
              label: const Text('Ajouter une étape', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _green)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _green), padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ]),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // Filtrer les ref events selon la cible
  List<(String, String, String, String)> _refEventsFor(String cible) {
    return switch (cible) {
      'gestantes' => _refEvents.where((r) => r.$1 == 'mise_bas' || r.$1 == 'saillie' || r.$1 == 'manuel').toList(),
      'bebes'     => _refEvents.where((r) => r.$1 == 'naissance' || r.$1 == 'age_semaines').toList(),
      _           => _refEvents.where((r) => r.$1 != 'age_semaines').toList(),
    };
  }
}

// ─── Carte d'étape ────────────────────────────────────────────────────────────

class _EtapeCard extends StatelessWidget {
  final int index;
  final _EtapeCtrl ctrl;
  final String cibleType;
  final String refEvent;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _EtapeCard({
    required this.index, required this.ctrl, required this.cibleType,
    required this.refEvent, required this.onRemove, required this.onChanged,
  });

  static const _green = Color(0xFF0C5C6C);

  static const _typesActes = [
    ('vermifuge',       '💊 Vermifuge'),
    ('vaccination',     '💉 Vaccination'),
    ('antiparasitaire', '🛡️ Antiparasitaire'),
    ('traitement',      '🩺 Traitement'),
    ('visite',          '🏥 Visite vétérinaire'),
    ('toilettage',      '🛁 Toilettage'),
    ('peignage',        '🪮 Peignage'),
    ('nettoyage',       '🧹 Nettoyage'),
    ('promenade',       '🦮 Promenade'),
    ('socialisation',   '🐾 Socialisation'),
    ('autre',           '📋 Autre'),
  ];

  static const _frequences = [
    ('ponctuel',      'Ponctuel',           'Une seule fois (ou N jours consécutifs)'),
    ('quotidien',     'Quotidien',          'Chaque jour pendant N semaines'),
    ('hebdomadaire',  '1-3x par semaine',   'Répété N fois/semaine pendant N semaines'),
    ('mensuel',       'Mensuel',            'Une fois par mois pendant N mois'),
  ];

  @override
  Widget build(BuildContext context) {
    final usesAge     = cibleType == 'bebes';
    final refLabel    = _refLabel(refEvent);
    final freq        = ctrl.frequence;
    final isHebdo     = freq == 'hebdomadaire';
    const fd = _fieldDeco;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('${index + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700))),
              ),
              const Spacer(),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Type d'acte
          DropdownButtonFormField<String>(
            initialValue: ctrl.typeActe,
            decoration: fd('Type d\'acte'),
            items: _typesActes.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))).toList(),
            onChanged: (v) { ctrl.typeActe = v ?? 'vermifuge'; onChanged(); },
          ),
          const SizedBox(height: 8),

          // Produit + dosage
          Row(children: [
            Expanded(child: TextFormField(controller: ctrl.produitCtrl, decoration: fd('Produit', hint: 'ex: Milbemax®'), style: _ts, onChanged: (_) => onChanged())),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: ctrl.dosageCtrl, decoration: fd('Dosage', hint: 'ex: 1 cp/5kg'), style: _ts, onChanged: (_) => onChanged())),
          ]),
          const SizedBox(height: 8),

          // ── Timing ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quand ?', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                if (usesAge) ...[
                  // Pour bébés : âge en semaines
                  Row(children: [
                    const Text('À partir de ', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        controller: ctrl.ageSemainesCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: fd('', hint: '3'),
                        textAlign: TextAlign.center,
                        style: _ts,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const Text(' semaines d\'âge', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  ]),
                ] else ...[
                  // Pour les autres : direction + offset + référence
                  Row(children: [
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        initialValue: ctrl.direction,
                        decoration: fd(''),
                        items: const [
                          DropdownMenuItem(value: 'apres', child: Text('Après', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                          DropdownMenuItem(value: 'avant', child: Text('Avant', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                        ],
                        onChanged: (v) { ctrl.direction = v ?? 'apres'; onChanged(); },
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        controller: ctrl.offsetCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: fd('', hint: '0'),
                        textAlign: TextAlign.center,
                        style: _ts,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text('jours $refLabel', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF0C5C6C), fontWeight: FontWeight.w600))),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Fréquence ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fréquence', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: _frequences.map((f) {
                    final active = freq == f.$1;
                    return GestureDetector(
                      onTap: () { ctrl.frequence = f.$1; onChanged(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? _green : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(f.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey.shade700)),
                      ),
                    );
                  }).toList(),
                ),
                // Nombre de fois / semaine (sur sa propre ligne)
                if (isHebdo) ...[
                  const SizedBox(height: 10),
                  const Text('Nb fois / semaine :', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [1, 2, 3].map((n) {
                    final sel = ctrl.nbFoisSemaine == n;
                    return GestureDetector(
                      onTap: () { ctrl.nbFoisSemaine = n; onChanged(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 44, height: 36,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: sel ? _green : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(
                          n == 1 ? '1x' : n == 2 ? '2x' : '3x',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: sel ? Colors.white : Colors.grey.shade700),
                        )),
                      ),
                    );
                  }).toList()),
                ],
                // Toggle récurrent (hors ponctuel)
                if (freq != 'ponctuel') ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () { ctrl.isRecurrent = !ctrl.isRecurrent; onChanged(); },
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 36, height: 20,
                        decoration: BoxDecoration(
                          color: ctrl.isRecurrent ? _green : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 150),
                          alignment: ctrl.isRecurrent ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 16, height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Protocole récurrent (sans fin)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  // Durée — masquée si récurrent
                  if (!ctrl.isRecurrent) Row(children: [
                    const Text('Pendant : ', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    SizedBox(
                      width: 52,
                      child: TextFormField(
                        controller: ctrl.dureeSemainesCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: fd('', hint: '4'),
                        textAlign: TextAlign.center,
                        style: _ts,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    Text(freq == 'mensuel' ? ' mois' : ' sem.', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  ]) else
                    Text('Génère 1 an de tâches à l\'application', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                ],
                // Durée en jours si ponctuel
                if (freq == 'ponctuel') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('Durée : ', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    SizedBox(
                      width: 52,
                      child: TextFormField(
                        controller: ctrl.dureeJoursCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: fd('', hint: '1'),
                        textAlign: TextAlign.center,
                        style: _ts,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const Text(' jours consécutifs', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Moment de la journée ──
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Moment de la journée (optionnel)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    (null,         '—',   'Non défini'),
                    ('matin',      '🌅',  'Matin'),
                    ('midi',       '☀️',  'Midi'),
                    ('apres_midi', '🌤️', 'Après-midi'),
                    ('soir',       '🌙',  'Soir'),
                  ].map((t) {
                    final active = ctrl.trancheHoraire == t.$1;
                    return GestureDetector(
                      onTap: () { ctrl.trancheHoraire = t.$1; onChanged(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? _green : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${t.$2} ${t.$3}', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey.shade700)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Lieu (promenade / socialisation) + description
          if (ctrl.typeActe == 'promenade' || ctrl.typeActe == 'socialisation') ...[
            TextFormField(controller: ctrl.lieuCtrl, decoration: fd('Lieu', hint: 'ex: parc, jardin, forêt…'), style: _ts, onChanged: (_) => onChanged()),
            const SizedBox(height: 6),
          ],
          TextFormField(controller: ctrl.descCtrl, decoration: fd('Notes / instructions'), style: _ts, maxLines: 2, onChanged: (_) => onChanged()),
        ],
      ),
    );
  }

  static String _refLabel(String refEvent) => switch (refEvent) {
    'saillie'       => 'la saillie',
    'mise_bas'      => 'la mise bas',
    'naissance'     => 'la naissance',
    'age_semaines'  => 'la naissance',
    _               => 'la date J0',
  };

  static const TextStyle _ts = TextStyle(fontFamily: 'Galey', fontSize: 13);

  static InputDecoration _fieldDeco(String label, {String? hint}) => InputDecoration(
    labelText: label.isEmpty ? null : label,
    hintText: hint,
    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    filled: true,
    fillColor: Colors.white,
  );
}

// ─── Contrôleur d'étape ───────────────────────────────────────────────────────

class _EtapeCtrl {
  String  typeActe       = 'vermifuge';
  String  direction      = 'apres';
  String  frequence      = 'ponctuel';
  int     nbFoisSemaine  = 1;
  bool    isRecurrent    = false;
  String? trancheHoraire;
  String? existingId;

  final TextEditingController produitCtrl;
  final TextEditingController dosageCtrl;
  final TextEditingController offsetCtrl;
  final TextEditingController ageSemainesCtrl;
  final TextEditingController dureeJoursCtrl;
  final TextEditingController dureeSemainesCtrl;
  final TextEditingController lieuCtrl;
  final TextEditingController descCtrl;

  _EtapeCtrl()
      : produitCtrl      = TextEditingController(),
        dosageCtrl       = TextEditingController(),
        offsetCtrl       = TextEditingController(text: '0'),
        ageSemainesCtrl  = TextEditingController(text: '3'),
        dureeJoursCtrl   = TextEditingController(text: '1'),
        dureeSemainesCtrl= TextEditingController(text: '1'),
        lieuCtrl         = TextEditingController(),
        descCtrl         = TextEditingController();

  _EtapeCtrl.fromData(Map<String, dynamic> d)
      : typeActe          = d['type_acte']   ?? 'vermifuge',
        direction         = d['offset_direction'] ?? 'apres',
        frequence         = d['frequence']   ?? 'ponctuel',
        nbFoisSemaine     = (d['nb_fois_semaine'] as num? ?? 1).toInt(),
        isRecurrent       = d['is_recurrent'] == true,
        trancheHoraire    = d['tranche_horaire'] as String?,
        existingId        = d['id'] as String?,
        produitCtrl       = TextEditingController(text: d['produit'] ?? ''),
        dosageCtrl        = TextEditingController(text: d['dosage'] ?? ''),
        offsetCtrl        = TextEditingController(text: '${d['jour_offset'] ?? 0}'),
        ageSemainesCtrl   = TextEditingController(text: '${d['age_min_semaines'] ?? 3}'),
        dureeJoursCtrl    = TextEditingController(text: '${d['duree_jours'] ?? 1}'),
        dureeSemainesCtrl = TextEditingController(text: '${d['duree_semaines'] ?? 1}'),
        lieuCtrl          = TextEditingController(text: d['lieu'] ?? ''),
        descCtrl          = TextEditingController(text: d['description'] ?? '');

  Map<String, dynamic> toMap({bool isBebes = false}) => {
    if (existingId != null) 'id': existingId,
    'type_acte':        typeActe,
    'offset_direction': direction,
    'jour_offset':      int.tryParse(offsetCtrl.text) ?? 0,
    'age_min_semaines': isBebes ? int.tryParse(ageSemainesCtrl.text) : null,
    'produit':          produitCtrl.text.trim().isEmpty  ? null : produitCtrl.text.trim(),
    'dosage':           dosageCtrl.text.trim().isEmpty   ? null : dosageCtrl.text.trim(),
    'frequence':        frequence,
    'nb_fois_semaine':  nbFoisSemaine,
    'is_recurrent':     isRecurrent,
    'duree_semaines':   isRecurrent ? 52 : (int.tryParse(dureeSemainesCtrl.text) ?? 1),
    'duree_jours':      int.tryParse(dureeJoursCtrl.text) ?? 1,
    'lieu':             lieuCtrl.text.trim().isEmpty ? null : lieuCtrl.text.trim(),
    'description':      descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    'tranche_horaire':  trancheHoraire,
  };

  void dispose() {
    produitCtrl.dispose(); dosageCtrl.dispose(); offsetCtrl.dispose();
    ageSemainesCtrl.dispose(); dureeJoursCtrl.dispose(); dureeSemainesCtrl.dispose();
    lieuCtrl.dispose(); descCtrl.dispose();
  }
}

// ─── Widgets réutilisables ────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
  );
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF0C5C6C))),
  );
}

class _Chip extends StatelessWidget {
  final String emoji, label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.emoji, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0C5C6C) : Colors.white,
        border: Border.all(color: active ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$emoji $label', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : const Color(0xFF1F2A2E))),
    ),
  );
}

class _RadioTile extends StatelessWidget {
  final String emoji, title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _RadioTile({required this.emoji, required this.title, required this.subtitle, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE0F2F1) : const Color(0xFFF8F8F6),
        border: Border.all(color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade200, width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: selected ? const Color(0xFF063D4A) : const Color(0xFF1F2A2E))),
              Text(subtitle, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
            ],
          )),
          if (selected) const Icon(Icons.check_circle, color: Color(0xFF0C5C6C), size: 18),
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  const _Field({required this.controller, required this.label, this.hint, this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller, maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      labelStyle: const TextStyle(fontFamily: 'Galey'),
      hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
      filled: true, fillColor: const Color(0xFFF8F8F6),
    ),
    style: const TextStyle(fontFamily: 'Galey'),
  );
}

class _DropField extends StatelessWidget {
  final String label, value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  const _DropField({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value, items: items, onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(fontFamily: 'Galey'),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
      filled: true, fillColor: const Color(0xFFF8F8F6),
    ),
  );
}
