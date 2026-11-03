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
import { libelleIntervention, envoyerConsignesPreop, messageIntervention } from '@/lib/intervention';

const TEAL = '#0C5C6C';
const VERT = '#2E7D32';
const AMBRE = '#B45309';
const GRIS = '#6B7280';

interface RdvIntervention {
  id: string; animal_id: string | null; client_uid: string | null; client_profile_id: string | null; motif: string | null;
  intervention_type: string | null; heure_recuperation: string | null; bloc_debut: string | null; bloc_fin: string | null;
  chirurgie_id: string | null; consignes_preop: string | null; admis_le: string | null; sortie_le: string | null; suivi_hospitalisation: string | null;
}
type Doc = { statut?: string } | null;

const hm = (d: string | null) => d ? new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }).replace(':', 'h') : '';
const etatDoc = (d: Doc) => d?.statut === 'valide' ? ['Validé', VERT] : d ? ['Brouillon', AMBRE] : ['À faire', GRIS];

/** null : ce RDV n'est pas une intervention (rien n'est affiché). */
export default function InterventionDossier({ rdvId, version, onOuvrirPage, animalNom }: {
  rdvId: string; version: number; animalNom?: string;
  onOuvrirPage: (url: string, titre: string) => void;
}) {
  const [r, setR] = useState<RdvIntervention | null>(null);
  const [chir, setChir] = useState<{ preop: Doc; operatoire: Doc; consignes: Doc } | null>(null);
  const [suivi, setSuivi] = useState('');
  const [message, setMessage] = useState('');
  const [enCours, setEnCours] = useState('');

  async function charger() {
    const { data } = await supabase.from('rdv')
      .select('id, animal_id, client_uid, client_profile_id, motif, intervention_type, heure_recuperation, bloc_debut, bloc_fin, chirurgie_id, consignes_preop, admis_le, sortie_le, suivi_hospitalisation')
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
    if (error) setMessage(`Non enregistré : ${error.message}`); else await charger();
  });
  const ouvrirDoc = (doc: 'preop' | 'operatoire' | 'consignes', titre: string) => r.animal_id && r.chirurgie_id
    ? onOuvrirPage(`/mes-patients/${encodeURIComponent(r.animal_id)}?chirDoc=${encodeURIComponent(`${r.chirurgie_id}:${doc}`)}`, titre)
    : setMessage('Intervention non rattachée à une fiche animal.');
  // Notification (appli), sinon e-mail, sinon « appelez-le au … » (vétérinaire ou ASV).
  const prevenirFamille = (m: 'reveille' | 'pret' | 'recuperation') => action(m, async () => setMessage(await messageIntervention(r.id, m)));
  const heureRecupLocale = r.heure_recuperation ? new Date(r.heure_recuperation).toTimeString().slice(0, 5) : '';
  async function changerRecuperation(hhmm: string) {
    if (!hhmm || !r) return;
    const base = new Date(r.heure_recuperation ?? Date.now());
    const [h, m] = hhmm.split(':').map(Number);
    base.setHours(h, m, 0, 0);
    await action('recuperation', async () => {
      const { error } = await supabase.from('rdv').update({ heure_recuperation: base.toISOString() }).eq('id', r.id);
      if (error) { setMessage(`Non enregistré : ${error.message}`); return; }
      await charger();
      setMessage(`Récupération à ${hhmm.replace(':', 'h')}. ${await messageIntervention(r.id, 'recuperation')}`);
    });
  }

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
        {[r.bloc_debut ? `au bloc ${hm(r.bloc_debut)}${r.bloc_fin ? `–${hm(r.bloc_fin)}` : ''}` : '', r.heure_recuperation ? `récupération prévue vers ${hm(r.heure_recuperation)}` : ''].filter(Boolean).join(' · ')}
      </p>
      {message && <p className="text-xs mt-2 rounded-lg px-2 py-1.5 bg-[#E6F2F3]" style={{ color: TEAL }}>{message}</p>}
      <div className="mt-1">
        {ligne('Consignes au propriétaire', r.consignes_preop ? 'Envoyées à la prise du RDV' : 'Aucune', r.consignes_preop ? VERT : GRIS,
          r.consignes_preop ? [btn('consignes', 'Renvoyer', () => action('consignes', async () => setMessage((await envoyerConsignesPreop(r.id)).message)))] : [],
          r.consignes_preop ?? undefined)}
        {ligne('Compte rendu préopératoire', ePre, cPre, [btn('preop', chir?.preop ? 'Ouvrir' : 'Rédiger', () => ouvrirDoc('preop', 'Compte rendu préopératoire'))],
          !chir?.preop || chir.preop.statut !== 'valide' ? 'À valider avant l’intervention (examen, anesthésie, consentement).' : undefined)}
        {ligne('Admission', r.admis_le ? `Déposé à ${hm(r.admis_le)}` : 'En attente', r.admis_le ? VERT : GRIS,
          r.admis_le ? [btn('admis_le', 'Annuler', () => maj({ admis_le: null }))] : [btn('admis_le', 'Animal déposé', () => maj({ admis_le: new Date().toISOString() }), true)])}
        {ligne('Compte rendu opératoire', eOp, cOp, [btn('operatoire', chir?.operatoire ? 'Ouvrir' : 'Rédiger', () => ouvrirDoc('operatoire', 'Compte rendu opératoire'))],
          'Anesthésie, protocole, actes réalisés.')}
        {ligne('Réveil / hospitalisation', suivi.trim() ? 'Noté' : '', suivi.trim() ? VERT : GRIS, [
          btn('suivi_hospitalisation', 'Enregistrer', () => maj({ suivi_hospitalisation: suivi.trim() || null })),
          btn('reveille', 'Prévenir : réveillé', () => prevenirFamille('reveille')),
          btn('pret', 'Prévenir : prêt à partir', () => prevenirFamille('pret')),
        ])}
        <textarea value={suivi} onChange={e => setSuivi(e.target.value)} rows={2} placeholder="Réveil, surveillance, prise d'eau, miction…"
          className="w-full -mt-1 mb-2 border border-gray-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:border-[#0C5C6C] resize-none" />
        <div className="flex items-center gap-2 pb-2 border-b border-gray-100">
          <p className="flex-1 text-sm font-bold text-[#1F2A2E]">Heure de récupération</p>
          <input type="time" step={300} defaultValue={heureRecupLocale} key={heureRecupLocale}
            onBlur={e => { if (e.target.value && e.target.value !== heureRecupLocale) changerRecuperation(e.target.value); }}
            className="border border-gray-200 rounded-lg px-2 py-1 text-sm" />
          <span className="text-[11px] text-gray-500">le client est prévenu</span>
        </div>
        {ligne('Sortie', r.sortie_le ? `Récupéré à ${hm(r.sortie_le)}` : 'Consignes postopératoires, puis animal récupéré', r.sortie_le ? VERT : GRIS, [
          btn('consignes_post', `Consignes post-op (${eCons.toLowerCase()})`, () => ouvrirDoc('consignes', 'Consignes après l’intervention')),
          r.sortie_le ? btn('sortie_le', 'Annuler', () => maj({ sortie_le: null })) : btn('sortie_le', 'Animal récupéré', () => maj({ sortie_le: new Date().toISOString() }), true),
        ])}
      </div>
      <p className="text-[11px] text-gray-500 mt-1">
        Ordonnance, soins et produits : compte rendu ci-dessous. Les comptes rendus validés et les consignes partent au client avec « Terminer la consultation ».
      </p>
    </div>
  );
}
