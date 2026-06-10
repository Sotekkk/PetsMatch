'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useRouter, useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal {
  id: number;
  nom: string;
  espece: string;
  race: string;
  sexe: string;
  couleur: string;
  date_naissance: string | null;
  identification: string | null;
  photo: string | null;
  sterilise: boolean;
  poids: number | null;
  notes: string | null;
}

interface Consultation {
  id: string;
  date: string;
  motif: string | null;
  diagnostic: string | null;
  traitement: string | null;
  notes: string | null;
  vet_uid: string;
  created_at: string;
}

interface Vaccine {
  id: string;
  vaccin: string;
  date_injection: string;
  date_rappel: string | null;
  lot: string | null;
  vet_uid: string;
}

const TABS = ['Fiche', 'Consultations', 'Vaccins'] as const;
type Tab = typeof TABS[number];

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}

function age(dateNaissance: string | null): string {
  if (!dateNaissance) return '';
  const birth = new Date(dateNaissance);
  const now = new Date();
  const months = (now.getFullYear() - birth.getFullYear()) * 12 + now.getMonth() - birth.getMonth();
  if (months < 24) return `${months} mois`;
  return `${Math.floor(months / 12)} ans`;
}

export default function PatientDetailPage() {
  const { user } = useAuth();
  const router = useRouter();
  const params = useParams();
  const animalId = Number(params.id);

  const [tab, setTab] = useState<Tab>('Fiche');
  const [animal, setAnimal] = useState<Animal | null>(null);
  const [consultations, setConsultations] = useState<Consultation[]>([]);
  const [vaccines, setVaccines] = useState<Vaccine[]>([]);
  const [loading, setLoading] = useState(true);
  const [addingConsult, setAddingConsult] = useState(false);

  // New consultation form
  const [consultMotif, setConsultMotif] = useState('');
  const [consultDiag, setConsultDiag] = useState('');
  const [consultTreatment, setConsultTreatment] = useState('');
  const [consultNotes, setConsultNotes] = useState('');
  const [consultDate, setConsultDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [savingConsult, setSavingConsult] = useState(false);

  useEffect(() => {
    if (!user || !animalId) return;
    async function load() {
      const [animalRes, consultRes, vaccineRes] = await Promise.all([
        supabase.from('animaux').select('*').eq('id', animalId).single(),
        supabase.from('consultations_vet').select('*').eq('animal_id', animalId)
          .order('date', { ascending: false }),
        supabase.from('vaccins').select('*').eq('animal_id', animalId)
          .order('date_injection', { ascending: false }),
      ]);
      setAnimal(animalRes.data as Animal | null);
      setConsultations((consultRes.data ?? []) as Consultation[]);
      setVaccines((vaccineRes.data ?? []) as Vaccine[]);
      setLoading(false);
    }
    load();
  }, [user, animalId]);

  async function saveConsultation() {
    if (!user || !animalId) return;
    setSavingConsult(true);
    const { data } = await supabase.from('consultations_vet').insert({
      animal_id: animalId,
      vet_uid: user.uid,
      date: consultDate,
      motif: consultMotif.trim() || null,
      diagnostic: consultDiag.trim() || null,
      traitement: consultTreatment.trim() || null,
      notes: consultNotes.trim() || null,
    }).select().single();
    if (data) {
      setConsultations(prev => [data as Consultation, ...prev]);
    }
    setConsultMotif(''); setConsultDiag(''); setConsultTreatment(''); setConsultNotes('');
    setConsultDate(new Date().toISOString().slice(0, 10));
    setAddingConsult(false);
    setSavingConsult(false);
  }

  if (!user) return null;

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!animal) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400 text-sm">
      Animal introuvable ou accès refusé.
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white">
        <div className="max-w-3xl mx-auto px-4 py-4 flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">←</button>
          <h1 className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>Fiche patient</h1>
        </div>

        {/* Animal summary */}
        <div className="max-w-3xl mx-auto px-4 pb-5 flex items-center gap-4">
          <div className="w-16 h-16 rounded-2xl overflow-hidden bg-white/20 flex-shrink-0 flex items-center justify-center">
            {animal.photo
              ? <Image src={animal.photo} alt="" width={64} height={64} className="object-cover w-full h-full" />
              : <span className="text-3xl">{ESPECE_EMOJI[animal.espece?.toLowerCase()] ?? '🐾'}</span>
            }
          </div>
          <div>
            <h2 className="text-xl font-bold">{animal.nom}</h2>
            <p className="text-white/70 text-sm">{animal.race || animal.espece}{animal.date_naissance ? ` · ${age(animal.date_naissance)}` : ''}</p>
            <div className="flex gap-2 mt-1">
              {animal.sterilise && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">Stérilisé(e)</span>}
              {animal.poids && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">{animal.poids} kg</span>}
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="max-w-3xl mx-auto px-4 overflow-x-auto">
          <div className="flex gap-1 bg-white/10 rounded-xl p-1 min-w-max">
            {TABS.map(t => (
              <button key={t} onClick={() => setTab(t)}
                className="whitespace-nowrap px-4 py-2 text-sm font-semibold rounded-lg transition-colors"
                style={{
                  background: tab === t ? 'white' : 'transparent',
                  color: tab === t ? '#0C5C6C' : 'rgba(255,255,255,0.7)',
                  fontFamily: 'Galey, sans-serif',
                }}>
                {t}
              </button>
            ))}
          </div>
        </div>
        <div className="h-4" />
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">

        {/* ── Fiche ── */}
        {tab === 'Fiche' && (
          <div className="space-y-4">
            <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-bold text-sm text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>Identité</h3>
              <div className="grid grid-cols-2 gap-3 text-sm">
                {[
                  { label: 'Espèce', value: animal.espece },
                  { label: 'Race', value: animal.race },
                  { label: 'Sexe', value: animal.sexe },
                  { label: 'Couleur', value: animal.couleur },
                  { label: 'Naissance', value: animal.date_naissance ? fmtDate(animal.date_naissance) : '—' },
                  { label: 'Poids', value: animal.poids ? `${animal.poids} kg` : '—' },
                  { label: 'Identification', value: animal.identification || '—' },
                  { label: 'Stérilisé(e)', value: animal.sterilise ? 'Oui' : 'Non' },
                ].map(row => (
                  <div key={row.label}>
                    <p className="text-[10px] text-gray-400 uppercase tracking-wide">{row.label}</p>
                    <p className="font-medium text-[#1F2A2E]">{row.value || '—'}</p>
                  </div>
                ))}
              </div>
            </div>
            {animal.notes && (
              <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
                <h3 className="font-bold text-sm text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Notes</h3>
                <p className="text-sm text-gray-600 whitespace-pre-wrap">{animal.notes}</p>
              </div>
            )}
          </div>
        )}

        {/* ── Consultations ── */}
        {tab === 'Consultations' && (
          <div className="space-y-4">
            <button onClick={() => setAddingConsult(true)}
              className="w-full bg-[#0C5C6C] text-white rounded-2xl py-3 font-semibold text-sm hover:bg-[#094F5D] transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              + Nouvelle consultation
            </button>

            {consultations.length === 0 ? (
              <div className="text-center py-12 text-gray-400 text-sm">Aucune consultation enregistrée</div>
            ) : (
              <div className="space-y-3">
                {consultations.map(c => (
                  <div key={c.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4">
                    <div className="flex items-center justify-between mb-2">
                      <p className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                        {fmtDate(c.date)}
                      </p>
                      {c.motif && <span className="text-xs bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">{c.motif}</span>}
                    </div>
                    {c.diagnostic && (
                      <div className="mb-1">
                        <span className="text-xs font-semibold text-gray-500">Diagnostic : </span>
                        <span className="text-xs text-gray-700">{c.diagnostic}</span>
                      </div>
                    )}
                    {c.traitement && (
                      <div className="mb-1">
                        <span className="text-xs font-semibold text-gray-500">Traitement : </span>
                        <span className="text-xs text-gray-700">{c.traitement}</span>
                      </div>
                    )}
                    {c.notes && <p className="text-xs text-gray-400 mt-1">{c.notes}</p>}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ── Vaccins ── */}
        {tab === 'Vaccins' && (
          <div className="space-y-3">
            {vaccines.length === 0 ? (
              <div className="text-center py-12 text-gray-400 text-sm">Aucun vaccin enregistré</div>
            ) : (
              vaccines.map(v => {
                const rappelDue = v.date_rappel && new Date(v.date_rappel) <= new Date();
                return (
                  <div key={v.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 flex items-center gap-4">
                    <div className="w-10 h-10 rounded-xl bg-[#E3F2FD] flex items-center justify-center flex-shrink-0 text-lg">💉</div>
                    <div className="flex-1">
                      <p className="font-bold text-sm text-[#1F2A2E]">{v.vaccin}</p>
                      <p className="text-xs text-gray-500">Injecté le {fmtDate(v.date_injection)}</p>
                      {v.date_rappel && (
                        <p className={`text-xs font-medium mt-0.5 ${rappelDue ? 'text-red-500' : 'text-[#0C5C6C]'}`}>
                          {rappelDue ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDate(v.date_rappel)}
                        </p>
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        )}

      </div>

      {/* Modal nouvelle consultation */}
      {addingConsult && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setAddingConsult(false)}>
          <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Nouvelle consultation
              </h3>
              <button onClick={() => setAddingConsult(false)} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Date</label>
              <input type="date" value={consultDate} onChange={e => setConsultDate(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Motif</label>
              <input value={consultMotif} onChange={e => setConsultMotif(e.target.value)}
                placeholder="Ex : Consultation, Vaccination…"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Diagnostic</label>
              <textarea value={consultDiag} onChange={e => setConsultDiag(e.target.value)}
                rows={2} placeholder="Diagnostic…"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Traitement prescrit</label>
              <textarea value={consultTreatment} onChange={e => setConsultTreatment(e.target.value)}
                rows={2} placeholder="Médicaments, posologie…"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
              <textarea value={consultNotes} onChange={e => setConsultNotes(e.target.value)}
                rows={2} placeholder="Notes libres…"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
            </div>
            <div className="flex gap-3 pt-1">
              <button onClick={() => setAddingConsult(false)}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                Annuler
              </button>
              <button onClick={saveConsultation} disabled={savingConsult}
                className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                {savingConsult ? 'Enregistrement…' : 'Enregistrer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
