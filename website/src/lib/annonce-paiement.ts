// Modification / renouvellement d'une annonce publiée (côté navigateur) :
// /api/annonces/modifier applique les changements gratuits (photos,
// disponibilité) et renvoie l'URL de paiement Stripe pour le reste (4,99 €).
// Miroir appli : lib/services/annonce_paiement.dart.

import { apiFetch } from '@/lib/api-fetch';

export type TableAnnonce = 'annonces' | 'annonces_objets';

async function appeler(body: Record<string, unknown>): Promise<{ applique?: boolean; url?: string; prix?: number; error?: string }> {
  const res = await apiFetch('/api/annonces/modifier', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  return res.json();
}

const prixTexte = (p?: number) => `${(p ?? 4.99).toFixed(2).replace('.', ',')} €`;

/** true = enregistré ; false = annulé ou redirection vers le paiement. Lève une erreur sinon. */
export async function enregistrerModificationAnnonce(table: TableAnnonce, id: string, changements: Record<string, unknown>): Promise<boolean> {
  const r = await appeler({ table, id, action: 'modification', changements });
  if (r.error) throw new Error(r.error);
  if (r.applique) return true;
  if (r.url) {
    const ok = confirm(`Cette modification est payante (${prixTexte(r.prix)}).\nLes photos et la disponibilité restent gratuites.\n\nVos changements seront appliqués dès le paiement. Continuer vers le paiement ?`);
    if (ok) window.location.href = r.url;
  }
  return false;
}

export async function renouvelerAnnonce(table: TableAnnonce, id: string): Promise<void> {
  if (!confirm(`Renouveler l'annonce pour 30 jours (${prixTexte()}) ?
Paiement sécurisé sur la page suivante.`)) return;
  const r = await appeler({ table, id, action: 'renouvellement' });
  if (r.error) throw new Error(r.error);
  if (r.url) window.location.href = r.url;
}
