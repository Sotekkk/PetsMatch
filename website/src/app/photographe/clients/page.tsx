'use client';
// Photographe — « Mes clients et suivi » : les clients sont les
// PROPRIÉTAIRES (pas les animaux). Onglets « À traiter » (travail en cours
// regroupé par tâche) et « Clients » (séances, galeries, factures par
// client). Chaque séance ouvre le dossier de la séance.
// Miroir appli : photographe_clients_page.dart. Scopé au profil actif.
import ContactCanaux from '@/components/ContactCanaux';
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import DossierSeanceModal, { type RdvDossier } from '@/components/photographe/DossierSeanceModal';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const VIOLET = '#7B5EA7';
const ROUGE = '#B3261E';
const GRIS = '#6B7280';

const TACHES: [string, string, string][] = [
  ['selection', 'Sélection reçue — photos à retoucher', AMBRE],
  ['livrer', 'En retouche — à livrer', VIOLET],
  ['galerie_creer', 'Galerie à créer', TEAL],
  ['galerie_partager', 'Galerie à compléter et partager', TEAL],
  ['facturer', 'À facturer', AMBRE],
  ['impayee', 'Facture émise, non payée', ROUGE],
  ['contrat', 'Contrat à envoyer ou en attente de signature', GRIS],
  ['devis', 'Devis en attente de réponse', GRIS],
];

interface Rdv extends RdvDossier { client_nom_manuel: string | null; client_telephone_manuel?: string | null; client_email_manuel?: string | null }
type Ligne = Record<string, unknown> & { statut?: string | null; id: string };

export default function PhotographeClientsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pid = useActiveProfile();
  const [onglet, setOnglet] = useState<'traiter' | 'clients'>('traiter');
  const [busy, setBusy] = useState(true);
  const [now, setNow] = useState(0);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [galeries, setGaleries] = useState<Record<string, Ligne>>({});
  const [choisies, setChoisies] = useState<Record<string, number>>({});
  const [devis, setDevis] = useState<Record<string, Ligne>>({});
  const [contrats, setContrats] = useState<Record<string, Ligne>>({});
  const [factures, setFactures] = useState<Record<string, Ligne>>({});
  const [profils, setProfils] = useState<Record<string, Record<string, string | null>>>({});
  const [prestations, setPrestations] = useState<Record<string, string>>({});
  const [recherche, setRecherche] = useState('');
  const [client, setClient] = useState<string | null>(null);
  const [dossier, setDossier] = useState<Rdv | null>(null);

  const charger = useCallback(async () => {
    if (!pid) return;
    const t = Date.now();
    const { data: rd } = await supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['confirme', 'termine'])
      .gte('date_heure', new Date(t - 540 * 86400000).toISOString()).order('date_heure', { ascending: false }).limit(400);
    const liste = (rd ?? []) as Rdv[];
    const ids = liste.map(r => r.id);
    const byRdv = (rows: Ligne[], cle: string) => Object.fromEntries(rows.map(x => [String(x[cle]), x]));
    if (ids.length) {
      const [g, d, c, f] = await Promise.all([
        supabase.from('albums_photo').select('*').in('rdv_id', ids),
        supabase.from('devis').select('id, rdv_id, statut, total_ttc').in('rdv_id', ids),
        supabase.from('documents_animaux').select('id, rdv_id, statut').eq('type', 'contrat_prestation_photo').in('rdv_id', ids),
        supabase.from('factures').select('id, source_rdv_id, statut, total_ttc').in('source_rdv_id', ids).neq('statut', 'annulee'),
      ]);
      const gal = (g.data ?? []) as Ligne[];
      setGaleries(byRdv(gal, 'rdv_id'));
      setDevis(byRdv(d.error ? [] : (d.data ?? []) as Ligne[], 'rdv_id'));
      setContrats(byRdv((c.data ?? []) as Ligne[], 'rdv_id'));
      setFactures(byRdv((f.data ?? []) as Ligne[], 'source_rdv_id'));
      if (gal.length) {
        const { data: ph } = await supabase.from('album_photos').select('album_id').in('album_id', gal.map(x => x.id)).eq('selectionnee', true);
        const n: Record<string, number> = {};
        for (const x of (ph ?? []) as { album_id: string }[]) n[x.album_id] = (n[x.album_id] ?? 0) + 1;
        setChoisies(n);
      }
    }
    const pids = [...new Set(liste.map(r => r.client_profile_id).filter(Boolean) as string[])];
    const prs = [...new Set(liste.map(r => r.prestation_id).filter(Boolean) as string[])];
    const [p, pr] = await Promise.all([
      pids.length ? supabase.from('user_profiles_complet').select('*').in('id', pids) : Promise.resolve({ data: [] }),
      prs.length ? supabase.from('prestations_photographe').select('id, nom').in('id', prs) : Promise.resolve({ data: [] }),
    ]);
    setProfils(Object.fromEntries(((p.data ?? []) as Record<string, string | null>[]).map(x => [String(x.id), x])));
    setPrestations(Object.fromEntries(((pr.data ?? []) as { id: string; nom: string }[]).map(x => [x.id, x.nom])));
    setRdvs(liste); setNow(t); setBusy(false);
  }, [pid]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  const cleClient = (r: Rdv) => r.client_profile_id ?? r.client_uid ?? `manuel:${(r.client_nom_manuel ?? '').trim().toLowerCase()}`;
  const nomClient = (r: Rdv) => {
    const p = r.client_profile_id ? profils[r.client_profile_id] : undefined;
    if (p) {
      const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim(); const st = (p.nom ?? '').trim();
      const n = p.profile_type !== 'particulier' && st ? st : perso || st;
      if (n) return n;
    }
    return r.client_nom_manuel?.trim() || 'Client';
  };
  const prestation = (r: Rdv) => (r.prestation_id && prestations[r.prestation_id]) || r.motif?.trim() || 'Séance photo';
  const jour = (iso: string) => new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });

  const taches = (r: Rdv): string[] => {
    const passee = new Date(r.date_heure).getTime() < now;
    const g = galeries[r.id], f = factures[r.id], c = contrats[r.id], d = devis[r.id];
    const out: string[] = [];
    if (passee) {
      if (!g) out.push('galerie_creer');
      else if (g.statut === 'selection_recue') out.push('selection');
      else if (g.statut === 'en_retouche') out.push('livrer');
      else if ((g.statut ?? 'brouillon') === 'brouillon') out.push('galerie_partager');
      if (!f) out.push('facturer');
    }
    if (f && f.statut !== 'payee') out.push('impayee');
    if (!passee && (!c || c.statut !== 'signe')) out.push('contrat');
    if (d && d.statut === 'envoye') out.push('devis');
    return out;
  };

  const ligneSeance = (r: Rdv, extra?: string) => {
    const g = galeries[r.id];
    const n = g ? choisies[g.id] ?? 0 : 0;
    return (
      <button key={r.id} onClick={() => setDossier(r)} className="w-full text-left flex items-center gap-2 py-2.5 border-t border-gray-50 first:border-0">
        <span className="flex-1 min-w-0">
          <span className="block text-sm font-bold text-[#1E2025] truncate">{nomClient(r)} — {prestation(r)}</span>
          <span className="block text-xs text-gray-500">
            {[`Séance du ${jour(r.date_heure)}`, r.animal_nom_manuel ?? '', n ? `${n} photo${n > 1 ? 's' : ''} choisie${n > 1 ? 's' : ''}` : '', extra ?? ''].filter(Boolean).join(' · ')}
          </span>
        </span>
        <span className="text-gray-400">›</span>
      </button>
    );
  };

  const parTache: Record<string, Rdv[]> = {};
  for (const r of rdvs) for (const t of taches(r)) (parTache[t] ??= []).push(r);
  const groupes: Record<string, Rdv[]> = {};
  for (const r of rdvs) (groupes[cleClient(r)] ??= []).push(r);
  const q = recherche.trim().toLowerCase();
  const cles = Object.keys(groupes).filter(k => !q || nomClient(groupes[k][0]).toLowerCase().includes(q))
    .sort((a, b) => nomClient(groupes[a][0]).localeCompare(nomClient(groupes[b][0])));

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-4xl mx-auto px-4 py-6 space-y-4">
        <h1 className="text-xl font-bold text-[#1F2A2E]">Mes clients et suivi</h1>
        <div className="flex gap-2">
          {([['traiter', 'À traiter'], ['clients', 'Clients']] as const).map(([k, l]) => (
            <button key={k} onClick={() => setOnglet(k)} className="px-4 py-2 rounded-full text-sm font-semibold border"
              style={onglet === k ? { background: TEAL, color: '#fff', borderColor: TEAL } : { background: '#fff', color: '#374151', borderColor: '#D1D5DB' }}>{l}</button>
          ))}
        </div>
        {busy ? <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
          : onglet === 'traiter' ? (
            Object.keys(parTache).length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Rien à traiter : tout est à jour.</p> : (
              <div className="space-y-3">
                {TACHES.filter(([k]) => parTache[k]?.length).map(([k, l, c]) => (
                  <div key={k} className="bg-white rounded-2xl border border-gray-100 p-4">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="w-2 h-2 rounded-full" style={{ background: c }} />
                      <p className="flex-1 text-sm font-bold text-[#1F2A2E]">{l}</p>
                      <span className="text-sm font-bold" style={{ color: c }}>{parTache[k].length}</span>
                    </div>
                    {parTache[k].map(r => ligneSeance(r))}
                  </div>
                ))}
              </div>
            )
          ) : (
            <>
              <input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Rechercher un client"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white" />
              {cles.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Aucun client pour le moment.</p> : (
                <div className="grid sm:grid-cols-2 gap-3">
                  {cles.map(k => {
                    const s = groupes[k];
                    const prochaine = s.filter(r => new Date(r.date_heure).getTime() > now).sort((a, b) => a.date_heure.localeCompare(b.date_heure))[0];
                    const n = s.reduce((x, r) => x + taches(r).length, 0);
                    return (
                      <button key={k} onClick={() => setClient(k)} className="text-left bg-white rounded-2xl border border-gray-100 p-4 hover:shadow-md transition-shadow">
                        <div className="flex items-start gap-2">
                          <p className="flex-1 text-sm font-bold text-[#1F2A2E]">{nomClient(s[0])}</p>
                          {n > 0 && <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ color: AMBRE, background: '#FFF4DC' }}>{n} à traiter</span>}
                        </div>
                        <p className="text-xs text-gray-500 mt-1">{[`${s.length} séance${s.length > 1 ? 's' : ''}`, prochaine ? `prochaine le ${jour(prochaine.date_heure)}` : ''].filter(Boolean).join(' · ')}</p>
                      </button>
                    );
                  })}
                </div>
              )}
            </>
          )}
      </div>

      {client && groupes[client] && (() => {
        const s = groupes[client];
        const r0 = s[0];
        const p = r0.client_profile_id ? profils[r0.client_profile_id] : undefined;
        const tel = p?.phone_number ?? p?.phone ?? r0.client_telephone_manuel ?? '';
        const mail = p?.email_contact ?? r0.client_email_manuel ?? '';
        return (
          <div className="fixed inset-0 z-40 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setClient(null)}>
            <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
              <p className="font-bold text-lg text-[#1E2025]">{nomClient(r0)}</p>
              {(tel || mail) && <p className="text-sm text-gray-500">{[tel, mail].filter(Boolean).join(' · ')}</p>}
              <ContactCanaux uid={r0.client_uid} tel={tel} email={mail} className="mt-2" />
              <p className="text-sm font-bold text-[#1E2025] mt-4 mb-1">Séances</p>
              {s.map(r => {
                const g = galeries[r.id], f = factures[r.id], t = taches(r);
                return ligneSeance(r, [
                  g ? `galerie : ${g.statut === 'livree' ? 'livrée' : g.statut === 'selection_recue' ? 'sélection reçue' : g.statut === 'en_retouche' ? 'en retouche' : g.statut === 'partagee' ? 'partagée' : 'brouillon'}` : '',
                  f ? (f.statut === 'payee' ? 'facture payée' : 'facture non payée') : '',
                  t.length ? `${t.length} à traiter` : '',
                ].filter(Boolean).join(' · '));
              })}
              <button onClick={() => setClient(null)} className="w-full mt-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
            </div>
          </div>
        );
      })()}

      {dossier && (
        <DossierSeanceModal rdv={dossier} nomClient={nomClient(dossier)} prestation={prestation(dossier)} animal={dossier.animal_nom_manuel}
          onClose={() => setDossier(null)} onChanged={charger} />
      )}
    </div>
  );
}
