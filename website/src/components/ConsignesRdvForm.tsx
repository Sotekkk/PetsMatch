'use client';
// Formulaire de consignes avant un rendez-vous (toiletteur) : par lien
// personnel (token, sans compte) ou par rendez-vous (client connecté /
// professionnel). Préremplissage avec les consignes de la fois précédente.
// Miroir appli : lib/pages/rdv_consignes_page.dart.
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import type { QuestionConsigne } from '@/lib/consignes-rdv';

const TEAL = '#0C5C6C';

interface Contexte {
  role: 'client' | 'pro'; pro_nom: string; animal_nom: string;
  rdv: { id: string; date_heure: string; motif: string | null; statut: string };
  questions: QuestionConsigne[]; reponses: Record<string, string> | null; saisi_le: string | null; prefill: Record<string, string> | null;
}

export default function ConsignesRdvForm({ token, rdvId, onSaved }: { token?: string; rdvId?: string; onSaved?: () => void }) {
  const [ctx, setCtx] = useState<Contexte | null>(null);
  const [err, setErr] = useState('');
  const [rep, setRep] = useState<Record<string, string>>({});
  const [etat, setEtat] = useState<'' | 'envoi' | 'ok'>('');

  useEffect(() => {
    const q = token ? `token=${encodeURIComponent(token)}` : `rdvId=${encodeURIComponent(rdvId ?? '')}`;
    (token ? fetch(`/api/rdv/consignes?${q}`, { cache: 'no-store' }) : apiFetch(`/api/rdv/consignes?${q}`, { cache: 'no-store' }))
      .then(async r => {
        const j = await r.json();
        if (!r.ok) throw new Error(j.error ?? 'Consignes indisponibles');
        setCtx(j as Contexte);
        setRep((j.reponses ?? j.prefill ?? {}) as Record<string, string>);
      })
      .catch(e => setErr((e as Error).message));
  }, [token, rdvId]);

  async function envoyer() {
    setEtat('envoi');
    const body = JSON.stringify({ ...(token ? { token } : { rdvId }), reponses: rep });
    const r = token
      ? await fetch('/api/rdv/consignes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body })
      : await apiFetch('/api/rdv/consignes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { setEtat(''); alert((j as { error?: string }).error ?? 'Enregistrement impossible'); return; }
    setEtat('ok');
    onSaved?.();
  }

  if (err) return <p className="text-sm text-gray-500 text-center py-10">{err}</p>;
  if (!ctx) return <div className="flex justify-center py-10"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const quand = new Date(ctx.rdv.date_heure).toLocaleString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });

  return (
    <div className="space-y-4" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div>
        <p className="text-lg font-bold text-[#1F2A2E]">Consignes{ctx.animal_nom ? ` pour ${ctx.animal_nom}` : ''}</p>
        <p className="text-sm text-gray-500">{ctx.pro_nom} · {quand}</p>
        {!ctx.reponses && ctx.prefill && <p className="text-xs text-gray-400 mt-1">Préremplies avec vos consignes de la dernière fois : vérifiez-les.</p>}
        {ctx.saisi_le && <p className="text-xs text-gray-400 mt-1">Envoyées le {new Date(ctx.saisi_le).toLocaleDateString('fr-FR')} — vous pouvez les modifier.</p>}
      </div>
      {ctx.questions.map(q => (
        <div key={q.cle}>
          <label className="block text-sm font-semibold text-[#1F2A2E]">{q.label}</label>
          {q.aide && <p className="text-xs text-gray-500 mb-1">{q.aide}</p>}
          {q.choix ? (
            <div className="flex flex-wrap gap-2 mt-1">
              {q.choix.map(c => (
                <button key={c} type="button" onClick={() => setRep(r => ({ ...r, [q.cle]: r[q.cle] === c ? '' : c }))}
                  className="px-3 py-1.5 rounded-xl text-sm font-semibold border"
                  style={rep[q.cle] === c ? { background: TEAL, color: '#fff', borderColor: TEAL } : { borderColor: '#E5E7EB', color: '#374151' }}>{c}</button>
              ))}
            </div>
          ) : (
            <textarea value={rep[q.cle] ?? ''} onChange={e => setRep(r => ({ ...r, [q.cle]: e.target.value }))} rows={2}
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none mt-1" />
          )}
        </div>
      ))}
      <button onClick={envoyer} disabled={etat === 'envoi'} className="w-full py-3 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
        {etat === 'envoi' ? 'Envoi…' : etat === 'ok' ? 'Consignes envoyées — merci !' : ctx.role === 'pro' ? 'Enregistrer les consignes' : 'Envoyer mes consignes'}
      </button>
    </div>
  );
}
