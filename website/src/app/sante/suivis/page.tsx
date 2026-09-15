'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useSanteAccess } from '@/hooks/useSanteAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { labelTypeSuivi, morphoSpeciesSupported, TEAL } from '@/lib/morpho';

interface SuiviRow {
  id: string; date: string; type_suivi: string; animal_id: string | null;
  animal_nom_libre: string | null; espece_libre: string | null;
  _animal_nom?: string; _animal_espece?: string;
}

interface Patient { id: string; nom: string; espece: string; ownerName?: string }

export default function SanteSuivisPage() {
  const { user, userData, isSante, loading: authLoading } = useSanteAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [suivis, setSuivis] = useState<SuiviRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [picker, setPicker] = useState<'closed' | 'choix' | 'libre'>('closed');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [patientSearch, setPatientSearch] = useState('');
  const [espece, setEspece] = useState('chien');
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isSante) { router.push('/'); return; }
  }, [user, userData, isSante, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('suivis_morpho').select('id, date, type_suivi, animal_id, animal_nom_libre, espece_libre').eq('uid_auteur', user.uid);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const { data } = await q.order('date', { ascending: false });
    const rows = (data ?? []) as SuiviRow[];
    const animalIds = [...new Set(rows.map(r => r.animal_id).filter((a): a is string => !!a))];
    if (animalIds.length) {
      const { data: animaux } = await supabase.from('animaux').select('id, nom, espece').in('id', animalIds);
      const byId = new Map((animaux ?? []).map(a => [a.id, a]));
      rows.forEach(r => {
        const a = r.animal_id ? byId.get(r.animal_id) : null;
        r._animal_nom = a?.nom ?? r.animal_nom_libre ?? 'Animal';
        r._animal_espece = a?.espece ?? r.espece_libre ?? '';
      });
    } else {
      rows.forEach(r => { r._animal_nom = r.animal_nom_libre ?? 'Animal'; r._animal_espece = r.espece_libre ?? ''; });
    }
    setSuivis(rows);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  // Tous les vrais patients du pro : accès accordés (animal_access) UNION
  // animaux d'un RDV confirmé/terminé — même requête que /mes-patients, pour
  // que « Mes suivis » propose la liste complète et pas seulement les
  // patients déjà venus en RDV.
  async function ouvrirChoixPatient() {
    if (!user || !activeProfileId) { setPatients([]); setPicker('choix'); return; }
    const { data: grantRows } = await supabase.from('animal_access')
      .select('animal_id, granted_by_profile_id')
      .eq('pro_profile_id', activeProfileId).in('statut', ['active', 'write_requested', 'active_write']);
    const seen = new Map<string, string | null>();
    for (const g of (grantRows ?? []) as { animal_id: string; granted_by_profile_id: string | null }[]) {
      seen.set(g.animal_id, g.granted_by_profile_id);
    }
    const { data: rdvRows } = await supabase.from('rdv').select('animal_id')
      .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
      .in('statut', ['confirme', 'termine']).not('animal_id', 'is', null);
    for (const r of (rdvRows ?? []) as { animal_id: string }[]) {
      if (!seen.has(r.animal_id)) seen.set(r.animal_id, null);
    }
    if (seen.size === 0) { setPatients([]); setPicker('choix'); return; }

    const { data: animaux } = await supabase.from('animaux').select('id, nom, espece').in('id', [...seen.keys()]);
    const ownerProfileIds = [...new Set([...seen.values()].filter((v): v is string => !!v))];
    const ownerNames = new Map<string, string>();
    if (ownerProfileIds.length) {
      const { data: profiles } = await supabase.from('user_profiles').select('id, firstname, lastname, nom').in('id', ownerProfileIds);
      for (const u of (profiles ?? []) as { id: string; firstname: string | null; lastname: string | null; nom: string | null }[]) {
        const name = u.nom?.trim() || `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        ownerNames.set(u.id, name || 'Propriétaire');
      }
    }
    const list: Patient[] = ((animaux ?? []) as { id: string; nom: string; espece: string }[])
      .map(a => {
        const ownerPid = seen.get(a.id);
        return { ...a, ownerName: ownerPid ? ownerNames.get(ownerPid) ?? '' : '' };
      })
      .sort((a, b) => a.nom.localeCompare(b.nom));
    setPatients(list);
    setPatientSearch('');
    setPicker('choix');
  }

  async function creerPourPatient(p: Patient) {
    setPicker('closed');
    router.push(`/sante/suivis/nouveau?animalId=${p.id}&espece=${encodeURIComponent(p.espece)}`);
  }

  function creerLibre() {
    setPicker('closed');
    router.push(`/sante/suivis/nouveau?espece=${encodeURIComponent(espece)}`);
  }

  if (!user || !userData) return null;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold font-galey" style={{ color: TEAL }}>Mes suivis</h1>
        <button onClick={ouvrirChoixPatient}
          className="text-white px-4 py-2 rounded-full text-sm font-galey font-semibold" style={{ background: TEAL }}>
          + Nouveau suivi
        </button>
      </div>
      <p className="text-sm text-gray-500 font-galey">Suivi morphologique &amp; bien-être — tous patients confondus.</p>

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-10 w-10 border-b-2" style={{ borderColor: TEAL }} /></div>
      ) : suivis.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">🦴</p>
          <p className="font-galey">Aucun suivi pour l&apos;instant</p>
        </div>
      ) : (
        <div className="space-y-3">
          {suivis.map(s => (
            <a key={s.id} href={`/sante/suivis/${s.id}`}
              className="block bg-white rounded-2xl shadow-sm p-4 border border-gray-100 hover:border-teal-200 transition-colors">
              <p className="font-bold font-galey text-gray-900">{s._animal_nom} — {labelTypeSuivi(s.type_suivi)}</p>
              <p className="text-xs text-gray-500 font-galey mt-1">{new Date(s.date).toLocaleDateString('fr-FR')}</p>
            </a>
          ))}
        </div>
      )}

      {picker === 'choix' && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setPicker('closed')}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[80vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-bold font-galey text-gray-900">Nouveau suivi</h3>
              <button onClick={() => setPicker('closed')} className="text-gray-400 hover:text-gray-600">✕</button>
            </div>
            <button onClick={() => setPicker('libre')}
              className="w-full text-left p-3 rounded-xl border border-gray-200 hover:bg-teal-50 mb-3 flex items-center gap-3">
              <span className="text-xl">👤</span>
              <span>
                <span className="block font-semibold font-galey text-gray-900 text-sm">Client occasionnel (sans compte)</span>
                <span className="block text-xs text-gray-500 font-galey">Nom de l&apos;animal saisi à la main</span>
              </span>
            </button>
            {patients.length > 0 && (
              <>
                <input value={patientSearch} onChange={e => setPatientSearch(e.target.value)}
                  placeholder="Rechercher un patient ou un propriétaire…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey mb-2" />
                <div className="flex flex-col gap-2 max-h-64 overflow-y-auto">
                  {patients
                    .filter(p => {
                      const q = patientSearch.trim().toLowerCase();
                      if (!q) return true;
                      return p.nom.toLowerCase().includes(q) || (p.ownerName ?? '').toLowerCase().includes(q);
                    })
                    .map(p => {
                      const supported = morphoSpeciesSupported(p.espece);
                      return (
                        <button key={p.id} disabled={!supported} onClick={() => creerPourPatient(p)}
                          className="text-left p-3 rounded-xl border border-gray-200 hover:bg-teal-50 disabled:opacity-40">
                          <p className="font-semibold font-galey text-gray-900 text-sm">{p.nom}</p>
                          <p className="text-xs text-gray-500 font-galey">
                            {!supported ? 'Espèce non disponible pour le suivi morphologique'
                              : p.ownerName ? `${p.espece} · ${p.ownerName}` : p.espece}
                          </p>
                        </button>
                      );
                    })}
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {picker === 'libre' && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setPicker('closed')}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold font-galey text-gray-900 mb-3">Espèce de l&apos;animal</h3>
            <div className="flex gap-2 mb-4">
              {['chien', 'chat', 'cheval'].map(e => (
                <button key={e} onClick={() => setEspece(e)}
                  className="px-3 py-1.5 rounded-full text-sm font-galey font-semibold border"
                  style={espece === e ? { background: TEAL, color: 'white', borderColor: TEAL } : { borderColor: '#E5E7EB', color: '#374151' }}>
                  {e[0].toUpperCase() + e.slice(1)}
                </button>
              ))}
            </div>
            <button disabled={creating} onClick={creerLibre}
              className="w-full py-2.5 rounded-xl text-sm font-galey font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
              Continuer
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
