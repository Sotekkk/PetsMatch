'use client';

import { useEffect, useState, useRef } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@supabase/supabase-js';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import AddressAutocomplete from '@/components/AddressAutocomplete';

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Certificat {
  id: string;
  animal_id: string;
  nom_animal: string;
  espece: string;
  acquereur_nom: string;
  acquereur_prenom: string;
  acquereur_email: string;
  acquereur_telephone: string;
  acquereur_adresse: string;
  statut: string;
  date_remise: string;
  date_limite_signature: string | null;
  date_signature_acquereur: string | null;
  token_signature: string;
  modalite_cession: string;
  prix: number | string | null;
  notes: string;
}

interface Animal { id: string; nom: string; espece: string; race: string; date_naissance: string; identification: string; }
interface UserProfile { name_elevage: string; siret: string; phone_number: string; rue_elevage: string; ville_elevage: string; code_postal_elevage: string; firstname: string; lastname: string; }

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
  const pathname = usePathname();
  const profilSource = pathname.startsWith('/association') ? 'association' : 'eleveur';
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

  // Recherche acquéreur dans la base PetsMatch
  const [userSearch, setUserSearch] = useState('');
  const [userResults, setUserResults] = useState<{uid:string;firstname:string;lastname:string;name_elevage?:string;is_elevage?:boolean;email:string;phone_number?:string;rue?:string;ville?:string;code_postal?:string;rue_elevage?:string;ville_elevage?:string;code_postal_elevage?:string}[]>([]);
  const [userSearchLoading, setUserSearchLoading] = useState(false);
  const [editingCert, setEditingCert] = useState<Certificat | null>(null);
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      (() => { const q = supabaseAdmin.from('certificats_engagement').select('id,animal_id,nom_animal,espece,acquereur_nom,acquereur_prenom,acquereur_email,acquereur_telephone,acquereur_adresse,statut,date_remise,date_limite_signature,date_signature_acquereur,token_signature,modalite_cession,prix,notes').eq('cedant_uid', user.uid).order('created_at', { ascending: false });
        return profilSource === 'association' ? q.eq('profil_source', 'association') : q.or('profil_source.is.null,profil_source.eq.eleveur'); })(),
      (() => { const q = supabaseAdmin.from('animaux').select('id,nom,espece,race,date_naissance,identification').eq('uid_eleveur', user.uid).order('nom');
        return profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false'); })(),
      supabaseAdmin.from('user_profiles').select('nom,siret,phone_number,rue_pro,ville_pro,code_postal_pro,firstname,lastname').eq('uid', user.uid).eq('is_main', true).maybeSingle(),
    ]).then(([certs, anim, prof]) => {
      setCertificats((certs.data ?? []) as Certificat[]);
      setAnimaux((anim.data ?? []) as Animal[]);
      const cp = prof.data;
      setProfile(cp ? {
        name_elevage: cp.nom, siret: cp.siret, phone_number: cp.phone_number,
        rue_elevage: cp.rue_pro, ville_elevage: cp.ville_pro, code_postal_elevage: cp.code_postal_pro,
        firstname: cp.firstname, lastname: cp.lastname,
      } : null);
      setFetching(false);
    });
  }, [user]);

  async function searchUsers(q: string) {
    setUserSearch(q);
    if (q.trim().length < 2) { setUserResults([]); return; }
    setUserSearchLoading(true);
    const cpFields = 'uid,firstname,lastname,nom,profile_type,email_contact,phone_number,rue,ville,code_postal,rue_pro,ville_pro,code_postal_pro';
    const toResult = (cp: Record<string, unknown>, email?: string) => ({
      uid: cp.uid as string, firstname: cp.firstname as string, lastname: cp.lastname as string,
      name_elevage: cp.nom as string | undefined, is_elevage: cp.profile_type === 'eleveur',
      email: email || (cp.email_contact as string | undefined) || '',
      phone_number: cp.phone_number as string | undefined,
      rue: cp.rue as string | undefined, ville: cp.ville as string | undefined, code_postal: cp.code_postal as string | undefined,
      rue_elevage: cp.rue_pro as string | undefined, ville_elevage: cp.ville_pro as string | undefined, code_postal_elevage: cp.code_postal_pro as string | undefined,
    });
    if (q.includes('@')) {
      const { data: users } = await supabaseAdmin.from('users').select('uid,email').ilike('email', `%${q}%`).neq('uid', user?.uid ?? '').limit(6);
      const uids = (users ?? []).map(u => u.uid);
      const emailByUid = new Map((users ?? []).map(u => [u.uid, u.email as string]));
      const { data: cps } = uids.length
        ? await supabaseAdmin.from('user_profiles').select(cpFields).in('uid', uids).eq('is_main', true)
        : { data: [] as Record<string, unknown>[] };
      setUserResults((cps ?? []).map(cp => toResult(cp, emailByUid.get(cp.uid as string))));
    } else {
      const { data: cps } = await supabaseAdmin.from('user_profiles').select(cpFields)
        .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%`).eq('is_main', true).neq('uid', user?.uid ?? '').limit(6);
      setUserResults((cps ?? []).map(cp => toResult(cp)));
    }
    setUserSearchLoading(false);
  }

  function prefillUser(u: typeof userResults[0]) {
    // Nom : utiliser name_elevage uniquement si c'est un professionnel, sinon nom personnel
    setAcqNom(u.is_elevage && u.name_elevage ? u.name_elevage : (u.lastname ?? ''));
    setAcqPrenom(u.is_elevage && u.name_elevage ? '' : (u.firstname ?? ''));
    setAcqEmail(u.email ?? '');
    setAcqTel(u.phone_number ?? '');
    // Préférer l'adresse personnelle (un éleveur peut acheter pour usage privé)
    const personalAddr = [u.rue, u.code_postal, u.ville].filter(Boolean).join(', ');
    const elevageAddr = [u.rue_elevage, u.code_postal_elevage, u.ville_elevage].filter(Boolean).join(', ');
    setAcqAdresse(personalAddr || elevageAddr || '');
    setUserSearch(`${u.firstname ?? ''} ${u.lastname ?? ''}`.trim());
    setUserResults([]);
  }

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
          num_identification: selectedAnimal.identification,
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
          profil_source: profilSource,
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
    setUserSearch(''); setUserResults([]);
    setEditingCert(null);
  }

  function openEdit(cert: Certificat) {
    setAcqNom(cert.acquereur_nom);
    setAcqPrenom(cert.acquereur_prenom);
    setAcqEmail(cert.acquereur_email);
    setAcqTel(cert.acquereur_telephone ?? '');
    setAcqAdresse(cert.acquereur_adresse ?? '');
    setModalite(cert.modalite_cession);
    setPrix(cert.prix != null ? String(cert.prix) : '');
    setNotes(cert.notes ?? '');
    setEditingCert(cert);
    setError('');
    setShowForm(true);
  }

  async function handleUpdate() {
    if (!editingCert || !user) return;
    setSaving(true); setError('');
    try {
      const { data, error: err } = await supabaseAdmin
        .from('certificats_engagement')
        .update({
          acquereur_nom: acqNom.trim(),
          acquereur_prenom: acqPrenom.trim(),
          acquereur_email: acqEmail.trim(),
          acquereur_telephone: acqTel.trim(),
          acquereur_adresse: acqAdresse.trim(),
          modalite_cession: modalite,
          prix: modalite === 'vente' && prix ? parseFloat(prix.replace(',', '.')) : null,
          notes: notes.trim(),
        })
        .eq('id', editingCert.id)
        .select()
        .single();
      if (err) { setError(err.message); return; }
      setCertificats(prev => prev.map(c => c.id === editingCert.id ? { ...c, ...data } : c));
      setShowForm(false); resetForm();
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(id: string) {
    await supabaseAdmin.from('certificats_engagement').delete().eq('id', id).neq('statut', 'signe');
    setCertificats(prev => prev.filter(c => c.id !== id));
    setDeleteConfirmId(null);
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

  const origin = typeof window !== 'undefined' ? window.location.origin : 'https://www.petsmatchapp.com';

  return (
    <div className="max-w-4xl mx-auto px-4 py-10 print:p-0">

      {/* Header — masqué à l'impression */}
      <div className="print:hidden">
        <Link href="/elevage/contrat" className="text-sm text-[#0C5C6C] hover:underline">← Mes Contrats</Link>
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
                <h2 className="text-lg font-bold text-[#1F2A2E]">
                  {editingCert ? `Modifier — ${editingCert.nom_animal}` : 'Nouveau certificat d\'engagement'}
                </h2>
                <button onClick={() => { setShowForm(false); resetForm(); }} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
              </div>

              {error && <div className="mb-4 text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-4 py-2">{error}</div>}

              <div className="space-y-4">
                {/* Animal */}
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Animal concerné *</label>
                  {editingCert ? (
                    <div className="bg-gray-50 border border-gray-200 rounded-xl px-3 py-2.5 text-sm text-gray-700">
                      {editingCert.nom_animal} <span className="text-gray-400">({editingCert.espece})</span>
                      <p className="text-[10px] text-gray-400 mt-0.5">L'animal ne peut pas être modifié après création</p>
                    </div>
                  ) : (
                    <>
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
                    </>
                  )}
                </div>

                {/* Acquéreur */}
                <div className="border-t pt-4">
                  <p className="text-xs font-semibold text-gray-500 uppercase mb-3">Acquéreur</p>

                  {/* Recherche utilisateur PetsMatch */}
                  <div className="relative mb-4">
                    <label className="block text-xs text-gray-600 mb-1">Rechercher un utilisateur PetsMatch (optionnel)</label>
                    <div className="relative">
                      <input
                        value={userSearch}
                        onChange={e => searchUsers(e.target.value)}
                        placeholder="Prénom, nom ou email…"
                        className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm pr-8 focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                      />
                      {userSearchLoading && <span className="absolute right-2 top-2.5 text-gray-400 text-xs">…</span>}
                    </div>
                    {userResults.length > 0 && (
                      <div className="absolute z-20 w-full bg-white border border-gray-200 rounded-xl shadow-lg mt-1 max-h-48 overflow-y-auto">
                        {userResults.map(u => (
                          <button key={u.uid} onClick={() => prefillUser(u)}
                            className="w-full text-left px-4 py-2.5 hover:bg-[#E8F4F6] text-sm flex flex-col">
                            <span className="font-medium text-[#1F2A2E]">{u.firstname} {u.lastname}</span>
                            <span className="text-xs text-gray-500">{u.email}{u.ville ? ` · ${u.ville}` : ''}</span>
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
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
                    <AddressAutocomplete value={acqAdresse} onChange={setAcqAdresse} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" placeholder="12 rue des Lilas, 75001 Paris" />
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
                {editingCert ? (
                  <button onClick={handleUpdate} disabled={saving || !acqNom || !acqPrenom || !acqEmail}
                    className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-2.5 rounded-xl text-sm">
                    {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
                  </button>
                ) : (
                  <button onClick={handleCreate} disabled={saving || !animalId || !acqNom || !acqPrenom || !acqEmail}
                    className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-2.5 rounded-xl text-sm">
                    {saving ? 'Création…' : 'Créer le certificat'}
                  </button>
                )}
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
                <div className="flex gap-1.5 shrink-0 flex-wrap justify-end">
                  <button onClick={() => navigator.clipboard.writeText(`${origin}/certificat/${cert.token_signature}`)}
                    className="text-xs border border-gray-200 text-gray-600 px-3 py-1.5 rounded-lg hover:bg-gray-50">
                    Lien
                  </button>
                  <Link href={`/certificat/${cert.token_signature}`} target="_blank"
                    className="text-xs bg-[#0C5C6C]/10 text-[#0C5C6C] px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/20 font-medium">
                    Voir
                  </Link>
                  {cert.statut !== 'signe' && (
                    <>
                      <button onClick={() => openEdit(cert)}
                        className="text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] px-3 py-1.5 rounded-lg hover:bg-[#E8F4F6]">
                        Modifier
                      </button>
                      {deleteConfirmId === cert.id ? (
                        <span className="flex gap-1">
                          <button onClick={() => handleDelete(cert.id)}
                            className="text-xs bg-red-600 hover:bg-red-700 text-white px-3 py-1.5 rounded-lg font-medium">
                            Confirmer
                          </button>
                          <button onClick={() => setDeleteConfirmId(null)}
                            className="text-xs border border-gray-200 text-gray-500 px-2 py-1.5 rounded-lg hover:bg-gray-50">
                            ✕
                          </button>
                        </span>
                      ) : (
                        <button onClick={() => setDeleteConfirmId(cert.id)}
                          className="text-xs border border-red-200 text-red-500 px-3 py-1.5 rounded-lg hover:bg-red-50">
                          Supprimer
                        </button>
                      )}
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
