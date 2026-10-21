part of 'employes_page.dart';

// ─── Équipe de l'association (employés + bénévoles) ──────────────────────────
// Miroir site : website/src/app/association/equipe/page.tsx — mêmes filtres
// (Tous / Employés / Bénévoles, recherche, statut), mêmes libellés et mêmes
// actions (+ Tâche, Congé, Modifier, menu : accès, désactiver, supprimer).
// Tout est lu / écrit dans le contexte du profil d'association (eleveur_profile_id).

class _EquipeAssociationTab extends StatefulWidget {
  final Color teal, dark, bg;
  const _EquipeAssociationTab({required this.teal, required this.dark, required this.bg});
  @override
  State<_EquipeAssociationTab> createState() => _EquipeAssociationTabState();
}

class _EquipeAssociationTabState extends State<_EquipeAssociationTab> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  final _rechercheCtrl = TextEditingController();
  String? _ownerUid;
  String? _profileId;
  String _nomAsso = '';
  bool _loading = true;
  List<Map<String, dynamic>> _membres = [];
  final Set<String> _deplies = {};
  String _role = 'tous';      // 'tous' | 'employe' | 'benevole'
  String _statut = 'actifs';  // 'actifs' | 'inactifs' | 'tous'

  static const _gris = Color(0xFF6F767B);
  static const _bordure = Color(0xFFE4E7EB);

  @override
  void initState() {
    super.initState();
    _rechercheCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final ownerUid = await _resolveOwnerUid(_supa, _uid);
      final profileId = await _resolveOwnerProfileId(_supa, ownerUid, true);
      _ownerUid = ownerUid;
      _profileId = profileId;

      final asso = profileId != null
          ? await _supa.from('user_profiles_complet').select('nom').eq('id', profileId).maybeSingle()
          : null;
      _nomAsso = ((asso?['nom'] as String?) ?? '').trim();

      // Actifs ET inactifs (filtre « Statut ») de l'association active.
      var q = _supa.from('employes').select().eq('profil_source', 'association');
      q = profileId != null ? q.eq('eleveur_profile_id', profileId) : q.eq('uid_eleveur', ownerUid);
      final rows = List<Map<String, dynamic>>.from(await q.order('created_at'));

      final uids = rows.map((e) => e['uid_employe'] as String?).whereType<String>().where((u) => u.isNotEmpty).toSet().toList();
      final profilsParUid = <String, Map<String, dynamic>>{};
      final tachesParUid = <String, int>{};
      if (uids.isNotEmpty) {
        final profils = await _supa.from('user_profiles_complet')
            .select('uid, firstname, lastname, avatar_url')
            .inFilter('uid', uids).eq('is_main', true) as List;
        for (final p in profils) {
          profilsParUid[p['uid'] as String] = Map<String, dynamic>.from(p as Map);
        }
        // Tâches en cours POUR cette association (anciennes tâches sans
        // profil comprises), comme sur le site.
        var tq = _supa.from('taches_elevage').select('assigne_a')
            .inFilter('assigne_a', uids).eq('uid_eleveur', ownerUid)
            .eq('profil_source', 'association').neq('statut', 'fait');
        var pq = _supa.from('plan_taches').select('assigned_to')
            .inFilter('assigned_to', uids).eq('uid_eleveur', ownerUid)
            .eq('profil_source', 'association').neq('statut', 'fait');
        if (profileId != null) {
          tq = tq.or('eleveur_profile_id.eq.$profileId,eleveur_profile_id.is.null');
          pq = pq.or('eleveur_profile_id.eq.$profileId,eleveur_profile_id.is.null');
        }
        final res = await Future.wait([tq, pq]);
        for (final t in res[0] as List) {
          final u = t['assigne_a'] as String?;
          if (u != null) tachesParUid[u] = (tachesParUid[u] ?? 0) + 1;
        }
        for (final t in res[1] as List) {
          final u = t['assigned_to'] as String?;
          if (u != null) tachesParUid[u] = (tachesParUid[u] ?? 0) + 1;
        }
      }

      final membres = rows.map((e) {
        final uidEmploye = (e['uid_employe'] as String?) ?? '';
        final u = profilsParUid[uidEmploye];
        final manuel = '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim();
        final nomCompte = u != null ? '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim() : '';
        final type = e['type'] == 'benevole' ? 'benevole' : 'employe';
        return {
          ...e,
          '_nom': nomCompte.isNotEmpty ? nomCompte : (manuel.isNotEmpty ? manuel : (type == 'benevole' ? 'Bénévole' : 'Employé')),
          '_photo': u?['avatar_url'] as String?,
          '_type': type,
          '_taches': tachesParUid[uidEmploye] ?? 0,
        };
      }).toList();

      if (mounted) setState(() { _membres = membres; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filtres ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _visibles {
    final q = _rechercheCtrl.text.trim().toLowerCase();
    return _membres.where((m) {
      final actif = m['actif'] == true;
      if (_statut == 'actifs' && !actif) return false;
      if (_statut == 'inactifs' && actif) return false;
      if (q.isEmpty) return true;
      return '${m['_nom']} ${m['email'] ?? ''} ${m['telephone'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _ouvrirRecherche(String type) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEmployeSheet(uid: _ownerUid ?? _uid, nomElevage: _nomAsso, teal: widget.teal, dark: widget.dark,
          isAssociation: true, type: type),
    );
    _load();
  }

  Future<void> _ouvrirManuel(String type) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEmployeManuelSheet(uid: _ownerUid ?? _uid, teal: widget.teal, profilSource: 'association', type: type),
    );
    _load();
  }

  /// « Ajouter un membre » : rôle, puis recherche PetsMatch ou saisie manuelle.
  void _ajouterMembre() {
    var type = 'employe';
    const roles = [('employe', 'Employé', Icons.badge_outlined), ('benevole', 'Bénévole', Icons.volunteer_activism_outlined)];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Ajouter un membre',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          Row(children: [
            for (final r in roles)
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: r == roles.first ? 6 : 0, left: r == roles.first ? 0 : 6),
                child: GestureDetector(
                  onTap: () => setS(() => type = r.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: type == r.$1 ? widget.teal : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.teal),
                    ),
                    child: Column(children: [
                      Icon(r.$3, color: type == r.$1 ? Colors.white : widget.teal),
                      const SizedBox(height: 4),
                      Text(r.$2, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          color: type == r.$1 ? Colors.white : widget.teal)),
                    ]),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
            icon: Icon(Icons.search, color: widget.teal),
            label: Text('Chercher sur PetsMatch',
                style: TextStyle(fontFamily: 'Galey', color: widget.teal, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: widget.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () { Navigator.pop(ctx); _ouvrirRecherche(type); },
          )),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            label: const Text('Ajouter manuellement',
                style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: widget.teal, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () { Navigator.pop(ctx); _ouvrirManuel(type); },
          )),
        ]),
      ))),
    );
  }

  Future<void> _tache(Map<String, dynamic> m) async {
    // Personnes assignables : la structure (« Moi ») + membres actifs avec compte.
    final assignables = <Map<String, dynamic>>[
      {'uid': _uid, 'nom': _nomAsso.isNotEmpty ? _nomAsso : 'Moi'},
      for (final x in _membres)
        if (x['actif'] == true && ((x['uid_employe'] as String?) ?? '').isNotEmpty && x['uid_employe'] != _uid)
          {'uid': x['uid_employe'], 'nom': x['_nom']},
    ];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddTacheSheet(
        day: DateTime.now(),
        uid: _ownerUid ?? _uid,
        myUid: _uid,
        profileId: _profileId,
        profilSource: 'association',
        employes: assignables,
        initialEmployeUid: m['uid_employe'] as String?,
        onSaved: () {},
      ),
    );
    _load();
  }

  Future<void> _conge(Map<String, dynamic> m) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CongesMembreSheet(membre: m, teal: widget.teal, dark: widget.dark, myUid: _uid),
    );
  }

  Future<void> _modifier(Map<String, dynamic> m) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditMembreSheet(membre: m, teal: widget.teal),
    );
    if (ok == true) _load();
  }

  Future<bool> _confirmer(String titre, String texte, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(texte, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(action, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  color: danger ? Colors.red : widget.teal))),
        ],
      ),
    );
    return ok == true;
  }

  // Désactiver : la personne perd l'accès à l'équipe, ses tâches et congés
  // restent dans l'historique (miroir site).
  Future<void> _desactiver(Map<String, dynamic> m) async {
    final nom = m['_nom'] as String;
    if (!await _confirmer('Désactiver', "Désactiver $nom ? La personne n'aura plus accès à l'équipe. Ses tâches et congés restent dans l'historique.", 'Désactiver')) return;
    await _supa.from('employes').update({'actif': false}).eq('id', m['id']);
    final employeProfileId = m['employe_profile_id'] as String?;
    if ((employeProfileId ?? '').isNotEmpty) {
      try {
        await _supa.from('animaux')
            .update({'chaleurs_responsable_uid': null, 'chaleurs_responsable_profile_id': null})
            .eq('chaleurs_responsable_profile_id', employeProfileId!);
      } catch (_) {}
    }
    final uidEmploye = m['uid_employe'] as String?;
    if ((uidEmploye ?? '').isNotEmpty) {
      await _supa.from('notifications').insert({
        'uid': uidEmploye,
        'type': 'employee_revoked',
        'title': 'Accès retiré',
        'body': "Vous avez été retiré de l'équipe de ${_nomAsso.isNotEmpty ? _nomAsso : "l'association"}",
        if ((employeProfileId ?? '').isNotEmpty) 'profile_id': employeProfileId,
        'data': {'eleveurUid': _uid},
        'read': false,
      });
    }
    _load();
  }

  Future<void> _reactiver(Map<String, dynamic> m) async {
    await _supa.from('employes').update({'actif': true}).eq('id', m['id']);
    _load();
  }

  Future<void> _supprimer(Map<String, dynamic> m) async {
    if (!await _confirmer('Supprimer', "Supprimer ${m['_nom']} de l'équipe ? Cette action est définitive.", 'Supprimer', danger: true)) return;
    await _supa.from('employes').delete().eq('id', m['id']);
    _load();
  }

  Future<void> _acces(Map<String, dynamic> m) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PermissionsSheet(employeId: m['id'].toString(), nom: m['_nom'] as String, teal: widget.teal),
    );
    _load();
  }

  // ── Interface ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final compte = {
      'tous': visibles.length,
      'employe': visibles.where((m) => m['_type'] == 'employe').length,
      'benevole': visibles.where((m) => m['_type'] == 'benevole').length,
    };
    final liste = _role == 'tous' ? visibles : visibles.where((m) => m['_type'] == _role).toList();

    return Container(
      color: widget.bg,
      child: RefreshIndicator(
        onRefresh: _load,
        color: widget.teal,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Gérez les employés et les bénévoles de votre association.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                onPressed: _ajouterMembre,
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: const Text('Ajouter un membre',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
                style: ElevatedButton.styleFrom(backgroundColor: widget.teal, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 16),
            // Filtres de rôle : texte turquoise + soulignement pour l'actif.
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _bordure))),
              child: Row(children: [
                for (final f in const [('tous', 'Tous'), ('employe', 'Employés'), ('benevole', 'Bénévoles')])
                  Expanded(child: InkWell(
                    onTap: () => setState(() => _role = f.$1),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(
                          color: _role == f.$1 ? widget.teal : Colors.transparent, width: 2))),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text('${f.$2} (${compte[f.$1]})',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                              fontWeight: _role == f.$1 ? FontWeight.w700 : FontWeight.w500,
                              color: _role == f.$1 ? widget.teal : _gris))),
                    ),
                  )),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rechercheCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _champ(hint: 'Rechercher un membre', prefix: const Icon(Icons.search, color: _gris, size: 20)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _statut,
              isExpanded: true,
              decoration: _champ(),
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: widget.dark),
              items: const [
                DropdownMenuItem(value: 'actifs', child: Text('Actifs')),
                DropdownMenuItem(value: 'inactifs', child: Text('Inactifs')),
                DropdownMenuItem(value: 'tous', child: Text('Tous les statuts')),
              ],
              onChanged: (v) => setState(() => _statut = v ?? 'actifs'),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            else if (_membres.isEmpty)
              _vide('Aucun membre dans votre équipe', 'Ajoutez un employé ou un bénévole avec « Ajouter un membre ».')
            else if (liste.isEmpty)
              _vide('Aucun membre ne correspond à votre recherche', 'Modifiez la recherche ou les filtres.')
            else
              ...liste.map(_carte),
          ],
        ),
      ),
    );
  }

  InputDecoration _champ({String? hint, Widget? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', color: _gris),
    prefixIcon: prefix,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _bordure)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.teal)),
  );

  Widget _vide(String titre, String texte) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _bordure)),
    child: Column(children: [
      Text(titre, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: widget.dark)),
      const SizedBox(height: 4),
      Text(texte, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _gris)),
    ]),
  );

  Widget _carte(Map<String, dynamic> m) {
    final id = m['id'].toString();
    final nom = m['_nom'] as String;
    final photo = m['_photo'] as String?;
    final actif = m['actif'] == true;
    final aCompte = ((m['uid_employe'] as String?) ?? '').isNotEmpty;
    final nbTaches = m['_taches'] as int;
    final tel = (m['telephone'] as String?)?.trim() ?? '';
    final email = (m['email'] as String?)?.trim() ?? '';
    final notes = (m['notes'] as String?)?.trim() ?? '';
    final deplie = _deplies.contains(id);

    Widget badge(String texte, {bool neutre = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: neutre ? const Color(0xFFF1F2F4) : widget.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texte, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w700,
          color: neutre ? _gris : widget.teal)),
    );

    Widget bouton(String texte, VoidCallback onTap, {IconData? icone, bool principal = false}) => SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icone != null ? Icon(icone, size: 17) : const SizedBox.shrink(),
        label: Text(texte, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5)),
        style: OutlinedButton.styleFrom(
          foregroundColor: principal ? widget.teal : widget.dark,
          side: BorderSide(color: principal ? widget.teal : const Color(0xFFD5D9DE)),
          padding: EdgeInsets.only(left: icone != null ? 10 : 14, right: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );

    Widget info(String libelle, String valeur) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _gris)),
        Text(valeur, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: widget.dark)),
      ]),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordure),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => deplie ? _deplies.remove(id) : _deplies.add(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: widget.teal.withValues(alpha: 0.10),
                backgroundImage: photo != null && photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                child: photo == null || photo.isEmpty
                    ? Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: widget.teal))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(nom, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15.5, color: widget.dark)),
                  badge(m['_type'] == 'benevole' ? 'Bénévole' : 'Employé'),
                  if (!actif) badge('Inactif', neutre: true),
                ]),
                if (tel.isNotEmpty || email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text([tel, email].where((v) => v.isNotEmpty).join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    aCompte ? (nbTaches == 0 ? 'Aucune tâche' : '$nbTaches tâche${nbTaches > 1 ? 's' : ''} en cours') : 'Sans compte PetsMatch',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _gris)),
                ),
              ])),
              Icon(deplie ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: _gris),
            ]),
          ),
        ),
        // Actions sous les informations (mobile), boutons jamais coupés.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 12),
          child: Row(children: [
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (aCompte && actif) bouton('Tâche', () => _tache(m), icone: Icons.add, principal: true),
              bouton('Congé', () => _conge(m)),
            ])),
            IconButton(
              tooltip: 'Modifier',
              onPressed: () => _modifier(m),
              icon: const Icon(Icons.edit_outlined, color: _gris, size: 21),
            ),
            PopupMenuButton<String>(
              tooltip: "Plus d'actions",
              icon: const Icon(Icons.more_horiz, color: _gris),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                switch (v) {
                  case 'acces': _acces(m);
                  case 'desactiver': _desactiver(m);
                  case 'reactiver': _reactiver(m);
                  case 'supprimer': _supprimer(m);
                }
              },
              itemBuilder: (_) => [
                if (aCompte)
                  const PopupMenuItem(value: 'acces', child: Text('Gérer les accès', style: TextStyle(fontFamily: 'Galey'))),
                PopupMenuItem(value: actif ? 'desactiver' : 'reactiver',
                    child: Text(actif ? 'Désactiver' : 'Réactiver', style: const TextStyle(fontFamily: 'Galey'))),
                const PopupMenuItem(value: 'supprimer',
                    child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
              ],
            ),
          ]),
        ),
        if (deplie)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              border: Border(top: BorderSide(color: _bordure)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              info('Téléphone', tel.isNotEmpty ? tel : 'Non renseigné'),
              info('Email', email.isNotEmpty ? email : 'Non renseigné'),
              info('Notes', notes.isNotEmpty ? notes : 'Aucune note'),
              if (aCompte)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: widget.teal, padding: EdgeInsets.zero),
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: const Text('Voir ses tâches', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _EmployeAgendaPage(
                    nom: nom, teal: widget.teal, dark: widget.dark, bg: widget.bg,
                    isAssociation: true,
                    employeUid: m['uid_employe'] as String?, employeProfileId: m['employe_profile_id'] as String?,
                  ))).then((_) => _load()),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ── Modifier un membre (miroir site : EditMembreModal) ───────────────────────
// Prénom / nom modifiables pour un membre saisi à la main seulement.

class _EditMembreSheet extends StatefulWidget {
  final Map<String, dynamic> membre;
  final Color teal;
  const _EditMembreSheet({required this.membre, required this.teal});
  @override
  State<_EditMembreSheet> createState() => _EditMembreSheetState();
}

class _EditMembreSheetState extends State<_EditMembreSheet> {
  late final _prenom = TextEditingController(text: widget.membre['prenom'] as String? ?? '');
  late final _nom    = TextEditingController(text: widget.membre['nom'] as String? ?? '');
  late final _email  = TextEditingController(text: widget.membre['email'] as String? ?? '');
  late final _tel    = TextEditingController(text: widget.membre['telephone'] as String? ?? '');
  late final _notes  = TextEditingController(text: widget.membre['notes'] as String? ?? '');
  bool _saving = false;

  bool get _manuel => ((widget.membre['uid_employe'] as String?) ?? '').isEmpty;

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _email, _tel, _notes]) { c.dispose(); }
    super.dispose();
  }

  String? _val(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _enregistrer() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('employes').update({
        if (_manuel) 'prenom': _val(_prenom),
        if (_manuel) 'nom': _val(_nom),
        'email': _val(_email),
        'telephone': _val(_tel),
        'notes': _val(_notes),
      }).eq('id', widget.membre['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboard, int maxLines = 1}) => TextField(
    controller: ctrl,
    keyboardType: keyboard,
    maxLines: maxLines,
    style: const TextStyle(fontFamily: 'Galey'),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Modifier — ${widget.membre['_nom']}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          if (_manuel) ...[
            Row(children: [
              Expanded(child: _field(_prenom, 'Prénom')),
              const SizedBox(width: 10),
              Expanded(child: _field(_nom, 'Nom')),
            ]),
            const SizedBox(height: 10),
          ],
          _field(_email, 'Email', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field(_tel, 'Téléphone', keyboard: TextInputType.phone),
          const SizedBox(height: 10),
          _field(_notes, 'Notes', maxLines: 3),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: _saving ? null : _enregistrer,
              style: ElevatedButton.styleFrom(backgroundColor: widget.teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ── Congés d'un membre (miroir site : CongeModal) ────────────────────────────
// employe_id = la relation précise (ligne employes) de cette association.

class _CongesMembreSheet extends StatefulWidget {
  final Map<String, dynamic> membre;
  final Color teal, dark;
  final String myUid;
  const _CongesMembreSheet({required this.membre, required this.teal, required this.dark, required this.myUid});
  @override
  State<_CongesMembreSheet> createState() => _CongesMembreSheetState();
}

class _CongesMembreSheetState extends State<_CongesMembreSheet> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _conges = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await _supa.from('employe_conges').select()
        .eq('employe_id', widget.membre['id']).order('date_debut', ascending: false);
    if (!mounted) return;
    setState(() {
      _conges = (rows as List).map((c) => {...Map<String, dynamic>.from(c as Map), '_employe': widget.membre}).toList();
      _loading = false;
    });
  }

  String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _ajouter() async {
    final range = await pickCongeDateRange(context, teal: widget.teal);
    if (range == null) return;
    await _supa.from('employe_conges').insert({
      'employe_id': widget.membre['id'],
      'date_debut': range.start.toIso8601String().substring(0, 10),
      'date_fin': range.end.toIso8601String().substring(0, 10),
      'statut': 'approuve',
      'demande_par_uid': widget.myUid,
    });
    _load();
  }

  Future<void> _repondre(Map<String, dynamic> c, bool approuve) async {
    await repondreConge(_supa, c, approuve, _fmt);
    _load();
  }

  Future<void> _supprimer(Map<String, dynamic> c) async {
    await _supa.from('employe_conges').delete().eq('id', c['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.membre['_nom'] as String;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: [
            Expanded(child: Text('Congés — $nom', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18, color: widget.dark))),
            IconButton(icon: Icon(Icons.close_rounded, color: Colors.grey.shade500), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(height: 44, child: ElevatedButton.icon(
            onPressed: _ajouter,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: widget.teal, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
        ),
        const SizedBox(height: 12),
        Flexible(child: _loading
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : _conges.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Text('Aucun congé enregistré.', textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      for (final c in _conges)
                        _CongeCard(
                          conge: c, nom: nom, dark: widget.dark, teal: widget.teal, fmt: _fmt,
                          onApprouver: c['statut'] == 'en_attente' ? () => _repondre(c, true) : null,
                          onRefuser: c['statut'] == 'en_attente' ? () => _repondre(c, false) : null,
                          onSupprimer: () => _supprimer(c),
                        ),
                    ],
                  )),
      ]),
    );
  }
}
