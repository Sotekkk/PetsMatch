'use client';
// Formulaire de consignes avant un rendez-vous (toiletteur) : par lien
// personnel (token, sans compte) ou par rendez-vous (client connecté /
// professionnel). Préremplissage avec les consignes de la fois précédente.
// RDV à plusieurs animaux : un formulaire par animal, le client doit en
// remplir un pour CHAQUE animal (contrôlé aussi par /api/rdv/consignes).
// Miroir appli : lib/pages/rdv_consignes_page.dart.
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import type { QuestionConsigne, Reponses } from '@/lib/consignes-rdv';

const TEAL = '#0C5C6C';

interface AnimalCtx { id: string; nom: string; reponses: Reponses | null; prefill: Reponses | null }
interface Contexte {
  role: 'client' | 'pro'; pro_nom: string; animal_nom: string;
  rdv: { id: string; date_heure: string; motif: string | null; statut: string };
  questions: QuestionConsigne[]; saisi_le: string | null;
  animaux?: AnimalCtx[];
  reponses: Reponses | null; prefill: Reponses | null;
}

const rempli = (r: Reponses | undefined) => Object.values(r ?? {}).some(v => (v ?? '').trim());

export default function ConsignesRdvForm({ token, rdvId, onSaved }: { token?: string; rdvId?: string; onSaved?: () => void }) {
  const [ctx, setCtx] = useState<Contexte | null>(null);
  const [err, setErr] = useState('');
  const [rep, setRep] = useState<Record<string, Reponses>>({});
  const [etat, setEtat] = useState<'' | 'envoi' | 'ok'>('');
  const [manque, setManque] = useState('');

  useEffect(() => {
    const q = token ? `token=${encodeURIComponent(token)}` : `rdvId=${encodeURIComponent(rdvId ?? '')}`;
    (token ? fetch(`/api/rdv/consignes?${q}`, { cache: 'no-store' }) : apiFetch(`/api/rdv/consignes?${q}`, { cache: 'no-store' }))
      .then(async r => {
        const j = await r.json();
        if (!r.ok) throw new Error(j.error ?? 'Consignes indisponibles');
        const c = j as Contexte;
        // Réponse d'une version antérieure de la route : un seul formulaire.
        if (!c.animaux?.length) c.animaux = [{ id: '', nom: c.animal_nom, reponses: c.reponses, prefill: c.prefill }];
        setCtx(c);
        setRep(Object.fromEntries(c.animaux.map(a => [a.id, { ...(a.reponses ?? a.prefill ?? {}) }])));
      })
      .catch(e => setErr((e as Error).message));
  }, [token, rdvId]);

  async function envoyer() {
    if (!ctx?.animaux) return;
    const plusieurs = ctx.animaux.length > 1;
    if (plusieurs && ctx.role === 'client') {
      const sans = ctx.animaux.filter(a => !rempli(rep[a.id])).map(a => a.nom);
      if (sans.length) { setManque(`Indiquez les consignes de chaque animal : il manque ${sans.join(', ')}.`); return; }
    }
    setManque('');
    setEtat('envoi');
    const body = JSON.stringify({ ...(token ? { token } : { rdvId }), reponses_par_animal: rep });
    const r = token
      ? await fetch('/api/rdv/consignes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body })
      : await apiFetch('/api/rdv/consignes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { setEtat(''); setManque((j as { error?: string }).error ?? 'Enregistrement impossible'); return; }
    setEtat('ok');
    onSaved?.();
  }

  if (err) return <p className="text-sm text-gray-500 text-center py-10">{err}</p>;
  if (!ctx?.animaux) return <div className="flex justify-center py-10"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const quand = new Date(ctx.rdv.date_heure).toLocaleString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  const animaux = ctx.animaux;
  const plusieurs = animaux.length > 1;
  const majRep = (id: string, cle: string, v: string) => setRep(r => ({ ...r, [id]: { ...(r[id] ?? {}), [cle]: v } }));

  return (
    <div className="space-y-4" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div>
        <p className="text-lg font-bold text-[#1F2A2E]">Consignes{ctx.animal_nom ? ` pour ${ctx.animal_nom}` : ''}</p>
        <p className="text-sm text-gray-500">{ctx.pro_nom} · {quand}</p>
        {plusieurs && <p className="text-sm text-[#0C5C6C] font-semibold mt-1">Une fiche par animal : remplissez-les toutes.</p>}
        {animaux.some(a => !a.reponses && a.prefill) && <p className="text-xs text-gray-400 mt-1">Préremplies avec vos consignes de la dernière fois : vérifiez-les.</p>}
        {ctx.saisi_le && <p className="text-xs text-gray-400 mt-1">Envoyées le {new Date(ctx.saisi_le).toLocaleDateString('fr-FR')} — vous pouvez les modifier.</p>}
      </div>

      {animaux.map((a, i) => (
        <section key={a.id || i} className={plusieurs ? 'rounded-2xl border border-gray-200 p-4 space-y-3' : 'space-y-4'}>
          {plusieurs && (
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <p className="font-bold text-[#1F2A2E] flex items-center gap-2">
                {a.nom}
                {rempli(rep[a.id])
                  ? <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-[#EAF5EC] text-[#2F7D3A]">Remplie</span>
                  : <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-[#FEF3C7] text-[#B45309]">À remplir</span>}
              </p>
              {i > 0 && rempli(rep[animaux[0].id]) && (
                <button type="button" onClick={() => setRep(r => ({ ...r, [a.id]: { ...(r[animaux[0].id] ?? {}) } }))}
                  className="text-xs font-semibold text-[#0C5C6C] hover:underline">
                  Reprendre les consignes de {animaux[0].nom}
                </button>
              )}
            </div>
          )}
          {ctx.questions.map(q => (
            <div key={q.cle}>
              <label className="block text-sm font-semibold text-[#1F2A2E]">{q.label}</label>
              {q.aide && <p className="text-xs text-gray-500 mb-1">{q.aide}</p>}
              {q.choix ? (
                <div className="flex flex-wrap gap-2 mt-1">
                  {q.choix.map(c => (
                    <button key={c} type="button" onClick={() => majRep(a.id, q.cle, rep[a.id]?.[q.cle] === c ? '' : c)}
                      className="px-3 py-1.5 rounded-xl text-sm font-semibold border"
                      style={rep[a.id]?.[q.cle] === c ? { background: TEAL, color: '#fff', borderColor: TEAL } : { borderColor: '#E5E7EB', color: '#374151' }}>{c}</button>
                  ))}
                </div>
              ) : (
                <textarea value={rep[a.id]?.[q.cle] ?? ''} onChange={e => majRep(a.id, q.cle, e.target.value)} rows={2}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none mt-1" />
              )}
            </div>
          ))}
        </section>
      ))}

      {manque && <p className="text-sm text-red-700 bg-red-50 rounded-xl px-3 py-2">{manque}</p>}
      <button onClick={envoyer} disabled={etat === 'envoi'} className="w-full py-3 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
        {etat === 'envoi' ? 'Envoi…' : etat === 'ok' ? 'Consignes envoyées — merci !' : ctx.role === 'pro' ? 'Enregistrer les consignes' : 'Envoyer mes consignes'}
      </button>
    </div>
  );
}
