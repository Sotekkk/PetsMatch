// Identification obligatoire avant une cession, selon l'espèce : libellé,
// exemple, clavier et contrôle du format. Miroir appli :
// lib/utils/identification_espece.dart.

export interface RegleIdentification { libelle: string; exemple: string; aide: string; numerique: boolean }

const esp = (e?: string | null) => (e ?? '').toLowerCase().trim();
const CARNIVORES = ['chien', 'chat', 'furet'];
const EQUIDES = ['cheval', 'ane', 'âne', 'equide', 'poney'];
const RENTE = ['ovin', 'caprin', 'porcin', 'bovin'];

export function regleIdentification(espece?: string | null): RegleIdentification {
  const e = esp(espece);
  if (CARNIVORES.includes(e)) return {
    libelle: 'N° de puce électronique (ou tatouage)', exemple: '250269812345678', numerique: true,
    aide: 'Chiens, chats et furets doivent être identifiés avant toute cession, même gratuite (I-CAD). Puce : 15 chiffres ; ancien tatouage : lettres et chiffres.',
  };
  if (EQUIDES.includes(e)) return {
    libelle: 'N° UELN / SIRE ou n° de puce', exemple: '250001A12345678', numerique: false,
    aide: 'Les équidés doivent être identifiés (SIRE) avant toute cession : n° UELN ou puce, 15 caractères.',
  };
  if (RENTE.includes(e)) return {
    libelle: "N° de boucle d'identification", exemple: 'FR 1234567890', numerique: false,
    aide: "Les animaux de rente doivent porter leur identification officielle (boucle) avant toute cession.",
  };
  if (e === 'oiseau') return {
    libelle: 'N° de bague', exemple: 'FR 123 AB 2024', numerique: false,
    aide: "Indiquez le n° de bague de l'oiseau (ou son n° de puce) : il figure sur le certificat de cession.",
  };
  return {
    libelle: "N° d'identification (puce, tatouage, bague…)", exemple: '250269812345678', numerique: false,
    aide: "Indiquez le n° d'identification de l'animal : il figure sur le certificat de cession.",
  };
}

/** Valeur enregistrée : sans espaces, en majuscules. */
export const normaliserIdentification = (v: string) => v.replace(/\s/g, '').toUpperCase();

/** Message d'erreur, ou null si le format convient à l'espèce. */
export function erreurIdentification(espece: string | null | undefined, valeur: string): string | null {
  const v = normaliserIdentification(valeur);
  if (!v) return "L'identification est obligatoire pour céder l'animal.";
  const e = esp(espece);
  if (CARNIVORES.includes(e)) {
    if (/^\d+$/.test(v)) return v.length === 15 ? null : `Un n° de puce compte 15 chiffres (${v.length} saisis).`;
    return /^[A-Z0-9]{3,10}$/.test(v) ? null : 'Format attendu : puce de 15 chiffres ou tatouage (lettres et chiffres).';
  }
  if (EQUIDES.includes(e)) return /^[A-Z0-9]{15}$/.test(v) ? null : `Un n° UELN ou de puce compte 15 caractères (${v.length} saisis).`;
  if (RENTE.includes(e)) return v.length >= 5 ? null : 'N° de boucle trop court.';
  return v.length >= 3 ? null : "N° d'identification trop court.";
}
