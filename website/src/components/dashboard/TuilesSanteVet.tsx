'use client';
// Accès rapide de l'accueil — santé (ostéo / kiné) et vétérinaire — en MIROIR
// de l'appli (eleveur_home.dart : _buildSanteShortcuts / _buildVetShortcuts) :
// mêmes tuiles, même ordre, même style (fond blanc, fin contour coloré, petite
// icône, texte foncé de même taille).
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Tuile { label: string; icone: string; couleur: string; href?: string; acte?: { libelle: string; onglet: string } }

const classeTuile = 'h-24 bg-white rounded-2xl border shadow-sm hover:shadow-md transition-shadow flex flex-col items-center justify-center gap-1.5 px-2 text-center';

function contenu(t: Tuile) {
  return (
    <>
      <span className="text-lg leading-none" aria-hidden>{t.icone}</span>
      <span className="text-xs font-semibold text-[#1F2A2E] leading-tight line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>{t.label}</span>
    </>
  );
}

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
        { label: 'Mes patients', icone: '🩺', couleur: '#0C5C6C', href: '/mes-patients' },
        { label: 'Agenda RDV', icone: '📅', couleur: '#5F9EAA', href: '/agenda' },
        { label: 'Mes suivis', icone: '🦴', couleur: '#7B5EA7', href: '/sante/suivis' },
        { label: 'Mes contrats', icone: '📄', couleur: '#B8860B', href: '/sante/contrat' },
        { label: 'Facturation', icone: '🧾', couleur: '#6E9E57', href: '/elevage/facturation' },
        { label: 'Mon abonnement', icone: '⭐', couleur: '#D97706', href: abonnementHref },
      ]
    : [
        { label: 'Mes patients', icone: '🩺', couleur: '#0C5C6C', href: '/mes-patients' },
        { label: 'Agenda RDV', icone: '📅', couleur: '#5F9EAA', href: '/agenda' },
        { label: 'Rechercher une puce', icone: '🔍', couleur: '#475569', href: '/mes-patients' },
        { label: 'Ordonnance', icone: '💊', couleur: '#7B5EA7', acte: { libelle: 'une ordonnance', onglet: 'Consultations' } },
        { label: 'Vaccin', icone: '💉', couleur: '#2E7D5E', acte: { libelle: 'un vaccin', onglet: 'Santé' } },
        { label: 'Compte rendu', icone: '📝', couleur: '#B8860B', acte: { libelle: 'un compte rendu', onglet: 'Consultations' } },
        { label: 'Messages', icone: '💬', couleur: '#5F9EAA', href: '/messages' },
        { label: 'Facturation', icone: '🧾', couleur: '#6E9E57', href: '/elevage/facturation' },
        { label: 'Mon abonnement', icone: '⭐', couleur: '#D97706', href: abonnementHref },
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
      <p className="text-xs font-bold text-gray-500 uppercase tracking-wide mb-3">Accès rapide</p>
      <div className="grid grid-cols-3 gap-3">
        {tuiles.map(t => t.href ? (
          <Link key={t.label} href={t.href} className={classeTuile} style={{ borderColor: `${t.couleur}59` }}>{contenu(t)}</Link>
        ) : (
          <button key={t.label} type="button" onClick={() => t.acte && choisirPatient(t.acte)}
            className={classeTuile} style={{ borderColor: `${t.couleur}59` }}>{contenu(t)}</button>
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
