'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { seancesDuRdv, pdfSeance, preparerFactureOsteo, type SeanceRdv } from '@/lib/seance-osteo';
import { seanceToilettageDuRdv, pdfCompteRenduToilettage, type SeanceToilettagePdf } from '@/lib/toilettage-pdf';
import { animauxDetailRdv } from '@/lib/rdv-animaux';
import { seancesEducationDuRdv, pdfSeanceEducation, notifierFamilleSeances, type SeanceEducation } from '@/lib/seance-education';
import { useAuth } from '@/lib/auth-context';
import { maSignaturePro } from '@/lib/signature-pro';
import { envoyerPiecesParEmail, pdfDepuisUrl } from '@/lib/transmission-document';
import { ACCEPT_DOCUMENT_PRO, TYPE_CONTRAT_PRO, fichierEnPdf, chargerCompteRenduPro, comptesRendusProDuRdv, type DocumentProRdv } from '@/lib/document-pro';
import {
  chargerDocsConsultation, pdfCompteRendu, pdfFacture, pdfOrdonnance, type DocsConsultation,
} from '@/lib/fin-consultation';
import { envoyerContratParEmail } from '@/lib/contrat-email';

const MODES = ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'];

// Fin de consultation : compte(s) rendu(s), ordonnance(s) et facture du RDV
// envoyés au propriétaire en un seul e-mail ; facture marquée acquittée.
// Ostéo / kiné (metier « sante ») : compte(s) rendu(s) de séance + facture,
// et « Préparer la facture » depuis les tarifs ostéo si elle n'existe pas.
// Miroir appli : _terminerConsultation (compte_rendu_page.dart), finSeanceOsteo (fin_seance_osteo.dart).
// Toiletteur (metier « toilettage ») : compte rendu de toilettage (fiche
// technique) + facture ; « Préparer la facture » via [onPreparerFacture].
// Éducateur (metier « education ») : compte rendu de séance / bilan avec
// exercices et programme (PDF signé) + facture.
export default function FinConsultationModal({ rdvId, proProfileId, clientNom, onClose, onDone, metier = 'veterinaire', onPreparerFacture, onTerminer }: {
  rdvId: string; proProfileId: string | null; clientNom?: string; onClose: () => void; onDone: () => void;
  /** RDV marqué terminé (avec ou sans envoi des documents). */
  onTerminer?: () => Promise<void> | void;
  metier?: 'veterinaire' | 'sante' | 'toilettage' | 'education';
  onPreparerFacture?: () => void;
}) {
  const { user, userData } = useAuth();
  const router = useRouter();
  const osteo = metier === 'sante';
  const toilettage = metier === 'toilettage';
  const education = metier === 'education';
  const [seancesEdu, setSeancesEdu] = useState<SeanceEducation[]>([]);
  const [ficheToil, setFicheToil] = useState<SeanceToilettagePdf | null>(null);
  const [docs, setDocs] = useState<(DocsConsultation & { seances?: SeanceRdv[] }) | null>(null);
  const [prepa, setPrepa] = useState(false);
  const [coches, setCoches] = useState<Record<string, boolean>>({});
  const [acquittee, setAcquittee] = useState(false);
  const [mode, setMode] = useState('Carte bancaire');
  const [envoi, setEnvoi] = useState(false);
  // Comptes rendus faits par le pro lui-même (PDF / photo) : envoyés à la place du compte rendu généré.
  const [crsPro, setCrsPro] = useState<DocumentProRdv[]>([]);
  const [depot, setDepot] = useState(false);
  // Éducateur : facture du forfait (séance décomptée d'un forfait payé
  // d'avance) et contrats de l'animal (chargé, ou PetsMatch signé).
  const [factureForfait, setFactureForfait] = useState<DocsConsultation['facture']>(null);
  const [acquitteeForfait, setAcquitteeForfait] = useState(false);
  const [contrats, setContrats] = useState<{ id: string; titre: string; url: string | null; token: string | null; email: string | null }[]>([]);

  useEffect(() => {
    comptesRendusProDuRdv(rdvId).then(l => {
      setCrsPro(l);
      if (l.length) setCoches(c => ({ ...c, ...Object.fromEntries(l.map(d => [`pro:${d.id}`, true])) }));
    });
  }, [rdvId]);

  /** Mon propre compte rendu : rangé avec le RDV, coché à la place des comptes rendus générés. */
  async function joindreMonCr(f: File | undefined) {
    if (!f || !user) return;
    setDepot(true);
    try {
      const { data: r } = await supabase.from('rdv').select('id, animal_id, pro_profile_id, client_uid, client_profile_id').eq('id', rdvId).maybeSingle();
      if (!r) throw new Error('Rendez-vous introuvable');
      const nomA = r.animal_id ? nom(String(r.animal_id)) : '';
      const titre = `Compte rendu${nomA ? ` — ${nomA}` : ''}`;
      const { id, url } = await chargerCompteRenduPro(await fichierEnPdf(f), {
        rdv: { ...r, id: String(r.id), animal_id: r.animal_id != null ? String(r.animal_id) : null }, uid: user.uid,
        proProfileId: (r.pro_profile_id as string | null) ?? proProfileId, titre });
      setCrsPro(l => [...l, { id, titre, url, created_at: new Date().toISOString() }]);
      setCoches(c => Object.fromEntries([...Object.entries(c).map(([k, v]) => [k, k === 'toil' || k.startsWith('cr:') || k.startsWith('seance:') || k.startsWith('edu:') ? false : v]), [`pro:${id}`, true]]));
    } catch (e) {
      alert(`Impossible : ${(e as Error).message}`);
    } finally { setDepot(false); }
  }

  useEffect(() => {
    if (education) {
      (async () => {
        const [seances, { data: r }, { data: fac }] = await Promise.all([
          seancesEducationDuRdv(rdvId),
          supabase.from('rdv').select('animal_id, animal_nom_manuel, animaux_detail, forfait_souscrit_id').eq('id', rdvId).maybeSingle(),
          supabase.from('factures').select('*').eq('source_rdv_id', rdvId).neq('statut', 'annulee').order('created_at', { ascending: false }).limit(1),
        ]);
        const aid = r?.animal_id != null ? String(r.animal_id) : null;
        const { data: an } = aid ? await supabase.from('animaux').select('id, nom').eq('id', aid).maybeSingle() : { data: null };
        const facture = ((fac ?? [])[0] as DocsConsultation['facture']) ?? null;
        setSeancesEdu(seances);
        // Plusieurs animaux : chaque compte rendu porte le nom de son animal.
        const nomsDetail = Object.fromEntries(animauxDetailRdv(r ?? {}).map(a => [a.id, a.nom]));
        setDocs({ rdvId, animalIdPrincipal: aid,
          noms: { ...nomsDetail, ...(aid ? { [aid]: (an?.nom as string | undefined) ?? nomsDetail[aid] ?? (r?.animal_nom_manuel as string | undefined) ?? 'Animal' } : {}) },
          crs: [], ordos: [], facture, seances: [] });
        setCoches(c => ({ ...c, ...Object.fromEntries([...seances.map(s => [`edu:${s.id}`, true]), ...(facture ? [[`fac:${facture.id}`, true]] : [])]) }));
        // Séance décomptée d'un forfait : sa facture (payé d'avance).
        const fsid = (r as { forfait_souscrit_id?: string | null } | null)?.forfait_souscrit_id;
        if (fsid) {
          const { data: fs } = await supabase.from('forfaits_souscrits').select('facture_id').eq('id', fsid).maybeSingle();
          const fid = (fs as { facture_id?: string | null } | null)?.facture_id;
          let ff: unknown = null;
          if (fid) ff = (await supabase.from('factures').select('*').eq('id', fid).neq('statut', 'annulee').maybeSingle()).data;
          // Forfait attribué avant le lien facture ↔ forfait : dernière facture
          // « Forfait … » de l'animal.
          else if (aid && user) {
            const { data: fl } = await supabase.from('factures').select('*').eq('uid_eleveur', user.uid).eq('source_animal_id', aid)
              .neq('statut', 'annulee').order('created_at', { ascending: false }).limit(10);
            ff = ((fl ?? []) as { lignes?: unknown }[]).find(x => /"(description|designation)":"Forfait /.test(JSON.stringify(x.lignes ?? []))) ?? null;
          }
          if (ff) { setFactureForfait(ff as DocsConsultation['facture']); setCoches(c => ({ ...c, [`facf:${(ff as { id: string }).id}`]: true })); }
        }
        // Contrats de l'animal : PDF signé (PetsMatch) ou document chargé.
        if (aid && user) {
          const { data: ct } = await supabase.from('documents_animaux').select('id, type, titre, url, pdf_signe_url, statut, token, metadata')
            .eq('uid_eleveur', user.uid).eq('animal_id', aid).in('type', ['contrat_education', TYPE_CONTRAT_PRO])
            .not('statut', 'in', '(annule,refuse)').order('created_at', { ascending: false });
          const liste = ((ct ?? []) as { id: string; type: string; titre: string | null; url: string | null; pdf_signe_url: string | null;
            statut: string; token: string | null; metadata: Record<string, unknown> | null }[])
            .map(d => ({ id: d.id, titre: d.titre ?? 'Contrat', token: d.token,
              email: ((d.metadata?.acquereur_email ?? d.metadata?.client_email) as string | undefined) ?? null,
              // PDF : signé (PetsMatch) ou document chargé ; sinon pas encore signé.
              url: d.statut === 'signe' ? (d.pdf_signe_url ?? d.url) : (d.type === TYPE_CONTRAT_PRO ? d.url : null) }));
          setContrats(liste);
          // Contrat pas encore signé : lien de signature proposé (coché).
          setCoches(c => ({ ...c, ...Object.fromEntries(liste.filter(x => !x.url && x.token).map(x => [`sig:${x.id}`, true])) }));
        }
      })();
      return;
    }
    if (toilettage) {
      (async () => {
        const [fiche, { data: r }, { data: fac }] = await Promise.all([
          seanceToilettageDuRdv(rdvId),
          supabase.from('rdv').select('animal_id, animal_nom_manuel').eq('id', rdvId).maybeSingle(),
          supabase.from('factures').select('*').eq('source_rdv_id', rdvId).neq('statut', 'annulee').order('created_at', { ascending: false }).limit(1),
        ]);
        const aid = r?.animal_id != null ? String(r.animal_id) : null;
        const { data: an } = aid ? await supabase.from('animaux').select('id, nom').eq('id', aid).maybeSingle() : { data: null };
        const facture = ((fac ?? [])[0] as DocsConsultation['facture']) ?? null;
        setFicheToil(fiche);
        setDocs({ rdvId, animalIdPrincipal: aid,
          noms: aid ? { [aid]: (an?.nom as string | undefined) ?? (r?.animal_nom_manuel as string | undefined) ?? 'Animal' } : {},
          crs: [], ordos: [], facture, seances: [] });
        setCoches(Object.fromEntries([...(fiche ? [['toil', true]] : []), ...(facture ? [[`fac:${facture.id}`, true]] : [])]));
      })();
      return;
    }
    if (osteo) {
      (async () => {
        const [seances, { data: r }, { data: fac }] = await Promise.all([
          seancesDuRdv(rdvId),
          supabase.from('rdv').select('animal_id').eq('id', rdvId).maybeSingle(),
          supabase.from('factures').select('*').eq('source_rdv_id', rdvId).neq('statut', 'annulee').order('created_at', { ascending: false }).limit(1),
        ]);
        const ids = [...new Set(seances.map(s => s.animal_id).filter(Boolean) as string[])];
        const { data: an } = ids.length ? await supabase.from('animaux').select('id, nom').in('id', ids) : { data: [] };
        const facture = ((fac ?? [])[0] as DocsConsultation['facture']) ?? null;
        setDocs({ rdvId, animalIdPrincipal: r?.animal_id != null ? String(r.animal_id) : null,
          noms: Object.fromEntries(((an ?? []) as { id: string; nom: string }[]).map(a => [String(a.id), a.nom])),
          crs: [], ordos: [], facture, seances });
        setCoches(Object.fromEntries([...seances.map(s => [`seance:${s.id}`, true]), ...(facture ? [[`fac:${facture.id}`, true]] : [])]));
      })();
      return;
    }
    chargerDocsConsultation(rdvId).then(d => {
      setDocs(d);
      setCoches(Object.fromEntries([...d.crs.map(c => [`cr:${c.id}`, true]), ...d.ordos.map(o => [`ordo:${o.id}`, !!o.doc_url]),
        ...(d.interventions ?? []).map(x => [`chir:${x.chirurgieId}:${x.doc}`, true]),
        ...(d.facture ? [[`fac:${d.facture.id}`, true]] : [])]));
    });
  }, [rdvId, osteo, toilettage, education]);

  /** Ostéo : facture préparée depuis les tarifs (séance / bilan / déplacement), client du RDV. */
  async function preparerFacture() {
    if (!docs?.seances?.length || !proProfileId) return;
    setPrepa(true);
    try {
      if (await preparerFactureOsteo(rdvId, proProfileId)) router.push('/elevage/facturation');
    } catch (e) {
      alert(`Impossible : ${(e as Error).message}`);
    } finally { setPrepa(false); }
  }

  const nom = (animalId: string) => docs?.noms[animalId] ?? 'Animal';
  const dejaPayee = docs?.facture?.statut === 'payee';
  const nbCoches = Object.values(coches).filter(Boolean).length;

  async function valider(envoyer: boolean) {
    if (!docs || !user) return;
    setEnvoi(true);
    try {
      let facture = docs.facture;
      if (facture && acquittee && !dejaPayee) {
        const maj = { statut: 'payee', mode_paiement: mode, date_paiement: new Date().toISOString() };
        const { error } = await supabase.from('factures').update(maj).eq('id', facture.id);
        if (error) { alert(`Facture non mise à jour : ${error.message}`); return; }
        facture = { ...facture, ...maj };
      }
      let ffac = factureForfait;
      if (ffac && acquitteeForfait && ffac.statut !== 'payee') {
        const maj = { statut: 'payee', mode_paiement: mode, date_paiement: new Date().toISOString() };
        const { error } = await supabase.from('factures').update(maj).eq('id', ffac.id);
        if (error) { alert(`Facture du forfait non mise à jour : ${error.message}`); return; }
        ffac = { ...ffac, ...maj };
      }
      if (envoyer && nbCoches > 0) {
        const signature = await maSignaturePro(user.uid).catch(() => null);
        const praticien = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();
        const pieces: { type: 'ordonnance' | 'compte_rendu' | 'facture' | 'consignes'; blob: Blob; nomFichier: string }[] = [];
        if (ficheToil && coches.toil) {
          const nomA = docs.animalIdPrincipal ? nom(docs.animalIdPrincipal) : 'animal';
          pieces.push({ type: 'compte_rendu', nomFichier: `Compte-rendu-toilettage-${nomA}.pdf`,
            blob: await pdfCompteRenduToilettage(ficheToil, { proProfileId, signature, nomAnimal: nomA }) });
        }
        for (const s of docs.seances ?? []) if (coches[`seance:${s.id}`]) {
          const { blob, animalNom } = await pdfSeance(s.id, signature);
          pieces.push({ type: 'compte_rendu', nomFichier: `Compte-rendu-seance-${animalNom}.pdf`, blob });
        }
        for (const c of docs.crs) if (coches[`cr:${c.id}`]) {
          pieces.push({ type: 'compte_rendu', nomFichier: `Compte-rendu-${nom(c.animal_id)}.pdf`,
            blob: await pdfCompteRendu(c, { proProfileId, praticien, signature, emailCompte: user.email, proprietaire: clientNom }) });
        }
        for (const s of seancesEdu) if (coches[`edu:${s.id}`]) {
          const nomA = s.animal_id ? nom(s.animal_id) : (docs.animalIdPrincipal ? nom(docs.animalIdPrincipal) : 'animal');
          pieces.push({ type: 'compte_rendu', nomFichier: `${s.type === 'bilan' ? 'Bilan' : 'Compte-rendu-seance'}-${nomA}.pdf`,
            blob: await pdfSeanceEducation(s, { proProfileId, praticien, signature, emailCompte: user.email, proprietaire: clientNom }) });
        }
        for (const d of crsPro) if (coches[`pro:${d.id}`]) {
          pieces.push({ type: 'compte_rendu', nomFichier: `${(d.titre ?? 'Compte rendu').replace(/[\\/:*?"<>|]/g, '-')}.pdf`, blob: await pdfDepuisUrl(d.url) });
        }
        // Interventions du jour : CR pré / opératoire et consignes au propriétaire.
        for (const x of docs.interventions ?? []) if (coches[`chir:${x.chirurgieId}:${x.doc}`]) {
          const n = x.doc === 'consignes' ? 'Consignes' : x.doc === 'preop' ? 'Compte-rendu-preoperatoire' : 'Compte-rendu-operatoire';
          pieces.push({ type: x.doc === 'consignes' ? 'consignes' : 'compte_rendu', nomFichier: `${n}-${nom(x.animal_id)}.pdf`, blob: await pdfDepuisUrl(x.url) });
        }
        for (const o of docs.ordos) if (coches[`ordo:${o.id}`]) {
          pieces.push({ type: 'ordonnance', nomFichier: `Ordonnance-${nom(o.animal_id)}.pdf`, blob: await pdfOrdonnance(o) });
        }
        if (ffac && coches[`facf:${ffac.id}`]) {
          pieces.push({ type: 'facture', nomFichier: `Facture-forfait-${ffac.numero_affichage ?? ''}${ffac.statut === 'payee' ? '-acquittee' : ''}.pdf`,
            blob: await pdfFacture(ffac) });
        }
        for (const c of contrats) if (c.url && coches[`ctr:${c.id}`]) {
          pieces.push({ type: 'compte_rendu', nomFichier: `${c.titre.replace(/[\\/:*?"<>|]/g, '-')}.pdf`, blob: await pdfDepuisUrl(c.url) });
        }
        if (facture && coches[`fac:${facture.id}`]) {
          pieces.push({ type: 'facture', nomFichier: `Facture-${facture.numero_affichage ?? ''}${facture.statut === 'payee' ? '-acquittee' : ''}.pdf`,
            blob: await pdfFacture(facture) });
        }
        const noms = [...new Set([...docs.crs.map(c => nom(c.animal_id)), ...(docs.seances ?? []).filter(s => s.animal_id).map(s => nom(s.animal_id!)),
          ...((toilettage || education) && docs.animalIdPrincipal ? [nom(docs.animalIdPrincipal)] : [])])];
        const ok = pieces.length === 0 ? true : await envoyerPiecesParEmail(pieces, {
          emailParDefaut: (facture?.email_client as string | null) ?? null, destinataireNom: clientNom,
          expediteur: userData?.nameElevage || praticien, animalNom: noms.join(', '),
          animalId: docs.animalIdPrincipal ?? docs.crs[0]?.animal_id ?? docs.seances?.find(s => s.animal_id)?.animal_id ?? null,
        });
        if (!ok) return;
        // Contrats non signés : lien de signature (notification si le client a
        // un compte, e-mail sinon — clients sans compte compris).
        const aSigner = contrats.filter(c => !c.url && c.token && coches[`sig:${c.id}`]);
        if (aSigner.length) {
          const { data: rv } = await supabase.from('rdv').select('client_uid, client_profile_id, client_email_manuel').eq('id', rdvId).maybeSingle();
          const r2 = rv as { client_uid?: string | null; client_profile_id?: string | null; client_email_manuel?: string | null } | null;
          const { data: cc } = await supabase.rpc('pm_contact_client_rdv', { p_rdv_id: rdvId });
          let email = (cc as { email?: string } | null)?.email || r2?.client_email_manuel || (facture?.email_client as string | null) || '';
          for (const c of aSigner) {
            if (r2?.client_uid) {
              await supabase.from('notifications').insert({
                uid: r2.client_uid, type: 'contrat_invite', title: 'Contrat de prestation à signer',
                body: `${userData?.nameElevage || 'Votre professionnel'} vous envoie le contrat — vérifiez et signez`,
                ...(r2.client_profile_id ? { profile_id: r2.client_profile_id } : {}),
                data: { token: c.token, url: `/signer-contrat/${c.token}` }, read: false,
              });
            }
            const dest = c.email || email || window.prompt('E-mail du client pour le lien de signature', '') || '';
            if (dest.trim()) {
              email = dest;
              await envoyerContratParEmail({ email: dest, clientNom: clientNom ?? 'Client', proProfileId, token: c.token!, titre: c.titre });
            } else if (!r2?.client_uid) {
              alert('Lien de signature non envoyé : aucune adresse e-mail.');
            }
          }
        }
        // Trace de l'envoi : affichée dans le dossier de la séance.
        await supabase.from('rdv').update({ documents_envoyes_le: new Date().toISOString() }).eq('id', rdvId);
        // Éducateur : la famille est prévenue dans l'appli à l'envoi.
        if (education) await notifierFamilleSeances(seancesEdu.filter(s => coches[`edu:${s.id}`]), userData?.nameElevage || praticien).catch(() => {});
      }
      await onTerminer?.();
      onDone();
    } catch (e) {
      alert(`Impossible : ${(e as Error).message}`);
    } finally { setEnvoi(false); }
  }

  const ligne = (cle: string, titre: string, sous?: string, desactive = false) => (
    <label key={cle} className={`flex items-center gap-3 px-3 py-2 rounded-xl border ${desactive ? 'opacity-50' : 'cursor-pointer'} border-gray-200`}>
      <input type="checkbox" disabled={desactive} checked={!!coches[cle]} onChange={e => setCoches(c => ({ ...c, [cle]: e.target.checked }))}
        className="w-4 h-4" style={{ accentColor: '#0C5C6C' }} />
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-semibold text-[#1E2025]">{titre}</span>
        {sous && <span className="block text-xs text-gray-500">{sous}</span>}
      </span>
    </label>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-bold text-lg text-[#1E2025]">{osteo || toilettage || education ? 'Fin de séance' : 'Fin de consultation'}</h2>
        {!docs ? <p className="text-sm text-gray-500">Chargement…</p> : (<>
          <div className="space-y-2">
            <p className="text-xs font-semibold text-gray-500">Envoyer au propriétaire par e-mail</p>
            {docs.crs.length === 0 && docs.ordos.length === 0 && !(docs.interventions?.length) && !docs.facture && !(docs.seances?.length) && !ficheToil && crsPro.length === 0 && seancesEdu.length === 0 && (
              <p className="text-sm text-gray-500">{osteo
                ? <>Aucun document pour ce rendez-vous pour l&apos;instant : finalisez d&apos;abord la séance.</>
                : <>Aucun document pour ce rendez-vous pour l&apos;instant (compte rendu validé, ordonnance ou facture).</>}</p>
            )}
            {toilettage && ficheToil && ligne('toil', `Compte rendu de toilettage — ${docs.animalIdPrincipal ? nom(docs.animalIdPrincipal) : 'Animal'}`)}
            {seancesEdu.map(s => ligne(`edu:${s.id}`, `${s.type === 'bilan' ? 'Bilan' : 'Compte rendu de séance'} — ${s.animal_id ? nom(s.animal_id) : 'Animal'}`,
              'Avec les exercices et le programme de travail, signé'))}
            {(docs.seances ?? []).map(s => ligne(`seance:${s.id}`, `Compte rendu de séance — ${s.animal_id ? nom(s.animal_id) : 'Animal'}`))}
            {docs.crs.map(c => ligne(`cr:${c.id}`, `Compte rendu — ${nom(c.animal_id)}`))}
            {crsPro.map(d => ligne(`pro:${d.id}`, d.titre ?? 'Compte rendu', 'Mon document'))}
            <label className={`block text-center text-sm font-semibold py-2 rounded-xl border border-dashed border-[#0C5C6C] text-[#0C5C6C] ${depot ? 'opacity-50' : 'cursor-pointer'}`}>
              {depot ? 'Envoi du fichier…' : '+ Joindre mon compte rendu (PDF ou photo)'}
              <input type="file" accept={ACCEPT_DOCUMENT_PRO} className="hidden" disabled={depot}
                onChange={e => { joindreMonCr(e.target.files?.[0]); e.target.value = ''; }} />
            </label>
            {docs.ordos.map(o => ligne(`ordo:${o.id}`, `Ordonnance — ${nom(o.animal_id)}`, o.doc_url ? undefined : 'PDF indisponible', !o.doc_url))}
            {(docs.interventions ?? []).map(x => ligne(`chir:${x.chirurgieId}:${x.doc}`,
              `${x.doc === 'consignes' ? 'Consignes après l’intervention' : x.doc === 'preop' ? 'Compte rendu préopératoire' : 'Compte rendu opératoire'} — ${nom(x.animal_id)}`,
              x.intitule || undefined))}
            {docs.facture && ligne(`fac:${docs.facture.id}`, `Facture ${docs.facture.numero_affichage ?? ''}`,
              `${Number(docs.facture.total_ttc ?? 0).toFixed(2)} € TTC${dejaPayee ? ' — acquittée' : ''}`)}
            {factureForfait && ligne(`facf:${factureForfait.id}`, `Facture du forfait ${factureForfait.numero_affichage ?? ''}`,
              `${Number(factureForfait.total_ttc ?? 0).toFixed(2)} € TTC — ${factureForfait.statut === 'payee' || acquitteeForfait ? 'acquittée' : 'à régler'}`)}
            {factureForfait && factureForfait.statut !== 'payee' && (
              <label className="flex items-center gap-3 cursor-pointer rounded-xl bg-[#0C5C6C]/5 px-3 py-2">
                <input type="checkbox" checked={acquitteeForfait} onChange={e => setAcquitteeForfait(e.target.checked)} className="w-4 h-4" style={{ accentColor: '#0C5C6C' }} />
                <span className="text-sm font-semibold text-[#1E2025]">Facture du forfait acquittée (réglée)</span>
              </label>
            )}
            {acquitteeForfait && !acquittee && (
              <div className="flex flex-wrap gap-1.5">
                {MODES.map(m => (
                  <button key={m} type="button" onClick={() => setMode(m)}
                    className="px-3 py-1.5 rounded-full text-xs font-semibold border"
                    style={mode === m ? { background: '#0C5C6C', color: 'white', borderColor: '#0C5C6C' } : { color: '#0C5C6C', borderColor: '#0C5C6C' }}>
                    {m}
                  </button>
                ))}
              </div>
            )}
            {contrats.map(c => c.url
              ? ligne(`ctr:${c.id}`, c.titre, 'Contrat signé (PDF)')
              : c.token ? ligne(`sig:${c.id}`, `${c.titre} — à signer`, 'Envoyer le lien de signature au client (e-mail, et notification s’il a un compte)')
              : ligne(`ctr:${c.id}`, c.titre, 'PDF disponible une fois signé', true))}
          </div>
          {(toilettage || education) && !docs.facture && onPreparerFacture && (
            <button type="button" onClick={onPreparerFacture}
              className="w-full py-2.5 rounded-xl text-sm font-semibold border border-[#0C5C6C] text-[#0C5C6C]">
              Préparer la facture
            </button>
          )}
          {osteo && !docs.facture && (docs.seances?.length ?? 0) > 0 && (
            <button type="button" disabled={prepa} onClick={preparerFacture}
              className="w-full py-2.5 rounded-xl text-sm font-semibold border border-[#0C5C6C] text-[#0C5C6C] disabled:opacity-40">
              {prepa ? '…' : 'Préparer la facture (tarifs de séance)'}
            </button>
          )}
          {docs.facture && !dejaPayee && (
            <div className="space-y-2 rounded-xl bg-[#0C5C6C]/5 px-3 py-2.5">
              <label className="flex items-center gap-3 cursor-pointer">
                <input type="checkbox" checked={acquittee} onChange={e => setAcquittee(e.target.checked)} className="w-4 h-4" style={{ accentColor: '#0C5C6C' }} />
                <span className="text-sm font-semibold text-[#1E2025]">Facture acquittée (réglée aujourd&apos;hui)</span>
              </label>
              {acquittee && (
                <div className="flex flex-wrap gap-1.5">
                  {MODES.map(m => (
                    <button key={m} type="button" onClick={() => setMode(m)}
                      className="px-3 py-1.5 rounded-full text-xs font-semibold border"
                      style={mode === m ? { background: '#0C5C6C', color: 'white', borderColor: '#0C5C6C' } : { color: '#0C5C6C', borderColor: '#0C5C6C' }}>
                      {m}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm border border-gray-200 text-gray-600">Fermer</button>
            {(onTerminer || acquittee || acquitteeForfait) && (
              <button type="button" disabled={envoi} onClick={() => valider(false)}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-[#0C5C6C] text-[#0C5C6C] disabled:opacity-40">
                {onTerminer ? 'Terminer sans envoyer' : 'Acquitter sans envoyer'}
              </button>
            )}
            <button type="button" disabled={envoi || nbCoches === 0} onClick={() => valider(true)}
              className="flex-[2] py-2.5 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] disabled:opacity-40">
              {envoi ? 'Préparation et envoi…' : `${onTerminer ? 'Terminer et envoyer' : 'Envoyer'} (${nbCoches})`}
            </button>
          </div>
        </>)}
      </div>
    </div>
  );
}
