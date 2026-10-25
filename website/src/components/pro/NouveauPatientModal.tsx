'use client';

// Clinique — nouveau patient dont le propriétaire n'a pas (forcément)
// PetsMatch : client du fichier de la clinique (clients_clinique) + fiche
// animal, via pm_creer_patient_clinique (migration_patients_clinique.sql).
// Anti-doublon : n° de puce (pm_puce_existante : une puce = une fiche ;
// fiche créée par un autre pro → rattachement « identité seule »,
// pm_rattacher_fiche_pro) et compte PetsMatch.
// Miroir app : lib/pages/pro/nouveau_patient_clinique_page.dart.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { trouverUtilisateurParEmail, type UtilisateurTrouve } from '@/lib/user-lookup';

const TEAL = '#0C5C6C';
const ESPECES = [['chien', 'Chien'], ['chat', 'Chat'], ['cheval', 'Cheval / équidé'], ['lapin', 'Lapin'], ['nac', 'NAC'],
  ['oiseau', 'Oiseau'], ['bovin', 'Bovin'], ['ovin', 'Ovin'], ['caprin', 'Caprin'], ['porcin', 'Porcin'], ['autre', 'Autre']];

interface Client { id: string; nom: string; prenom: string | null; telephone: string | null; email: string | null }

export default function NouveauPatientModal({ cliniqueProfileId, onClose, onCree, estClinique = true, titre: titreModal }: {
  cliniqueProfileId: string; onClose: () => void; onCree: (animalId: string) => void;
  /** Titre selon le métier (« Nouvel animal suivi », « Nouvel équidé »…). */
  titre?: string;
  /** Vocabulaire : « patient » (vétérinaire) ou « client » (toiletteur, maréchal-ferrant, ostéopathe, éducateur). */
  estClinique?: boolean;
}) {
  const [clients, setClients] = useState<Client[]>([]);
  const [rechercheClient, setRechercheClient] = useState('');
  const [clientExistant, setClientExistant] = useState<Client | null>(null);
  const [c, setC] = useState({ nom: '', prenom: '', telephone: '', email: '', adresse: '', code_postal: '', ville: '' });
  const [a, setA] = useState({ nom: '', espece: 'chien', race: '', sexe: '', date_naissance: '', identification: '', poids: '', couleur: '' });
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);
  // Étape 1 franchie : puce vérifiée (aucune fiche) ou animal sans puce.
  const [puceOk, setPuceOk] = useState(false);
  /** Fiche d'un autre pro à rattacher : on ne saisit que le client. */
  const [rattacherA, setRattacherA] = useState<string | null>(null);
  const [doublon, setDoublon] = useState<{ type: 'animal' | 'compte' | 'pro'; texte: string; animalId?: string } | null>(null);
  const mot = estClinique ? 'patients' : 'clients';

  useEffect(() => {
    supabase.from('clients_clinique').select('id, nom, prenom, telephone, email')
      .eq('clinique_profile_id', cliniqueProfileId).order('nom')
      .then(({ data }) => setClients((data ?? []) as Client[]));
  }, [cliniqueProfileId]);

  const q = rechercheClient.trim().toLowerCase();
  const suggestions = q ? clients.filter(x => `${x.prenom ?? ''} ${x.nom} ${x.telephone ?? ''} ${x.email ?? ''}`.toLowerCase().includes(q)).slice(0, 8) : [];

  /** Une puce = une fiche : false si l'animal est déjà sur PetsMatch (le pro
   *  est alors orienté : déjà suivi, rattachement ou demande d'accès). */
  async function controlerPuce(): Promise<boolean> {
    if (a.identification.trim().length >= 6) {
      const { data } = await supabase.rpc('pm_puce_existante', { p_identification: a.identification.trim(), p_profile: cliniqueProfileId });
      const ex = ((data ?? []) as { animal_id: string; nom: string | null; detenteur: string; deja_lie: boolean }[])[0];
      if (ex) {
        const nom = ex.nom ?? 'Cet animal';
        setDoublon(ex.deja_lie
          ? { type: 'animal', texte: `${nom} est déjà dans vos ${mot}.` }
          : ex.detenteur === 'pro'
            ? { type: 'pro', animalId: ex.animal_id, texte: `${nom} a déjà une fiche, créée par un autre professionnel pour son client. Rattachez-la à vos ${mot} : vous verrez son identité et ajouterez vos propres documents. Son carnet de santé et les documents de l’autre professionnel restent privés tant que le propriétaire ne les a pas partagés.` }
            : { type: 'animal', texte: `Le n° ${a.identification.trim()} correspond à ${nom}, déjà enregistré par son ${ex.detenteur === 'eleveur' ? 'éleveur' : 'propriétaire'} sur PetsMatch. Demandez plutôt l'accès à son carnet (recherche par puce dans Mes ${mot}).` });
        return false;
      }
    }
    return true;
  }

  /** Étape 1 : la puce d'abord. */
  async function verifierPuceDabord() {
    setErreur(null); setDoublon(null);
    if (a.identification.replace(/[^0-9A-Za-z]/g, '').length < 6) {
      setErreur('Saisissez le n° de puce ou de tatouage (6 caractères au moins), ou indiquez que l’animal n’en a pas.');
      return;
    }
    setSaving(true);
    const libre = await controlerPuce();
    setSaving(false);
    if (libre) setPuceOk(true);
  }

  async function creer(forcer = false) {
    setErreur(null);
    if (rattacherA) {
      if (!clientExistant && !c.nom.trim()) { setErreur('Nom du propriétaire obligatoire.'); return; }
      await rattacher(rattacherA);
      return;
    }
    if (!a.nom.trim() || (!clientExistant && !c.nom.trim())) { setErreur("Nom du propriétaire et nom de l'animal obligatoires."); return; }
    setSaving(true);
    try {
      if (!forcer) {
        if (!(await controlerPuce())) { setSaving(false); return; }
        // 2. Propriétaire ayant un compte PetsMatch
        if (!clientExistant && c.email.trim()) {
          const u: UtilisateurTrouve | null = await trouverUtilisateurParEmail(c.email.trim());
          if (u) {
            setDoublon({ type: 'compte', texte: `${u.firstname ?? ''} ${u.lastname ?? ''} a un compte PetsMatch. Si son animal y est déjà, demandez l'accès à son carnet pour éviter un doublon. Sinon, créez la fiche : il pourra la rattacher à son compte.` });
            setSaving(false); return;
          }
        }
      }
      const { data, error } = await supabase.rpc('pm_creer_patient_clinique', {
        p_clinique: cliniqueProfileId, p_client_id: clientExistant?.id ?? null, p_client: c, p_animal: a,
      });
      if (error) { setErreur(error.code === 'P0001' || error.code === '23505' ? error.message : `Création impossible : ${error.message}`); setSaving(false); return; }
      onCree(String(data));
    } catch (e) {
      setErreur(`Création impossible : ${(e as Error).message}`);
      setSaving(false);
    }
  }

  /** Fiche créée par un autre pro : rattachement « identité seule ». */
  async function rattacher(animalId: string) {
    setErreur(null); setSaving(true);
    const { data, error } = await supabase.rpc('pm_rattacher_fiche_pro', {
      p_profile: cliniqueProfileId, p_animal: animalId, p_client_id: clientExistant?.id ?? null, p_client: clientExistant ? null : c,
    });
    if (error) { setErreur(error.code === 'P0001' ? error.message : `Rattachement impossible : ${error.message}`); setSaving(false); return; }
    onCree(String(data));
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
  const titre = 'text-sm font-bold text-[#1E2025] mt-2';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-lg p-6 space-y-3 max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <h2 className="font-bold text-lg text-[#1E2025]">{titreModal ?? (estClinique ? 'Nouveau patient' : 'Nouveau client')}</h2>
          <p className="text-xs text-gray-400 mt-0.5">{estClinique
            ? 'Pour un animal dont le propriétaire n\'a pas PetsMatch. Il pourra rattacher la fiche à son compte plus tard.'
            : 'Pour un client qui n\'a pas PetsMatch : contrat, facture et demandes lui sont envoyés par e-mail, avec une invitation à créer son compte.'}</p>
        </div>

        {!puceOk && (
          <div className="space-y-2">
            <p className={titre}>1. Puce ou tatouage</p>
            <p className="text-xs text-gray-500">On vérifie d’abord que l’animal n’a pas déjà une fiche sur PetsMatch (une puce = un animal).</p>
            <input value={a.identification} autoFocus onChange={e => { setA({ ...a, identification: e.target.value }); setDoublon(null); }}
              onKeyDown={e => { if (e.key === 'Enter') verifierPuceDabord(); }}
              placeholder="N° de puce / tatouage" className={champ} />
            <button type="button" onClick={() => { setA({ ...a, identification: '' }); setDoublon(null); setPuceOk(true); }}
              className="text-xs font-semibold" style={{ color: TEAL }}>L’animal n’a pas de puce</button>
          </div>
        )}
        {puceOk && (<>
        <p className={titre}>Propriétaire</p>
        {clientExistant ? (
          <div className="flex items-center gap-3 rounded-xl px-3 py-2" style={{ background: `${TEAL}0F`, border: `1px solid ${TEAL}40` }}>
            <span className="flex-1 text-sm">
              <strong>{`${clientExistant.prenom ?? ''} ${clientExistant.nom}`.trim()}</strong>
              <span className="block text-xs text-gray-500">{[clientExistant.telephone, clientExistant.email].filter(Boolean).join(' · ')}</span>
            </span>
            <button onClick={() => setClientExistant(null)} className="text-xs font-semibold" style={{ color: TEAL }}>Changer</button>
          </div>
        ) : (
          <>
            {clients.length > 0 && (
              <div className="relative">
                <input value={rechercheClient} onChange={e => setRechercheClient(e.target.value)}
                  placeholder="🔎 Client déjà dans votre fichier (rechercher)" className={champ} />
                {suggestions.length > 0 && (
                  <div className="absolute z-10 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                    {suggestions.map(x => (
                      <button key={x.id} type="button" onClick={() => { setClientExistant(x); setRechercheClient(''); }}
                        className="w-full text-left px-3 py-2 text-sm hover:bg-gray-50 border-b border-gray-50 last:border-0">
                        {`${x.prenom ?? ''} ${x.nom}`.trim()} <span className="text-xs text-gray-400">{x.telephone ?? x.email ?? ''}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
            <div className="grid grid-cols-2 gap-2">
              <input value={c.nom} onChange={e => setC({ ...c, nom: e.target.value })} placeholder="Nom *" className={champ} />
              <input value={c.prenom} onChange={e => setC({ ...c, prenom: e.target.value })} placeholder="Prénom" className={champ} />
            </div>
            <input value={c.telephone} onChange={e => setC({ ...c, telephone: e.target.value })} type="tel" placeholder="Téléphone" className={champ} />
            <input value={c.email} onChange={e => setC({ ...c, email: e.target.value })} type="email" placeholder="E-mail (envoi des ordonnances, rappels)" className={champ} />
            <input value={c.adresse} onChange={e => setC({ ...c, adresse: e.target.value })} placeholder="Adresse" className={champ} />
            <div className="grid grid-cols-[110px_1fr] gap-2">
              <input value={c.code_postal} onChange={e => setC({ ...c, code_postal: e.target.value })} placeholder="Code postal" className={champ} />
              <input value={c.ville} onChange={e => setC({ ...c, ville: e.target.value })} placeholder="Ville" className={champ} />
            </div>
          </>
        )}

        {rattacherA ? (
          <p className="text-xs rounded-xl p-3" style={{ background: `${TEAL}0F` }}>
            Fiche existante : l’animal sera rattaché à votre fichier avec ce client. Son carnet de santé et les documents de l’autre professionnel restent privés.
          </p>
        ) : (<>
        <p className={titre}>Animal</p>
        <input value={a.nom} onChange={e => setA({ ...a, nom: e.target.value })} placeholder="Nom *" className={champ} />
        <div className="grid grid-cols-2 gap-2">
          <select value={a.espece} onChange={e => setA({ ...a, espece: e.target.value })} className={champ}>
            {ESPECES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
          <select value={a.sexe} onChange={e => setA({ ...a, sexe: e.target.value })} className={champ}>
            <option value="">Sexe —</option><option value="male">Mâle</option><option value="femelle">Femelle</option>
          </select>
        </div>
        <input value={a.race} onChange={e => setA({ ...a, race: e.target.value })} placeholder="Race" className={champ} />
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs text-gray-500">Naissance
            <input type="date" value={a.date_naissance} onChange={e => setA({ ...a, date_naissance: e.target.value })} className={`${champ} mt-1`} />
          </label>
          <label className="text-xs text-gray-500">Poids (kg)
            <input value={a.poids} inputMode="decimal" onChange={e => setA({ ...a, poids: e.target.value })} className={`${champ} mt-1`} />
          </label>
        </div>
        <div className="flex items-center justify-between gap-2 text-sm">
          <span>{a.identification.trim() ? `Puce / tatouage : ${a.identification.trim()} (vérifié)` : 'Sans puce ni tatouage'}</span>
          <button type="button" onClick={() => { setPuceOk(false); setRattacherA(null); }} className="text-xs font-semibold" style={{ color: TEAL }}>Modifier</button>
        </div>
        <input value={a.couleur} onChange={e => setA({ ...a, couleur: e.target.value })} placeholder="Robe / couleur" className={champ} />
        </>)}

        </>)}
        {doublon && (
          <div className="rounded-xl p-3 text-xs space-y-2" style={{ background: '#FFF4DC', color: '#8A5A00' }}>
            <p>{doublon.texte}</p>
            {doublon.type === 'compte' && (
              <button onClick={() => { setDoublon(null); creer(true); }} className="font-bold underline">Créer quand même</button>
            )}
            {doublon.type === 'pro' && doublon.animalId && (
              <button onClick={() => { setRattacherA(doublon.animalId!); setDoublon(null); setPuceOk(true); }} disabled={saving}
                className="px-3 py-2 rounded-lg text-white font-bold disabled:opacity-50" style={{ background: TEAL }}>
                Rattacher à mes {mot}
              </button>
            )}
          </div>
        )}
        {erreur && <p className="text-xs text-red-500">{erreur}</p>}

        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">Annuler</button>
          {puceOk ? (
            <button onClick={() => creer()} disabled={saving} className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50" style={{ background: TEAL }}>
              {saving ? '…' : rattacherA ? `Rattacher à mes ${mot}` : estClinique ? 'Créer le patient' : 'Créer le client'}
            </button>
          ) : (
            <button onClick={verifierPuceDabord} disabled={saving} className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50" style={{ background: TEAL }}>
              {saving ? '…' : 'Vérifier la puce'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
