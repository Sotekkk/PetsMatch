'use client';

// Clinique — salles typées et salle occupée par motif (miroir appli :
// salles_clinique_page.dart). Un RDV en ligne n'est proposé que si un
// vétérinaire ET une salle du bon type sont libres.
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { TYPES_SALLE, MOTIFS_VETO, libelleTypeSalle } from '@/lib/salles-clinique';

interface Salle { id: string; nom: string; type_salle: string; actif: boolean; ordre: number }

const iCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

export default function SallesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const { id: pid, loaded } = useActiveProfileState();
  const [salles, setSalles] = useState<Salle[]>([]);
  const [parMotif, setParMotif] = useState<Record<string, string>>({});
  // Les clients peuvent choisir leur vétérinaire à la réservation.
  const [choixPraticien, setChoixPraticien] = useState(true);
  const [fetching, setFetching] = useState(true);
  const [edit, setEdit] = useState<{ id?: string; nom: string; type_salle: string } | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  const load = useCallback(async () => {
    if (!user || !loaded || !pid) { setFetching(false); return; }
    const [{ data: s }, { data: p }] = await Promise.all([
      supabase.from('salles_clinique').select('id, nom, type_salle, actif, ordre').eq('clinique_profile_id', pid).order('ordre').order('created_at'),
      supabase.from('user_profiles_complet').select('salles_par_motif, rdv_choix_praticien').eq('id', pid).maybeSingle(),
    ]);
    setSalles((s ?? []) as Salle[]);
    setParMotif(((p?.salles_par_motif ?? {}) as Record<string, string>));
    setChoixPraticien(p?.rdv_choix_praticien !== false);
    setFetching(false);
  }, [user, loaded, pid]);

  useEffect(() => { load(); }, [load]);

  async function enregistrer() {
    if (!edit || !edit.nom.trim() || !pid) return;
    const { error } = edit.id
      ? await supabase.from('salles_clinique').update({ nom: edit.nom.trim(), type_salle: edit.type_salle }).eq('id', edit.id)
      : await supabase.from('salles_clinique').insert({ clinique_profile_id: pid, nom: edit.nom.trim(), type_salle: edit.type_salle, ordre: salles.length });
    if (error) { alert(error.message); return; }
    setEdit(null);
    load();
  }

  async function basculer(s: Salle) {
    await supabase.from('salles_clinique').update({ actif: !s.actif }).eq('id', s.id);
    load();
  }

  async function supprimer(s: Salle) {
    if (!confirm(`Supprimer « ${s.nom} » ? Les RDV déjà attribués à cette salle la perdent.`)) return;
    await supabase.from('salles_clinique').delete().eq('id', s.id);
    load();
  }

  async function majMotif(motif: string, type: string) {
    const m = { ...parMotif, [motif]: type };
    setParMotif(m);
    const { error } = await supabase.from('user_profiles').update({ salles_par_motif: m }).eq('id', pid);
    if (error) alert(error.message);
  }

  if (loading || fetching) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  const typesPresents = new Set(salles.filter(s => s.actif).map(s => s.type_salle));
  const manque = salles.length > 0 && MOTIFS_VETO.some(m => !typesPresents.has(parMotif[m.key] ?? 'consultation'));

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">🚪 Salles & motifs</h1>
          <p className="text-sm text-gray-500 mt-0.5">Un RDV en ligne n&apos;est proposé que si un vétérinaire ET une salle du bon type sont libres. Sans salle déclarée, seuls les vétérinaires comptent.</p>
        </div>
        <button onClick={() => setEdit({ nom: '', type_salle: 'consultation' })}
          className="bg-[#0C5C6C] text-white text-sm font-semibold px-4 py-2 rounded-xl whitespace-nowrap">+ Salle</button>
      </div>

      <label className="flex items-start gap-3 bg-white border border-gray-100 rounded-xl p-4 cursor-pointer">
        <input type="checkbox" className="mt-1 w-4 h-4 accent-[#0C5C6C]" checked={choixPraticien}
          onChange={async e => {
            const v = e.target.checked;
            setChoixPraticien(v);
            const { error } = await supabase.from('user_profiles').update({ rdv_choix_praticien: v }).eq('id', pid);
            if (error) alert(error.message);
          }} />
        <span>
          <span className="block text-sm font-semibold text-[#1F2A2E]">Les clients peuvent choisir leur vétérinaire</span>
          <span className="block text-xs text-gray-500">
            {choixPraticien ? '« Peu importe » ou un vétérinaire précis, au choix du client.' : 'Le premier vétérinaire libre est attribué automatiquement.'}
          </span>
        </span>
      </label>

      <section className="space-y-2">
        <h2 className="font-bold text-[#1F2A2E]">Salles</h2>
        {salles.length === 0 && <p className="text-sm text-gray-400">Aucune salle déclarée.</p>}
        {salles.map(s => (
          <div key={s.id} className="bg-white border border-gray-100 rounded-xl p-3 flex items-center gap-3">
            <span className="text-xl">🚪</span>
            <button className="flex-1 text-left" onClick={() => setEdit({ id: s.id, nom: s.nom, type_salle: s.type_salle })}>
              <p className={`text-sm font-semibold ${s.actif ? 'text-[#1F2A2E]' : 'text-gray-400 line-through'}`}>{s.nom}</p>
              <p className="text-xs text-gray-500">{libelleTypeSalle(s.type_salle)}{s.actif ? '' : ' · désactivée'}</p>
            </button>
            <button onClick={() => basculer(s)} className="text-xs text-[#0C5C6C] underline">{s.actif ? 'Désactiver' : 'Réactiver'}</button>
            <button onClick={() => supprimer(s)} className="text-xs text-red-500 underline">Supprimer</button>
          </div>
        ))}
      </section>

      <section className="space-y-2">
        <h2 className="font-bold text-[#1F2A2E]">Salle occupée par motif</h2>
        <p className="text-xs text-gray-500">Les visites à domicile n&apos;occupent aucune salle.</p>
        {MOTIFS_VETO.map(m => (
          <div key={m.key} className="flex items-center gap-3">
            <span className="flex-1 text-sm font-semibold text-[#1F2A2E]">{m.label}</span>
            <select className={`${iCls} max-w-[220px]`} value={parMotif[m.key] ?? 'consultation'} onChange={e => majMotif(m.key, e.target.value)}>
              {TYPES_SALLE.map(t => (
                <option key={t.key} value={t.key}>{t.label}{salles.length > 0 && !typesPresents.has(t.key) ? ' ⚠' : ''}</option>
              ))}
            </select>
          </div>
        ))}
        {manque && <p className="text-xs text-orange-700">⚠ Aucune salle active de ce type : ces RDV ne pourront pas être pris en ligne.</p>}
      </section>

      {edit && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4"
          onClick={e => { if (e.target === e.currentTarget) setEdit(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5 space-y-3">
            <p className="font-bold text-[#1F2A2E]">{edit.id ? 'Modifier la salle' : 'Nouvelle salle'}</p>
            <input autoFocus className={iCls} placeholder="Nom (ex. Consultation 1, Bloc)" value={edit.nom}
              onChange={e => setEdit({ ...edit, nom: e.target.value })} />
            <select className={iCls} value={edit.type_salle} onChange={e => setEdit({ ...edit, type_salle: e.target.value })}>
              {TYPES_SALLE.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
            </select>
            <div className="flex gap-3 pt-1">
              <button onClick={() => setEdit(null)} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm text-gray-600">Annuler</button>
              <button onClick={enregistrer} className="flex-1 py-2.5 bg-[#0C5C6C] text-white rounded-xl text-sm font-semibold">Enregistrer</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
