// État des chaleurs d'une femelle pour Mes animaux (filtres + étiquettes) :
//   • en chaleurs : une chaleur notée a commencé et n'est pas finie — date de
//     fin saisie, sinon durée saisie (« 18 jours »), sinon durée habituelle ;
//   • à vérifier  : prochaines chaleurs (dernières + intervalle) dans les 7
//     jours ou dépassées, sans nouvelle chaleur notée.
// Miroir appli : lib/utils/chaleurs_etat.dart.

const DUREE_CHALEURS: Record<string, number> = { chien: 21, chat: 7, cheval: 6, ovin: 2, caprin: 2, porcin: 3 };
const RETARD_MAX_JOURS = 90;
const jour = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

export function dureeChaleursJours(espece: string) { return DUREE_CHALEURS[espece.toLowerCase()] ?? 7; }

export function estEnChaleurs(debut: Date | null, fin: Date | null, dureeTexte: string | null | undefined, espece: string, now = new Date()) {
  if (!debut) return false;
  const j = jour(now), d = jour(debut);
  if (d > j) return false;
  const duree = parseInt((dureeTexte ?? '').match(/\d+/)?.[0] ?? '', 10);
  const finEff = fin ? jour(fin) : new Date(d.getTime() + ((Number.isFinite(duree) ? duree : dureeChaleursJours(espece)) - 1) * 86400000);
  return j <= finEff;
}

export function chaleursAVerifier(derniere: Date | null, intervalle: number, now = new Date()) {
  if (!derniere || intervalle <= 0) return false;
  const ecart = Math.floor((derniere.getTime() + intervalle * 86400000 - now.getTime()) / 86400000);
  return ecart <= 7 && ecart >= -RETARD_MAX_JOURS;
}
