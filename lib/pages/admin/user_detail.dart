import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserDetail extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;

  const UserDetail({super.key, required this.uid, required this.data});

  @override
  State<UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<UserDetail> {
  bool _isLoading = false;
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
  }

  Future<void> _saveField(String field, dynamic value) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({field: value});
      setState(() => _data[field] = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modifié avec succès.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editTextField(String label, String field, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF8F8F6),
        title: Text(
          'Modifier $label',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFA7C79A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA7C79A)),
            onPressed: () {
              Navigator.pop(ctx);
              _saveField(field, controller.text.trim());
            },
            child: const Text('Enregistrer',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _confirmToggle(String label, String field, bool current) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF8F8F6),
        title: Text(
          current ? 'Désactiver $label ?' : 'Activer $label ?',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  current ? Colors.red : Colors.green,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _saveField(field, !current);
            },
            child: Text(current ? 'Désactiver' : 'Activer',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name =
        '${_data['firstname'] ?? ''} ${_data['lastname'] ?? ''}'.trim();
    final ppUrl = _data['profilePictureUrl'] ?? '';
    final ppElevageUrl = _data['profilePictureUrlElevage'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Profil utilisateur',
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + nom
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage:
                              ppUrl.isNotEmpty ? NetworkImage(ppUrl) : null,
                          backgroundColor:
                              const Color(0xFFA7C79A),
                          child: ppUrl.isEmpty
                              ? const Icon(Icons.person,
                                  size: 48, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          name.isNotEmpty ? name : 'Nom inconnu',
                          style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          _data['email'] ?? '',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Rôles & accès
                  _SectionTitle('Rôles & accès'),
                  _ToggleRow(
                    icon: Icons.admin_panel_settings,
                    label: 'Admin',
                    value: _data['isAdmin'] ?? false,
                    onTap: () => _confirmToggle(
                        'Admin', 'isAdmin', _data['isAdmin'] ?? false),
                  ),
                  _ToggleRow(
                    icon: Icons.check_circle,
                    label: 'Compte validé',
                    value: _data['isValidate'] ?? false,
                    onTap: () => _confirmToggle('Compte validé', 'isValidate',
                        _data['isValidate'] ?? false),
                  ),
                  _ToggleRow(
                    icon: Icons.pets,
                    label: 'Éleveur',
                    value: _data['isElevage'] ?? false,
                    onTap: () => _confirmToggle(
                        'Éleveur', 'isElevage', _data['isElevage'] ?? false),
                  ),
                  _ToggleRow(
                    icon: Icons.work,
                    label: 'Professionnel',
                    value: _data['isPro'] ?? false,
                    onTap: () => _confirmToggle(
                        'Professionnel', 'isPro', _data['isPro'] ?? false),
                  ),
                  const SizedBox(height: 20),

                  // Informations personnelles
                  _SectionTitle('Informations personnelles'),
                  _EditableRow(
                    icon: Icons.person,
                    label: 'Prénom',
                    value: _data['firstname'] ?? '',
                    onTap: () => _editTextField(
                        'Prénom', 'firstname', _data['firstname'] ?? ''),
                  ),
                  _EditableRow(
                    icon: Icons.person_outline,
                    label: 'Nom',
                    value: _data['lastname'] ?? '',
                    onTap: () => _editTextField(
                        'Nom', 'lastname', _data['lastname'] ?? ''),
                  ),
                  _EditableRow(
                    icon: Icons.email,
                    label: 'Email',
                    value: _data['email'] ?? '',
                    onTap: () => _editTextField(
                        'Email', 'email', _data['email'] ?? ''),
                  ),
                  _EditableRow(
                    icon: Icons.phone,
                    label: 'Téléphone',
                    value:
                        '${_data['codeISO'] ?? ''} ${_data['phone_number'] ?? ''}',
                    onTap: () => _editTextField('Téléphone', 'phone_number',
                        _data['phone_number'] ?? ''),
                  ),
                  if (!(_data['isElevage'] ?? false) &&
                      !(_data['isPro'] ?? false)) ...[
                    _EditableRow(
                      icon: Icons.signpost,
                      label: 'Rue',
                      value: _data['rue'] ?? '',
                      onTap: () => _editTextField('Rue', 'rue', _data['rue'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.location_city,
                      label: 'Ville',
                      value: _data['ville'] ?? '',
                      onTap: () => _editTextField('Ville', 'ville', _data['ville'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.markunread_mailbox,
                      label: 'Code postal',
                      value: _data['codePostal'] ?? '',
                      onTap: () => _editTextField('Code postal', 'codePostal', _data['codePostal'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.flag,
                      label: 'Pays',
                      value: _data['pays'] ?? '',
                      onTap: () => _editTextField('Pays', 'pays', _data['pays'] ?? ''),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Élevage / Entreprise
                  if ((_data['isElevage'] ?? false) ||
                      (_data['isPro'] ?? false)) ...[
                    _SectionTitle('Élevage / Entreprise'),
                    _EditableRow(
                      icon: Icons.business,
                      label: 'Nom structure',
                      value: _data['nameElevage'] ?? '',
                      onTap: () => _editTextField('Nom structure',
                          'nameElevage', _data['nameElevage'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.numbers,
                      label: 'SIRET',
                      value: _data['siret'] ?? '',
                      onTap: () => _editTextField(
                          'SIRET', 'siret', _data['siret'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.receipt,
                      label: 'N° TVA',
                      value: _data['numeroTVA'] ?? '',
                      onTap: () => _editTextField(
                          'N° TVA', 'numeroTVA', _data['numeroTVA'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.signpost,
                      label: 'Rue',
                      value: _data['rueElevage'] ?? '',
                      onTap: () => _editTextField('Rue', 'rueElevage', _data['rueElevage'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.location_city,
                      label: 'Ville',
                      value: _data['villeElevage'] ?? '',
                      onTap: () => _editTextField('Ville', 'villeElevage', _data['villeElevage'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.markunread_mailbox,
                      label: 'Code postal',
                      value: _data['codePostalElevage'] ?? '',
                      onTap: () => _editTextField('Code postal', 'codePostalElevage', _data['codePostalElevage'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.flag,
                      label: 'Pays',
                      value: _data['paysElevage'] ?? '',
                      onTap: () => _editTextField('Pays', 'paysElevage', _data['paysElevage'] ?? ''),
                    ),
                    _EditableRow(
                      icon: Icons.description,
                      label: 'Description',
                      value: _data['descEntreprise'] ?? '',
                      onTap: () => _editTextField('Description',
                          'descEntreprise', _data['descEntreprise'] ?? ''),
                    ),
                    if (ppElevageUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Photo élevage',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontFamily: 'Galey')),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          ppElevageUrl,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  // UID (lecture seule)
                  _SectionTitle('Technique'),
                  _InfoRow(Icons.fingerprint, 'UID', widget.uid),
                  _InfoRow(Icons.calendar_today, 'Date de naissance',
                      _data['dateofbirth'] ?? ''),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Color(0xFF6E9E57),
        ),
      ),
    );
  }
}

class _EditableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _EditableRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    value.isNotEmpty ? value : '—',
                    style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback onTap;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: value
                    ? Colors.green.withOpacity(0.15)
                    : Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                value ? 'Actif' : 'Inactif',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w500,
                  color: value ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
