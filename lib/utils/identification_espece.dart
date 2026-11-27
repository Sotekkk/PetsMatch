// Identification obligatoire avant une cession, selon l'espèce : libellé,
// exemple, clavier et contrôle du format. Miroir site :
// website/src/lib/identification-espece.ts.
class RegleIdentification {
  final String libelle;
  final String exemple;
  final String aide;
  final bool numerique;
  const RegleIdentification({required this.libelle, required this.exemple, required this.aide, this.numerique = false});
}

String _esp(String? espece) => (espece ?? '').toLowerCase().trim();

RegleIdentification regleIdentification(String? espece) {
  switch (_esp(espece)) {
    case 'chien':
    case 'chat':
    case 'furet':
      return const RegleIdentification(
        libelle: 'N° de puce électronique (ou tatouage)',
        exemple: '250269812345678',
        aide: "Chiens, chats et furets doivent être identifiés avant toute cession, même gratuite (I-CAD). "
            'Puce : 15 chiffres ; ancien tatouage : lettres et chiffres.',
        numerique: true,
      );
    case 'cheval':
    case 'ane':
    case 'âne':
    case 'equide':
    case 'poney':
      return const RegleIdentification(
        libelle: 'N° UELN / SIRE ou n° de puce',
        exemple: '250001A12345678',
        aide: "Les équidés doivent être identifiés (SIRE) avant toute cession : n° UELN ou puce, 15 caractères.",
      );
    case 'ovin':
    case 'caprin':
    case 'porcin':
    case 'bovin':
      return const RegleIdentification(
        libelle: "N° de boucle d'identification",
        exemple: 'FR 1234567890',
        aide: "Les animaux de rente doivent porter leur identification officielle (boucle) avant toute cession.",
      );
    case 'oiseau':
      return const RegleIdentification(
        libelle: 'N° de bague',
        exemple: 'FR 123 AB 2024',
        aide: "Indiquez le n° de bague de l'oiseau (ou son n° de puce) : il figure sur le certificat de cession.",
      );
    default:
      return const RegleIdentification(
        libelle: "N° d'identification (puce, tatouage, bague…)",
        exemple: '250269812345678',
        aide: "Indiquez le n° d'identification de l'animal : il figure sur le certificat de cession.",
      );
  }
}

/// Valeur enregistrée : sans espaces, en majuscules.
String normaliserIdentification(String v) => v.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// Message d'erreur, ou null si le format convient à l'espèce.
String? erreurIdentification(String? espece, String valeur) {
  final v = normaliserIdentification(valeur);
  if (v.isEmpty) return "L'identification est obligatoire pour céder l'animal.";
  switch (_esp(espece)) {
    case 'chien':
    case 'chat':
    case 'furet':
      if (RegExp(r'^\d+$').hasMatch(v)) {
        return v.length == 15 ? null : 'Un n° de puce compte 15 chiffres (${v.length} saisis).';
      }
      return RegExp(r'^[A-Z0-9]{3,10}$').hasMatch(v) ? null : 'Format attendu : puce de 15 chiffres ou tatouage (lettres et chiffres).';
    case 'cheval':
    case 'ane':
    case 'âne':
    case 'equide':
    case 'poney':
      return RegExp(r'^[A-Z0-9]{15}$').hasMatch(v) ? null : 'Un n° UELN ou de puce compte 15 caractères (${v.length} saisis).';
    case 'ovin':
    case 'caprin':
    case 'porcin':
    case 'bovin':
      return v.length >= 5 ? null : "N° de boucle trop court.";
    default:
      return v.length >= 3 ? null : "N° d'identification trop court.";
  }
}
