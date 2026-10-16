'use client';
// Demandes de récupération reçues par l'élevage : un acquéreur (particulier
// sans compte au moment de la cession) demande à rattacher la fiche à son
// nouveau compte. L'éleveur accepte (transfert de propriété) ou refuse.
// Miroir appli : lib/pages/eleveur/animaux/recuperations_page.dart.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { appelRecuperation } from '@/components/animaux/RecuperationAnimal';

const TEAL = '#0C5C6C';

interface Demande {
  id: string; animal_id: string; demandeur_uid: string; message: string | null; created_at: string;
  _animal?: { nom: string | null; photo_url: string | null; destinataire_nom: string | null; date_sortie: string | null };
  _demandeur?: string;
}

export default function RecuperationsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [demandes, setDemandes] = useState<Demande[] | null>(null);
  const [encours, setEncours] = useState<string | null>(null);
  const [message, setMessage] = useState('');

  const charger = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from('animal_recuperations').select('*').eq('eleveur_uid', user.uid).eq('statut', 'en_attente').order('created_at', { ascending: false });
    const l = (data ?? []) as Demande[];
    if (l.length) {
      const [{ data: an }, { data: pr }] = await Promise.all([
        supabase.from('animaux').select('id, nom, photo_url, destinataire_nom, date_sortie').in('id', l.map(d => d.animal_id)),
        supabase.from('user_profiles_complet').select('uid, firstname, lastname, nom, is_main').in('uid', l.map(d => d.demandeur_uid)),
      ]);
      for (const d of l) {
        d._animal = ((an ?? []) as (Demande['_animal'] & { id: string })[]).find(a => a.id === d.animal_id);
        const ps = ((pr ?? []) as { uid: string; firstname?: string; lastname?: string; nom?: string; is_main?: boolean }[]).filter(p => p.uid === d.demandeur_uid);
        const p = ps.find(x => x.is_main) ?? ps[0];
        d._demandeur = p ? (`${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || p.nom || '') : '';
      }
    }
    setDemandes(l);
  }, [user]);
  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  async function decider(d: Demande, accepter: boolean) {
    setEncours(d.id); setMessage('');
    try {
      await appelRecuperation({ action: 'decider', demandeId: d.id, accepter });
      setMessage(accepter ? `${d._animal?.nom ?? "L'animal"} est rattaché au compte de ${d._demandeur || 'son propriétaire'}.` : 'Demande refusée.');
      charger();
    } catch (e) { setMessage((e as Error).message); }
    setEncours(null);
  }

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <Link href="/mes-animaux" className="text-sm font-semibold" style={{ color: TEAL }}>← Mes animaux</Link>
        <h1 className="text-xl font-bold text-[#1F2A2E]">Demandes de récupération</h1>
        <p className="text-sm text-gray-600">Des acquéreurs ont créé leur compte et demandent à récupérer la fiche de leur animal. Vérifiez qu&apos;il s&apos;agit bien de la personne à qui vous l&apos;avez cédé avant d&apos;accepter : la fiche (carnet, généalogie, documents) lui sera transférée, votre historique est conservé.</p>
        {message && <p className="text-sm" style={{ color: TEAL }}>{message}</p>}
        {demandes === null ? <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
          : demandes.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Aucune demande en attente.</p> : (
          <div className="space-y-3">
            {demandes.map(d => (
              <div key={d.id} className="bg-white rounded-2xl border border-gray-100 p-4">
                <div className="flex items-center gap-3">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {d._animal?.photo_url && <img src={d._animal.photo_url} alt="" className="w-12 h-12 rounded-xl object-cover" />}
                  <div className="flex-1">
                    <p className="text-sm font-bold text-[#1F2A2E]">{d._demandeur || 'Un utilisateur'} demande {d._animal?.nom ?? 'un animal'}</p>
                    <p className="text-xs text-gray-500">
                      {[d._animal?.destinataire_nom ? `Acquéreur enregistré : ${d._animal.destinataire_nom}` : 'Aucun acquéreur enregistré',
                        d._animal?.date_sortie ? `cédé le ${new Date(d._animal.date_sortie).toLocaleDateString('fr-FR')}` : ''].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                </div>
                {d.message && <p className="text-sm text-gray-700 mt-2">« {d.message} »</p>}
                <div className="flex gap-2 mt-3">
                  <button onClick={() => decider(d, false)} disabled={encours === d.id} className="flex-1 py-2 rounded-xl text-sm font-semibold border border-gray-200 disabled:opacity-50">Refuser</button>
                  <button onClick={() => decider(d, true)} disabled={encours === d.id} className="flex-1 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Accepter et transférer</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
