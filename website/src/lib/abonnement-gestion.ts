// Gestion des abonnements par le pro (serveur) : plan du profil activé /
// retiré (pause, grâce dépassée, reprise), e-mails et notifications liés à
// l'abonnement. Utilisé par /api/stripe/abonnement, /api/abonnement/email et
// le webhook Stripe. Migration : migration_abonnements_gestion.sql.
import type { SupabaseClient } from '@supabase/supabase-js';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';

export const SITE = process.env.NEXT_PUBLIC_SITE_URL || 'https://petsmatchapp.com';

export interface LigneAbonnement {
  id: string; uid: string; profile_id: string | null; profil_type: string | null;
  plan_code: string | null; periodicite: string | null; statut: string;
  stripe_subscription_id: string | null; date_fin: string | null;
  resiliation_prevue?: boolean | null; pause_jusquau?: string | null; grace_jusquau?: string | null;
}

export const libellePlan = (code?: string | null) => ({
  premium: 'Premium', pro: 'Pro', clinique: 'Clinique', avance: 'Avancé', essentiel: 'Essentiel', free: 'Découverte',
} as Record<string, string>)[code ?? ''] ?? (code || 'Abonnement');

/** Page de la formule (changer de formule) selon le métier. */
export function pageFormule(profilType?: string | null): string {
  const m: Record<string, string> = {
    garde: '/garde/abonnement', education: '/education/abonnement', pension: '/pension/abonnement',
    photographe: '/photographe/abonnement', sante: '/sante/abonnement', toilettage: '/toilettage/abonnement',
    veterinaire: '/veterinaire/abonnement', marechal_ferrant: '/marechal-ferrant/abonnement',
  };
  return m[profilType ?? ''] ?? '/abonnement';
}

/** Plan payé appliqué au profil (true) ou retiré, profil repassé en gratuit (false). */
export async function appliquerPlan(supabase: SupabaseClient, a: LigneAbonnement, actif: boolean, dateFin?: string | null) {
  const plan = actif ? (a.plan_code ?? 'free') : 'free';
  const maj = { plan_code: plan, is_premium: actif && plan === 'premium', plan_until: actif ? (dateFin ?? a.date_fin) : null };
  if (a.profile_id) await supabase.from('user_profiles').update(maj).eq('id', a.profile_id);
  else await supabase.from('user_profiles').update(maj).eq('uid', a.uid).eq('is_main', true);
  await supabase.from('users').update({ plan_code: plan, is_premium: maj.is_premium }).eq('uid', a.uid);
}

export type TypeMessage = 'renouvellement' | 'fin_resiliation' | 'resiliation' | 'pause' | 'reprise'
  | 'paiement_refuse' | 'suspendu' | 'carte_expire' | 'paiement_ok';

const fr = (iso?: string | null) => iso ? new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : '';

/** Titre et texte du message (notification + e-mail). */
export function messageAbonnement(type: TypeMessage, o: { plan: string; date?: string | null; montant?: string | null; jours?: number }) {
  const d = fr(o.date);
  switch (type) {
    case 'renouvellement': return {
      titre: `Votre abonnement ${o.plan} se renouvelle ${o.jours === 7 ? 'dans 7 jours' : 'dans 30 jours'}`,
      texte: `Votre abonnement annuel ${o.plan} sera renouvelé automatiquement le ${d}${o.montant ? ` (${o.montant})` : ''}. Rien à faire si vous souhaitez continuer. Vous pouvez aussi changer de formule ou ne pas renouveler depuis « Mon abonnement ».`,
    };
    case 'fin_resiliation': return {
      titre: `Votre abonnement ${o.plan} se termine dans 3 jours`,
      texte: `Comme demandé, votre abonnement ${o.plan} s'arrête le ${d}. Vous gardez toutes vos fonctionnalités jusque-là, puis votre profil passe en formule Découverte (vos données sont conservées). Vous pouvez encore annuler la résiliation depuis « Mon abonnement ».`,
    };
    case 'resiliation': return {
      titre: 'Résiliation enregistrée',
      texte: `Votre abonnement ${o.plan} ne sera pas renouvelé. Vous gardez toutes vos fonctionnalités jusqu'au ${d}. Vous pouvez annuler la résiliation à tout moment d'ici là depuis « Mon abonnement ».`,
    };
    case 'pause': return {
      titre: 'Abonnement mis en pause',
      texte: `Votre abonnement ${o.plan} est en pause jusqu'au ${d} : aucun prélèvement pendant la pause. Votre profil passe en formule Découverte et toutes vos données sont conservées. L'abonnement reprend automatiquement le ${d}, ou plus tôt depuis « Mon abonnement ».`,
    };
    case 'reprise': return {
      titre: 'Abonnement repris',
      texte: `Votre abonnement ${o.plan} a repris : toutes vos fonctionnalités sont de nouveau disponibles.`,
    };
    case 'paiement_refuse': return {
      titre: 'Prélèvement refusé',
      texte: `Le prélèvement de votre abonnement ${o.plan}${o.montant ? ` (${o.montant})` : ''} n'a pas abouti. Mettez à jour votre carte avant le ${d} pour garder vos fonctionnalités ; passé ce délai, votre profil passera en formule Découverte (vos données sont conservées).`,
    };
    case 'suspendu': return {
      titre: 'Abonnement suspendu',
      texte: `Le paiement de votre abonnement ${o.plan} n'a toujours pas pu être effectué : votre profil est passé en formule Découverte. Vos données sont conservées ; mettez à jour votre carte pour tout retrouver immédiatement.`,
    };
    case 'carte_expire': return {
      titre: 'Votre carte arrive à expiration',
      texte: `La carte utilisée pour votre abonnement ${o.plan} expire bientôt. Mettez-la à jour pour éviter un refus de prélèvement.`,
    };
    case 'paiement_ok': return {
      titre: 'Paiement reçu',
      texte: `Le paiement de votre abonnement ${o.plan} a bien été effectué : toutes vos fonctionnalités sont disponibles.`,
    };
  }
}

/** Notification dans l'appli + e-mail au pro (adresse de son compte). */
export async function prevenirPro(supabase: SupabaseClient, a: LigneAbonnement, type: TypeMessage,
  o: { date?: string | null; montant?: string | null; jours?: number } = {}) {
  const plan = libellePlan(a.plan_code);
  const m = messageAbonnement(type, { plan, ...o });
  await supabase.from('notifications').insert({
    uid: a.uid, type: 'abonnement_gestion', title: m.titre, body: m.texte,
    data: { abonnementId: a.id, action: type, profilType: a.profil_type, url: '/mon-abonnement' }, read: false,
    ...(a.profile_id ? { profile_id: a.profile_id } : {}),
  });
  const { data: u } = await supabase.from('users').select('email').eq('uid', a.uid).maybeSingle();
  const email = (u as { email?: string | null } | null)?.email;
  if (!email) return;
  const { data: p } = await supabase.from('user_profiles').select('firstname').eq('uid', a.uid).eq('is_main', true).maybeSingle();
  const prenom = (p as { firstname?: string | null } | null)?.firstname ?? '';
  const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:22px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:20px;font-weight:700;margin:0;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.85);font-size:13px;margin:6px 0 0;">${m.titre}</p>
    </div>
    <div style="padding:26px 32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 14px;">Bonjour${prenom ? ` ${prenom}` : ''},</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 20px;">${m.texte}</p>
      <div style="text-align:center;margin-bottom:16px;">
        <a href="${SITE}/mon-abonnement" style="display:inline-block;background:#0C5C6C;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;padding:11px 28px;border-radius:12px;">Mon abonnement</a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">Message automatique de PetsMatch concernant votre abonnement.</p>
    </div>
  </div>
</body></html>`;
  try {
    await mailTransporter.sendMail({ from: MAIL_FROM, to: email, subject: `${m.titre} — PetsMatch`, html });
  } catch (e) {
    console.error('[abonnement] e-mail', type, e);
  }
}
