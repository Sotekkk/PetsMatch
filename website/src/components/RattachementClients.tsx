'use client';
// Fiches créées par un professionnel pour un client sans appli (clinique,
// toiletteur, maréchal-ferrant, ostéopathe, éducateur) : encadré proposant au
// propriétaire (même adresse e-mail) de les rattacher à son compte.
// Route /api/clients/rattachement. Miroir appli : lib/utils/rattachement_clients.dart.
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL = '#0C5C6C';
interface Proposition { clientId: string; pro: { nom: string; metier: string }; animaux: { id: string; nom: string | null; espece: string | null }[] }

export default function RattachementClients({ onRattache }: { onRattache?: () => void }) {
  const { user } = useAuth();
  const pid = useActiveProfile();
  const [props, setProps] = useState<Proposition[]>([]);
  const [enCours, setEnCours] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    apiFetch('/api/clients/rattachement', { cache: 'no-store' })
      .then(r => (r.ok ? r.json() : { propositions: [] }))
      .then(j => setProps((j.propositions ?? []) as Proposition[]))
      .catch(() => {});
  }, [user]);

  async function repondre(p: Proposition, accepter: boolean) {
    setEnCours(p.clientId);
    const r = await apiFetch('/api/clients/rattachement', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId: p.clientId, accepter, ...(pid ? { profileId: pid } : {}) }),
    });
    setEnCours(null);
    if (!r.ok) { alert('Action impossible, réessayez plus tard.'); return; }
    setProps(prev => prev.filter(x => x.clientId !== p.clientId));
    if (accepter) onRattache?.();
  }

  if (!props.length) return null;
  return (
    <div className="rounded-2xl border p-4 mb-4 bg-white" style={{ borderColor: `${TEAL}55`, fontFamily: 'Galey, sans-serif' }}>
      <p className="font-bold text-[#1F2A2E]">Des fiches vous attendent</p>
      <p className="text-sm text-gray-600 mt-0.5">Ces professionnels ont créé une fiche pour votre animal avec votre adresse e-mail. Récupérez-la dans votre compte : carnet, rendez-vous et documents au même endroit. Le professionnel garde son accès.</p>
      <div className="mt-3 space-y-2">
        {props.map(p => (
          <div key={p.clientId} className="rounded-xl border border-gray-100 p-3 flex flex-wrap items-center gap-2">
            <div className="flex-1 min-w-[180px]">
              <p className="text-sm font-semibold text-[#1F2A2E]">{p.pro.nom}</p>
              <p className="text-xs text-gray-500">{p.animaux.map(a => a.nom).filter(Boolean).join(', ')}</p>
            </div>
            <button onClick={() => repondre(p, true)} disabled={!!enCours} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Récupérer la fiche</button>
            <button onClick={() => repondre(p, false)} disabled={!!enCours} className="px-3 py-1.5 text-sm text-gray-500">Ce n&apos;est pas mon animal</button>
          </div>
        ))}
      </div>
    </div>
  );
}
