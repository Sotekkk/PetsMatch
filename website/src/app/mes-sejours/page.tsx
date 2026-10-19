'use client';
// Mes séjours en pension (client) : demandes de séjour du profil actif, statut,
// annulation tant que la pension n'a pas répondu. Miroir appli :
// MesSejoursPensionPage (pension_reservation_page.dart).
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Demande {
  id: string; pro_profile_id: string | null; client_profile_id: string | null; animal_nom: string | null;
  date_arrivee: string; date_depart: string; essai_date: string | null; statut: string; motif_refus: string | null;
}

const STATUTS: Record<string, [string, string]> = {
  demande: ['En attente de la pension', '#D97706'],
  acceptee: ['Confirmé', '#2E7D5E'],
  refusee: ['Non accepté', '#B3261E'],
  annulee: ['Annulé', '#9CA3AF'],
};
const jour = (s: string | null) => s ? new Date(`${s}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' }) : '';

export default function MesSejoursPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pid = useActiveProfile();
  const [demandes, setDemandes] = useState<Demande[] | null>(null);
  const [pensions, setPensions] = useState<Record<string, string>>({});
  const [enCours, setEnCours] = useState('');

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  const charger = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('pension_demandes')
      .select('id, pro_profile_id, client_profile_id, animal_nom, date_arrivee, date_depart, essai_date, statut, motif_refus')
      .eq('client_uid', user.uid).order('date_arrivee', { ascending: false });
    // Profil actif : ses demandes (les anciennes sans profil restent visibles).
    const liste = ((data ?? []) as Demande[]).filter(d => !pid || !d.client_profile_id || d.client_profile_id === pid);
    const ids = [...new Set(liste.map(d => d.pro_profile_id).filter(Boolean) as string[])];
    const { data: ps } = ids.length ? await supabase.from('user_profiles').select('id, nom').in('id', ids) : { data: [] };
    const noms: Record<string, string> = {};
    for (const p of (ps ?? []) as { id: string; nom: string | null }[]) noms[p.id] = p.nom ?? 'Pension';
    setPensions(noms);
    setDemandes(liste);
  }, [user, pid]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  async function annuler(d: Demande) {
    if (!window.confirm(`Annuler la demande de séjour pour ${d.animal_nom ?? 'votre animal'} ? La pension sera prévenue.`)) return;
    setEnCours(d.id);
    const r = await apiFetch('/api/pension/sejour', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'annuler', demandeId: d.id }) });
    const j = await r.json().catch(() => ({})) as { error?: string };
    setEnCours('');
    if (!r.ok) { window.alert(j.error ?? 'Annulation impossible'); return; }
    charger();
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6" style={{ fontFamily: 'Galey, sans-serif' }}>
      <h1 className="text-2xl font-bold text-[#0C5C6C] mb-4">Mes séjours en pension</h1>
      {demandes === null ? (
        <p className="text-sm text-gray-400">Chargement…</p>
      ) : demandes.length === 0 ? (
        <p className="text-sm text-gray-500">Aucune demande de séjour. Réservez depuis la fiche d&apos;une pension dans l&apos;annuaire des pros.</p>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 divide-y divide-gray-100">
          {demandes.map(d => {
            const [lib, coul] = STATUTS[d.statut] ?? STATUTS.demande;
            return (
              <div key={d.id} className="p-4">
                <div className="flex items-start gap-3">
                  <p className="flex-1 font-bold text-sm text-[#1E2025]">{d.animal_nom ?? 'Animal'} · {pensions[d.pro_profile_id ?? ''] ?? 'Pension'}</p>
                  <span className="text-xs font-semibold" style={{ color: coul }}>{lib}</span>
                </div>
                <p className="text-sm text-gray-600 mt-0.5">Du {jour(d.date_arrivee)} au {jour(d.date_depart)}{d.essai_date ? ` · essai le ${jour(d.essai_date)}` : ''}</p>
                {d.statut === 'refusee' && d.motif_refus && <p className="text-xs text-gray-500 mt-0.5">Motif : {d.motif_refus}</p>}
                {d.statut === 'demande' && (
                  <button onClick={() => annuler(d)} disabled={enCours === d.id} className="mt-1 text-sm font-semibold text-[#B3261E] disabled:opacity-50">
                    {enCours === d.id ? 'Annulation…' : 'Annuler la demande'}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
