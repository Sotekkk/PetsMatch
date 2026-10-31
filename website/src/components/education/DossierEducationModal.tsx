'use client';

// Éducateur — dossier d'une séance (RDV), ouvert depuis Gérer mes RDV ou le
// tableau de bord : compte rendu, exercices, programme de travail, forfait,
// devis, facture, contrat, puis fin de séance (PDF signé + facture par e-mail).
// Chaque action ouvre le formulaire existant (fiche de l'élève, devis,
// facturation) et revient ensuite sur ce dossier (/mes-rdv?rdv=…&dossier=1).
// Miroir appli : EducationSuiviPage(rdvId, dossier: true).

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import FinConsultationModal from '@/components/rdv/FinConsultationModal';
import DocumentProModal from '@/components/pro/DocumentProModal';
import { animauxDetailRdv } from '@/lib/rdv-animaux';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const VERT = '#2E7D5E';
const GRIS = '#6B7280';

interface RdvRow {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null; lieu: string | null;
  animal_id: string | null; animal_nom_manuel?: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel?: string | null; client_email_manuel?: string | null; client_telephone_manuel?: string | null;
  pro_profile_id?: string | null; prix_calcule?: number | null; animaux_detail?: unknown;
}

/** Lien de retour vers ce dossier (après une action dans une autre page). */
export const retourDossierEducation = (rdvId: string) => `/mes-rdv?rdv=${encodeURIComponent(rdvId)}&dossier=1`;

export default function DossierEducationModal({ rdvId, nomClient, onClose, onChanged, onOuvrirPage, version }: {
  rdvId: string; nomClient: string; onClose: () => void; onChanged?: () => void;
  /** Ouvre une page (fiche animal, devis, facturation) dans un panneau au lieu
   *  de quitter Gérer mes RDV ; sans lui, navigation classique. */
  onOuvrirPage?: (url: string, titre: string) => void;
  /** Change à la fermeture du panneau → rechargement du dossier. */
  version?: number;
}) {
  const router = useRouter();
  const { user } = useAuth();
  const pidActif = useActiveProfile();
  const [r, setR] = useState<RdvRow | null>(null);
  // Plusieurs animaux (comme véto / ostéo) : un compte rendu, des exercices et
  // un programme par animal — animal affiché (le premier par défaut).
  const [animalChoisi, setAnimalChoisi] = useState<string | null>(null);
  const [animalNom, setAnimalNom] = useState('');
  const [cr, setCr] = useState<{ id: string; statut: string | null; type: string | null } | null>(null);
  const [nbExercices, setNbExercices] = useState(0);
  const [nbObjectifs, setNbObjectifs] = useState(0);
  const [forfait, setForfait] = useState<{ nom_snapshot: string; nb_seances_utilisees: number; nb_seances_total: number } | null>(null);
  const [devis, setDevis] = useState<{ id: string; statut: string | null; total_ttc: number | null } | null>(null);
  const [facture, setFacture] = useState<{ id: string; statut: string | null; total_ttc: number | null; numero_affichage: string | null } | null>(null);
  const [coord, setCoord] = useState<Record<string, string>>({});
  const [finSeance, setFinSeance] = useState(false);
  const [docPro, setDocPro] = useState<'compte_rendu' | 'contrat' | null>(null);

  const charger = useCallback(async () => {
    const { data: rdv } = await supabase.from('rdv').select('*').eq('id', rdvId).maybeSingle();
    const x = rdv as RdvRow | null;
    if (!x) return;
    setR(x);
    const pid = x.pro_profile_id || pidActif;
    const detail = animauxDetailRdv(x);
    const aid = (detail.length > 0 && animalChoisi && detail.some(a => a.id === animalChoisi)) ? animalChoisi : x.animal_id;
    const [an, pr, dv, fa, cc] = await Promise.all([
      aid ? supabase.from('animaux').select('nom').eq('id', aid).maybeSingle() : Promise.resolve({ data: null }),
      (detail.length > 0 && aid
        ? supabase.from('education_progression').select('id, statut, type').eq('rdv_id', rdvId).eq('animal_id', aid)
        : supabase.from('education_progression').select('id, statut, type').eq('rdv_id', rdvId)).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('devis').select('id, statut, total_ttc').eq('rdv_id', rdvId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('factures').select('id, statut, total_ttc, numero_affichage').eq('source_rdv_id', rdvId).neq('statut', 'annulee')
        .or('type_facture.is.null,type_facture.not.in.(acompte,avoir)').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      supabase.rpc('pm_contact_client_rdv', { p_rdv_id: rdvId }),
    ]);
    setAnimalNom((an.data as { nom?: string } | null)?.nom ?? detail.find(a => a.id === aid)?.nom ?? x.animal_nom_manuel ?? '');
    setCr((pr.data as typeof cr) ?? null);
    setDevis(dv.error ? null : (dv.data as typeof devis) ?? null);
    setFacture((fa.data as typeof facture) ?? null);
    const c = (cc.data ?? {}) as Record<string, string>;
    setCoord({ prenom: c.prenom ?? '', nom: c.nom ?? x.client_nom_manuel ?? '', email: c.email || x.client_email_manuel || '',
      tel: c.telephone || x.client_telephone_manuel || '', rue: c.rue ?? '', cp: c.code_postal ?? '', ville: c.ville ?? '' });
    if (aid) {
      let ob = supabase.from('education_objectifs').select('id', { count: 'exact', head: true }).eq('animal_id', aid).neq('statut', 'acquis');
      let ex = supabase.from('exercices_attribues').select('id', { count: 'exact', head: true }).eq('animal_id', aid).in('statut', ['a_faire', 'en_cours']);
      let fo = supabase.from('forfaits_souscrits').select('nom_snapshot, nb_seances_utilisees, nb_seances_total').eq('animal_id', aid).eq('statut', 'actif');
      if (pid) { ob = ob.eq('pro_profile_id', pid); ex = ex.eq('pro_profile_id', pid); fo = fo.eq('pro_profile_id', pid); }
      const [o, e, f] = await Promise.all([ob, ex, fo.order('souscrit_le', { ascending: false }).limit(1).maybeSingle()]);
      setNbObjectifs(o.count ?? 0); setNbExercices(e.count ?? 0);
      setForfait((f.data as typeof forfait) ?? null);
    }
  }, [rdvId, pidActif, animalChoisi, version]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  if (!r) return null;
  const debut = new Date(r.date_heure);
  const pid = r.pro_profile_id || pidActif;
  const retour = retourDossierEducation(r.id);
  const detail = animauxDetailRdv(r);
  const aidSel = (detail.length > 0 && animalChoisi && detail.some(a => a.id === animalChoisi)) ? animalChoisi : r.animal_id;
  const ouvrir = (url: string, titre: string) => onOuvrirPage ? onOuvrirPage(url, titre) : router.push(url);
  const fiche = (suite: string, titre: string) => aidSel
    ? ouvrir(`/mes-patients/${encodeURIComponent(aidSel)}?${suite}&retourRdv=${encodeURIComponent(r.id)}`, `${titre} — ${animalNom || 'animal'}`)
    : alert('Ce rendez-vous n’est rattaché à aucune fiche animal : créez d’abord la fiche du client (Gérer mes RDV → nouveau client).');

  function creerDevis() {
    if (!r) return;
    const q = new URLSearchParams({ prefill: '1', rdv: r.id, retour });
    if (r.animal_id) q.set('animal', r.animal_id);
    if (r.client_uid) q.set('clientUid', r.client_uid);
    if (r.client_profile_id) q.set('clientProfileId', r.client_profile_id);
    if (coord.nom) q.set('nom', coord.nom);
    if (coord.prenom) q.set('prenom', coord.prenom);
    if (coord.email) q.set('email', coord.email);
    if (coord.tel) q.set('tel', coord.tel);
    // Plusieurs animaux : une ligne par animal (son cours, son prix).
    if (detail.length > 0) q.set('lignes', JSON.stringify(detail.map(a => ({ d: [a.motif?.trim(), a.nom].filter(Boolean).join(' — '), q: 1, p: a.prix ?? 0 }))));
    else if (r.motif?.trim()) { q.set('ligneDesc', [r.motif.trim(), animalNom].filter(Boolean).join(' — ')); q.set('ligneQte', '1');
      if (r.prix_calcule != null) q.set('lignePrix', String(r.prix_calcule)); }
    ouvrir(`/education/devis?${q.toString()}`, 'Devis de la séance');
  }

  function facturer() {
    if (!r) return;
    try {
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
        nomClient: coord.nom || nomClient, prenomClient: coord.prenom || undefined, emailClient: coord.email || undefined, telClient: coord.tel || undefined,
        rueClient: coord.rue || undefined, cpClient: coord.cp || undefined, villeClient: coord.ville || undefined,
        sourceRdvId: r.id, sourceAnimalId: r.animal_id ?? undefined, clientUid: r.client_uid ?? undefined, clientProfileId: r.client_profile_id ?? undefined,
        retour,
        lignes: detail.length > 0
          ? detail.map(a => ({ description: [a.motif?.trim() || 'Séance d’éducation', a.nom].filter(Boolean).join(' — ') + ` — ${debut.toLocaleDateString('fr-FR')}`,
              quantite: 1, prixUnitaire: 0, prixTTC: Number(a.prix ?? 0), tva: 20 }))
          : [{ description: [r.motif?.trim() || 'Séance d’éducation', animalNom].filter(Boolean).join(' — ') + ` — ${debut.toLocaleDateString('fr-FR')}`,
          quantite: 1, prixUnitaire: 0, prixTTC: Number(r.prix_calcule ?? 0), tva: 20 }],
      }));
    } catch { /* facture vierge */ }
    ouvrir('/elevage/facturation', 'Facture de la séance');
  }

  const eur = (n: number | null | undefined) => `${Number(n ?? 0).toFixed(2)} €`;
  const btn = (label: string, onClick: () => void) => (
    <button key={label} type="button" onClick={onClick}
      className="px-3 py-1.5 rounded-lg text-xs font-semibold border" style={{ borderColor: TEAL, color: TEAL }}>{label}</button>
  );
  const ligne = (titre: string, etat: string, couleur: string, actions: React.ReactNode[]) => (
    <div className="flex items-center gap-3 py-3 border-b border-gray-100 last:border-0">
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-[#1E2025]">{titre}</p>
        <p className="text-xs font-semibold" style={{ color: couleur }}>{etat}</p>
      </div>
      <div className="flex flex-wrap gap-1.5 justify-end">{actions}</div>
    </div>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-lg p-5 max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-bold text-lg text-[#1E2025]">Dossier de la séance</h2>
        <p className="text-sm text-gray-500">
          {[animalNom, nomClient].filter(Boolean).join(' · ')} — {debut.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })} à {debut.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
        </p>
        {r.motif && <p className="text-xs text-gray-500 mt-0.5">{r.motif}{r.lieu ? ` · ${r.lieu}` : ''}</p>}
        {detail.length > 0 && (
          <div className="mt-3">
            <p className="text-xs text-gray-500 mb-1.5">Plusieurs animaux : un compte rendu par animal.</p>
            <div className="flex flex-wrap gap-1.5">
              {detail.map(a => {
                const actif = a.id === aidSel;
                return (
                  <button key={a.id} type="button" onClick={() => setAnimalChoisi(a.id)}
                    className="px-3 py-1.5 rounded-full text-xs font-semibold border"
                    style={{ borderColor: TEAL, background: actif ? TEAL : '#fff', color: actif ? '#fff' : TEAL }}>
                    {a.nom}{a.motif ? ` · ${a.motif}` : ''}
                  </button>
                );
              })}
            </div>
          </div>
        )}

        <div className="mt-3">
          {ligne('Compte rendu',
            !cr ? 'À rédiger' : cr.statut === 'brouillon' ? 'Brouillon' : cr.type === 'bilan' ? 'Bilan rédigé' : 'Rédigé',
            !cr ? GRIS : cr.statut === 'brouillon' ? AMBRE : VERT,
            [btn(cr ? 'Modifier / voir' : 'Rédiger', () => fiche(`rdv=${encodeURIComponent(r.id)}`, 'Compte rendu')),
              btn('Mon compte rendu', () => setDocPro('compte_rendu'))])}
          {ligne('Exercices', nbExercices ? `${nbExercices} en cours` : 'Aucun en cours', nbExercices ? VERT : GRIS,
            [btn('Attribuer', () => fiche('tab=Programme', 'Exercices'))])}
          {ligne('Programme de travail', nbObjectifs ? `${nbObjectifs} objectif${nbObjectifs > 1 ? 's' : ''} en cours` : 'Aucun objectif', nbObjectifs ? VERT : GRIS,
            [btn(nbObjectifs ? 'Voir / ajouter' : 'Définir', () => fiche('tab=Programme', 'Programme de travail'))])}
          {ligne('Forfait', forfait ? `${forfait.nom_snapshot} · ${forfait.nb_seances_utilisees}/${forfait.nb_seances_total} séances` : 'Aucun forfait en cours',
            forfait ? VERT : GRIS, [btn(forfait ? 'Gérer' : 'Appliquer un forfait', () => fiche('tab=Programme&forfait=1', 'Forfait'))])}
          {ligne('Devis', !devis ? 'Aucun' : `${devis.statut === 'accepte' ? 'Accepté' : devis.statut === 'refuse' ? 'Refusé' : devis.statut === 'envoye' ? 'Envoyé' : 'Brouillon'} · ${eur(devis.total_ttc)}`,
            !devis ? GRIS : devis.statut === 'accepte' ? VERT : AMBRE,
            [!devis ? btn('Créer', creerDevis) : btn('Voir', () => ouvrir('/education/devis', 'Devis'))])}
          {ligne('Facture', !facture ? 'À émettre' : `${facture.statut === 'payee' ? 'Payée' : 'Émise'} · ${eur(facture.total_ttc)}`,
            !facture ? GRIS : facture.statut === 'payee' ? VERT : AMBRE,
            [!facture ? btn('Facturer', facturer) : btn('Voir', () => ouvrir('/elevage/facturation', 'Factures'))])}
          {ligne('Contrat', 'Votre contrat (photo ou PDF), signé en ligne par le client', GRIS,
            [btn('Mon contrat', () => setDocPro('contrat'))])}
        </div>

        <button type="button" onClick={() => setFinSeance(true)}
          className="w-full mt-4 py-3 rounded-xl text-sm font-bold text-white" style={{ background: TEAL }}>
          Terminer et envoyer au client
        </button>
        <p className="text-[11px] text-gray-400 mt-1.5 text-center">Compte rendu avec exercices et programme (PDF signé) et facture, en un seul e-mail.</p>
        <button type="button" onClick={onClose} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>

      {finSeance && (
        <FinConsultationModal metier="education" rdvId={r.id} proProfileId={pid || null} clientNom={nomClient}
          onPreparerFacture={() => { setFinSeance(false); facturer(); }}
          onClose={() => setFinSeance(false)} onDone={() => { setFinSeance(false); charger(); onChanged?.(); }} />
      )}
      {docPro && (
        <DocumentProModal mode={docPro} catPro="education" rdv={{ ...r, animal_id: aidSel, pro_profile_id: pid || null }} clientNom={nomClient}
          animalNom={animalNom || undefined} proNom={user?.displayName ?? ''} onClose={() => setDocPro(null)}
          onDone={() => { setDocPro(null); charger(); onChanged?.(); }} />
      )}
    </div>
  );
}
