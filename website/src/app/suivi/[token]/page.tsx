'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { RichText } from '@/lib/rich-text';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  photo_url?: string;
}

interface Objectif {
  id: string; libelle: string; categorie: string | null; statut: string;
}

interface Exercice {
  id: string; titre_snapshot: string; description_snapshot: string | null;
  cadence: string | null; echeance: string | null; statut: string;
}

interface Rapport {
  id: string; date_seance: string; contenu: string; type?: string;
  bilan_recommandation?: string | null;
}

const CAT_LABEL: Record<string, string> = {
  rappel: 'Rappel', laisse: 'Marche en laisse', proprete: 'Propreté', aboiements: 'Aboiements',
  destruction: 'Destruction', socialisation_chien: 'Socialisation chiens', socialisation_humain: 'Socialisation humains',
  manipulation: 'Manipulation / soins', solitude: 'Solitude', agressivite: 'Agressivité', peurs: 'Peurs', autre: 'Autre',
};
const STATUT_COLOR: Record<string, string> = { a_travailler: '#D5573B', en_cours: '#EFA100', acquis: '#6E9E57' };
const STATUT_LABEL: Record<string, string> = { a_travailler: 'À travailler', en_cours: 'En cours', acquis: 'Acquis' };

type State =
  | { status: 'loading' }
  | { status: 'expired' }
  | { status: 'invalid' }
  | { status: 'ok'; animal: Animal; objectifs: Objectif[]; exercices: Exercice[]; rapports: Rapport[] };

export default function SuiviPartagePage() {
  const { token } = useParams<{ token: string }>();
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (!token) { setState({ status: 'invalid' }); return; }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  async function load() {
    try {
      const { data: partage, error } = await supabase
        .from('partage_suivi_education')
        .select('animal_id, expire_at, actif')
        .eq('token', token)
        .single();
      if (error || !partage) { setState({ status: 'invalid' }); return; }
      if (!partage.actif || new Date(partage.expire_at) < new Date()) { setState({ status: 'expired' }); return; }

      const animalId = partage.animal_id as string;
      const [{ data: animal, error: aErr }, { data: objectifs }, { data: exercices }, { data: rapports }] = await Promise.all([
        supabase.from('animaux').select('id, nom, espece, race, photo_url').eq('id', animalId).single(),
        supabase.from('education_objectifs').select('id, libelle, categorie, statut').eq('animal_id', animalId).order('ordre').order('created_at'),
        supabase.from('exercices_attribues').select('id, titre_snapshot, description_snapshot, cadence, echeance, statut').eq('animal_id', animalId).order('assigned_at', { ascending: false }),
        supabase.from('education_progression').select('id, date_seance, contenu, type, bilan_recommandation').eq('animal_id', animalId).order('date_seance', { ascending: false }),
      ]);
      if (aErr || !animal) { setState({ status: 'invalid' }); return; }

      setState({
        status: 'ok', animal: animal as Animal,
        objectifs: (objectifs ?? []) as Objectif[],
        exercices: (exercices ?? []) as Exercice[],
        rapports: (rapports ?? []) as Rapport[],
      });
    } catch {
      setState({ status: 'invalid' });
    }
  }

  if (state.status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-[#EF6C00] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <p className="text-gray-500 font-medium">Chargement du suivi…</p>
        </div>
      </div>
    );
  }
  if (state.status === 'expired') {
    return <ErrorPage icon="⏰" title="Lien expiré" message="Ce lien de suivi n'est plus valide. Demandez un nouveau lien à l'éducateur." />;
  }
  if (state.status === 'invalid') {
    return <ErrorPage icon="🔒" title="Lien invalide" message="Ce lien de suivi est introuvable ou a été désactivé." />;
  }

  const { animal, objectifs, exercices, rapports } = state;

  return (
    <div className="min-h-screen bg-gradient-to-b from-orange-50 to-white">
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-2">
        <span className="text-xl font-bold text-[#EF6C00]" style={{ fontFamily: 'Galey, sans-serif' }}>PetsMatch</span>
        <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full ml-auto">Suivi éducatif · lecture seule</span>
      </div>

      <div className="max-w-md mx-auto px-4 py-8">
        {/* Identité */}
        <div className="bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden mb-4 flex items-center gap-4 p-4">
          <div className="w-16 h-16 rounded-2xl overflow-hidden bg-orange-50 flex items-center justify-center flex-shrink-0">
            {animal.photo_url
              // eslint-disable-next-line @next/next/no-img-element
              ? <img src={animal.photo_url} alt={animal.nom ?? ''} className="w-full h-full object-cover" />
              : <span className="text-3xl">🐾</span>}
          </div>
          <div className="min-w-0">
            <h1 className="text-xl font-bold text-gray-900" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.nom ?? 'Sans nom'}</h1>
            {animal.race && <p className="text-sm text-gray-500">{animal.race}</p>}
          </div>
        </div>

        {/* Plan de travail */}
        {objectifs.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">🎯 Plan de travail</p>
            <div className="space-y-2">
              {objectifs.map(o => (
                <div key={o.id} className="flex items-start gap-2">
                  <span className="w-2.5 h-2.5 rounded-full mt-1 shrink-0" style={{ background: STATUT_COLOR[o.statut] ?? '#999' }} />
                  <div>
                    <p className="text-sm font-semibold text-gray-800">{o.libelle}</p>
                    <p className="text-xs" style={{ color: STATUT_COLOR[o.statut] ?? '#999' }}>
                      {STATUT_LABEL[o.statut] ?? o.statut}{o.categorie && CAT_LABEL[o.categorie] ? ` · ${CAT_LABEL[o.categorie]}` : ''}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Exercices */}
        {exercices.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">🏋️ Exercices à faire</p>
            <div className="space-y-3">
              {exercices.map(e => (
                <div key={e.id} className="border border-gray-100 rounded-xl p-3">
                  <p className={`text-sm font-semibold ${e.statut === 'fait' ? 'line-through text-gray-400' : 'text-gray-800'}`}>{e.titre_snapshot}</p>
                  {(e.cadence || e.echeance) && (
                    <p className="text-[11px] text-gray-400 mt-0.5">
                      {[e.cadence, e.echeance ? `avant le ${new Date(e.echeance).toLocaleDateString('fr-FR')}` : null].filter(Boolean).join(' · ')}
                    </p>
                  )}
                  {e.description_snapshot && (
                    <div className="text-xs text-gray-600 mt-1.5"><RichText value={e.description_snapshot} /></div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Comptes rendus */}
        {rapports.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">📋 Comptes rendus</p>
            <div className="space-y-3">
              {rapports.map(r => {
                const isBilan = r.type === 'bilan';
                return (
                  <div key={r.id} className={`border rounded-xl p-3 ${isBilan ? 'border-[#EF6C00]' : 'border-gray-100'}`}>
                    <p className="text-xs text-gray-400 flex items-center gap-1.5 mb-1">
                      {isBilan && <span className="text-[9px] bg-[#EF6C00] text-white px-1 py-0.5 rounded font-bold">BILAN</span>}
                      {new Date(r.date_seance).toLocaleDateString('fr-FR')}
                    </p>
                    <div className="text-sm text-gray-800"><RichText value={r.contenu} /></div>
                    {isBilan && r.bilan_recommandation && (
                      <div className="mt-2 bg-[#FFF3E9] rounded-lg px-2.5 py-1.5">
                        <p className="text-[11px] font-bold text-[#EF6C00]">📋 Recommandation</p>
                        <div className="text-xs text-gray-800"><RichText value={r.bilan_recommandation} /></div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {objectifs.length === 0 && exercices.length === 0 && rapports.length === 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 text-center">
            <p className="text-sm text-gray-400">Aucun suivi disponible pour l&apos;instant.</p>
          </div>
        )}

        <p className="text-center text-xs text-gray-400 mt-6">Suivi partagé via PetsMatch · Lecture seule</p>
      </div>
    </div>
  );
}

function ErrorPage({ icon, title, message }: { icon: string; title: string; message: string }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="text-center max-w-sm">
        <div className="text-6xl mb-4">{icon}</div>
        <h1 className="text-xl font-bold text-gray-800 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h1>
        <p className="text-gray-500 text-sm leading-relaxed">{message}</p>
        <a href="/" className="mt-6 inline-block bg-[#EF6C00] text-white px-6 py-2.5 rounded-full text-sm font-medium hover:bg-[#d95f00] transition-colors">
          Retour à l&apos;accueil
        </a>
      </div>
    </div>
  );
}
