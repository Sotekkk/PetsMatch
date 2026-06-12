'use client';

import { useEffect, useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@supabase/supabase-js';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Certificat {
  id: string;
  nom_animal: string;
  espece: string;
  acquereur_nom: string;
  acquereur_prenom: string;
  acquereur_email: string;
  statut: string;
  date_remise: string;
  date_limite_signature: string | null;
  date_signature_acquereur: string | null;
  token_signature: string;
  modalite_cession: string;
}

interface Animal { id: string; nom: string; espece: string; race: string; date_naissance: string; num_identification: string; }
interface UserProfile { name_elevage: string; siret: string; phone: string; rue_elevage: string; ville_elevage: string; code_postal_elevage: string; first_name: string; last_name: string; }

const STATUT_STYLE: Record<string, string> = {
  envoye:  'bg-blue-100 text-blue-700',
  lu:      'bg-amber-100 text-amber-700',
  signe:   'bg-green-100 text-green-700',
  refuse:  'bg-red-100 text-red-600',
};
const STATUT_LABEL: Record<string, string> = { envoye: 'Envoyé', lu: 'Lu', signe: 'Signé', refuse: 'Refusé' };

const ESPECES_DELAI = ['Chien', 'Chat'];

export default function CertificatEngagementPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const { config: planConfig, loading: planLoading } = usePlan();
  const [certificats, setCertificats] = useState<Certificat[]>([]);
  const [fetching, setFetching] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const printRef = useRef<HTMLDivElement>(null);

  // Form state
  const [animalId, setAnimalId] = useState('');
  const [selectedAnimal, setSelectedAnimal] = useState<Animal | null>(null);
  const [acqNom, setAcqNom] = useState('');
  const [acqPrenom, setAcqPrenom] = useState('');
  const [acqEmail, setAcqEmail] = useState('');
  const [acqTel, setAcqTel] = useState('');
  const [acqAdresse, setAcqAdresse] = useState('');
  const [modalite, setModalite] = useState('vente');
  const [prix, setPrix] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [newToken, setNewToken] = useState<string | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabaseAdmin.from('certificats_engagement').select('*').eq('cedant_uid', user.uid).order('created_at', { ascending: false }),
      supabaseAdmin.from('animaux').select('id,nom,espece,race,date_naissance,num_identification').eq('uid_eleveur', user.uid).neq('statut', 'decede').order('nom'),
      supabaseAdmin.from('users').select('name_elevage,siret,phone,rue_elevage,ville_elevage,code_postal_elevage,first_name,last_name').eq('uid', user.uid).maybeSingle(),
    ]).then(([certs, anim, prof]) => {
      setCertificats((certs.data ?? []) as Certificat[]);
      setAnimaux((anim.data ?? []) as Animal[]);
      setProfile(prof.data as UserProfile | null);
      setFetching(false);
    });
  }, [user]);

  function selectAnimal(id: string) {
    setAnimalId(id);
    setSelectedAnimal(animaux.find(a => a.id === id) ?? null);
  }

  async function handleCreate() {
    if (!user || !selectedAnimal) return;
    if (!acqEmail.trim() || !acqNom.trim() || !acqPrenom.trim()) {
      setError('Nom, prénom et email de l\'acquéreur sont obligatoires.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const needsDelai = ESPECES_DELAI.includes(selectedAnimal.espece);
      const dateRemise = new Date();
      const dateLimite = needsDelai ? new Date(dateRemise.getTime() + 7 * 86400_000) : null;

      const res = await fetch('/api/certificat/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid: user.uid,
          animal_id: selectedAnimal.id,
          espece: selectedAnimal.espece,
          race: selectedAnimal.race,
          nom_animal: selectedAnimal.nom,
          date_naissance_animal: selectedAnimal.date_naissance,
          num_identification: selectedAnimal.num_identification,
          acquereur_nom: acqNom.trim(),
          acquereur_prenom: acqPrenom.trim(),
          acquereur_email: acqEmail.trim(),
          acquereur_telephone: acqTel.trim(),
          acquereur_adresse: acqAdresse.trim(),
          modalite_cession: modalite,
          prix: prix ? parseFloat(prix) : null,
          date_remise: dateRemise.toISOString(),
          date_limite_signature: dateLimite?.toISOString() ?? null,
          notes: notes.trim(),
        }),
      });
      const json = await res.json();
      if (!res.ok) { setError(json.error ?? 'Erreur serveur'); return; }
      setNewToken(json.token);
      setCertificats(prev => [json.certificat, ...prev]);
      setShowForm(false);
      resetForm();
    } finally {
      setSaving(false);
    }
  }

  function resetForm() {
    setAnimalId(''); setSelectedAnimal(null);
    setAcqNom(''); setAcqPrenom(''); setAcqEmail(''); setAcqTel(''); setAcqAdresse('');
    setModalite('vente'); setPrix(''); setNotes(''); setError('');
  }

  function handlePrint() { window.print(); }

  if (loading || planLoading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  if (!planConfig.hasRegistres) {
    return (
      <div className="min-h-[70vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
        <span className="text-5xl">🔒</span>
        <h2 className="text-xl font-bold text-[#1F2A2E]">Certificats — Plan Pro requis</h2>
        <p className="text-gray-500 text-sm max-w-sm">La gestion des certificats d'engagement est disponible à partir du plan Pro.</p>
        <a href="/abonnement" className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-6 py-3 rounded-xl text-sm">⚡ Voir les plans</a>
      </div>
    );
  }

  const origin = typeof window !== 'undefined' ? window.location.origin : 'https://petsmatch.fr';

  return (
    <div className="max-w-4xl mx-auto px-4 py-10 print:p-0">

      {/* Header — masqué à l'impression */}
      <div className="print:hidden">
        <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces</Link>
        <div className="flex items-center justify-between mt-1 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Certificats d'engagement</h1>
            <p className="text-gray-500 text-sm">Loi du 30/11/2021 — obligatoire pour chiens et chats</p>
          </div>
          <button onClick={() => { setShowForm(true); setNewToken(null); }}
            className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-5 py-2.5 rounded-xl text-sm">
            + Nouveau certificat
          </button>
        </div>

        {/* Bandeau lien après création */}
        {newToken && (
          <div className="mb-6 bg-green-50 border border-green-200 rounded-xl p-4">
            <p className="text-sm font-semibold text-green-800 mb-1">✅ Certificat créé — partagez ce lien à l'acquéreur :</p>
            <div className="flex items-center gap-2 mt-2">
              <code className="text-xs bg-white border border-green-200 rounded px-3 py-2 flex-1 text-green-700 break-all">
                {origin}/certificat/{newToken}
              </code>
              <button onClick={() => navigator.clipboard.writeText(`${origin}/certificat/${newToken}`)}
                className="shrink-0 bg-green-600 hover:bg-green-700 text-white text-xs font-semibold px-3 py-2 rounded-lg">
                Copier
              </button>
            </div>
            <p className="text-xs text-green-600 mt-2">
              L'acquéreur ouvre ce lien, lit le certificat, et peut signer après le délai légal (7 jours pour chien/chat).
            </p>
          </div>
        )}

        {/* Formulaire nouveau certificat */}
        {showForm && (
          <div className="fixed inset-0 bg-black/50 z-50 flex items-start justify-center overflow-y-auto py-8 px-4">
            <div className="bg-white rounded-2xl shadow-2xl w-full max-w-2xl p-6">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-lg font-bold text-[#1F2A2E]">Nouveau certificat d'engagement</h2>
                <button onClick={() => { setShowForm(false); resetForm(); }} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
              </div>

              {error && <div className="mb-4 text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-4 py-2">{error}</div>}

              <div className="space-y-4">
                {/* Animal */}
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Animal concerné *</label>
                  <select value={animalId} onChange={e => selectAnimal(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30">
                    <option value="">Sélectionner un animal…</option>
                    {animaux.map(a => (
                      <option key={a.id} value={a.id}>{a.nom} — {a.espece} {a.race ? `(${a.race})` : ''}</option>
                    ))}
                  </select>
                  {selectedAnimal && ESPECES_DELAI.includes(selectedAnimal.espece) && (
                    <p className="text-xs text-amber-600 mt-1">⚠ {selectedAnimal.espece} : délai légal de 7 jours avant signature de l'acquéreur.</p>
                  )}
                </div>

                {/* Acquéreur */}
                <div className="border-t pt-4">
                  <p className="text-xs font-semibold text-gray-500 uppercase mb-3">Acquéreur</p>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-600 mb-1">Nom *</label>
                      <input value={acqNom} onChange={e => setAcqNom(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="Dupont" />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-600 mb-1">Prénom *</label>
                      <input value={acqPrenom} onChange={e => setAcqPrenom(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="Marie" />
                    </div>
                  </div>
                  <div className="mt-3">
                    <label className="block text-xs text-gray-600 mb-1">Email *</label>
                    <input type="email" value={acqEmail} onChange={e => setAcqEmail(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="marie@example.com" />
                  </div>
                  <div className="grid grid-cols-2 gap-3 mt-3">
                    <div>
                      <label className="block text-xs text-gray-600 mb-1">Téléphone</label>
                      <input value={acqTel} onChange={e => setAcqTel(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="06 12 34 56 78" />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-600 mb-1">Modalité</label>
                      <select value={modalite} onChange={e => setModalite(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm">
                        <option value="vente">Vente</option>
                        <option value="gratuit">Cession gratuite</option>
                        <option value="adoption">Adoption</option>
                      </select>
                    </div>
                  </div>
                  <div className="mt-3">
                    <label className="block text-xs text-gray-600 mb-1">Adresse complète</label>
                    <input value={acqAdresse} onChange={e => setAcqAdresse(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="12 rue des Lilas, 75001 Paris" />
                  </div>
                  {modalite === 'vente' && (
                    <div className="mt-3">
                      <label className="block text-xs text-gray-600 mb-1">Prix (€)</label>
                      <input type="number" value={prix} onChange={e => setPrix(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="500" />
                    </div>
                  )}
                  <div className="mt-3">
                    <label className="block text-xs text-gray-600 mb-1">Notes internes</label>
                    <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm resize-none" />
                  </div>
                </div>
              </div>

              <div className="flex gap-3 mt-6">
                <button onClick={() => { setShowForm(false); resetForm(); }} className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50">Annuler</button>
                <button onClick={handleCreate} disabled={saving || !animalId || !acqNom || !acqPrenom || !acqEmail}
                  className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-2.5 rounded-xl text-sm">
                  {saving ? 'Création…' : 'Créer le certificat'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Liste */}
        {fetching ? (
          <div className="text-center py-16 text-gray-400">Chargement…</div>
        ) : certificats.length === 0 ? (
          <div className="text-center py-16 text-gray-400">
            <p className="text-4xl mb-3">📄</p>
            <p className="font-medium text-gray-600">Aucun certificat</p>
            <p className="text-sm mt-1">Créez votre premier certificat d'engagement pour une cession</p>
          </div>
        ) : (
          <div className="space-y-3">
            {certificats.map(cert => (
              <div key={cert.id} className="bg-white border border-gray-100 rounded-xl p-4 flex items-center gap-4 shadow-sm">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-[#1F2A2E] text-sm">{cert.nom_animal}</span>
                    <span className="text-xs text-gray-400">({cert.espece})</span>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${STATUT_STYLE[cert.statut] ?? 'bg-gray-100 text-gray-600'}`}>
                      {STATUT_LABEL[cert.statut] ?? cert.statut}
                    </span>
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    Acquéreur : {cert.acquereur_prenom} {cert.acquereur_nom} — {cert.acquereur_email}
                  </p>
                  <p className="text-xs text-gray-400 mt-0.5">
                    Remis le {new Date(cert.date_remise).toLocaleDateString('fr-FR')}
                    {cert.date_limite_signature && cert.statut !== 'signe' && (
                      <> · Signature possible à partir du {new Date(cert.date_limite_signature).toLocaleDateString('fr-FR')}</>
                    )}
                    {cert.date_signature_acquereur && (
                      <> · Signé le {new Date(cert.date_signature_acquereur).toLocaleDateString('fr-FR')}</>
                    )}
                  </p>
                </div>
                <div className="flex gap-2 shrink-0">
                  <button onClick={() => navigator.clipboard.writeText(`${origin}/certificat/${cert.token_signature}`)}
                    className="text-xs border border-gray-200 text-gray-600 px-3 py-1.5 rounded-lg hover:bg-gray-50">
                    Copier lien
                  </button>
                  <Link href={`/certificat/${cert.token_signature}`} target="_blank"
                    className="text-xs bg-[#0C5C6C]/10 text-[#0C5C6C] px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/20 font-medium">
                    Voir
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
