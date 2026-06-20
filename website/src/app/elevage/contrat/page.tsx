'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import { generateContratHTML, generateContratVente, generateContratReservationHTML } from '@/lib/contrat-vente';

interface DocAnimal {
  id: string;
  animal_id: string;
  type: 'contrat_vente' | 'contrat_reservation' | 'certificat_cession';
  titre: string;
  url: string | null;
  token: string | null;
  statut: 'brouillon' | 'en_attente' | 'signe' | 'archive' | 'partiellement_signe' | 'annule' | 'expire' | 'refuse';
  signe_le: string | null;
  pdf_signe_url: string | null;
  rejection_reason: string | null;
  metadata: Record<string, string | number | null>;
  created_at: string;
}

interface AuditEntry {
  id: string;
  action: string;
  actor_email: string | null;
  actor_role: string | null;
  details: Record<string, unknown>;
  created_at: string;
}

interface Animal { id: string; nom: string; espece: string; race: string; identification: string; date_naissance: string; sexe: string; couleur?: string; pedigree_numero?: string; pedigree_lof?: string; nom_pere?: string; puce_pere?: string; nom_mere?: string; puce_mere?: string; }
interface UserProfile { firstname: string; lastname: string; name_elevage: string; is_elevage: boolean; adress_elevage: string; adress: string; rue: string; ville: string; ville_elevage: string; code_postal: string; siret: string; email: string; numero_elevage: string; code_iso_elevage: string; phone_number: string; code_iso: string; }

const TYPE_META = {
  contrat_vente:       { label: 'Vente',        icon: '🤝', color: 'bg-green-50 text-green-700 border-green-200' },
  contrat_reservation: { label: 'Réservation',  icon: '🐾', color: 'bg-teal-50 text-teal-700 border-teal-200' },
  certificat_cession:  { label: 'Cession',      icon: '📋', color: 'bg-purple-50 text-purple-700 border-purple-200' },
};

const ACTION_LABEL: Record<string, string> = {
  created:           '📝 Créé',
  opened:            '👁️ Ouvert',
  signed:            '✅ Signé',
  partially_signed:  '✍️ Signature partielle',
  cancelled:         '🚫 Annulé',
  refused:           '❌ Refusé',
  expired:           '⏰ Expiré',
  sent:              '📤 Envoyé (YouSign)',
};

const STATUT_META: Record<string, { label: string; cls: string }> = {
  brouillon:          { label: 'Brouillon',             cls: 'bg-gray-100 text-gray-500' },
  en_attente:         { label: '⏳ Attente acquéreur',  cls: 'bg-amber-100 text-amber-700' },
  partiellement_signe:{ label: '✍️ Partiel',            cls: 'bg-blue-100 text-blue-700' },
  signe:              { label: '✅ Signé',              cls: 'bg-green-100 text-green-700' },
  archive:            { label: 'Archivé',               cls: 'bg-gray-100 text-gray-400' },
  annule:             { label: '🚫 Annulé',             cls: 'bg-red-100 text-red-500' },
  expire:             { label: '⏰ Expiré',             cls: 'bg-orange-100 text-orange-600' },
  refuse:             { label: '❌ Refusé',             cls: 'bg-red-100 text-red-700' },
};

export default function ContratsPage() {
  const { user, loading } = useAuth();
  const { config: planConfig, loading: planLoading } = usePlan();
  const router = useRouter();

  const [docs, setDocs]           = useState<DocAnimal[]>([]);
  const [animaux, setAnimaux]     = useState<Animal[]>([]);
  const [profile, setProfile]     = useState<UserProfile | null>(null);
  const [fetching, setFetching]   = useState(true);
  const [showForm, setShowForm]   = useState(false);
  const [formType, setFormType]   = useState<DocAnimal['type']>('contrat_vente');
  const [saving, setSaving]       = useState(false);
  const [deleting, setDeleting]   = useState<string | null>(null);
  const [cancelling, setCancelling] = useState<string | null>(null);
  const [auditOpen, setAuditOpen] = useState<Record<string, boolean>>({});
  const [auditCache, setAuditCache] = useState<Record<string, AuditEntry[]>>({});

  // Form
  const [animalId, setAnimalId]       = useState('');
  const [selectedAnimal, setSelectedAnimal] = useState<Animal | null>(null);
  const [acqNom, setAcqNom]           = useState('');
  const [acqPrenom, setAcqPrenom]     = useState('');
  const [acqEmail, setAcqEmail]       = useState('');
  const [acqTel, setAcqTel]           = useState('');
  const [acqAdresse, setAcqAdresse]   = useState('');
  const [prix, setPrix]               = useState('');
  const [dateDoc, setDateDoc]         = useState(new Date().toISOString().split('T')[0]);
  const [notes, setNotes]             = useState('');
  const [avecSteril, setAvecSteril]   = useState(true);
  // Recherche acquéreur PetsMatch
  const [userSearch, setUserSearch]   = useState('');
  const [userResults, setUserResults] = useState<{uid:string;firstname:string;lastname:string;email:string;phone_number:string;rue:string;ville:string;code_postal:string}[]>([]);

  const popupRef = useRef<Window | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    load();
  }, [user]);

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data?.type === 'contract_signed') load();
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);

  async function load() {
    if (!user) return;
    setFetching(true);
    const [docsRes, animauxRes, profileRes] = await Promise.all([
      supabase.from('documents_animaux').select('*').eq('uid_eleveur', user.uid).order('created_at', { ascending: false }),
      supabase.from('animaux').select('id, nom, espece, race, identification, date_naissance, sexe, couleur, pedigree_numero, pedigree_lof, nom_pere, puce_pere, nom_mere, puce_mere').eq('uid_eleveur', user.uid).not('statut', 'in', '(sorti,decede)').order('nom'),
      supabase.from('users').select('firstname,lastname,name_elevage,is_elevage,adress_elevage,adress,rue,ville,ville_elevage,code_postal,siret,email,numero_elevage,code_iso_elevage,phone_number,code_iso').eq('uid', user.uid).maybeSingle(),
    ]);
    setDocs((docsRes.data ?? []) as DocAnimal[]);
    setAnimaux((animauxRes.data ?? []) as Animal[]);
    setProfile(profileRes.data as UserProfile | null);
    setFetching(false);
  }

  async function searchUser(q: string) {
    setUserSearch(q);
    if (q.length < 2) { setUserResults([]); return; }
    const isEmail = q.includes('@');
    const { data } = isEmail
      ? await supabase.from('users').select('uid,firstname,lastname,email,phone_number,rue,ville,code_postal').ilike('email', `%${q}%`).limit(5)
      : await supabase.from('users').select('uid,firstname,lastname,email,phone_number,rue,ville,code_postal').or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%`).limit(8);
    setUserResults(data ?? []);
  }

  function selectUser(u: typeof userResults[0]) {
    setAcqNom(u.lastname); setAcqPrenom(u.firstname); setAcqEmail(u.email);
    setAcqTel(u.phone_number ?? '');
    setAcqAdresse([u.rue, u.code_postal, u.ville].filter(Boolean).join(', '));
    setUserResults([]); setUserSearch('');
  }

  function selectAnimal(id: string) {
    setAnimalId(id);
    setSelectedAnimal(animaux.find(a => a.id === id) ?? null);
  }

  function resetForm() {
    setAnimalId(''); setSelectedAnimal(null); setAcqNom(''); setAcqPrenom('');
    setAcqEmail(''); setAcqTel(''); setAcqAdresse(''); setPrix('');
    setDateDoc(new Date().toISOString().split('T')[0]); setNotes('');
    setAvecSteril(true);
    setUserSearch(''); setUserResults([]);
  }

  function eleveurInfo() {
    if (!profile) return { nom: '', adresse: '', tel: '', siret: '', email: '' };
    const nom = profile.is_elevage ? (profile.name_elevage || `${profile.firstname} ${profile.lastname}`.trim()) : `${profile.firstname} ${profile.lastname}`.trim();
    const adresse = profile.is_elevage ? (profile.adress_elevage || [profile.rue, profile.code_postal, profile.ville].filter(Boolean).join(', ')) : (profile.adress || [profile.rue, profile.code_postal, profile.ville].filter(Boolean).join(', '));
    const tel = profile.is_elevage ? `${profile.code_iso_elevage ?? '+33'} ${profile.numero_elevage ?? ''}`.trim() : `${profile.code_iso ?? '+33'} ${profile.phone_number ?? ''}`.trim();
    return { nom, adresse, tel, siret: profile.siret ?? '', email: profile.email ?? '' };
  }

  async function openAndSign() {
    if (!selectedAnimal || !user) return;
    const elv = eleveurInfo();
    const acqNomFull = `${acqPrenom} ${acqNom}`.trim();
    const opts = { animalId: selectedAnimal.id, supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL!, supabaseKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! };
    const dataContrat = { nom: acqNomFull, adresse: acqAdresse, email: acqEmail, tel: acqTel, prix, dateCession: dateDoc, notes };
    const elvInfo = { nom: elv.nom, adresse: elv.adresse, email: elv.email, siret: elv.siret, tel: elv.tel };
    // Champs enrichis animal + ville naissance = ville_elevage du profil
    const villeElevage = profile?.ville_elevage ?? profile?.ville ?? '';
    const animalEnrichi = {
      ...selectedAnimal,
      ville_naissance: villeElevage,
    };

    // Sauvegarder d'abord pour obtenir le token, puis ouvrir via /signer-contrat/[token]
    const token = await saveDraft();
    if (token) {
      const win = window.open(`/signer-contrat/${token}`, '_blank', 'width=900,height=700');
      popupRef.current = win;
    } else {
      // Fallback : HTML en mémoire si l'insert a échoué
      const html = formType === 'contrat_reservation'
        ? generateContratReservationHTML(animalEnrichi, dataContrat, elvInfo, opts)
        : generateContratHTML(animalEnrichi, dataContrat, elvInfo, opts);
      const win = window.open('', '_blank', 'width=900,height=700');
      if (!win) { alert('Autorisez les popups'); return; }
      popupRef.current = win;
      win.document.write(html); win.document.close();
    }
  }

  async function openBlankVente() {
    const elv = eleveurInfo();
    const html = generateContratVente(elv);
    const win = window.open('', '_blank');
    if (!win) { alert('Autorisez les popups'); return; }
    win.document.write(html); win.document.close();
  }

  async function saveDraft(): Promise<string | null> {
    if (!user || !selectedAnimal) return null;
    const titreLabel = formType === 'contrat_vente' ? 'Contrat de vente' : formType === 'contrat_reservation' ? 'Contrat de réservation' : 'Certificat de cession';
    const { data } = await supabase.from('documents_animaux').insert({
      animal_id:   selectedAnimal.id,
      uid_eleveur: user.uid,
      type:        formType,
      titre:       `${titreLabel} — ${selectedAnimal.nom ?? 'Animal'}`,
      statut:      'brouillon',
      metadata: {
        acquereur_nom:       `${acqPrenom} ${acqNom}`.trim(),
        acquereur_email:     acqEmail,
        acquereur_tel:       acqTel,
        acquereur_adresse:   acqAdresse,
        prix:                parseFloat(prix) || null,
        date_cession:        dateDoc,
        notes,
        avec_sterilisation:  avecSteril,
      },
    }).select('token').single();
    await load();
    return (data as { token: string } | null)?.token ?? null;
  }

  async function deleteDoc(id: string, titre: string) {
    if (!confirm(`Supprimer "${titre}" ?`)) return;
    setDeleting(id);
    await supabase.from('documents_animaux').delete().eq('id', id);
    setDocs(prev => prev.filter(d => d.id !== id));
    setDeleting(null);
  }

  async function cancelDoc(id: string) {
    if (!user || !confirm('Annuler ce contrat ? L\'acquéreur ne pourra plus le signer.')) return;
    setCancelling(id);
    await fetch(`/api/contracts/${id}/cancel`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ actorUid: user.uid }),
    });
    setDocs(prev => prev.map(d => d.id === id ? { ...d, statut: 'annule' as const } : d));
    setCancelling(null);
  }

  async function toggleAudit(id: string) {
    const next = !auditOpen[id];
    setAuditOpen(prev => ({ ...prev, [id]: next }));
    if (next && !auditCache[id]) {
      const res = await fetch(`/api/contracts/${id}/audit`);
      const data = await res.json();
      setAuditCache(prev => ({ ...prev, [id]: data }));
    }
  }

  if (!planLoading && !planConfig.hasPremiumFeatures) return (
    <div className="min-h-[70vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
      <span className="text-5xl">🔒</span>
      <h2 className="text-xl font-bold text-[#1F2A2E] font-galey">Contrats — Plan Premium requis</h2>
      <a href="/abonnement" className="bg-[#D97706] text-white font-semibold px-6 py-3 rounded-xl text-sm">👑 Voir les plans</a>
    </div>
  );

  const iCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">📄 Mes Contrats</h1>
          <p className="text-sm text-gray-500 mt-0.5">Réservations, ventes — liés à vos animaux</p>
        </div>
        <button onClick={() => { resetForm(); setFormType('contrat_vente'); setShowForm(true); }}
          className="flex items-center gap-2 bg-[#0C5C6C] hover:bg-[#0a4f5e] text-white text-sm font-semibold px-4 py-2.5 rounded-xl transition-colors">
          + Nouveau contrat
        </button>
      </div>

      {/* Types de contrats disponibles */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {([
          { type: 'contrat_vente' as const, title: 'Contrat de vente', icon: '🤝', desc: 'Transfert de propriété, garanties légales, vices rédhibitoires.' },
          { type: 'contrat_reservation' as const, title: 'Contrat de réservation', icon: '🐾', desc: 'Arrhes, conditions d\'annulation, engagement des deux parties.' },
          { type: 'certificat_cession' as const, title: 'Certificat de cession', icon: '📋', desc: 'Attestation de transfert de propriété après la vente.' },
        ] as const).map(m => (
          <div key={m.type} className="bg-white border border-gray-100 rounded-xl p-4 space-y-1.5 shadow-sm">
            <div className="text-2xl">{m.icon}</div>
            <p className="text-sm font-semibold text-[#1F2A2E] font-galey">{m.title}</p>
            <p className="text-xs text-gray-500 leading-relaxed">{m.desc}</p>
            <button onClick={() => { resetForm(); setFormType(m.type); setShowForm(true); }}
              className="text-xs font-semibold text-[#0C5C6C] hover:underline mt-1">
              + Créer
            </button>
          </div>
        ))}
      </div>

      {/* Liste des contrats */}
      <div>
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Contrats enregistrés ({docs.length})</h2>
        {fetching ? (
          <div className="flex justify-center py-12"><div className="animate-spin w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full" /></div>
        ) : docs.length === 0 ? (
          <div className="text-center py-12 border-2 border-dashed border-gray-200 rounded-xl text-gray-400">
            <div className="text-4xl mb-3">📂</div>
            <p className="text-sm font-medium">Aucun contrat</p>
            <p className="text-xs mt-1">Créez votre premier contrat en sélectionnant un type ci-dessus</p>
          </div>
        ) : (
          <div className="space-y-2">
            {docs.map(d => {
              const tm = TYPE_META[d.type] ?? TYPE_META.contrat_vente;
              const sm = STATUT_META[d.statut] ?? STATUT_META.brouillon;
              const date = new Date(d.created_at).toLocaleDateString('fr-FR');
              const acqNomMeta = (d.metadata?.acquereur_nom as string) ?? '';
              return (
                <div key={d.id} className="border border-gray-100 rounded-xl bg-white hover:border-gray-200 transition-colors overflow-hidden">
                  <div className="flex items-center gap-3 p-3">
                  <div className="w-10 h-10 rounded-lg flex items-center justify-center text-xl flex-shrink-0 bg-gray-50 border border-gray-100">
                    {tm.icon}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-[#1F2A2E] truncate">{d.titre}</p>
                    <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                      <span className={`text-xs px-2 py-0.5 rounded-full border font-medium ${tm.color}`}>{tm.label}</span>
                      <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${sm.cls}`}>{sm.label}</span>
                      {acqNomMeta && <span className="text-xs text-gray-400">→ {acqNomMeta}</span>}
                      <span className="text-xs text-gray-400">{date}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {d.token && (
                      <a href={`/signer-contrat/${d.token}`} target="_blank" rel="noopener noreferrer"
                        className="text-xs text-[#0C5C6C] hover:underline font-medium">✏️ Ouvrir</a>
                    )}
                    {d.token && d.statut !== 'annule' && d.statut !== 'refuse' && (
                      <button onClick={() => {
                        const link = `${window.location.origin}/signer-contrat/${d.token}`;
                        navigator.clipboard.writeText(link);
                        alert('Lien copié ! Envoyez-le à l\'acquéreur pour signature.');
                      }} className="text-xs text-[#6E9E57] hover:underline font-medium">
                        🔗 Partager
                      </button>
                    )}
                    {/* PREP07 — Télécharger PDF signé */}
                    {d.statut === 'signe' && d.pdf_signe_url && (
                      <a href={d.pdf_signe_url} download target="_blank" rel="noopener noreferrer"
                        className="text-xs text-green-600 hover:underline font-medium">📥 PDF</a>
                    )}
                    {/* PREP08 — Annuler */}
                    {!['signe','annule','expire','refuse'].includes(d.statut) && (
                      <button onClick={() => cancelDoc(d.id)} disabled={cancelling === d.id}
                        className="text-xs text-orange-400 hover:text-orange-600 font-medium disabled:opacity-40">
                        {cancelling === d.id ? '…' : '🚫'}
                      </button>
                    )}
                    {/* PREP09 — Historique */}
                    <button onClick={() => toggleAudit(d.id)}
                      className="text-xs text-gray-400 hover:text-gray-600 font-medium">
                      {auditOpen[d.id] ? '▲' : '📋'}
                    </button>
                    {d.url && !d.token && (
                      <a href={d.url} target="_blank" rel="noopener noreferrer"
                        className="text-xs text-[#0C5C6C] hover:underline font-medium">Voir</a>
                    )}
                    <button onClick={() => deleteDoc(d.id, d.titre)} disabled={deleting === d.id}
                      className="text-xs text-red-400 hover:text-red-600 font-medium disabled:opacity-40">
                      {deleting === d.id ? '…' : 'Supprimer'}
                    </button>
                  </div>
                  </div>

                {/* PREP09 — Panneau audit */}
                {auditOpen[d.id] && (
                  <div className="px-3 pb-3 border-t border-gray-50">
                    {!auditCache[d.id] ? (
                      <p className="text-xs text-gray-400 mt-2">Chargement…</p>
                    ) : auditCache[d.id].length === 0 ? (
                      <p className="text-xs text-gray-400 mt-2">Aucune action enregistrée.</p>
                    ) : (
                      <div className="mt-2 border-l-2 border-gray-100 pl-3 space-y-1.5">
                        {auditCache[d.id].map(e => (
                          <div key={e.id} className="text-xs text-gray-500">
                            <span className="font-medium text-gray-700">{ACTION_LABEL[e.action] ?? e.action}</span>
                            {e.actor_email && <span className="text-gray-400 ml-1">— {e.actor_email}</span>}
                            {typeof (e.details as Record<string, unknown>)?.reason === 'string' && (
                              <span className="text-gray-400 italic ml-1">({(e.details as Record<string, string>).reason})</span>
                            )}
                            <span className="block text-gray-300 text-[10px]">
                              {new Date(e.created_at).toLocaleString('fr-FR')}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Modal création contrat */}
      {showForm && (
        <div className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center bg-black/50 px-4 pb-4 sm:pb-0"
          onClick={e => { if (e.target === e.currentTarget) setShowForm(false); }}>
          <div className="bg-white rounded-2xl p-6 w-full max-w-lg shadow-xl space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-[#1F2A2E] text-base font-galey">
                {formType === 'contrat_vente' ? '🤝 Contrat de vente' : formType === 'contrat_reservation' ? '🐾 Contrat de réservation' : '📋 Certificat de cession'}
              </h3>
              <button onClick={() => setShowForm(false)} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
            </div>

            {/* Sélecteur animal */}
            <div>
              <label className="text-xs font-semibold text-gray-600 mb-1 block">Animal concerné *</label>
              <select value={animalId} onChange={e => selectAnimal(e.target.value)} className={iCls}>
                <option value="">— Sélectionner un animal —</option>
                {animaux.map(a => (
                  <option key={a.id} value={a.id}>{a.nom} ({a.espece}{a.race ? ` · ${a.race}` : ''})</option>
                ))}
              </select>
              {selectedAnimal && (
                <div className="mt-2 bg-[#EEF5EA] rounded-xl p-3 text-xs text-[#1F2A2E] space-y-0.5">
                  <p><span className="font-semibold">{selectedAnimal.nom}</span> · {selectedAnimal.espece} {selectedAnimal.race && `· ${selectedAnimal.race}`}</p>
                  {selectedAnimal.identification && <p>Puce : {selectedAnimal.identification}</p>}
                  {selectedAnimal.date_naissance && <p>Né le : {new Date(selectedAnimal.date_naissance).toLocaleDateString('fr-FR')}</p>}
                </div>
              )}
            </div>

            {/* Recherche acquéreur */}
            <div>
              <label className="text-xs font-semibold text-gray-600 mb-1 block">Rechercher l&apos;acquéreur (PetsMatch)</label>
              <input value={userSearch} onChange={e => searchUser(e.target.value)}
                placeholder="Nom, prénom ou email…" className={iCls} />
              {userResults.length > 0 && (
                <div className="border border-gray-100 rounded-xl mt-1 divide-y divide-gray-50 shadow-sm">
                  {userResults.map(u => (
                    <button key={u.uid} onClick={() => selectUser(u)}
                      className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm">
                      <span className="font-medium">{u.firstname} {u.lastname}</span>
                      <span className="text-gray-400 text-xs ml-2">{u.email}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Infos acquéreur */}
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-xs text-gray-500 mb-1 block">Prénom</label><input value={acqPrenom} onChange={e => setAcqPrenom(e.target.value)} className={iCls} /></div>
              <div><label className="text-xs text-gray-500 mb-1 block">Nom</label><input value={acqNom} onChange={e => setAcqNom(e.target.value)} className={iCls} /></div>
            </div>
            <div><label className="text-xs text-gray-500 mb-1 block">Email</label><input type="email" value={acqEmail} onChange={e => setAcqEmail(e.target.value)} className={iCls} /></div>
            <div><label className="text-xs text-gray-500 mb-1 block">Téléphone</label><input value={acqTel} onChange={e => setAcqTel(e.target.value)} className={iCls} /></div>
            <div><label className="text-xs text-gray-500 mb-1 block">Adresse</label><input value={acqAdresse} onChange={e => setAcqAdresse(e.target.value)} className={iCls} /></div>
            <div className="grid grid-cols-2 gap-3">
              <div><label className="text-xs text-gray-500 mb-1 block">Prix (€)</label><input type="number" value={prix} onChange={e => setPrix(e.target.value)} placeholder="0 = gratuit" className={iCls} /></div>
              <div><label className="text-xs text-gray-500 mb-1 block">Date</label><input type="date" value={dateDoc} onChange={e => setDateDoc(e.target.value)} className={iCls} /></div>
            </div>
            <div><label className="text-xs text-gray-500 mb-1 block">Notes</label><textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={iCls} /></div>

            {formType === 'contrat_vente' && (
              <label className="flex items-start gap-3 p-3 bg-amber-50 border border-amber-200 rounded-xl cursor-pointer">
                <input type="checkbox" checked={avecSteril} onChange={e => setAvecSteril(e.target.checked)}
                  className="mt-0.5 accent-[#0C5C6C]" />
                <div>
                  <p className="text-xs font-semibold text-amber-800">Clause de stérilisation (Tranche 2)</p>
                  <p className="text-xs text-amber-700 mt-0.5">Inclure la pénalité financière si l&apos;acquéreur ne stérilise pas l&apos;animal dans le délai légal.</p>
                </div>
              </label>
            )}

            <div className="flex gap-2 pt-2">
              <button onClick={() => setShowForm(false)}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50">
                Annuler
              </button>
              {formType === 'contrat_vente' && (
                <button onClick={() => { setShowForm(false); openBlankVente(); }}
                  disabled={saving}
                  className="flex-1 border border-[#0C5C6C] text-[#0C5C6C] text-sm font-medium py-2.5 rounded-xl hover:bg-[#EEF5FA] transition-colors">
                  🖨️ Vierge
                </button>
              )}
              <button onClick={() => { setShowForm(false); openAndSign(); }}
                disabled={!animalId || saving}
                className="flex-1 bg-[#0C5C6C] hover:bg-[#0a4f5e] disabled:opacity-50 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors">
                ✍️ Générer & signer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
