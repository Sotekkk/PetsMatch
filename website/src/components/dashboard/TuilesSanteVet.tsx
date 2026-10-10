'use client';
// Accès rapide de l'accueil — santé (ostéo / kiné) et vétérinaire — en MIROIR
// de l'appli (eleveur_home.dart : _buildSanteShortcuts / _buildVetShortcuts) :
// mêmes tuiles, même ordre, même style (fond blanc, contour fin, icône au
// trait dans un cercle teinté de la couleur de la tuile, texte foncé).
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { Tuile as TuileAccueil, TitreRubrique } from '@/components/dashboard/kit';

interface Tuile { label: string; icone: string; couleur: string; href?: string; acte?: { libelle: string; onglet: string } }

interface Patient { id: string; nom: string | null; espece: string | null; race: string | null }

export default function TuilesSanteVet({ catPro, uid, profileId, abonnementHref }: {
  catPro: 'sante' | 'veterinaire'; uid: string; profileId: string; abonnementHref: string;
}) {
  const router = useRouter();
  const [acte, setActe] = useState<{ libelle: string; onglet: string } | null>(null);
  const [patients, setPatients] = useState<Patient[] | null>(null);
  const [filtre, setFiltre] = useState('');

  const tuiles: Tuile[] = catPro === 'sante'
    ? [
        { label: 'Mes patients', icone: 'stetho', couleur: '#0C5C6C', href: '/mes-patients' },
        { label: 'Agenda RDV', icone: 'calendrier', couleur: '#5F9EAA', href: '/agenda' },
        { label: 'Mes suivis', icone: 'suivi', couleur: '#7B5EA7', href: '/sante/suivis' },
        { label: 'Mes contrats', icone: 'document', couleur: '#B8860B', href: '/sante/contrat' },
        { label: 'Facturation', icone: 'facture', couleur: '#6E9E57', href: '/elevage/facturation' },
        { label: 'Mon abonnement', icone: 'etoile', couleur: '#D97706', href: abonnementHref },
      ]
    : [
        { label: 'Mes patients', icone: 'stetho', couleur: '#0C5C6C', href: '/mes-patients' },
        { label: 'Agenda RDV', icone: 'calendrier', couleur: '#5F9EAA', href: '/agenda' },
        { label: 'Rechercher une puce', icone: 'recherche', couleur: '#475569', href: '/mes-patients' },
        { label: 'Ordonnance', icone: 'pilule', couleur: '#7B5EA7', acte: { libelle: 'une ordonnance', onglet: 'Consultations' } },
        { label: 'Vaccin', icone: 'seringue', couleur: '#2E7D5E', acte: { libelle: 'un vaccin', onglet: 'Santé' } },
        { label: 'Compte rendu', icone: 'crayon', couleur: '#B8860B', acte: { libelle: 'un compte rendu', onglet: 'Consultations' } },
        { label: 'Messages', icone: 'message', couleur: '#5F9EAA', href: '/messages' },
        { label: 'Facturation', icone: 'facture', couleur: '#6E9E57', href: '/elevage/facturation' },
        { label: 'Mon abonnement', icone: 'etoile', couleur: '#D97706', href: abonnementHref },
      ];

  // Patients avec accès accordé (profil pro ACTIF), comme l'appli.
  async function choisirPatient(a: { libelle: string; onglet: string }) {
    setActe(a); setFiltre(''); setPatients(null);
    let pid = profileId;
    if (!pid) {
      const { data } = await supabase.from('user_profiles_complet').select('id')
        .eq('uid', uid).eq('profile_type', catPro).limit(1).maybeSingle();
      pid = (data?.id as string) ?? '';
    }
    if (!pid) { setPatients([]); return; }
    const { data: acces } = await supabase.from('animal_access').select('animal_id')
      .eq('pro_profile_id', pid).in('statut', ['active', 'active_write']);
    const ids = [...new Set((acces ?? []).map((g: { animal_id: string }) => g.animal_id))];
    if (!ids.length) { setPatients([]); return; }
    const { data: animaux } = await supabase.from('animaux').select('id, nom, espece, race')
      .in('id', ids).order('nom', { ascending: true });
    setPatients((animaux ?? []) as Patient[]);
  }

  const liste = (patients ?? []).filter(p => (p.nom ?? '').toLowerCase().includes(filtre.toLowerCase()));

  return (
    <div>
      <TitreRubrique titre="Accès rapide" />
      <div className="grid grid-cols-3 gap-3">
        {tuiles.map(t => (
          <TuileAccueil key={t.label} label={t.label} icone={t.icone} teinte={t.couleur}
            href={t.href} onClick={t.href ? undefined : () => t.acte && choisirPatient(t.acte)} />
        ))}
      </div>

      {acte && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={() => setActe(null)}>
          <div className="bg-white w-full sm:max-w-md rounded-t-2xl sm:rounded-2xl p-5 max-h-[70vh] flex flex-col" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Pour quel patient ? ({acte.libelle})</p>
            <input value={filtre} onChange={e => setFiltre(e.target.value)} placeholder="Rechercher un patient…"
              className="w-full px-3 py-2 rounded-xl border text-sm mb-3" />
            <div className="overflow-y-auto flex-1 divide-y">
              {patients === null ? <p className="text-sm text-gray-400 py-4 text-center">Chargement…</p>
                : liste.length === 0 ? (
                  <p className="text-sm text-gray-500 py-4 text-center">
                    Aucun patient avec accès accordé. Demandez l&apos;accès depuis « Mes patients ».
                  </p>
                ) : liste.map(p => (
                  <button key={p.id} type="button"
                    onClick={() => router.push(`/mes-patients/${p.id}?tab=${encodeURIComponent(acte.onglet)}`)}
                    className="w-full flex items-center justify-between py-3 text-left hover:bg-gray-50 px-1">
                    <span>
                      <span className="block text-sm font-semibold text-[#1F2A2E]">{p.nom ?? 'Animal'}</span>
                      <span className="block text-xs text-gray-500">{[p.espece, p.race].filter(Boolean).join(' · ')}</span>
                    </span>
                    <span className="text-gray-400">›</span>
                  </button>
                ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
