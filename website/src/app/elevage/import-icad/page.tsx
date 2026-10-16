'use client';
// Import I-CAD : création / mise à jour des fiches animaux du profil actif à
// partir des exports CSV « actuellement détenus » et « anciennement
// détenus ». Analyse d'abord (rapprochement puce, sinon prénom + date de
// naissance), puis l'utilisateur valide ce qu'il applique. Met aussi à jour
// le registre d'entrées / sorties et l'historique de propriété.
// Miroir appli : lib/pages/eleveur/animaux/icad_import_page.dart.
import { useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { lireCsvIcad, analyser, ligneNouvelle, champsMiseAJour, correctionCompte, entreeRegistre, neALElevage, libelleDate, type Analyse, type FicheExistante, type IcadAnimal } from '@/lib/icad-import';
import { apiFetch } from '@/lib/api-fetch';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const COLS = 'id, nom, identification, espece, sexe, race, couleur, date_naissance, statut, date_entree, date_sortie, destinataire_nom, destinataire_adresse, uid_acquereur, profile_id_acquereur';
const estUuid = (s: string) => /^[0-9a-f-]{36}$/i.test(s);

export default function ImportIcadPage() {
  const { user } = useAuth();
  const pid = useActiveProfile();
  const [analyse, setAnalyse] = useState<Analyse | null>(null);
  const [creer, setCreer] = useState<Set<string>>(new Set());
  /** Changements validés, un par ligne : « idFiche|champ ». */
  const [maj, setMaj] = useState<Set<string>>(new Set());
  const [etat, setEtat] = useState('');
  const [bilan, setBilan] = useState<string | null>(null);
  const [erreur, setErreur] = useState('');

  const cle = (a: IcadAnimal) => a.puce || `${a.nom}|${a.dateNaissance}`;

  async function charger(files: File[]) {
    if (!user || !files.length) return;
    setErreur(''); setBilan(null); setAnalyse(null); setEtat('Analyse…');
    try {
      const icad: IcadAnimal[] = [];
      for (const f of files) icad.push(...lireCsvIcad(await f.text()));
      // Fiches du profil actif (historique de propriété), jamais tout le compte.
      const { data: props } = await supabase.from('animaux_proprietes').select('animal_id')
        .eq('uid_proprio', user.uid).eq('statut', 'actif').eq('profile_id_proprio', pid);
      const ids = [...new Set(((props ?? []) as { animal_id: string }[]).map(p => p.animal_id))];
      const { data: f1 } = ids.length ? await supabase.from('animaux').select(COLS).in('id', ids) : { data: [] };
      const { data: f2 } = await supabase.from('animaux').select(COLS).eq('uid_eleveur', user.uid).eq('profile_id', pid);
      const fiches = new Map<string, FicheExistante>();
      for (const f of [...((f1 ?? []) as FicheExistante[]), ...((f2 ?? []) as FicheExistante[])]) fiches.set(String(f.id), f);
      const puces = icad.map(a => a.puce).filter(Boolean);
      const { data: autres } = puces.length ? await supabase.from('animaux').select('id, identification').in('identification', puces) : { data: [] };
      const pucesAutres = new Set(((autres ?? []) as { id: string; identification: string }[])
        .filter(x => !fiches.has(String(x.id))).map(x => x.identification.replace(/\D/g, '')));
      // Nom du compte PetsMatch rattaché comme acquéreur (cessions faites dans l'appli).
      const liees = [...fiches.values()].filter(f => f.uid_acquereur);
      if (liees.length) {
        const pids = liees.map(f => f.profile_id_acquereur).filter((x): x is string => !!x);
        const uids = liees.map(f => f.uid_acquereur as string);
        const [{ data: parPid }, { data: parUid }] = await Promise.all([
          pids.length ? supabase.from('user_profiles_complet').select('id, uid, firstname, lastname, nom').in('id', pids) : Promise.resolve({ data: [] }),
          supabase.from('user_profiles_complet').select('id, uid, firstname, lastname, nom').in('uid', uids).eq('is_main', true),
        ]);
        type P = { id: string; uid: string; firstname?: string | null; lastname?: string | null; nom?: string | null };
        const nomP = (p?: P) => (p ? `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || (p.nom ?? '') : '');
        for (const f of liees) {
          const p = ((parPid ?? []) as P[]).find(x => x.id === f.profile_id_acquereur) ?? ((parUid ?? []) as P[]).find(x => x.uid === f.uid_acquereur);
          f._compteAcquereur = nomP(p);
        }
      }
      const r = analyser(icad, [...fiches.values()], pucesAutres);
      setAnalyse(r);
      setCreer(new Set(r.nouvelles.map(cle)));
      setMaj(new Set(r.majs.flatMap(m => m.changements.map(c => `${m.fiche.id}|${c.champ}`))));
    } catch (e) { setErreur((e as Error).message); }
    setEtat('');
  }

  async function appliquer() {
    if (!analyse || !user) return;
    setEtat('Enregistrement…');
    let crees = 0, majs = 0;
    const erreurs: string[] = [];
    const today = new Date().toISOString().slice(0, 10);
    for (const [i, a] of analyse.nouvelles.filter(x => creer.has(cle(x))).entries()) {
      const id = `${Date.now()}${i}`;
      const ligne = { id, uid_eleveur: user.uid, ...(pid ? { profile_id: pid } : {}), ...ligneNouvelle(a), updated_at: new Date().toISOString() };
      let { error } = await supabase.from('animaux').insert(ligne);
      if (error?.message.includes('acquereur_contact_manuel')) {
        const { acquereur_contact_manuel: _ignore, ...sans } = ligne as typeof ligne & { acquereur_contact_manuel?: unknown };
        void _ignore;
        ({ error } = await supabase.from('animaux').insert(sans));
      }
      if (error) { erreurs.push(`${a.nom} : ${error.message}`); continue; }
      await supabase.from('animaux_proprietes').insert({
        animal_id: id, uid_proprio: user.uid, ...(pid ? { profile_id_proprio: pid } : {}),
        date_debut: entreeRegistre(a) || today, ...(a.dateCession ? { date_fin: a.dateCession } : {}),
      });
      crees++;
    }
    for (const m of analyse.majs) {
      const id = String(m.fiche.id);
      const choisis = new Set(m.changements.map(c => c.champ).filter(c => maj.has(`${id}|${c}`)));
      if (!choisis.size) continue;
      const champs = { ...champsMiseAJour(m, choisis), updated_at: new Date().toISOString() };
      if (Object.keys(champs).length > 1) {
        let { error } = await supabase.from('animaux').update(champs).eq('id', id);
        if (error?.message.includes('acquereur_contact_manuel')) {
          delete (champs as Record<string, unknown>).acquereur_contact_manuel;
          ({ error } = await supabase.from('animaux').update(champs).eq('id', id));
        }
        if (error) { erreurs.push(`${m.icad.nom} : ${error.message}`); continue; }
      }
      // Cession test vers un compte PetsMatch : annulée par le serveur
      // (retrait de ce compte), acquéreur I-CAD en destinataire.
      if (correctionCompte(m, choisis) && m.icad.acquereur) {
        const r = await apiFetch('/api/icad/corriger-cession', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ animalId: id, acquereur: m.icad.acquereur, dateCession: choisis.has('sortie') ? m.icad.dateCession : null }),
        });
        if (!r.ok) { erreurs.push(`${m.icad.nom} : ${((await r.json()) as { error?: string }).error ?? 'correction impossible'}`); continue; }
      } else {
        // Sortie : la propriété du profil se clôt à la cession ; le registre suit.
        if (choisis.has('sortie')) {
          await supabase.from('animaux_proprietes').update({ date_fin: m.icad.dateCession })
            .eq('animal_id', id).eq('uid_proprio', user.uid).is('date_fin', null);
        }
        if (estUuid(id) && (choisis.has('sortie') || choisis.has('acquereur'))) {
          await supabase.from('registre_mouvements').update({
            ...(choisis.has('sortie') ? { date_mouvement: m.icad.dateCession } : {}),
            ...(choisis.has('acquereur') && m.icad.acquereur ? {
              destinataire_nom: `${m.icad.acquereur.prenom} ${m.icad.acquereur.nom}`.trim(),
              destinataire_qualite: 'particulier', destinataire_adresse: m.icad.acquereur.adresse,
            } : {}),
          }).eq('animal_id', id).eq('uid_eleveur', user.uid).eq('type', 'sortie');
        }
      }
      majs++;
    }
    setEtat('');
    setAnalyse(null);
    setBilan(`${crees} fiche${crees > 1 ? 's' : ''} créée${crees > 1 ? 's' : ''}, ${majs} mise${majs > 1 ? 's' : ''} à jour.${erreurs.length ? ` Erreurs : ${erreurs.join(' ; ')}` : ''}`);
  }

  const bascule = (s: Set<string>, set: (x: Set<string>) => void, k: string) => {
    const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); set(n);
  };
  const sexe = (s: string) => (s === 'male' ? 'Mâle' : s === 'femelle' ? 'Femelle' : '—');

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-5xl mx-auto px-4 py-6 space-y-4">
        <div>
          <Link href="/mes-animaux" className="text-sm font-semibold" style={{ color: TEAL }}>← Mes animaux</Link>
          <h1 className="text-xl font-bold text-[#1F2A2E] mt-1">Importer depuis I-CAD</h1>
          <p className="text-sm text-gray-600 mt-1">
            Sur i-cad.fr, exportez vos animaux « actuellement détenus » et « anciennement détenus » au format CSV, puis déposez les fichiers ici.
            Les fiches existantes sont reconnues par le numéro de puce, ou à défaut par le prénom et la date de naissance. Rien n&apos;est enregistré avant votre validation.
          </p>
        </div>

        <label className={`block rounded-2xl border-2 border-dashed border-gray-300 bg-white p-6 text-center cursor-pointer ${etat ? 'opacity-60 pointer-events-none' : ''}`}>
          <input type="file" accept=".csv,text/csv" multiple className="hidden" onChange={e => { charger([...(e.target.files ?? [])]); e.target.value = ''; }} />
          <p className="text-sm font-semibold text-[#1F2A2E]">{etat || 'Choisir le ou les fichiers CSV I-CAD'}</p>
          <p className="text-xs text-gray-500 mt-1">Vous pouvez sélectionner les deux exports en même temps.</p>
        </label>
        {erreur && <p className="text-sm" style={{ color: '#B3261E' }}>{erreur}</p>}
        {bilan && (
          <div className="bg-white rounded-2xl border border-gray-100 p-4 text-sm">
            <p className="font-semibold text-[#1F2A2E]">{bilan}</p>
            <Link href="/mes-animaux" className="font-semibold" style={{ color: TEAL }}>Voir mes animaux →</Link>
          </div>
        )}

        {analyse && (
          <>
            {analyse.alertes.length > 0 && (
              <div className="bg-white rounded-2xl border p-4 space-y-1" style={{ borderColor: '#F5D9A8' }}>
                <p className="text-sm font-bold" style={{ color: AMBRE }}>Points à vérifier ({analyse.alertes.length})</p>
                {analyse.alertes.map((t, k) => <p key={k} className="text-sm text-gray-700">{t}</p>)}
              </div>
            )}

            <div className="bg-white rounded-2xl border border-gray-100 p-4">
              <p className="text-sm font-bold text-[#1F2A2E] mb-2">Fiches existantes à mettre à jour ({analyse.majs.length})</p>
              {analyse.majs.length === 0 ? <p className="text-sm text-gray-400">Aucune.</p> : analyse.majs.map(m => (
                <div key={m.fiche.id} className="py-3 border-t border-gray-50 first:border-0">
                  <p className="text-sm font-bold text-[#1F2A2E]">{m.fiche.nom || m.icad.nom}
                    <span className="font-normal text-xs text-gray-500"> — reconnu par {m.par === 'puce' ? 'la puce' : 'le prénom et la date de naissance'}</span></p>
                  <div className="mt-1 space-y-1">
                    {m.changements.map(c => {
                      const k = `${m.fiche.id}|${c.champ}`;
                      return (
                        <label key={k} className="flex items-start gap-2 text-xs cursor-pointer">
                          <input type="checkbox" className="mt-0.5" checked={maj.has(k)} onChange={() => bascule(maj, setMaj, k)} />
                          <span><span className="font-semibold text-gray-700">{c.libelle} :</span> <span className="text-gray-500">{c.actuel}</span> → <span style={{ color: c.champ === 'acquereur' && m.fiche.uid_acquereur ? AMBRE : TEAL }}>{c.icad}</span></span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>

            <div className="bg-white rounded-2xl border border-gray-100 p-4">
              <p className="text-sm font-bold text-[#1F2A2E] mb-2">Nouvelles fiches à créer ({analyse.nouvelles.length})</p>
              {analyse.nouvelles.length === 0 ? <p className="text-sm text-gray-400">Aucune.</p> : (
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead><tr className="text-left text-gray-500"><th className="py-1 pr-2"></th><th className="pr-2">Nom</th><th className="pr-2">Puce</th><th className="pr-2">Race</th><th className="pr-2">Sexe</th><th className="pr-2">Naissance</th><th>Registre</th></tr></thead>
                    <tbody>
                      {analyse.nouvelles.map(a => (
                        <tr key={cle(a)} className="border-t border-gray-50">
                          <td className="py-1.5 pr-2"><input type="checkbox" checked={creer.has(cle(a))} onChange={() => bascule(creer, setCreer, cle(a))} /></td>
                          <td className="pr-2 font-semibold text-[#1F2A2E]">{a.nom}</td>
                          <td className="pr-2">{a.puce}</td>
                          <td className="pr-2">{a.race} · {a.couleur}</td>
                          <td className="pr-2">{sexe(a.sexe)}</td>
                          <td className="pr-2">{libelleDate(a.dateNaissance)}</td>
                          <td>{`${neALElevage(a) ? "Né à l'élevage" : `Entré le ${libelleDate(entreeRegistre(a))}`}${a.dateCession ? `, sorti le ${libelleDate(a.dateCession)}${a.acquereur ? ` → ${a.acquereur.prenom} ${a.acquereur.nom}` : ''}` : ', présent'}`}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            {analyse.aJour.length > 0 && (
              <div className="bg-white rounded-2xl border border-gray-100 p-4">
                <p className="text-sm font-bold text-[#1F2A2E] mb-1">Déjà à jour ({analyse.aJour.length})</p>
                <p className="text-xs text-gray-500">{analyse.aJour.map(x => x.fiche.nom || x.icad.nom).join(', ')}</p>
              </div>
            )}

            <div className="flex flex-wrap items-center gap-3">
              <button onClick={appliquer} disabled={!!etat || (creer.size === 0 && maj.size === 0)}
                className="px-5 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>
                Valider : {creer.size} création{creer.size > 1 ? 's' : ''}, {maj.size} mise{maj.size > 1 ? 's' : ''} à jour
              </button>
              <button onClick={() => setAnalyse(null)} className="px-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200 bg-white">Annuler</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
