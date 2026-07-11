'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import {
  generateContratAdoptionHTML,
  PARTICIPATION_DEFAUT,
  AssociationInfo, AnimalAdoption, AdoptantInfo, DataAdoption,
} from '@/lib/contrat-adoption';
import { sendNotification } from '@/lib/notifications';
import AddressAutocomplete from '@/components/AddressAutocomplete';

// ── Types ──────────────────────────────────────────────────────────────────────

interface DocAdoption {
  id: string;
  animal_id: string;
  type: string;
  titre: string;
  statut: 'brouillon' | 'en_attente' | 'signe' | 'archive' | 'annule' | 'partiellement_signe';
  signe_le: string | null;
  metadata: Record<string, string | number | null>;
  created_at: string;
}

interface Animal {
  id: string;
  nom: string;
  espece: string;
  race: string;
  sexe: string;
  identification: string;
  date_naissance: string;
  couleur?: string;
  sterilise?: boolean;
}

interface UserProfile {
  nom: string;
  rue?: string;
  ville?: string;
  code_postal?: string;
  siret?: string;
  email: string;
  phone?: string;
}

const STATUT_META: Record<string, { label: string; cls: string }> = {
  brouillon:           { label: 'Brouillon',        cls: 'bg-gray-100 text-gray-500' },
  en_attente:          { label: '⏳ En attente',    cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe: { label: '✍️ Partiel',       cls: 'bg-blue-100 text-blue-700' },
  signe:               { label: '✅ Signé',         cls: 'bg-green-100 text-green-700' },
  archive:             { label: 'Archivé',           cls: 'bg-gray-100 text-gray-400' },
  annule:              { label: '🚫 Annulé',         cls: 'bg-red-100 text-red-500' },
};

// ── Page ──────────────────────────────────────────────────────────────────────

export default function ContratsAdoptionPage() {
  const { user, loading } = useAuth();
  const { id: profileId, loaded: profileLoaded } = useActiveProfileState();
  const router = useRouter();

  const [docs, setDocs]       = useState<DocAdoption[]>([]);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [fetching, setFetching] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving]   = useState(false);
  const [deleteId, setDeleteId]         = useState<string | null>(null);
  const [transmitting, setTransmitting] = useState<string | null>(null);

  // Form fields
  const [animalId, setAnimalId]     = useState('');
  const [selectedAnimal, setSelectedAnimal] = useState<Animal | null>(null);
  const [acqNom, setAcqNom]         = useState('');
  const [acqPrenom, setAcqPrenom]   = useState('');
  const [acqEmail, setAcqEmail]     = useState('');
  const [acqTel, setAcqTel]         = useState('');
  const [acqAdresse, setAcqAdresse] = useState('');
  const [participation, setParticipation] = useState('');
  const [dateDoc, setDateDoc]       = useState(new Date().toISOString().split('T')[0]);
  const [avecSteril, setAvecSteril] = useState(true);
  const [notes, setNotes]           = useState('');

  // Recherche adoptant PetsMatch
  const [userSearch, setUserSearch]   = useState('');
  type UserResult = { uid: string; firstname: string; lastname: string; name_elevage?: string; is_elevage?: boolean; email: string; phone_number?: string; rue?: string; ville?: string; code_postal?: string; rue_elevage?: string; ville_elevage?: string; code_postal_elevage?: string };
  const [userResults, setUserResults] = useState<UserResult[]>([]);

  const popupRef = useRef<Window | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  useEffect(() => { if (user && profileLoaded) load(); }, [user, profileLoaded]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const handler = (e: MessageEvent) => { if (e.data?.type === 'contract_signed') load(); };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const load = useCallback(async () => {
    if (!user || !profileLoaded) return;
    setFetching(true);
    const profQuery = profileId
      ? supabase.from('user_profiles').select('nom,siret,email_contact,phone,telephone,rue,ville,code_postal').eq('id', profileId).maybeSingle()
      : supabase.from('user_profiles').select('nom,siret,email_contact,phone,telephone,rue,ville,code_postal').eq('uid', user.uid).eq('is_main', true).maybeSingle();
    const [docsRes, aniRes, profRes, userRes] = await Promise.all([
      supabase.from('documents_animaux').select('*').eq('uid_eleveur', user.uid).eq('type', 'contrat_adoption').order('created_at', { ascending: false }),
      supabase.from('animaux').select('id, nom, espece, race, sexe, identification, date_naissance, couleur, sterilise').eq('uid_eleveur', user.uid).eq('is_association', true).not('statut', 'in', '(sorti,decede,adopte)').order('nom'),
      profQuery,
      supabase.from('users').select('email').eq('uid', user.uid).maybeSingle(),
    ]);
    const allDocs = (docsRes.data ?? []) as DocAdoption[];
    setDocs(allDocs);
    // Un animal déjà adopté ou déjà engagé dans un contrat en cours/signé ne doit plus être proposé
    const blockedAnimalIds = new Set(
      allDocs.filter(d => !['annule', 'refuse', 'expire'].includes(d.statut)).map(d => d.animal_id)
    );
    setAnimaux(((aniRes.data ?? []) as Animal[]).filter(a => !blockedAnimalIds.has(a.id)));
    const cp = profRes.data;
    setProfile(cp ? {
      nom: cp.nom, rue: cp.rue, ville: cp.ville, code_postal: cp.code_postal,
      siret: cp.siret, email: userRes.data?.email || cp.email_contact || '',
      phone: cp.phone || cp.telephone || '',
    } : null);
    setFetching(false);
  }, [user, profileId, profileLoaded]);

  async function searchUser(q: string) {
    setUserSearch(q);
    if (q.length < 2) { setUserResults([]); return; }
    const cpFields = 'uid,firstname,lastname,nom,profile_type,email_contact,phone_number,rue,ville,code_postal,rue_pro,ville_pro,code_postal_pro';
    const toResult = (cp: Record<string, unknown>, email?: string): UserResult => ({
      uid: cp.uid as string, firstname: cp.firstname as string, lastname: cp.lastname as string,
      name_elevage: cp.nom as string | undefined, is_elevage: cp.profile_type === 'eleveur',
      email: email || (cp.email_contact as string | undefined) || '',
      phone_number: cp.phone_number as string | undefined,
      rue: cp.rue as string | undefined, ville: cp.ville as string | undefined, code_postal: cp.code_postal as string | undefined,
      rue_elevage: cp.rue_pro as string | undefined, ville_elevage: cp.ville_pro as string | undefined, code_postal_elevage: cp.code_postal_pro as string | undefined,
    });
    if (q.includes('@')) {
      const { data: users } = await supabase.from('users').select('uid,email').ilike('email', `%${q}%`).limit(5);
      const uids = (users ?? []).map(u => u.uid);
      const emailByUid = new Map((users ?? []).map(u => [u.uid, u.email as string]));
      const { data: cps } = uids.length
        ? await supabase.from('user_profiles').select(cpFields).in('uid', uids).eq('is_main', true)
        : { data: [] as Record<string, unknown>[] };
      setUserResults((cps ?? []).map(cp => toResult(cp, emailByUid.get(cp.uid as string))));
    } else {
      const { data: cps } = await supabase.from('user_profiles').select(cpFields)
        .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%`).eq('is_main', true).limit(8);
      setUserResults((cps ?? []).map(cp => toResult(cp)));
    }
  }

  function selectUser(u: UserResult) {
    // Nom : si éleveur professionnel, on garde name_elevage ; sinon nom personnel
    setAcqNom(u.is_elevage && u.name_elevage ? u.name_elevage : (u.lastname ?? ''));
    setAcqPrenom(u.is_elevage && u.name_elevage ? '' : (u.firstname ?? ''));
    setAcqEmail(u.email ?? '');
    setAcqTel(u.phone_number ?? '');
    const personalAddr = [u.rue, u.code_postal, u.ville].filter(Boolean).join(', ');
    const elevageAddr = [u.rue_elevage, u.code_postal_elevage, u.ville_elevage].filter(Boolean).join(', ');
    setAcqAdresse(personalAddr || elevageAddr || '');
    setUserResults([]); setUserSearch('');
  }

  function selectAnimal(id: string) {
    setAnimalId(id);
    const a = animaux.find(x => x.id === id) ?? null;
    setSelectedAnimal(a);
    if (a) setParticipation(String(PARTICIPATION_DEFAUT[a.espece?.toLowerCase() ?? ''] ?? 50));
    setAvecSteril(a ? !a.sterilise : true);
  }

  function resetForm() {
    setAnimalId(''); setSelectedAnimal(null); setAcqNom(''); setAcqPrenom('');
    setAcqEmail(''); setAcqTel(''); setAcqAdresse(''); setParticipation('');
    setDateDoc(new Date().toISOString().split('T')[0]); setNotes(''); setAvecSteril(true);
    setUserSearch(''); setUserResults([]);
  }

  function assoInfo(): AssociationInfo {
    if (!profile) return { nom: '' };
    return {
      nom: profile.nom || '',
      adresse: [profile.rue, profile.code_postal, profile.ville].filter(Boolean).join(', '),
      tel: profile.phone ?? '',
      email: profile.email ?? '',
      siret: profile.siret ?? '',
    };
  }

  async function saveDraft(): Promise<string | null> {
    if (!user || !selectedAnimal) return null;
    const asso = assoInfo();
    const titre = `Adoption ${selectedAnimal.nom} — ${acqPrenom} ${acqNom}`.trim();
    const token = crypto.randomUUID();
    const payload = {
      uid_eleveur: user.uid,
      pro_profile_id: profileId || null,
      animal_id: selectedAnimal.id,
      type: 'contrat_adoption',
      titre,
      statut: 'brouillon',
      token,
      metadata: {
        asso_nom: asso.nom, asso_adresse: asso.adresse, asso_tel: asso.tel, asso_email: asso.email, asso_siret: asso.siret,
        acquereur_nom: acqNom, acquereur_prenom: acqPrenom, acquereur_email: acqEmail, acquereur_tel: acqTel, acquereur_adresse: acqAdresse,
        participation, dateContrat: dateDoc, avecSteril: avecSteril ? 'true' : 'false', notes,
      },
    };
    const { data, error } = await supabase.from('documents_animaux').insert(payload).select().single();
    if (error || !data) return null;
    return token;
  }

  async function openAndSign() {
    if (!selectedAnimal || !user) return;
    setSaving(true);
    const token = await saveDraft();
    if (token) {
      await load();
      const url = `${window.location.origin}/signer-contrat/${token}`;
      if (acqEmail.trim()) {
        try {
          const { data: adoptantUser } = await supabase
            .from('users').select('uid').eq('email', acqEmail.trim()).maybeSingle();
          if (adoptantUser?.uid) {
            await sendNotification({ uid: adoptantUser.uid, type: 'contrat_invite', title: '🏡 Contrat d\'adoption à signer', body: `Un contrat d'adoption pour ${selectedAnimal.nom} vous a été envoyé — vérifiez et signez`, data: { url } });
          }
        } catch { /* ignore */ }
      }
      popupRef.current = window.open(url, '_blank', 'width=900,height=700,scrollbars=yes');
      setShowForm(false);
      resetForm();
    }
    setSaving(false);
  }

  async function transmettreDoc(doc: DocAdoption) {
    if (!user) return;
    setTransmitting(doc.id);
    const token = await getToken(doc.id);
    // Passer statut en_attente
    await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', doc.id);
    // Notifier l'adoptant si sur PetsMatch
    const acqEmail = doc.metadata?.acquereur_email as string | undefined;
    const acqNom   = doc.metadata?.acquereur_nom as string | undefined;
    if (acqEmail?.trim()) {
      const { data: targetUser } = await supabase.from('users').select('uid').eq('email', acqEmail.trim()).maybeSingle();
      if (targetUser?.uid) {
        const assoNom = profile?.nom || 'Une association';
        const signingUrl = `${window.location.origin}/signer-contrat/${token}`;
        await sendNotification({
          uid: targetUser.uid, type: 'contrat_invite',
          title: '📄 Contrat d\'adoption à signer',
          body: `${assoNom} vous envoie "${doc.titre}" — vérifiez et signez`,
          data: { token, url: signingUrl },
        });
      }
    }
    setDocs(prev => prev.map(d => d.id === doc.id ? { ...d, statut: 'en_attente' as const } : d));
    setTransmitting(null);
    const label = acqNom || acqEmail || 'l\'adoptant';
    alert(`Contrat transmis à ${label} !`);
  }

  async function openDoc(doc: DocAdoption) {
    if (!doc.metadata) return;
    const url = `${window.location.origin}/signer-contrat/${await getToken(doc.id)}`;
    window.open(url, '_blank', 'width=900,height=700,scrollbars=yes');
  }

  async function getToken(docId: string): Promise<string> {
    const { data } = await supabase.from('documents_animaux').select('token').eq('id', docId).single();
    return (data as { token: string } | null)?.token ?? docId;
  }

  async function handleDelete(id: string) {
    await supabase.from('documents_animaux').delete().eq('id', id);
    setDocs(prev => prev.filter(d => d.id !== id));
    setDeleteId(null);
  }

  async function downloadPDF(doc: DocAdoption) {
    const asso = assoInfo();
    const a = animaux.find(x => x.id === doc.animal_id);
    const m = doc.metadata;
    const adoptant: AdoptantInfo = { nom: m.acquereur_nom as string, prenom: m.acquereur_prenom as string, adresse: m.acquereur_adresse as string, tel: m.acquereur_tel as string, email: m.acquereur_email as string };
    const data: DataAdoption = { participation: m.participation as string, dateContrat: m.dateContrat as string, avecSteril: m.avecSteril === 'true', notes: m.notes as string };
    const html = generateContratAdoptionHTML(asso, a ?? {}, adoptant, data);
    const win = window.open('', '_blank');
    if (win) { win.document.write(html); win.document.close(); win.print(); }
  }

  const inp = "w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300";

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold font-galey text-teal-800">Contrats d'adoption</h1>
          <p className="text-sm text-gray-500 font-galey">Contrats d'adoption avec participation aux frais par espèce</p>
        </div>
        <button onClick={() => { resetForm(); setShowForm(true); }}
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Nouveau contrat
        </button>
      </div>

      {/* Tableau des contrats */}
      {fetching ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" /></div>
      ) : docs.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p className="font-galey font-semibold text-gray-600 mb-1">Aucun contrat d'adoption</p>
          <p className="text-sm mb-4">Créez vos contrats d'adoption avec participation aux frais.</p>
          <button onClick={() => { resetForm(); setShowForm(true); }}
            className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
            Créer un contrat
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {docs.map(doc => {
            const sm = STATUT_META[doc.statut] ?? STATUT_META.brouillon;
            const m = doc.metadata ?? {};
            const adoptantNom = `${m.acquereur_prenom ?? ''} ${m.acquereur_nom ?? ''}`.trim() || '—';
            const anim = animaux.find(a => a.id === doc.animal_id);
            return (
              <div key={doc.id} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-4 hover:border-teal-200 transition-all">
                <div className="w-12 h-12 rounded-xl bg-teal-50 flex items-center justify-center text-2xl flex-shrink-0">📋</div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="font-bold font-galey text-gray-900 truncate">{doc.titre}</p>
                    <span className={`text-xs font-galey font-semibold px-2 py-0.5 rounded-full flex-shrink-0 ${sm.cls}`}>{sm.label}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-gray-500 font-galey mt-0.5 flex-wrap">
                    <span>🧑 {adoptantNom}</span>
                    {anim && <span>🐾 {anim.nom} ({anim.espece})</span>}
                    {m.participation && <span>💶 {m.participation} €</span>}
                    <span>📅 {new Date(doc.created_at).toLocaleDateString('fr-FR')}</span>
                  </div>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {/* Transmettre — brouillon uniquement */}
                  {doc.statut === 'brouillon' && (
                    <button onClick={() => transmettreDoc(doc)} disabled={transmitting === doc.id}
                      className="text-xs font-galey font-semibold px-3 py-1.5 rounded-xl transition-colors disabled:opacity-40"
                      style={{ backgroundColor: '#0C5C6C', color: '#fff' }}>
                      {transmitting === doc.id ? '…' : '📤 Transmettre'}
                    </button>
                  )}
                  <button onClick={() => openDoc(doc)}
                    className="text-xs font-galey font-semibold text-teal-700 border border-teal-200 px-3 py-1.5 rounded-xl hover:bg-teal-50 transition-colors">
                    {doc.statut === 'brouillon' ? '👁 Aperçu' : '✍️ Signer'}
                  </button>
                  <button onClick={() => downloadPDF(doc)}
                    className="text-xs font-galey font-semibold text-gray-600 border border-gray-200 px-3 py-1.5 rounded-xl hover:bg-gray-50 transition-colors">
                    🖨️ PDF
                  </button>
                  {deleteId === doc.id ? (
                    <div className="flex items-center gap-1">
                      <button onClick={() => handleDelete(doc.id)} className="text-xs text-red-600 font-bold px-2 py-1 rounded hover:bg-red-50">Oui</button>
                      <button onClick={() => setDeleteId(null)} className="text-xs text-gray-400 px-2 py-1">Non</button>
                    </div>
                  ) : (
                    <button onClick={() => setDeleteId(doc.id)} className="text-gray-300 hover:text-red-400 transition-colors text-sm px-1">🗑</button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Infos participations par défaut */}
      <div className="bg-teal-50 border border-teal-100 rounded-2xl p-4">
        <p className="text-sm font-bold font-galey text-teal-800 mb-2">💶 Participations aux frais par défaut</p>
        <div className="flex flex-wrap gap-2">
          {Object.entries(PARTICIPATION_DEFAUT).map(([espece, montant]) => (
            <span key={espece} className="bg-white border border-teal-200 text-teal-700 text-xs font-galey font-semibold px-3 py-1 rounded-full">
              {espece.charAt(0).toUpperCase() + espece.slice(1)} : {montant} €
            </span>
          ))}
        </div>
        <p className="text-xs text-gray-400 font-galey mt-2">Ces montants sont pré-remplis automatiquement selon l'espèce et restent modifiables.</p>
      </div>

      {/* Modal formulaire */}
      {showForm && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4 overflow-y-auto" onClick={() => setShowForm(false)}>
          <div className="bg-white rounded-2xl w-full max-w-xl my-4" onClick={e => e.stopPropagation()}>
            <div className="bg-teal-700 text-white px-5 py-4 rounded-t-2xl flex items-center justify-between">
              <h2 className="font-bold font-galey text-lg">Nouveau contrat d'adoption</h2>
              <button onClick={() => setShowForm(false)} className="text-white/70 hover:text-white text-xl leading-none">✕</button>
            </div>
            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">

              {/* Animal */}
              <div>
                <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Animal *</label>
                <select value={animalId} onChange={e => selectAnimal(e.target.value)} className={inp} required>
                  <option value="">— Choisir un animal —</option>
                  {animaux.map(a => (
                    <option key={a.id} value={a.id}>{a.nom} ({a.espece}{a.race ? ` · ${a.race}` : ''})</option>
                  ))}
                </select>
                {selectedAnimal && (
                  <div className="mt-2 bg-teal-50 rounded-xl px-3 py-2 text-xs text-teal-700 font-galey">
                    🐾 {selectedAnimal.nom} · {selectedAnimal.espece} {selectedAnimal.race ? `· ${selectedAnimal.race}` : ''} · {selectedAnimal.sexe}
                    {selectedAnimal.sterilise && ' · ✂️ Stérilisé'}
                  </div>
                )}
              </div>

              {/* Participation */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Participation aux frais (€)</label>
                  <input type="number" min={0} value={participation} onChange={e => setParticipation(e.target.value)} placeholder="150" className={inp} />
                </div>
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Date du contrat</label>
                  <input type="date" value={dateDoc} onChange={e => setDateDoc(e.target.value)} className={inp} />
                </div>
              </div>

              {selectedAnimal && !selectedAnimal.sterilise && (
                <label className="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" checked={avecSteril} onChange={e => setAvecSteril(e.target.checked)} className="w-4 h-4 rounded text-teal-600" />
                  <span className="text-sm font-galey text-gray-700">Inclure clause de stérilisation obligatoire</span>
                </label>
              )}

              {/* Adoptant */}
              <div>
                <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Rechercher un adoptant PetsMatch</label>
                <div className="relative">
                  <input value={userSearch} onChange={e => searchUser(e.target.value)} placeholder="Nom, prénom ou email…" className={inp} />
                  {userResults.length > 0 && (
                    <div className="absolute z-20 left-0 right-0 top-full mt-1 bg-white border border-teal-200 rounded-xl shadow-lg overflow-hidden">
                      {userResults.map(u => (
                        <button key={u.uid} onClick={() => selectUser(u)}
                          className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-teal-50 text-left border-b border-gray-50 last:border-0">
                          <div className="w-7 h-7 rounded-full bg-teal-100 flex items-center justify-center text-xs font-bold text-teal-700 flex-shrink-0">
                            {(u.firstname?.[0] ?? '?').toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm font-galey font-semibold">{u.firstname} {u.lastname}</p>
                            <p className="text-xs text-gray-400">{u.email}</p>
                          </div>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Prénom adoptant</label>
                  <input value={acqPrenom} onChange={e => setAcqPrenom(e.target.value)} className={inp} />
                </div>
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Nom adoptant</label>
                  <input value={acqNom} onChange={e => setAcqNom(e.target.value)} className={inp} />
                </div>
              </div>
              <div>
                <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Email adoptant</label>
                <input type="email" value={acqEmail} onChange={e => setAcqEmail(e.target.value)} className={inp} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Téléphone</label>
                  <input value={acqTel} onChange={e => setAcqTel(e.target.value)} className={inp} />
                </div>
                <div>
                  <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Adresse</label>
                  <AddressAutocomplete value={acqAdresse} onChange={setAcqAdresse} className={inp} placeholder="12 rue des Lilas, 75001 Paris" />
                </div>
              </div>
              <div>
                <label className="block text-sm font-galey font-semibold text-gray-700 mb-1">Notes / Conditions particulières</label>
                <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={inp + ' resize-none'} placeholder="Suivi post-adoption, accord visite, etc." />
              </div>
            </div>

            <div className="flex gap-3 px-5 pb-5 pt-3 border-t border-gray-100">
              <button onClick={openAndSign} disabled={saving || !selectedAnimal || !acqNom}
                className="flex-1 bg-teal-700 hover:bg-teal-800 disabled:opacity-50 text-white font-galey font-semibold py-2.5 rounded-xl text-sm transition-colors">
                {saving ? 'Création…' : '✍️ Créer et signer'}
              </button>
              <button onClick={() => setShowForm(false)}
                className="flex-1 border border-gray-200 text-gray-600 font-galey font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                Annuler
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
