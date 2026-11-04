'use client';

// Dossier d'un RDV « Intervention » (vétérinaire) : consignes avant
// l'intervention, CR préopératoire, admission (animal déposé), CR opératoire,
// réveil / hospitalisation (notes, famille prévenue), sortie (consignes
// postopératoires, animal récupéré). Affiché en tête du dossier de la séance ;
// le compte rendu (soins, ordonnance, produits), le devis, la facture et le
// prochain RDV suivent comme pour une consultation.
// Miroir appli : _dossierIntervention (pro_agenda.dart).
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { libelleIntervention, envoyerConsignesPreop, messageIntervention, chirurgiesAnimal, rattacherChirurgie } from '@/lib/intervention';

const TEAL = '#0C5C6C';
const VERT = '#2E7D32';
const AMBRE = '#B45309';
const GRIS = '#6B7280';

interface RdvIntervention {
  id: string; animal_id: string | null; client_uid: string | null; client_profile_id: string | null; motif: string | null;
  date_heure: string; pro_uid: string; pro_profile_id: string | null; instructeur_profile_id: string | null;
  reveil_le: string | null; pret_le: string | null;
  intervention_type: string | null; heure_recuperation: string | null; bloc_debut: string | null; bloc_fin: string | null;
  chirurgie_id: string | null; consignes_preop: string | null; admis_le: string | null; sortie_le: string | null; suivi_hospitalisation: string | null;
}
type Doc = { statut?: string } | null;

/** Erreurs de cohérence de la base, en clair. */
const erreurLisible = (m: string) => /rdv_intervention_horaires/.test(m)
  ? 'Horaires incohérents : intervention après le dépôt, récupération après le dépôt et après l’intervention.'
  : /rdv_intervention_etapes/.test(m) ? 'Étapes dans le désordre : l’animal doit d’abord être déposé.' : m;
/** « jeu. 5 nov. 17h00 » si ce n'est pas le jour de référence, sinon « 17h00 ». */
const jourHm = (d: string | null, ref: string) => !d ? '' : new Date(d).toDateString() === new Date(ref).toDateString() ? hm(d)
  : `${new Date(d).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' })} ${hm(d)}`;
/** Valeur d'un <input type="datetime-local"> (heure locale). */
const versLocal = (d: string | null) => { if (!d) return ''; const x = new Date(d); x.setMinutes(x.getMinutes() - x.getTimezoneOffset()); return x.toISOString().slice(0, 16); };
const hm = (d: string | null) => d ? new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }).replace(':', 'h') : '';
const etatDoc = (d: Doc) => d?.statut === 'valide' ? ['Validé', VERT] : d ? ['Brouillon', AMBRE] : ['À faire', GRIS];

/** null : ce RDV n'est pas une intervention (rien n'est affiché). */
export default function InterventionDossier({ rdvId, version, onOuvrirPage, animalNom, onProgrammerRdv }: {
  rdvId: string; version: number; animalNom?: string;
  onOuvrirPage: (url: string, titre: string) => void;
  /** RDV de contrôle : prise de RDV préremplie (agenda du vétérinaire et de la famille). */
  onProgrammerRdv?: (p: { animalId?: string; motif?: string }) => void;
}) {
  const [r, setR] = useState<RdvIntervention | null>(null);
  const [chir, setChir] = useState<{ preop: Doc; operatoire: Doc; consignes: Doc } | null>(null);
  const [suivi, setSuivi] = useState('');
  const [message, setMessage] = useState('');
  const [enCours, setEnCours] = useState('');
  // Choix du CR préopératoire existant (consultation d'un autre jour).
  const [choixPreop, setChoixPreop] = useState<Awaited<ReturnType<typeof chirurgiesAnimal>> | null>(null);

  async function charger() {
    const { data } = await supabase.from('rdv')
      .select('id, animal_id, client_uid, client_profile_id, motif, date_heure, pro_uid, pro_profile_id, instructeur_profile_id, intervention_type, heure_recuperation, bloc_debut, bloc_fin, chirurgie_id, consignes_preop, admis_le, reveil_le, pret_le, sortie_le, suivi_hospitalisation')
      .eq('id', rdvId).maybeSingle();
    const x = data as RdvIntervention | null;
    setR(x);
    setSuivi(x?.suivi_hospitalisation ?? '');
    if (x?.chirurgie_id) {
      const { data: c } = await supabase.from('chirurgies').select('preop, operatoire, consignes').eq('id', x.chirurgie_id).maybeSingle();
      setChir((c as { preop: Doc; operatoire: Doc; consignes: Doc } | null) ?? null);
    }
  }
  useEffect(() => { charger(); // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rdvId, version]);

  if (!r?.intervention_type) return null;

  const action = async (cle: string, f: () => Promise<unknown>) => {
    setEnCours(cle); setMessage('');
    try { await f(); } finally { setEnCours(''); }
  };
  const maj = (champs: Partial<RdvIntervention>) => action(Object.keys(champs)[0], async () => {
    const { error } = await supabase.from('rdv').update(champs).eq('id', r.id);
    if (error) setMessage(`Non enregistré : ${erreurLisible(error.message)}`); else await charger();
  });
  const ouvrirDoc = (doc: 'preop' | 'operatoire' | 'consignes', titre: string) => r.animal_id && r.chirurgie_id
    ? onOuvrirPage(`/mes-patients/${encodeURIComponent(r.animal_id)}?chirDoc=${encodeURIComponent(`${r.chirurgie_id}:${doc}`)}`, titre)
    : setMessage('Intervention non rattachée à une fiche animal.');
  // Notification (appli), sinon e-mail, sinon « appelez-le au … » (vétérinaire ou ASV).
  const prevenirFamille = (m: 'reveille' | 'pret' | 'recuperation') => action(m, async () => setMessage(await messageIntervention(r.id, m)));
  // Récupération (date + heure : hospitalisation de plusieurs jours possible).
  async function changerRecuperation(valeur: string) {
    if (!valeur || !r) return;
    const nouvelle = new Date(valeur);
    if (isNaN(nouvelle.getTime())) { setMessage('Date et heure de récupération obligatoires.'); return; }
    if (nouvelle <= new Date(r.date_heure)) { setMessage('La récupération doit être après le dépôt.'); return; }
    if (r.bloc_fin && nouvelle < new Date(r.bloc_fin)) { setMessage('La récupération doit être après la fin de l’intervention.'); return; }
    await action('recuperation', async () => {
      const { error } = await supabase.from('rdv').update({ heure_recuperation: nouvelle.toISOString() }).eq('id', r.id);
      if (error) { setMessage(`Non enregistré : ${erreurLisible(error.message)}`); return; }
      await charger();
      setMessage(`Récupération ${jourHm(nouvelle.toISOString(), r.date_heure)}. ${await messageIntervention(r.id, 'recuperation')}`);
    });
  }
  // Créneau d'intervention (bloc) modifiable : salle de bloc / indisponibilité suivent.
  async function changerBloc(debutLocal: string, duree: number) {
    if (!r || !debutLocal) return;
    const bd = new Date(debutLocal), bf = new Date(bd.getTime() + duree * 60000);
    if (isNaN(bd.getTime())) { setMessage('Heure d’intervention obligatoire.'); return; }
    if (bd < new Date(r.date_heure)) { setMessage('L’intervention ne peut pas commencer avant le dépôt.'); return; }
    if (r.heure_recuperation && bf > new Date(r.heure_recuperation)) { setMessage('L’intervention doit finir avant la récupération : changez d’abord l’heure de récupération.'); return; }
    await action('bloc', async () => {
      const { data: occ } = await supabase.from('occupations_salle').select('id').eq('rdv_id', r.id).limit(1).maybeSingle();
      if (occ) {
        const { error: e1 } = await supabase.from('occupations_salle').update({ debut: bd.toISOString(), fin: bf.toISOString() }).eq('id', (occ as { id: string }).id);
        if (e1) { setMessage(`Non enregistré : ${e1.message}`); return; }
      } else {
        const { data: ev } = await supabase.from('agenda_events').select('id').eq('couleur', `bloc:${r.id}`).limit(1).maybeSingle();
        const { error: e2 } = ev
          ? await supabase.from('agenda_events').update({ date_debut: bd.toISOString(), date_fin: bf.toISOString() }).eq('id', (ev as { id: string }).id)
          : await supabase.from('agenda_events').insert({ uid: r.pro_uid, titre: `Intervention — ${r.motif || libelleIntervention(r.intervention_type)}${animalNom ? ` — ${animalNom}` : ''}`,
              type: 'indisponible', date_debut: bd.toISOString(), date_fin: bf.toISOString(), pro_profile_id: r.pro_profile_id,
              praticien_profile_id: r.instructeur_profile_id, couleur: `bloc:${r.id}` });
        if (e2) { setMessage(`Non enregistré : ${e2.message}`); return; }
      }
      const { error } = await supabase.from('rdv').update({ bloc_debut: bd.toISOString(), bloc_fin: bf.toISOString() }).eq('id', r.id);
      if (error) { setMessage(`Non enregistré : ${erreurLisible(error.message)}`); return; }
      await charger();
      setMessage(`Intervention de ${hm(bd.toISOString())} à ${hm(bf.toISOString())}.`);
    });
  }
  const dureeBloc = r.bloc_debut && r.bloc_fin ? Math.round((Date.parse(r.bloc_fin) - Date.parse(r.bloc_debut)) / 60000) : 60;
  const etapesApres = !!(r.reveil_le || r.pret_le || r.sortie_le);

  const btn = (cle: string, label: string, f: () => unknown, plein = false) => (
    <button key={cle} type="button" disabled={!!enCours} onClick={() => f()}
      className="text-xs font-semibold px-3 py-1.5 rounded-xl border whitespace-nowrap disabled:opacity-50"
      style={plein ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: TEAL, color: TEAL }}>
      {enCours === cle ? '…' : label}
    </button>
  );
  const ligne = (titre: string, etat: string, couleur: string, actions: React.ReactNode, aide?: string) => (
    <div className="py-2 border-b border-gray-100 last:border-0">
      <div className="flex items-center gap-2">
        <p className="flex-1 text-sm font-bold text-[#1F2A2E]">{titre}</p>
        <span className="text-[11px] font-semibold text-right" style={{ color: couleur }}>{etat}</span>
      </div>
      {aide && <p className="text-[11px] text-gray-500 mt-0.5 whitespace-pre-line">{aide}</p>}
      <div className="flex flex-wrap gap-2 mt-1.5">{actions}</div>
    </div>
  );
  const [ePre, cPre] = etatDoc(chir?.preop ?? null);
  const [eOp, cOp] = etatDoc(chir?.operatoire ?? null);
  const [eCons] = etatDoc(chir?.consignes ?? null);

  return (
    <div className="border-2 rounded-2xl p-3" style={{ borderColor: `${TEAL}33` }}>
      <p className="text-sm font-bold" style={{ color: TEAL }}>Intervention — {r.motif || libelleIntervention(r.intervention_type)}</p>
      <p className="text-[11px] text-gray-500">
        {[r.bloc_debut ? `au bloc ${hm(r.bloc_debut)}${r.bloc_fin ? `–${hm(r.bloc_fin)}` : ''}` : '', r.heure_recuperation ? `récupération prévue ${jourHm(r.heure_recuperation, r.date_heure)}` : ''].filter(Boolean).join(' · ')}
      </p>
      {message && <p className="text-xs mt-2 rounded-lg px-2 py-1.5 bg-[#E6F2F3]" style={{ color: TEAL }}>{message}</p>}
      <div className="mt-1">
        {ligne('Consignes au propriétaire', r.consignes_preop ? 'Envoyées à la prise du RDV' : 'Aucune', r.consignes_preop ? VERT : GRIS,
          r.consignes_preop ? [btn('consignes', 'Renvoyer', () => action('consignes', async () => setMessage((await envoyerConsignesPreop(r.id)).message)))] : [],
          r.consignes_preop ?? undefined)}
        {ligne('Compte rendu préopératoire', ePre, cPre, [
            btn('preop', chir?.preop ? 'Ouvrir' : 'Rédiger', () => ouvrirDoc('preop', 'Compte rendu préopératoire')),
            ...(r.animal_id && !chir?.operatoire ? [btn('choixpreop', 'Choisir un CR pré-op existant', () => action('choixpreop', async () => {
              const l = (await chirurgiesAnimal(r.animal_id!)).filter(c => c.id !== r.chirurgie_id && c.preop);
              if (!l.length) setMessage('Aucun autre compte rendu préopératoire pour cet animal.'); else setChoixPreop(l);
            }))] : []),
          ],
          !chir?.preop || chir.preop.statut !== 'valide' ? 'À valider avant l’intervention (examen, anesthésie, consentement).' : undefined)}
        {choixPreop && (
          <div className="rounded-xl border border-gray-200 p-2 mb-2 space-y-1">
            <p className="text-[11px] font-semibold text-gray-500">Reprendre pour cette intervention :</p>
            {choixPreop.map(c => (
              <button key={c.id} type="button" disabled={!!enCours}
                onClick={() => action('rattacher', async () => {
                  const err = await rattacherChirurgie(r, c.id);
                  setChoixPreop(null);
                  if (err) setMessage(`Non enregistré : ${err}`); else { await charger(); setMessage('Compte rendu préopératoire repris.'); }
                })}
                className="block w-full text-left text-xs px-2 py-1.5 rounded-lg hover:bg-[#F1F7F8]">
                <span className="font-semibold">{c.intitule || 'Intervention'}</span>
                {c.date ? ` · ${new Date(`${c.date}T12:00:00`).toLocaleDateString('fr-FR')}` : ''}
                {` · CR pré-op ${c.preop?.statut === 'valide' ? 'validé' : 'brouillon'}`}
              </button>
            ))}
            <button type="button" onClick={() => setChoixPreop(null)} className="text-[11px] text-gray-500 px-2">Garder un CR neuf</button>
          </div>
        )}
        {ligne('Admission', r.admis_le ? `Déposé à ${hm(r.admis_le)}` : 'En attente', r.admis_le ? VERT : GRIS,
          r.admis_le
            ? [btn('admis_le', 'Annuler', () => etapesApres ? setMessage('Réveil, départ ou sortie déjà notés : annulez-les d’abord.') : maj({ admis_le: null }))]
            : [btn('admis_le', 'Animal déposé', () => maj({ admis_le: new Date().toISOString() }), true)])}
        <div className="flex flex-wrap items-center gap-2 py-2 border-b border-gray-100">
          <p className="flex-1 min-w-[140px] text-sm font-bold text-[#1F2A2E]">Créneau d’intervention</p>
          <input type="datetime-local" step={300} defaultValue={versLocal(r.bloc_debut)} key={`bd${r.bloc_debut}`} min={versLocal(r.date_heure)} id={`bloc-${r.id}`}
            className="border border-gray-200 rounded-lg px-2 py-1 text-sm" />
          <select defaultValue={dureeBloc} key={`bdu${dureeBloc}`} id={`blocd-${r.id}`} className="border border-gray-200 rounded-lg px-2 py-1 text-sm bg-white">
            {[30, 45, 60, 90, 120, 180, 240].map(m => <option key={m} value={m}>{m < 60 ? `${m} min` : m % 60 ? `${Math.floor(m / 60)}h${m % 60}` : `${m / 60} h`}</option>)}
          </select>
          {btn('bloc', 'Enregistrer', () => changerBloc((document.getElementById(`bloc-${r.id}`) as HTMLInputElement | null)?.value ?? '',
            Number((document.getElementById(`blocd-${r.id}`) as HTMLSelectElement | null)?.value ?? 60)))}
        </div>
        {ligne('Compte rendu opératoire', eOp, cOp, [btn('operatoire', chir?.operatoire ? 'Ouvrir' : 'Rédiger', () => ouvrirDoc('operatoire', 'Compte rendu opératoire'))],
          'Anesthésie, protocole, actes réalisés.')}
        {ligne('Réveil / hospitalisation', suivi.trim() ? 'Noté' : '', suivi.trim() ? VERT : GRIS, [
          btn('suivi_hospitalisation', 'Enregistrer', () => maj({ suivi_hospitalisation: suivi.trim() || null })),
          ...(r.admis_le ? [
            btn('reveille', r.reveil_le ? `Réveillé à ${hm(r.reveil_le)}` : 'Prévenir : réveillé', () => prevenirFamille('reveille')),
            btn('pret', r.pret_le ? `Prêt à ${hm(r.pret_le)}` : 'Prévenir : prêt à partir', () => prevenirFamille('pret')),
          ] : [<span key="att" className="text-[11px] text-gray-500">Après l’admission : prévenir la famille (réveillé, prêt).</span>]),
        ])}
        <textarea value={suivi} onChange={e => setSuivi(e.target.value)} rows={2} placeholder="Réveil, surveillance, prise d'eau, miction…"
          className="w-full -mt-1 mb-2 border border-gray-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] resize-none" />
        <div className="flex items-center gap-2 pb-2 border-b border-gray-100">
          <p className="flex-1 text-sm font-bold text-[#1F2A2E]">Récupération</p>
          <input type="datetime-local" step={300} defaultValue={versLocal(r.heure_recuperation)} key={`rc${r.heure_recuperation}`} min={versLocal(r.date_heure)}
            onBlur={e => { if (e.target.value && e.target.value !== versLocal(r.heure_recuperation)) changerRecuperation(e.target.value); }}
            className="border border-gray-200 rounded-lg px-2 py-1 text-sm" />
          <span className="text-[11px] text-gray-500">le client est prévenu</span>
        </div>
        {r.animal_id && ligne('Soins après l’intervention', '', GRIS, [
            ...([['traitement', 'Traitement'], ['vaccin', 'Vaccin'], ['vermifuge', 'Vermifuge'], ['antiparasitaire', 'Antiparasitaire']] as const).map(([t, l]) =>
              btn(`soin-${t}`, `+ ${l}`, () => onOuvrirPage(`/mes-patients/${encodeURIComponent(r.animal_id!)}?ajout=${t}`, `${l} — ${animalNom || 'animal'}`))),
          ], 'Inscrit au carnet de l’animal (et rappels de prise chez le propriétaire), comme lors d’une consultation.')}
        {ligne('RDV de contrôle', '', GRIS, [
            btn('controle', 'Planifier le contrôle', () => {
              const motif = `Contrôle — ${r.motif || libelleIntervention(r.intervention_type)}`;
              if (onProgrammerRdv) onProgrammerRdv({ animalId: r.animal_id ?? undefined, motif });
              else onOuvrirPage(`/mes-rdv?nouveau=1${r.animal_id ? `&animal=${encodeURIComponent(r.animal_id)}` : ''}&motif=${encodeURIComponent(motif)}`, 'RDV de contrôle');
            }),
          ], 'Dans votre agenda et celui du propriétaire (s’il a l’appli), avec rappels.')}
        {ligne('Sortie', r.sortie_le ? `Récupéré à ${hm(r.sortie_le)}` : 'Consignes postopératoires, puis animal récupéré', r.sortie_le ? VERT : GRIS, [
          btn('consignes_post', `Consignes post-op (${eCons.toLowerCase()})`, () => ouvrirDoc('consignes', 'Consignes après l’intervention')),
          r.sortie_le ? btn('sortie_le', 'Annuler', () => maj({ sortie_le: null }))
            : r.admis_le ? btn('sortie_le', 'Animal récupéré', () => maj({ sortie_le: new Date().toISOString() }), true)
            : <span key="att2" className="text-[11px] text-gray-500">L’animal n’a pas encore été déposé.</span>,
        ])}
      </div>
      <p className="text-[11px] text-gray-500 mt-1">
        Ordonnance, soins et produits : compte rendu ci-dessous. Les comptes rendus validés et les consignes partent au client avec « Terminer la consultation ».
      </p>
    </div>
  );
}
