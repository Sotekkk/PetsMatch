'use client';
// « Mon abonnement » — une seule page pour tous les pros (profil actif) :
// formule, mensuel / annuel, prochaine échéance et montant, état ; pause du
// mensuel (3 mois max, pas d'annuel), reprise, résiliation en fin de période
// (et son annulation), changer de formule, carte et factures (portail Stripe).
// Ouverte aussi depuis l'appli (paiement et gestion sur le site).
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { apiFetch } from '@/lib/api-fetch';

const TEAL = '#0C5C6C';

interface Infos {
  plan: string; plan_code: string | null; profil_type: string | null; periodicite: 'mensuel' | 'annuel'; statut: string;
  prochaine_echeance: string | null; montant: number | null; resiliation_prevue: boolean;
  pause_jusquau: string | null; grace_jusquau: string | null;
  carte: { marque: string; fin: string; expire: string } | null; en_ligne: boolean; page_formule: string; pause_max_mois: number;
}

const date = (iso?: string | null) => iso ? new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : '—';
const eur = (v: number | null) => v == null ? '—' : `${v.toFixed(2).replace('.', ',')} €`;

export default function MonAbonnementPage() {
  const { user, loading: authLoading } = useAuth();
  const router = useRouter();
  const { loaded: profilCharge, id: profileId } = useActiveProfileState();
  const [pageFormule, setPageFormule] = useState('/abonnement');
  const [infos, setInfos] = useState<Infos | null | undefined>(undefined);
  const [busy, setBusy] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [mois, setMois] = useState(1);
  const [choixPause, setChoixPause] = useState(false);

  useEffect(() => {
    if (!authLoading && !user) router.push(`/connexion?suite=${encodeURIComponent('/mon-abonnement')}`);
  }, [authLoading, user, router]);

  const appel = useCallback(async (action: string, extra: Record<string, unknown> = {}) => {
    const res = await apiFetch('/api/stripe/abonnement', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, profile_id: profileId || null, ...extra }),
    });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(j.error ?? 'Erreur');
    if (j.page_formule) setPageFormule(j.page_formule);
    return j.abonnement as Infos | null;
  }, [profileId]);

  useEffect(() => {
    if (!user || !profilCharge) return;
    appel('infos').then(setInfos).catch(() => setInfos(null));
  }, [user, profilCharge, appel]);

  async function agir(action: string, texteOk: string, extra: Record<string, unknown> = {}) {
    setBusy(action); setMsg(null);
    try { setInfos(await appel(action, extra)); setMsg({ ok: true, t: texteOk }); setChoixPause(false); }
    catch (e) { setMsg({ ok: false, t: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(''); }
  }

  async function portail() {
    setBusy('portail');
    try {
      const res = await apiFetch('/api/stripe/portal', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnPath: '/mon-abonnement' }),
      });
      const j = await res.json();
      if (j.url) window.location.href = j.url; else setMsg({ ok: false, t: j.error ?? 'Portail indisponible' });
    } finally { setBusy(''); }
  }

  if (authLoading || infos === undefined) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const etat = !infos ? null
    : infos.statut === 'pause' ? { t: `En pause jusqu'au ${date(infos.pause_jusquau)}`, c: 'bg-amber-50 text-amber-800' }
    : infos.statut === 'grace' ? { t: `Prélèvement refusé — mettez à jour votre carte avant le ${date(infos.grace_jusquau)}`, c: 'bg-red-50 text-red-700' }
    : infos.statut === 'suspendu' ? { t: 'Suspendu : paiement à régulariser (profil en formule Découverte)', c: 'bg-red-50 text-red-700' }
    : infos.resiliation_prevue ? { t: `Résilié — accès jusqu'au ${date(infos.prochaine_echeance)}`, c: 'bg-gray-100 text-gray-700' }
    : { t: 'Actif', c: 'bg-green-50 text-green-700' };

  const bouton = (label: string, onClick: () => void, cle: string, principal = false, danger = false) => (
    <button type="button" onClick={onClick} disabled={!!busy}
      className={`w-full py-3 rounded-xl text-sm font-bold disabled:opacity-50 ${principal ? 'text-white' : danger ? 'border border-red-200 text-red-600' : 'border border-gray-200 text-[#1F2A2E]'}`}
      style={principal ? { background: TEAL } : undefined}>
      {busy === cle ? '…' : label}
    </button>
  );

  return (
    <div className="max-w-lg mx-auto px-4 py-8 font-galey">
      <h1 className="text-2xl font-bold mb-5" style={{ color: TEAL }}>Mon abonnement</h1>

      {!infos ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-5 shadow-sm">
          <p className="text-sm text-gray-700">Ce profil est en formule <b>Découverte</b> (gratuite).</p>
          <Link href={pageFormule} className="inline-block mt-3 text-sm font-semibold" style={{ color: TEAL }}>Voir les formules</Link>
        </div>
      ) : (
        <>
          <div className="bg-white rounded-2xl border border-gray-100 p-5 shadow-sm space-y-3">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-lg font-bold text-[#1F2A2E]">{infos.plan}</p>
                <p className="text-sm text-gray-500">{infos.periodicite === 'annuel' ? 'Abonnement annuel' : 'Abonnement mensuel'} · prélèvement automatique</p>
              </div>
              {etat && <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${etat.c}`}>{etat.t}</span>}
            </div>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><p className="text-xs text-gray-400">{infos.resiliation_prevue ? 'Fin de l’accès' : 'Prochaine échéance'}</p><p className="font-semibold">{date(infos.prochaine_echeance)}</p></div>
              <div><p className="text-xs text-gray-400">Montant</p><p className="font-semibold">{eur(infos.montant)} TTC{infos.periodicite === 'annuel' ? ' / an' : ' / mois'}</p></div>
              {infos.carte && <div className="col-span-2"><p className="text-xs text-gray-400">Carte</p><p className="font-semibold capitalize">{infos.carte.marque} •••• {infos.carte.fin} — expire {infos.carte.expire}</p></div>}
            </div>
          </div>

          {msg && <p className={`mt-4 text-sm ${msg.ok ? 'text-[#5B8648]' : 'text-red-600'}`}>{msg.t}</p>}

          {infos.en_ligne ? (
            <div className="mt-5 space-y-2.5">
              {infos.statut === 'pause' && bouton("Reprendre l'abonnement maintenant", () => agir('reprendre', 'Abonnement repris : toutes vos fonctionnalités sont de nouveau disponibles.'), 'reprendre', true)}
              {(infos.statut === 'grace' || infos.statut === 'suspendu') && bouton('Mettre à jour ma carte', portail, 'portail', true)}
              {bouton('Changer de formule', () => router.push(infos.page_formule), 'formule')}
              {infos.periodicite === 'mensuel' && infos.statut === 'actif' && !infos.resiliation_prevue && (
                choixPause ? (
                  <div className="rounded-xl border border-gray-200 p-3 space-y-2">
                    <p className="text-sm font-semibold">Mettre en pause pendant</p>
                    <div className="flex gap-2">
                      {Array.from({ length: infos.pause_max_mois }, (_, i) => i + 1).map(n => (
                        <button key={n} type="button" onClick={() => setMois(n)} className="flex-1 py-2 rounded-lg text-sm font-semibold"
                          style={mois === n ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1F2A2E' }}>{n} mois</button>
                      ))}
                    </div>
                    <p className="text-xs text-gray-500">Aucun prélèvement pendant la pause. Votre profil passe en formule Découverte, toutes vos données sont conservées, et l&apos;abonnement reprend automatiquement à la fin de la pause.</p>
                    <div className="flex gap-2">
                      <button type="button" onClick={() => setChoixPause(false)} className="flex-1 py-2 rounded-lg text-sm border border-gray-200">Annuler</button>
                      <button type="button" disabled={!!busy} onClick={() => agir('pause', `Abonnement en pause pour ${mois} mois.`, { mois })}
                        className="flex-1 py-2 rounded-lg text-sm font-bold text-white disabled:opacity-50" style={{ background: TEAL }}>{busy === 'pause' ? '…' : 'Confirmer la pause'}</button>
                    </div>
                  </div>
                ) : bouton('Mettre en pause (1 à 3 mois)', () => setChoixPause(true), 'choix')
              )}
              {bouton('Carte et factures', portail, 'portail')}
              {infos.resiliation_prevue
                ? bouton('Annuler la résiliation', () => agir('annuler_resiliation', 'Résiliation annulée : votre abonnement continue.'), 'annuler_resiliation')
                : infos.statut !== 'pause' && bouton('Résilier', () => {
                    if (confirm(`Résilier votre abonnement ${infos.plan} ? Il ne sera pas renouvelé et vous gardez vos fonctionnalités jusqu'au ${date(infos.prochaine_echeance)}.`)) {
                      agir('resilier', `Résiliation enregistrée : accès jusqu'au ${date(infos.prochaine_echeance)}.`);
                    }
                  }, 'resilier', false, true)}
              <p className="text-xs text-gray-400 pt-1">
                {infos.periodicite === 'annuel'
                  ? 'Abonnement annuel : rappel par e-mail et notification 30 jours et 7 jours avant le renouvellement. Pas de pause en cours d’année.'
                  : 'Abonnement mensuel : reçu par e-mail à chaque prélèvement.'}
              </p>
            </div>
          ) : (
            <p className="mt-5 text-sm text-gray-600">Cet abonnement n&apos;est pas prélevé automatiquement : il se renouvelle depuis la page de votre formule. <Link href={infos.page_formule} className="font-semibold" style={{ color: TEAL }}>Voir ma formule</Link></p>
          )}
        </>
      )}
    </div>
  );
}
