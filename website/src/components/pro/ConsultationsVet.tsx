'use client';

// Onglet « Consultations » de la fiche patient (vue vétérinaire) : une ligne
// compacte par consultation (date, motif, intervenant, poids, actes, statut
// du CR, nombre d'ordonnances) ; le détail (CR complet, ordonnances,
// traçabilité) s'ouvre dans un panneau latéral. Le carnet de santé reste
// dans l'onglet Santé — rien n'est dupliqué ici.
// Miroir appli : lib/widgets/vet/consultation_widgets.dart.

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import LienDocument from '@/components/LienDocument';

const TEAL = '#0C5C6C';

export interface CrVet {
  id: string; created_at: string; contenu: string | null; statut?: 'brouillon' | 'valide' | null;
  motif?: string | null; poids?: number | null; actes?: string[] | null; prescription?: string | null;
  doc_url?: string | null; rdv_id?: string | null;
  redige_par_uid?: string | null; redige_par_profile_id?: string | null;
  valide_par_uid?: string | null; valide_par_profile_id?: string | null; valide_le?: string | null;
}
export interface OrdoVet {
  id: string; date_emit: string; doc_url: string | null; notes: string | null; created_at?: string | null;
  rdv_id?: string | null; praticien_uid?: string | null; praticien_profile_id?: string | null;
}
interface Consultation { cle: string; date: Date; cr: CrVet | null; ordos: OrdoVet[] }
interface Journal { table_source: string; ligne_id: string; action: string; auteur_uid: string | null; auteur_profile_id: string | null; cree_le: string }

const ACTIONS: Record<string, string> = { creation: 'Création', modification: 'Modification', validation: 'Validation', suppression: 'Suppression' };
const jour = (d: Date) => d.toLocaleDateString('fr-FR');
const jourHeure = (d: Date) => `${jour(d)} à ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`;
const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const fmtPoids = (p: number) => `${p} kg`;

/** Une consultation = un CR (lié au RDV) + ses ordonnances ; une ordonnance
 *  sans CR forme sa propre consultation. */
export function regrouperConsultations(crs: CrVet[], ordos: OrdoVet[]): Consultation[] {
  let restantes = [...ordos];
  const out: Consultation[] = crs.map(cr => {
    const d = new Date(cr.created_at);
    const liees = restantes.filter(o => cr.rdv_id && o.rdv_id ? o.rdv_id === cr.rdv_id
      : !o.rdv_id && !cr.rdv_id && (o.date_emit ?? '').startsWith(ymd(d)));
    restantes = restantes.filter(o => !liees.includes(o));
    return { cle: `cr:${cr.id}`, date: d, cr, ordos: liees };
  });
  const groupes: Record<string, OrdoVet[]> = {};
  for (const o of restantes) (groupes[o.rdv_id ?? `jour:${o.date_emit}`] ??= []).push(o);
  for (const [k, liste] of Object.entries(groupes)) {
    out.push({ cle: `ordo:${k}`, date: new Date(liste[0].created_at ?? liste[0].date_emit), cr: null, ordos: liste });
  }
  return out.sort((a, b) => b.date.getTime() - a.date.getTime());
}

/** Noms des intervenants : profils (user_profiles) puis comptes (users). */
export async function chargerNoms(profils: string[], uids: string[]): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  const p = [...new Set(profils.filter(Boolean))], u = [...new Set(uids.filter(Boolean))];
  const nom = (x: { firstname?: string | null; lastname?: string | null; nom?: string | null }) =>
    `${x.firstname ?? ''} ${x.lastname ?? ''}`.trim() || x.nom || '';
  const [pr, ur] = await Promise.all([
    p.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', p) : Promise.resolve({ data: [] }),
    u.length ? supabase.from('users_complet').select('uid, firstname, lastname').in('uid', u) : Promise.resolve({ data: [] }),
  ]);
  for (const x of (pr.data ?? []) as { id: string; firstname?: string | null; lastname?: string | null; nom?: string | null }[]) { const n = nom(x); if (n) out[x.id] = n; }
  for (const x of (ur.data ?? []) as { uid: string; firstname?: string | null; lastname?: string | null }[]) { const n = nom(x); if (n) out[x.uid] = n; }
  return out;
}

const nomDe = (noms: Record<string, string>, profil?: string | null, uid?: string | null) =>
  (profil && noms[profil]) || (uid && noms[uid]) || null;

function intervenant(c: Consultation, noms: Record<string, string>) {
  if (c.cr) return nomDe(noms, c.cr.valide_par_profile_id, c.cr.valide_par_uid) ?? nomDe(noms, c.cr.redige_par_profile_id, c.cr.redige_par_uid);
  for (const o of c.ordos) { const n = nomDe(noms, o.praticien_profile_id, o.praticien_uid); if (n) return n; }
  return null;
}
const motifDe = (c: Consultation) => c.cr?.motif?.trim() || (c.cr ? 'Consultation' : 'Ordonnance');

export default function ConsultationsVet({ crs, ordos, peutCr, peutCarnet, peutValider, menuCarnet, onNouveauCr, onHistorique, onValider, onTransmettreCr, onTransmettreOrdo }: {
  crs: CrVet[]; ordos: OrdoVet[];
  peutCr: boolean; peutCarnet: boolean; peutValider: boolean;
  /** Entrées du menu « Ajouter au carnet » (modales existantes de la page). */
  menuCarnet: { label: string; onClick: () => void }[];
  onNouveauCr: () => void; onHistorique: () => void;
  onValider: (cr: CrVet) => Promise<void>;
  onTransmettreCr: (cr: CrVet, action: 'imprimer' | 'email') => void;
  onTransmettreOrdo: (o: OrdoVet, action: 'imprimer' | 'email') => void;
}) {
  const consultations = useMemo(() => regrouperConsultations(crs, ordos), [crs, ordos]);
  const [noms, setNoms] = useState<Record<string, string>>({});
  const [ouverte, setOuverte] = useState<string | null>(null);
  const [menu, setMenu] = useState(false);

  useEffect(() => {
    const profils = [...crs.flatMap(c => [c.redige_par_profile_id ?? '', c.valide_par_profile_id ?? '']), ...ordos.map(o => o.praticien_profile_id ?? '')];
    const uids = [...crs.flatMap(c => [c.redige_par_uid ?? '', c.valide_par_uid ?? '']), ...ordos.map(o => o.praticien_uid ?? '')];
    chargerNoms(profils, uids).then(setNoms);
  }, [crs, ordos]);

  const detail = consultations.find(c => c.cle === ouverte) ?? null;

  return (
    <div className="space-y-3" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="flex-1 text-base font-bold text-[#1E2025]">Consultations ({consultations.length})</h2>
        {crs.length > 0 && (
          <button onClick={onHistorique} className="text-sm font-semibold hover:underline" style={{ color: TEAL }}>Historique complet</button>
        )}
        {peutCr && (
          <button onClick={onNouveauCr} className="text-sm font-semibold text-white rounded-lg px-3 py-1.5" style={{ background: TEAL }}>
            Nouveau compte rendu
          </button>
        )}
        {peutCarnet && menuCarnet.length > 0 && (
          <div className="relative">
            <button onClick={() => setMenu(v => !v)} className="text-sm font-semibold rounded-lg px-3 py-1.5 border border-[#CFDCDD]" style={{ color: TEAL }}>
              Ajouter au carnet ▾
            </button>
            {menu && (
              <div className="absolute right-0 top-full mt-1 w-60 bg-white rounded-xl shadow-lg border border-gray-100 z-20 overflow-hidden">
                {menuCarnet.map(m => (
                  <button key={m.label} onClick={() => { setMenu(false); m.onClick(); }}
                    className="w-full text-left px-4 py-2.5 text-sm text-[#1E2025] hover:bg-gray-50 border-b border-gray-50 last:border-0">
                    {m.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {consultations.length === 0 ? (
        <p className="bg-white border border-[#E4E7E2] rounded-xl text-sm text-gray-400 text-center py-10">Aucune consultation enregistrée pour cet animal.</p>
      ) : (
        <div className="bg-white border border-[#E4E7E2] rounded-xl divide-y divide-[#F0F1EF]">
          {consultations.map(c => {
            const qui = intervenant(c, noms);
            const actes = c.cr?.actes ?? [];
            const brouillon = c.cr?.statut === 'brouillon';
            return (
              <button key={c.cle} onClick={() => setOuverte(c.cle)}
                className={`w-full text-left px-4 py-3 hover:bg-gray-50 grid grid-cols-[84px_1fr_auto] gap-x-3 items-start ${ouverte === c.cle ? 'bg-[#0C5C6C]/5' : ''}`}>
                <span className="text-sm font-bold" style={{ color: TEAL }}>{jour(c.date)}</span>
                <span className="min-w-0">
                  <span className="block text-sm font-bold text-[#1E2025] truncate">{motifDe(c)}</span>
                  {(qui || c.cr?.poids != null) && (
                    <span className="block text-xs text-gray-500">{[qui, c.cr?.poids != null ? fmtPoids(c.cr.poids) : null].filter(Boolean).join(' · ')}</span>
                  )}
                  {actes.length > 0 && (
                    <span className="block text-xs text-[#1E2025] truncate">{actes.length <= 3 ? actes.join(', ') : `${actes.slice(0, 3).join(', ')} +${actes.length - 3}`}</span>
                  )}
                </span>
                <span className="text-right text-xs whitespace-nowrap">
                  <span className={`block font-semibold ${brouillon ? 'text-[#8A5A00]' : 'text-gray-500'}`}>
                    {!c.cr ? 'Sans compte rendu' : brouillon ? 'CR à valider' : 'CR validé'}
                  </span>
                  {c.ordos.length > 0 && <span className="block text-gray-500">Ordonnances ({c.ordos.length})</span>}
                </span>
              </button>
            );
          })}
        </div>
      )}
      <p className="text-xs text-gray-400 text-center">Vaccins, traitements et autres soins : onglet Santé.</p>

      {detail && (
        <PanneauConsultation c={detail} noms={noms} onClose={() => setOuverte(null)}
          peutValider={peutValider} onValider={onValider}
          onTransmettreCr={onTransmettreCr} onTransmettreOrdo={onTransmettreOrdo} />
      )}
    </div>
  );
}

function PanneauConsultation({ c, noms: nomsInit, onClose, peutValider, onValider, onTransmettreCr, onTransmettreOrdo }: {
  c: Consultation; noms: Record<string, string>; onClose: () => void; peutValider: boolean;
  onValider: (cr: CrVet) => Promise<void>;
  onTransmettreCr: (cr: CrVet, action: 'imprimer' | 'email') => void;
  onTransmettreOrdo: (o: OrdoVet, action: 'imprimer' | 'email') => void;
}) {
  const [journal, setJournal] = useState<Journal[]>([]);
  const [nomsJournal, setNomsJournal] = useState<Record<string, string>>({});
  const [validation, setValidation] = useState(false);
  const noms = { ...nomsInit, ...nomsJournal };
  const cr = c.cr;
  const brouillon = cr?.statut === 'brouillon';

  // Journal serveur (migration_journal_medical.sql) : vide tant que la
  // migration n'est pas passée — la traçabilité des colonnes du CR reste.
  useEffect(() => {
    const ids = [...(c.cr ? [c.cr.id] : []), ...c.ordos.map(o => o.id)];
    let annule = false;
    supabase.from('journal_medical').select('table_source, ligne_id, action, auteur_uid, auteur_profile_id, cree_le')
      .in('table_source', ['comptes_rendus', 'ordonnances']).in('ligne_id', ids).order('cree_le')
      .then(async ({ data }) => {
        const liste = (data ?? []) as Journal[];
        const n = await chargerNoms(liste.map(j => j.auteur_profile_id ?? ''), liste.map(j => j.auteur_uid ?? ''));
        if (!annule) { setJournal(liste); setNomsJournal(n); }
      });
    return () => { annule = true; };
  }, [c]);

  const redacteur = cr ? nomDe(noms, cr.redige_par_profile_id, cr.redige_par_uid) : null;
  const validateur = cr ? nomDe(noms, cr.valide_par_profile_id, cr.valide_par_uid) : null;
  const ligne = (label: string, valeur: string) => (
    <div className="grid grid-cols-[120px_1fr] gap-2 text-sm py-0.5">
      <span className="text-gray-500">{label}</span><span className="text-[#1E2025]">{valeur}</span>
    </div>
  );
  const titre = (t: string) => <p className="text-[11px] font-bold tracking-wider uppercase text-gray-500 mt-5 mb-2">{t}</p>;
  const bouton = 'text-xs font-semibold px-3 py-1.5 rounded-lg border';

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/30" onClick={onClose}>
      <aside className="h-full w-full max-w-xl bg-white shadow-2xl overflow-y-auto p-6" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-start gap-3">
          <div className="flex-1">
            <p className="text-sm font-bold" style={{ color: TEAL }}>{jour(c.date)}</p>
            <h3 className="text-xl font-bold text-[#1E2025]">{motifDe(c)}</h3>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl w-8 h-8" aria-label="Fermer">✕</button>
        </div>

        <div className="mt-3">
          {intervenant(c, noms) && ligne('Intervenant', intervenant(c, noms)!)}
          {cr?.poids != null && ligne('Poids', fmtPoids(cr.poids))}
          {!!cr?.actes?.length && ligne('Actes réalisés', cr.actes.join(', '))}
          {cr && ligne('Compte rendu', brouillon ? 'Brouillon — à valider' : 'Validé')}
        </div>

        {cr && (
          <>
            {titre('Compte rendu')}
            {cr.contenu?.trim()
              ? <p className="text-sm text-[#1E2025] whitespace-pre-wrap leading-relaxed">{cr.contenu}</p>
              : <p className="text-sm text-gray-400">Aucun texte saisi.</p>}
            {cr.prescription && (
              <div className="mt-3">
                <p className="text-xs font-bold text-gray-500">Prescription</p>
                <p className="text-sm text-[#1E2025] whitespace-pre-wrap">{cr.prescription}</p>
              </div>
            )}
            {cr.doc_url && (
              <LienDocument href={cr.doc_url} target="_blank" rel="noopener noreferrer" className="inline-block mt-2 text-sm font-semibold underline" style={{ color: TEAL }}>
                Document joint
              </LienDocument>
            )}
            <div className="flex flex-wrap gap-2 mt-3">
              {brouillon && peutValider && (
                <button disabled={validation} onClick={async () => { setValidation(true); await onValider(cr); setValidation(false); }}
                  className="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50" style={{ background: TEAL }}>
                  {validation ? '…' : 'Valider et envoyer au propriétaire'}
                </button>
              )}
              {!brouillon && (
                <>
                  <button onClick={() => onTransmettreCr(cr, 'imprimer')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>Imprimer</button>
                  <button onClick={() => onTransmettreCr(cr, 'email')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>Envoyer au propriétaire</button>
                </>
              )}
            </div>
          </>
        )}

        {c.ordos.length > 0 && (
          <>
            {titre(`Ordonnances (${c.ordos.length})`)}
            <div className="space-y-2">
              {c.ordos.map(o => {
                const prescripteur = nomDe(noms, o.praticien_profile_id, o.praticien_uid);
                return (
                  <div key={o.id} className="border border-[#E4E7E2] rounded-lg px-3 py-2 flex items-center gap-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-[#1E2025]">Émise le {jour(new Date(o.date_emit ?? o.created_at ?? ''))}</p>
                      {(prescripteur || o.notes) && <p className="text-xs text-gray-500 truncate">{[prescripteur, o.notes].filter(Boolean).join(' · ')}</p>}
                    </div>
                    {o.doc_url && (
                      <>
                        <button onClick={() => onTransmettreOrdo(o, 'imprimer')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>Imprimer</button>
                        <button onClick={() => onTransmettreOrdo(o, 'email')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>Envoyer</button>
                        <LienDocument href={o.doc_url} target="_blank" rel="noopener noreferrer" className="text-xs font-semibold px-3 py-1.5 rounded-lg text-white" style={{ background: TEAL }}>
                          Ouvrir
                        </LienDocument>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          </>
        )}

        {titre('Traçabilité')}
        {cr && ligne('Rédigé', [redacteur ? `par ${redacteur}` : null, `le ${jourHeure(new Date(cr.created_at))}`].filter(Boolean).join(' '))}
        {cr && !brouillon && ligne('Validé', [validateur ? `par ${validateur}` : null, cr.valide_le ? `le ${jourHeure(new Date(cr.valide_le))}` : null].filter(Boolean).join(' ') || 'Oui')}
        {c.ordos.map(o => {
          const prescripteur = nomDe(noms, o.praticien_profile_id, o.praticien_uid);
          return <div key={o.id}>{ligne('Ordonnance', [prescripteur ? `prescrite par ${prescripteur}` : null, o.created_at ? `le ${jourHeure(new Date(o.created_at))}` : null].filter(Boolean).join(' ') || '—')}</div>;
        })}
        {journal.length > 0 && (
          <div className="mt-3">
            <p className="text-xs font-bold text-gray-500 mb-1">Journal des modifications</p>
            <ul className="text-xs text-[#1E2025] space-y-0.5">
              {journal.map((j, i) => {
                const auteur = nomDe(noms, j.auteur_profile_id, j.auteur_uid);
                return (
                  <li key={i}>
                    {jourHeure(new Date(j.cree_le))} · {ACTIONS[j.action] ?? j.action}{j.table_source === 'ordonnances' ? ' (ordonnance)' : ''}{auteur ? ` · ${auteur}` : ''}
                  </li>
                );
              })}
            </ul>
          </div>
        )}
      </aside>
    </div>
  );
}
