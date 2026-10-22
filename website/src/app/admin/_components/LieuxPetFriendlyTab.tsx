'use client';
// Modération des lieux pet-friendly : fiches proposées par la communauté et
// par les établissements, corrections, revendications, doublons, historique.
// Chaque décision passe par /api/admin/moderation (clé service), avec motif
// transmis à la personne concernée et trace dans l'historique.
import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { ActionBtn, Badge, InfoRow, fmtDate } from './ui';
import AddressAutocomplete from '@/components/AddressAutocomplete';
import { ESPECES_LIEUX } from '@/lib/especes-lieux';
import { TYPES_LIEU } from '@/lib/lieux-categories';

type Lieu = Record<string, unknown> & {
  id: string; nom?: string; statut?: string; created_at?: string; origine?: string; verification?: string;
  plan?: string; ajoute_par_uid?: string | null; uid_pro?: string | null; motif_moderation?: string | null;
};
type Correction = { id: string; place_id: string; uid: string; champs: Record<string, unknown>; commentaire?: string | null; created_at: string; place?: { nom?: string; ville?: string } | null };
type Revendication = {
  id: string; place_id: string; uid: string; fonction: string; siret?: string | null; methode: string;
  email_pro?: string | null; email_confirme?: boolean; justificatif_url?: string | null; created_at: string;
  place?: { nom?: string; ville?: string; site_web?: string | null; siret?: string | null } | null;
};
type Journal = { id: string; objet: string; action: string; motif?: string | null; created_at: string; place?: { nom?: string } | null };
type Doublon = { id: string; nom?: string; ville?: string; statut?: string; metres: number };

const STATUTS: Record<string, { label: string; color: string }> = {
  brouillon: { label: 'Brouillon', color: '#64748b' },
  en_attente_validation: { label: 'En attente', color: '#d97706' },
  actif: { label: 'Publié', color: '#16a34a' },
  a_corriger: { label: 'À corriger', color: '#2563eb' },
  refuse: { label: 'Refusé', color: '#dc2626' },
  masque: { label: 'Masqué', color: '#64748b' },
  suspendu: { label: 'Suspendu', color: '#dc2626' },
};
const TROIS_ETATS: [string, string][] = [
  ['animaux_en_salle', 'Accès intérieur'], ['terrasse', 'Terrasse / extérieur'], ['restriction_taille', 'Restriction de taille'],
  ['supplement_animal', 'Supplément'], ['animaux_dans_chambre', 'Animaux en chambre'], ['espace_detente', 'Espace détente'],
];
const ONGLETS = [
  ['nouvelles', 'Nouvelles fiches'], ['corrections', 'Corrections proposées'], ['revendications', 'Revendications'],
  ['a_corriger', 'À corriger'], ['publies', 'Publiés'], ['historique', 'Historique'],
] as const;
type Onglet = typeof ONGLETS[number][0];

type TroisEtats = boolean | null;

/** Correction directe d'une fiche par l'admin (enregistrée puis tracée). */
function FormModifierLieu({ l, onEnregistrer, onAnnuler }: { l: Lieu; onEnregistrer: (champs: Record<string, unknown>) => void; onAnnuler: () => void }) {
  const v = (k: string) => (l[k] == null ? '' : String(l[k]));
  const [nom, setNom] = useState(v('nom'));
  const [type, setType] = useState(v('sous_categorie'));
  const [adresse, setAdresse] = useState([v('adresse'), v('code_postal'), v('ville')].filter(Boolean).join(' '));
  const [lieu, setLieu] = useState<{ rue: string; codePostal: string; ville: string; lat: number; lng: number } | null>(null);
  const [site, setSite] = useState(v('site_web'));
  const [tel, setTel] = useState(v('telephone'));
  const [especes, setEspeces] = useState<string[]>((l.especes_acceptees as string[] | null) ?? []);
  const [etats, setEtats] = useState<Record<string, TroisEtats>>({
    animaux_en_salle: (l.animaux_en_salle as TroisEtats) ?? null, terrasse: (l.terrasse as TroisEtats) ?? null,
    restriction_taille: (l.restriction_taille as TroisEtats) ?? null, supplement_animal: (l.supplement_animal as TroisEtats) ?? null,
  });
  const [nb, setNb] = useState(v('nb_animaux_max'));
  const [conditions, setConditions] = useState(v('conditions_particulieres'));
  const [description, setDescription] = useState(v('description'));
  const input = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white';

  function enregistrer() {
    const t = TYPES_LIEU.find(x => x.value === type);
    const champs: Record<string, unknown> = {
      nom: nom.trim(), site_web: site.trim() || null, telephone: tel.trim() || null, especes_acceptees: especes,
      ...etats, nb_animaux_max: nb.trim() ? Number(nb) : null,
      conditions_particulieres: conditions.trim() || null, description: description.trim() || null,
      ...(t ? { categorie: t.categorie, sous_categorie: t.value } : {}),
      ...(lieu ? { adresse: lieu.rue, code_postal: lieu.codePostal || null, ville: lieu.ville, lat: lieu.lat, lng: lieu.lng } : {}),
    };
    onEnregistrer(champs);
  }

  return (
    <div className="space-y-3 border border-[#0C5C6C]/30 rounded-xl p-3 bg-[#F7FBFB]">
      <p className="text-sm font-bold text-[#0C5C6C]">Modifier la fiche</p>
      <div className="grid grid-cols-2 gap-3">
        <label className="text-xs font-semibold text-gray-500">Nom<input value={nom} onChange={e => setNom(e.target.value)} className={input} /></label>
        <label className="text-xs font-semibold text-gray-500">Catégorie
          <select value={type} onChange={e => setType(e.target.value)} className={input}>
            {!TYPES_LIEU.some(t => t.value === type) && <option value={type}>{type || '—'}</option>}
            {TYPES_LIEU.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select></label>
      </div>
      <div className="text-xs font-semibold text-gray-500">Adresse (choisir dans la liste pour déplacer le point sur la carte)
        <AddressAutocomplete value={adresse} onChange={setAdresse} className={input} onSelectDetails={d => setLieu(d)} />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <label className="text-xs font-semibold text-gray-500">Site web<input value={site} onChange={e => setSite(e.target.value)} className={input} /></label>
        <label className="text-xs font-semibold text-gray-500">Téléphone<input value={tel} onChange={e => setTel(e.target.value)} className={input} /></label>
      </div>
      <div>
        <p className="text-xs font-semibold text-gray-500 mb-1">Espèces accueillies</p>
        <div className="flex flex-wrap gap-2">
          {ESPECES_LIEUX.map(e => (
            <label key={e.value} className="flex items-center gap-1.5 text-sm border border-gray-200 rounded-lg px-2 py-1 bg-white">
              <input type="checkbox" className="accent-[#0C5C6C]" checked={especes.includes(e.value)}
                onChange={() => setEspeces(p => p.includes(e.value) ? p.filter(x => x !== e.value) : [...p, e.value])} />{e.label}
            </label>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3">
        {([['animaux_en_salle', 'Accès intérieur'], ['terrasse', 'Terrasse / extérieur'], ['restriction_taille', 'Restriction de taille'], ['supplement_animal', 'Supplément']] as const).map(([k, lib]) => (
          <label key={k} className="text-xs font-semibold text-gray-500">{lib}
            <select value={etats[k] === true ? 'oui' : etats[k] === false ? 'non' : ''} className={input}
              onChange={e => setEtats(p => ({ ...p, [k]: e.target.value === 'oui' ? true : e.target.value === 'non' ? false : null }))}>
              <option value="">Non renseigné</option><option value="oui">Oui</option><option value="non">Non</option>
            </select></label>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-3">
        <label className="text-xs font-semibold text-gray-500">Nombre d&apos;animaux max<input type="number" min={1} value={nb} onChange={e => setNb(e.target.value)} className={input} /></label>
        <label className="text-xs font-semibold text-gray-500">Conditions particulières<input value={conditions} onChange={e => setConditions(e.target.value)} className={input} /></label>
      </div>
      <label className="block text-xs font-semibold text-gray-500">Description<textarea rows={2} value={description} onChange={e => setDescription(e.target.value)} className={input} /></label>
      <div className="flex gap-2">
        <ActionBtn label="Enregistrer" color="#0C5C6C" onClick={enregistrer} />
        <ActionBtn label="Annuler" color="#64748b" onClick={onAnnuler} />
      </div>
    </div>
  );
}

function referencement(l: Lieu): string {
  if (!l.uid_pro) return 'Communauté';
  if (l.plan && l.plan !== 'decouverte') return 'Partenaire PetsMatch';
  return l.verification === 'verifie' ? 'Établissement vérifié' : 'Établissement (non vérifié)';
}

export default function LieuxPetFriendlyTab() {
  const [donnees, setDonnees] = useState<{
    enAttente: Lieu[]; aCorriger: Lieu[]; publies: Lieu[]; corrections: Correction[];
    revendications: Revendication[]; journal: Journal[]; doublons: Record<string, Doublon[]>;
  }>({ enAttente: [], aCorriger: [], publies: [], corrections: [], revendications: [], journal: [], doublons: {} });
  const [onglet, setOnglet] = useState<Onglet>('nouvelles');
  const [ouvert, setOuvert] = useState<string | null>(null);
  const [motif, setMotif] = useState('');
  const [enEdition, setEnEdition] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setErreur(null);
    const r = await apiFetch('/api/admin/moderation?type=lieux');
    const j = await r.json().catch(() => ({}));
    if (!r.ok) setErreur(j.error ?? 'Erreur de chargement');
    else setDonnees({
      enAttente: j.enAttente ?? [], aCorriger: j.aCorriger ?? [], publies: j.publies ?? [], corrections: j.corrections ?? [],
      revendications: j.revendications ?? [], journal: j.journal ?? [], doublons: j.doublons ?? {},
    });
    setLoading(false);
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function agir(action: string, id: string, extra: Record<string, unknown> = {}) {
    if (['lieu_a_corriger', 'lieu_refuser', 'lieu_masquer', 'correction_refuser', 'revendication_refuser'].includes(action) && !motif.trim()) {
      alert('Indiquez le motif : il est transmis à la personne.'); return;
    }
    const r = await apiFetch('/api/admin/moderation', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, id, motif: motif.trim(), ...extra }),
    });
    if (!r.ok) { alert((await r.json().catch(() => ({}))).error ?? 'Erreur'); return; }
    setMotif(''); setOuvert(null);
    void load();
  }

  const s = (v: unknown) => (v === null || v === undefined || v === '' ? null : String(v));
  const etat = (v: unknown) => (v === true ? 'Oui' : v === false ? 'Non' : 'Non renseigné');

  const champMotif = (
    <div>
      <label htmlFor="motif-lieu" className="text-xs font-semibold text-gray-500 block mb-1">Motif (transmis à la personne si à corriger, refusé ou masqué)</label>
      <textarea id="motif-lieu" value={motif} onChange={e => setMotif(e.target.value)} rows={2}
        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
    </div>
  );

  function carteLieu(l: Lieu, actions: React.ReactNode) {
    const st = STATUTS[l.statut ?? ''] ?? { label: l.statut ?? '—', color: '#64748b' };
    const photos = [s(l.photo_profil_url), ...((l.photos as string[] | null) ?? [])].filter(Boolean) as string[];
    const detail = ouvert === l.id;
    const doublons = donnees.doublons[l.id] ?? [];
    return (
      <div key={l.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
        <button type="button" className="w-full flex items-start justify-between gap-2 text-left" onClick={() => { setOuvert(detail ? null : l.id); setMotif(''); }}>
          <div>
            <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{l.nom ?? '—'}</p>
            <p className="text-xs text-gray-500">
              {[s(l.categorie), s(l.sous_categorie), s(l.ville)].filter(Boolean).join(' · ')} · {referencement(l)} · le {fmtDate(l.created_at)}
            </p>
            {doublons.length > 0 && (
              <p className="text-xs font-semibold text-[#B45309] mt-1">Doublon possible : {doublons.map(d => `${d.nom ?? '?'} (${d.metres} m)`).join(', ')}</p>
            )}
          </div>
          <Badge label={st.label} color={st.color} />
        </button>
        {detail && (
          <div className="space-y-3 pt-2 border-t">
            {photos.length > 0 && (
              <div className="flex gap-2 flex-wrap">
                {photos.map((u, i) => (
                  <a key={i} href={u} target="_blank" rel="noopener noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={u} alt="" className="w-24 h-24 object-cover rounded-lg border" />
                  </a>
                ))}
              </div>
            )}
            {s(l.recommandation) && <p className="text-sm text-gray-700 whitespace-pre-line">« {s(l.recommandation)} »</p>}
            {s(l.description) && <p className="text-sm text-gray-700 whitespace-pre-line">{s(l.description)}</p>}
            {s(l.motif_moderation) && <p className="text-xs text-gray-500">Dernier motif : {s(l.motif_moderation)}</p>}
            <div className="grid grid-cols-2 gap-3">
              <InfoRow label="Adresse" value={[s(l.adresse), s(l.code_postal), s(l.ville)].filter(Boolean).join(' ')} />
              <InfoRow label="Origine des conditions" value={l.source_conditions === 'communaute' ? 'Communauté (déclaratif)' : 'Établissement'} />
              <InfoRow label="Dernière visite / confirmation" value={fmtDate(l.derniere_confirmation_le as string | undefined)} />
              <InfoRow label="SIRET" value={s(l.siret)} mono />
              <InfoRow label="Site web" value={s(l.site_web)} />
              <InfoRow label="Téléphone" value={s(l.telephone)} />
              <InfoRow label="Espèces acceptées" value={Array.isArray(l.especes_acceptees) ? (l.especes_acceptees as string[]).join(', ') : s(l.especes_acceptees)} />
              <InfoRow label="Animaux max / poids max" value={[s(l.nb_animaux_max), s(l.poids_max_kg) && `${s(l.poids_max_kg)} kg`].filter(Boolean).join(' / ')} />
              <InfoRow label="Formule" value={s(l.plan)} />
              <InfoRow label="Conditions particulières" value={s(l.conditions_particulieres)} />
            </div>
            <div className="grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
              {TROIS_ETATS.map(([k, label]) => <p key={k}><span className="text-gray-500">{label} :</span> {etat(l[k])}</p>)}
            </div>
            {enEdition === l.id
              ? <FormModifierLieu l={l} onAnnuler={() => setEnEdition(null)}
                  onEnregistrer={champs => { void agir('lieu_modifier', l.id, { champs }).then(() => setEnEdition(null)); }} />
              : <ActionBtn label="Modifier la fiche" color="#0C5C6C" onClick={() => setEnEdition(l.id)} />}
            {champMotif}
            <div className="flex gap-2 flex-wrap">{actions}</div>
            {doublons.length > 0 && (
              <div className="flex gap-2 flex-wrap items-center">
                <span className="text-xs text-gray-500">Fusionner dans :</span>
                {doublons.map(d => (
                  <ActionBtn key={d.id} label={d.nom ?? d.id} color="#0C5C6C"
                    onClick={() => { if (confirm(`Rattacher cette fiche à « ${d.nom} » ? Ses avis et corrections suivront.`)) void agir('lieu_fusionner', l.id, { cible: d.id }); }} />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    );
  }

  const vide = (t: string) => <p className="text-sm text-gray-400">{t}</p>;
  const compteurs: Record<Onglet, number> = {
    nouvelles: donnees.enAttente.length, corrections: donnees.corrections.length, revendications: donnees.revendications.length,
    a_corriger: donnees.aCorriger.length, publies: donnees.publies.length, historique: 0,
  };

  if (loading) return <p className="text-sm text-gray-400">Chargement…</p>;
  return (
    <div className="space-y-5">
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      <div role="tablist" aria-label="Files de modération des lieux" className="flex gap-2 flex-wrap">
        {ONGLETS.map(([cle, label]) => (
          <button key={cle} type="button" role="tab" aria-selected={onglet === cle} onClick={() => { setOnglet(cle); setOuvert(null); setMotif(''); }}
            className={`px-3.5 py-1.5 rounded-full text-sm font-semibold border ${onglet === cle ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
            {label}{compteurs[cle] ? ` (${compteurs[cle]})` : ''}
          </button>
        ))}
      </div>
      <p className="text-xs text-gray-500">Les signalements et les avis contestés se traitent dans les onglets Signalements et Avis contestés.</p>

      {onglet === 'nouvelles' && (donnees.enAttente.length === 0 ? vide('Aucune fiche en attente.') : donnees.enAttente.map(l => carteLieu(l, <>
        <ActionBtn label="Publier" color="#16a34a" onClick={() => agir('lieu_valider', l.id)} />
        <ActionBtn label="À corriger" color="#2563eb" onClick={() => agir('lieu_a_corriger', l.id)} />
        <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('lieu_refuser', l.id)} />
      </>)))}

      {onglet === 'a_corriger' && (donnees.aCorriger.length === 0 ? vide('Aucune fiche à corriger.') : donnees.aCorriger.map(l => carteLieu(l, <>
        <ActionBtn label="Publier quand même" color="#16a34a" onClick={() => agir('lieu_valider', l.id)} />
        <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('lieu_refuser', l.id)} />
      </>)))}

      {onglet === 'publies' && (donnees.publies.length === 0 ? vide('Aucun lieu.') : donnees.publies.map(l => carteLieu(l, <>
        {l.statut === 'actif' && <ActionBtn label="Masquer" color="#64748b" onClick={() => agir('lieu_masquer', l.id)} />}
        {l.statut === 'actif' && <ActionBtn label="Suspendre" color="#dc2626" onClick={() => agir('lieu_suspendre', l.id)} />}
        {l.statut !== 'actif' && <ActionBtn label="Republier" color="#16a34a" onClick={() => agir('lieu_reactiver', l.id)} />}
      </>)))}

      {onglet === 'corrections' && (donnees.corrections.length === 0 ? vide('Aucune correction proposée.') : donnees.corrections.map(c => (
        <div key={c.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
          <p className="font-semibold text-gray-800">{c.place?.nom ?? 'Lieu'} <span className="text-xs text-gray-500 font-normal">· {c.place?.ville ?? ''} · le {fmtDate(c.created_at)}</span></p>
          <div className="text-sm space-y-0.5">
            {Object.entries(c.champs ?? {}).map(([k, v]) => <p key={k}><span className="text-gray-500">{k} :</span> {Array.isArray(v) ? v.join(', ') : v === true ? 'Oui' : v === false ? 'Non' : String(v ?? '—')}</p>)}
          </div>
          {c.commentaire && <p className="text-sm text-gray-700">« {c.commentaire} »</p>}
          {ouvert === c.id ? (<>
            {champMotif}
            <div className="flex gap-2">
              <ActionBtn label="Appliquer" color="#16a34a" onClick={() => agir('correction_appliquer', c.id)} />
              <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('correction_refuser', c.id)} />
            </div>
          </>) : <ActionBtn label="Traiter" color="#0C5C6C" onClick={() => { setOuvert(c.id); setMotif(''); }} />}
        </div>
      )))}

      {onglet === 'revendications' && (donnees.revendications.length === 0 ? vide('Aucune revendication en attente.') : donnees.revendications.map(r => (
        <div key={r.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
          <p className="font-semibold text-gray-800">{r.place?.nom ?? 'Lieu'} <span className="text-xs text-gray-500 font-normal">· {r.place?.ville ?? ''} · le {fmtDate(r.created_at)}</span></p>
          <div className="grid grid-cols-2 gap-3">
            <InfoRow label="Fonction" value={r.fonction} />
            <InfoRow label="SIRET déclaré" value={r.siret ?? null} mono />
            <InfoRow label="SIRET de la fiche" value={r.place?.siret ?? null} mono />
            <InfoRow label="Site de l'établissement" value={r.place?.site_web ?? null} />
            <InfoRow label="Preuve" value={r.methode === 'email_pro' ? `E-mail pro : ${r.email_pro ?? '—'}${r.email_confirme ? ' (confirmé)' : ' (non confirmé)'}` : 'Justificatif'} />
          </div>
          {r.justificatif_url && <a href={r.justificatif_url} target="_blank" rel="noopener noreferrer" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Ouvrir le justificatif</a>}
          {ouvert === r.id ? (<>
            {champMotif}
            <div className="flex gap-2">
              <ActionBtn label="Valider" color="#16a34a" onClick={() => agir('revendication_valider', r.id)} />
              <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('revendication_refuser', r.id)} />
            </div>
          </>) : <ActionBtn label="Traiter" color="#0C5C6C" onClick={() => { setOuvert(r.id); setMotif(''); }} />}
        </div>
      )))}

      {onglet === 'historique' && (donnees.journal.length === 0 ? vide('Aucune décision pour le moment.') : (
        <div className="bg-white rounded-2xl shadow-sm divide-y">
          {donnees.journal.map(j => (
            <div key={j.id} className="px-4 py-2.5 text-sm flex gap-3">
              <span className="text-gray-400 w-24 flex-shrink-0">{fmtDate(j.created_at)}</span>
              <span className="flex-1"><strong>{j.place?.nom ?? 'Lieu'}</strong> · {j.objet} · {j.action}{j.motif ? ` — ${j.motif}` : ''}</span>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}
