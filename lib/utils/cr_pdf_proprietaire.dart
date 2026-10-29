// Côté propriétaire : compte rendu vétérinaire téléchargeable en PDF (e-mail
// perdu…). Même PDF que celui envoyé par le vétérinaire (en-tête du cabinet,
// patient, propriétaire), sans la signature manuscrite, qui n'est lisible
// que par le vétérinaire. Miroir site : « Télécharger le PDF » (VetDocCard,
// mes-animaux).

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart' show compteRenduPdfBytes, ageAnimal, sexeAnimal;

Future<void> telechargerCompteRenduProprietaire(BuildContext context, Map<String, dynamic> cr) async {
  final supa = Supabase.instance.client;
  String s(dynamic v) => v?.toString().trim() ?? '';
  try {
    final animal = await supa.from('animaux')
        .select('nom, espece, race, sexe, date_naissance, age_estime, identification, uid_proprietaire')
        .eq('id', cr['animal_id']).maybeSingle() ?? {};
    Map<String, dynamic>? pro;
    if (cr['pro_profile_id'] != null) {
      pro = await supa.from('user_profiles_complet')
          .select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, telephone, email_contact')
          .eq('id', cr['pro_profile_id']).maybeSingle();
    }
    var proprio = '';
    if (s(animal['uid_proprietaire']).isNotEmpty) {
      final u = await supa.from('users_complet').select('firstname, lastname').eq('uid', animal['uid_proprietaire']).maybeSingle();
      proprio = '${s(u?['firstname'])} ${s(u?['lastname'])}'.trim();
    }
    final adresse = (s(pro?['rue_pro']).isNotEmpty || s(pro?['ville_pro']).isNotEmpty)
        ? [s(pro?['rue_pro']), '${s(pro?['code_postal_pro'])} ${s(pro?['ville_pro'])}'.trim()]
        : [s(pro?['rue']), '${s(pro?['code_postal'])} ${s(pro?['ville'])}'.trim()];
    final bytes = await compteRenduPdfBytes(
      cliniqueNom: s(pro?['nom']).isNotEmpty ? s(pro?['nom']) : 'Cabinet vétérinaire',
      cliniqueAdresse: adresse.where((x) => x.isNotEmpty).join(', '),
      cliniqueTel: [pro?['phone_number'], pro?['phone'], pro?['telephone']].map(s).firstWhere((x) => x.isNotEmpty, orElse: () => ''),
      cliniqueEmail: s(pro?['email_contact']),
      praticien: '${s(pro?['firstname'])} ${s(pro?['lastname'])}'.trim(),
      animalNom: s(animal['nom']).isNotEmpty ? s(animal['nom']) : 'Animal',
      animalEspeceRace: [s(animal['espece']), s(animal['race'])].where((x) => x.isNotEmpty).join(' · '),
      animalSexe: sexeAnimal(animal['sexe']),
      animalAge: ageAnimal(animal['date_naissance'], animal['age_estime']),
      animalIdentification: s(animal['identification']),
      proprietaire: proprio,
      contenu: s(cr['contenu']),
      date: DateTime.tryParse(s(cr['created_at']))?.toLocal(),
    );
    final jour = s(cr['created_at']).split('T').first;
    await Printing.sharePdf(bytes: bytes, filename: 'Compte-rendu-${s(animal['nom']).replaceAll(' ', '_')}-$jour.pdf');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF indisponible : $e', style: const TextStyle(fontFamily: 'Galey'))));
    }
  }
}
