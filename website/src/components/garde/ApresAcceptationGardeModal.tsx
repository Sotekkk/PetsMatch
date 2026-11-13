'use client';
// Pet-sitting — après l'acceptation d'une demande (un passage ou une série) :
// contrat de garde pré-rempli à faire signer, facture au choix (maintenant /
// acompte / après la prestation), enregistrement de la clé si le client la
// remet. Miroir appli : lib/pages/pro/garde_acceptation.dart.
// Scopé au profil pet-sitter actif (pro_profile_id) — jamais l'uid seul.
import { coordonneesClientRdv, prefillClient } from '@/lib/coordonnees-client-rdv';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { usePlanGarde } from '@/lib/use-plan';
import { gardeTarif } from '@/lib/garde-facturation';
import { accesLogementLabel } from '@/lib/garde-labels';
import CompteRenduExpressModal from '@/components/garde/CompteRenduExpressModal';
import { useAuth } from '@/lib/auth-context';
import { rattacherForfaitGarde, acomptesGarde, deductionsAcompteGarde, uniteForfaitGarde, type ForfaitGardeClient } from '@/lib/forfait-garde';

const TEAL = '#0C5C6C';

export interface RdvAccepte {
  id: string; pro_uid: string; client_uid: string; client_profile_id?: string | null;
  animal_id?: string | null; date_heure: string; motif?: string | null; lieu?: string | null;
  notes_client?: string | null; acces_logement?: string | null; forfait_id?: string | null;
  animaux_ids?: unknown[] | null; clientName?: string; animalNom?: string;
}
// commune : prestation pour tous les animaux du foyer (comptée une fois).
type Ligne = { description: string; quantite: number; prixUnitaire: number; tva: number; commune?: boolean; prixTTC?: number };

const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;
function periode(rdvs: RdvAccepte[]) {
  const d = rdvs.map(r => new Date(r.date_heure)).sort((a, b) => a.getTime() - b.getTime());
  if (!d.length) return '';
  const f = (x: Date) => x.toLocaleDateString('fr-FR');
  return d.length === 1 ? `le ${f(d[0])}` : `du ${f(d[0])} au ${f(d[d.length - 1])}`;
}

interface EtatDoc { texte: string; couleur: string }
const GRIS = '#6B7280', VERT = '#5B8648', ORANGE = '#C0661B';

/** dossier : « Dossier de la garde » depuis le RDV (état de chaque document,
 *  compte rendu de visite, facture) — miroir appli garde_dossier.dart. */
export default function ApresAcceptationGardeModal({ rdvs, proProfileId, onClose, dossier = false, onChanged, onOuvrirPage }: {
  rdvs: RdvAccepte[]; proProfileId: string | null; onClose: () => void;
  dossier?: boolean; onChanged?: () => void;
  /** Ouvre une page dans le panneau de « Mes RDV » (comme le vétérinaire). */
  onOuvrirPage?: (url: string, titre: string) => void;
}) {
  const { user, userData } = useAuth();
  const [etats, setEtats] = useState<{
    contrat?: EtatDoc; devis?: EtatDoc; devisId?: string; acompte?: EtatDoc; acompteFait?: boolean;
    facture?: EtatDoc; factureFaite?: boolean; rapports?: EtatDoc; cles?: EtatDoc; nbCles?: number;
  }>({});
  const [compteRendu, setCompteRendu] = useState(false);
  // Forfait acheté par le client (facturé à l'achat, passages décomptés).
  const [forfait, setForfait] = useState<ForfaitGardeClient | null>(null);
  const [aFacturer, setAFacturer] = useState<string[]>(rdvs.map(r => r.id));
  const router = useRouter();
  // Depuis « Mes RDV » : facture, devis, contrat s'ouvrent dans le panneau de
  // la page (on reste sur le RDV, comme le vétérinaire) ; sinon navigation.
  const ouvrirPage = (url: string, titre: string) => {
    onClose();
    if (onOuvrirPage) onOuvrirPage(url, titre); else router.push(url);
  };
  const { plan } = usePlanGarde();
  const premium = plan === 'premium';
  const first = rdvs[0];
  const [lignes, setLignes] = useState<Ligne[]>([]);
  const [total, setTotal] = useState(0);
  const [busy, setBusy] = useState('');
  const [msg, setMsg] = useState('');

  // Chiffrage : forfait choisi, sinon tarif × passages (+ animal supplémentaire).
  useEffect(() => {
    let alive = true;
    (async () => {
      const n = rdvs.length;
      const noms = first.animalNom ? ` — ${first.animalNom}` : '';
      // Plusieurs animaux : visites et forfait communs au foyer (section « Prestations communes »).
      const commune = Array.isArray(first.animaux_ids) && first.animaux_ids.length > 1;
      // Forfait acheté : ses passages ne sont plus facturés (facture à l'achat).
      const fg = await rattacherForfaitGarde(rdvs.map(r => r.id));
      if (!alive) return;
      setForfait(fg);
      const couverts = new Set(fg?.couverts ?? []);
      const horsForfait = rdvs.filter(r => !couverts.has(r.id));
      setAFacturer(horsForfait.map(r => r.id));
      const info: Ligne[] = fg && couverts.size
        ? [{ description: `${fg.nom} — ${couverts.size} ${uniteForfaitGarde(fg.type, couverts.size > 1)} inclus dans le forfait (facturé à l'achat)`, quantite: 1, prixUnitaire: 0, tva: 20, commune: true }]
        : [];
      if (fg) {
        const m = horsForfait.length;
        if (!m) { setLignes(info); setTotal(0); return; }
        const prixF = await gardeTarif(first.pro_uid, proProfileId, { ...first, animal_id: first.animal_id ?? null });
        if (!alive) return;
        setLignes([{ description: `${first.motif ?? 'Prestation'}${noms} (${periode(horsForfait)})`, quantite: m, prixUnitaire: prixF, tva: 20, ...(commune ? { commune } : {}) }, ...info]);
        setTotal(prixF * m);
        return;
      }
      if (first.forfait_id) {
        const { data: f } = await supabase.from('forfaits_garde').select('nom, prix').eq('id', first.forfait_id).maybeSingle();
        const prix = Number(f?.prix) || 0;
        if (f && prix > 0) {
          if (!alive) return;
          setLignes([{ description: `Forfait ${f.nom}${noms} (${periode(rdvs)})`, quantite: 1, prixUnitaire: prix, tva: 20, ...(commune ? { commune } : {}) }]);
          setTotal(prix);
          return;
        }
      }
      const prix = await gardeTarif(first.pro_uid, proProfileId, { ...first, animal_id: first.animal_id ?? null });
      const l: Ligne[] = [{ description: `${first.motif ?? 'Prestation'}${noms} (${periode(rdvs)})`, quantite: n, prixUnitaire: prix, tva: 20, ...(commune ? { commune } : {}) }];
      let t = prix * n;
      const animaux = Array.isArray(first.animaux_ids) && first.animaux_ids.length > 0 ? first.animaux_ids.length : 1;
      if (animaux > 1 && proProfileId) {
        const { data: p } = await supabase.from('user_profiles_complet').select('tarifs_garde').eq('id', proProfileId).maybeSingle();
        const supp = Number((p?.tarifs_garde as Record<string, number> | null)?.animal_supplementaire) || 0;
        if (supp > 0) {
          l.push({ description: 'Animal supplémentaire', quantite: (animaux - 1) * n, prixUnitaire: supp, tva: 20, commune: true });
          t += supp * (animaux - 1) * n;
        }
      }
      if (!alive) return;
      setLignes(l); setTotal(t);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Dossier : où en est chaque document de la garde.
  const idsCle = rdvs.map(r => r.id).join(',');
  useEffect(() => {
    if (!dossier) return;
    let alive = true;
    (async () => {
      const ids = rdvs.map(r => r.id);
      const [ct, dv, fa, ac, pu, cl] = await Promise.all([
        supabase.from('documents_animaux').select('statut, metadata').eq('uid_eleveur', first.pro_uid).eq('type', 'contrat_garde')
          .eq('metadata->>client_uid', first.client_uid)
          .or(proProfileId ? `pro_profile_id.eq.${proProfileId},pro_profile_id.is.null` : 'pro_profile_id.is.null')
          .order('created_at', { ascending: false }).limit(1).maybeSingle(),
        supabase.from('devis').select('id, statut').in('rdv_id', ids).order('created_at', { ascending: false }).limit(1).maybeSingle(),
        supabase.from('factures').select('statut, type_facture, numero_affichage, total_ttc').in('source_rdv_id', ids).neq('statut', 'annulee')
          .order('created_at', { ascending: false }),
        proProfileId && first.client_profile_id
          ? supabase.from('factures').select('statut, numero_affichage, total_ttc').eq('profile_id', proProfileId)
            .eq('client_profile_id', first.client_profile_id).eq('type_facture', 'acompte').neq('statut', 'annulee')
            .order('created_at', { ascending: false }).limit(1).maybeSingle()
          : Promise.resolve({ data: null }),
        supabase.from('pension_updates').select('id').in('rdv_id', ids),
        supabase.from('cles_clients').select('id, date_restitution').eq('pro_uid', first.pro_uid).eq('owner_uid', first.client_uid),
      ]);
      if (!alive) return;
      const c = ct.data as { statut?: string; metadata?: Record<string, unknown> } | null;
      const contratE: EtatDoc = c?.statut === 'signe' ? { texte: 'Signé par les deux parties', couleur: VERT }
        : c?.statut === 'partiellement_signe' ? (c.metadata?.signature_eleveur
          ? { texte: 'Signé par vous — en attente du client', couleur: ORANGE }
          : { texte: 'Signé par le client — à signer par vous', couleur: ORANGE })
        : c ? { texte: 'Préparé — à signer et envoyer', couleur: ORANGE } : { texte: 'À envoyer', couleur: GRIS };
      const d = dv.data as { id: string; statut?: string } | null;
      const devisE: EtatDoc = d?.statut === 'accepte' ? { texte: 'Accepté par le client', couleur: VERT }
        : d?.statut === 'envoye' ? { texte: 'Envoyé — en attente de réponse', couleur: ORANGE }
        : d?.statut === 'refuse' ? { texte: 'Refusé par le client', couleur: '#DC2626' }
        : d ? { texte: 'Brouillon — à envoyer', couleur: ORANGE } : { texte: 'Facultatif — aucun devis', couleur: GRIS };
      type F = { statut?: string; type_facture?: string | null; numero_affichage?: string | null; total_ttc?: number | null };
      const liste = (fa.data ?? []) as F[];
      const fac = liste.find(f => f.type_facture !== 'acompte' && f.type_facture !== 'avoir') ?? null;
      const lies = await acomptesGarde(ids);
      const acp = (lies[lies.length - 1] as F | undefined) ?? (ac.data as F | null) ?? liste.find(f => f.type_facture === 'acompte') ?? null;
      const etatF = (f: F | null, vide: string): EtatDoc => !f ? { texte: vide, couleur: GRIS }
        : f.statut === 'payee' ? { texte: `${f.numero_affichage ?? 'Facture'} — payée`, couleur: VERT }
        : { texte: `${f.numero_affichage ?? 'Facture'} — ${eur(Number(f.total_ttc) || 0)}, en attente de paiement`, couleur: ORANGE };
      const nbR = (pu.data ?? []).length;
      const cles = (cl.data ?? []) as { date_restitution?: string | null }[];
      const enCours = cles.filter(k => !k.date_restitution).length;
      const termine = rdvs.every(r => (r as RdvAccepte & { statut?: string }).statut === 'termine');
      setEtats({
        contrat: contratE, devis: devisE, devisId: d?.id,
        acompte: etatF(acp, 'Facultatif — aucun acompte'), acompteFait: !!acp,
        facture: etatF(fac, termine ? 'À faire' : 'Après la prestation, ou d\u2019avance'), factureFaite: !!fac,
        rapports: nbR > 0 ? { texte: `${nbR} message${nbR > 1 ? 's' : ''} envoyé${nbR > 1 ? 's' : ''} au client`, couleur: VERT }
          : { texte: 'Nouvelles et photos au client — aucun envoi', couleur: GRIS },
        cles: cles.length === 0 ? { texte: 'Remise des clés prévue — à enregistrer', couleur: ORANGE }
          : enCours > 0 ? { texte: `${enCours} clé${enCours > 1 ? 's' : ''} en votre possession`, couleur: VERT }
          : { texte: 'Clés rendues', couleur: VERT },
        nbCles: cles.length,
      });
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dossier, idsCle]);

  async function contrat() {
    if (!proProfileId) return;
    setBusy('contrat'); setMsg('');
    try {
      const acces = accesLogementLabel(first.acces_logement);
      // Identité et coordonnées du client (profil, compte, saisie manuelle).
      const co = await coordonneesClientRdv(first.id, first.client_profile_id).catch(() => null);
      const nomComplet = [co?.prenom, co?.nom].filter(Boolean).join(' ');
      const adresseClient = [co?.rue, [co?.cp, co?.ville].filter(Boolean).join(' ')].filter(Boolean).join(', ');
      const details: Record<string, unknown> = {
        rdv_id: first.id,
        ...(nomComplet ? { client_nom: nomComplet } : {}),
        ...(co?.email ? { client_email: co.email } : {}),
        ...(co?.tel ? { client_tel: co.tel } : {}),
        prestation: [first.motif ?? 'Prestation', rdvs.length > 1 ? `${rdvs.length} passages ${periode(rdvs)}` : ''].filter(Boolean).join(' — '),
        date_prestation: first.date_heure.slice(0, 10),
        ...(total > 0 ? { tarif: total.toFixed(2) } : {}),
        notes: [
          first.lieu ? `Lieu de prise en charge : ${first.lieu}` : '',
          acces ? `Accès au logement : ${acces}` : '',
          first.notes_client?.trim() ? `Consignes : ${first.notes_client.trim()}` : '',
        ].filter(Boolean).join('\n'),
        ...(adresseClient ? { client_adresse: adresseClient } : first.lieu ? { client_adresse: first.lieu } : {}),
        ...(first.lieu ? { lieu_prestation: first.lieu } : {}),
      };
      const noms = first.animalNom ? first.animalNom.split(' + ') : [];
      const { data: ex } = await supabase.from('documents_animaux').select('id, token, statut, metadata')
        .eq('uid_eleveur', first.pro_uid).eq('pro_profile_id', proProfileId)
        .eq('type', 'contrat_garde').eq('metadata->>client_uid', first.client_uid)
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      let token = (ex?.token as string | undefined) ?? null;
      if (!token || String(ex?.statut ?? '').startsWith('signe')) {
        const { data, error } = await supabase.from('documents_animaux').insert({
          uid_eleveur: first.pro_uid, pro_profile_id: proProfileId, type: 'contrat_garde',
          titre: `Contrat de prestation — ${first.clientName ?? 'Client'}`, statut: 'en_attente',
          ...(first.animal_id ? { animal_id: first.animal_id } : {}),
          metadata: {
            client_nom: first.clientName ?? 'Client', client_uid: first.client_uid,
            ...(first.client_profile_id ? { client_profile_id: first.client_profile_id } : {}),
            ...(noms.length ? { animal_nom: first.animalNom, animal_noms: noms } : {}),
            ...details,
          },
        }).select('token').single();
        if (error) throw error;
        token = (data?.token as string | null) ?? null;
      } else {
        const meta = { ...((ex!.metadata as Record<string, unknown>) ?? {}), ...details };
        const l = new Set([...(((meta.animal_noms as string[] | undefined) ?? [])), ...noms]);
        if (l.size) meta.animal_noms = [...l];
        await supabase.from('documents_animaux').update({ metadata: meta }).eq('id', ex!.id);
      }
      if (token) {
        if (onOuvrirPage) { onClose(); onOuvrirPage(`/signer-contrat/${token}`, 'Contrat de garde'); }
        else router.push(`/signer-contrat/${token}`);
      }
    } catch (e) {
      setMsg(`Contrat : ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(''); }
  }

  async function facturer(acompte: boolean) {
    if (!acompte && forfait && aFacturer.length === 0) { setMsg('Tous les passages sont couverts par le forfait du client : rien à facturer.'); return; }
    // Facture finale : acomptes de la garde déduits.
    const deductions = acompte ? [] : await deductionsAcompteGarde(rdvs.map(r => r.id));
    const l: Ligne[] = acompte
      ? [{ description: `Acompte — ${first.motif ?? 'Prestation'} (${periode(rdvs)})`, quantite: 1, prixUnitaire: Math.round(total * 30) / 100, tva: 20 }]
      : [...lignes, ...deductions];
    // Nom, prénom, e-mail, téléphone, adresse du client (profil, compte, saisie manuelle).
    const coord = await coordonneesClientRdv(first.id, first.client_profile_id).catch(() => null);
    const prefill = {
      ...(coord ? prefillClient(coord, first.clientName ?? '') : { nomClient: first.clientName ?? '' }),
      lignes: l,
      ...(acompte ? { typeFacture: 'acompte', acompteRdvId: first.id }
        : { sourceRdvId: aFacturer[0] ?? first.id, sourceRdvIds: aFacturer, ...(deductions.length ? { typeFacture: 'solde' } : {}) }),
      sourceAnimalId: first.animal_id ?? undefined,
      clientUid: first.client_uid,
      clientProfileId: first.client_profile_id ?? undefined,
    };
    try { sessionStorage.setItem('pm_facture_prefill', JSON.stringify(prefill)); } catch { /* ignore */ }
    ouvrirPage('/elevage/facturation', 'Facture');
  }

  async function facturerForfait() {
    if (!forfait) return;
    const coord = await coordonneesClientRdv(first.id, first.client_profile_id).catch(() => null);
    const prefill = {
      ...(coord ? prefillClient(coord, first.clientName ?? '') : { nomClient: first.clientName ?? '' }),
      lignes: [{ description: `Forfait ${forfait.nom}${first.animalNom ? ` — ${first.animalNom}` : ''} (${forfait.total} ${uniteForfaitGarde(forfait.type, forfait.total > 1)}, décomptés à chaque passage)`,
        quantite: 1, prixUnitaire: 0, prixTTC: forfait.prix, tva: 20, commune: true }],
      forfaitSouscritId: forfait.souscription.id,
      sourceAnimalId: first.animal_id ?? undefined,
      clientUid: first.client_uid,
      clientProfileId: first.client_profile_id ?? undefined,
    };
    try { sessionStorage.setItem('pm_facture_prefill', JSON.stringify(prefill)); } catch { /* ignore */ }
    ouvrirPage('/elevage/facturation', 'Facture');
  }

  // Devis avant la garde (le client l'accepte ; acompte possible ensuite).
  function devis() {
    const qs = new URLSearchParams({
      prefill: '1', rdv: first.id, clientUid: first.client_uid ?? '',
      ...(first.client_profile_id ? { clientProfileId: first.client_profile_id } : {}),
      ...(first.animal_id ? { animal: String(first.animal_id) } : {}),
      nom: first.clientName ?? '',
      lignes: JSON.stringify(lignes.map(x => ({ d: x.description, q: x.quantite, p: x.prixUnitaire }))),
    });
    ouvrirPage(`/garde/devis?${qs.toString()}`, 'Devis');
  }

  async function cle() {
    const desc = window.prompt('Description de la clé (aucun code d\'accès ici)', 'Clé du logement');
    if (desc === null || !proProfileId) return;
    setBusy('cle');
    const { error } = await supabase.from('cles_clients').insert({
      pro_uid: first.pro_uid, pro_profile_id: proProfileId,
      ...(first.animal_id ? { animal_id: first.animal_id } : {}),
      owner_uid: first.client_uid,
      ...(first.client_profile_id ? { owner_profile_id: first.client_profile_id } : {}),
      description: desc.trim() || 'Clé du logement',
      date_recuperation: new Date().toISOString().slice(0, 10),
    });
    setBusy('');
    setMsg(error ? `Clé : ${error.message}` : 'Clé enregistrée dans « Gestion des clés ».');
  }

  const tuile = (icone: string, titre: string, sous: string, onClick: () => void, cle?: string, etat?: EtatDoc, action?: string) => (
    <button type="button" onClick={onClick} disabled={!!busy}
      className="w-full flex items-center gap-3 text-left py-2.5 px-1 rounded-xl hover:bg-gray-50 disabled:opacity-50">
      <span className="w-9 h-9 rounded-full flex items-center justify-center text-base flex-shrink-0" style={{ background: `${TEAL}18` }}>{icone}</span>
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-bold text-[#1E2025]">{busy === cle && cle ? '…' : titre}</span>
        {etat ? <span className="block text-xs font-semibold" style={{ color: etat.couleur }}>{etat.texte}</span>
          : <span className="block text-xs text-gray-500">{sous}</span>}
      </span>
      {action && <span className="text-xs font-bold" style={{ color: TEAL }}>{action}</span>}
      <span className="text-gray-400">›</span>
    </button>
  );
  const verrou = (
    <p className="text-xs text-amber-700 bg-amber-50 rounded-lg px-3 py-2">
      Contrat et facturation inclus dans la formule Premium. <Link href="/garde/abonnement" className="underline font-semibold">Voir les plans</Link>
    </p>
  );

  if (dossier) {
    const nomPro = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pet-sitter';
    const aller = (href: string) => ouvrirPage(href, 'Dossier de la garde');
    const nbCles = etats.nbCles ?? 0;
    return (
      <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
        <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-1 max-h-[90vh] overflow-y-auto"
          onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
          <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>Dossier de la garde</h2>
          <p className="text-xs text-gray-600">
            {[first.animalNom, first.clientName, rdvs.length > 1 ? `${rdvs.length} passages` : '', total > 0 ? eur(total) : ''].filter(Boolean).join(' · ')}
          </p>
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Avant la garde</p>
          {premium ? (
            <>
              {tuile('✍️', 'Contrat de garde', '', contrat, 'contrat', etats.contrat, etats.contrat?.texte === 'À envoyer' ? 'Envoyer' : 'Ouvrir')}
              {tuile('📝', 'Devis', '', () => (etats.devisId ? aller('/garde/devis') : devis()), undefined, etats.devis, etats.devisId ? 'Voir' : 'Créer')}
              {forfait && tuile('🎁', `Forfait ${forfait.nom}`, '',
                () => (forfait.factureId ? aller('/elevage/facturation') : facturerForfait()), undefined,
                { texte: `${forfait.utilises}/${forfait.total} ${uniteForfaitGarde(forfait.type)} utilisés · ${forfait.factureId ? 'facturé' : 'à facturer'}`, couleur: forfait.factureId ? VERT : ORANGE },
                forfait.factureId ? 'Voir' : 'Facturer')}
              {tuile('💶', 'Acompte', '', () => (etats.acompteFait ? aller('/elevage/facturation') : facturer(true)), undefined, etats.acompte, etats.acompteFait ? 'Voir' : 'Demander')}
            </>
          ) : verrou}
          {(first.acces_logement === 'remise_cles' || nbCles > 0) &&
            tuile('🔑', 'Clés du logement', '', () => (nbCles > 0 ? aller('/garde/cles') : cle()), 'cle', etats.cles, nbCles > 0 ? 'Voir' : 'Enregistrer')}
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Pendant et après la garde</p>
          {first.animal_id && tuile('📷', 'Compte rendu de visite', '', () => setCompteRendu(true), undefined, etats.rapports, 'Envoyer')}
          {premium && tuile('🧾', 'Facture', '', () => (etats.factureFaite ? aller('/elevage/facturation') : facturer(false)), undefined,
            forfait && aFacturer.length === 0 && !etats.factureFaite ? { texte: 'Tous les passages sont dans le forfait', couleur: VERT } : etats.facture,
            etats.factureFaite ? 'Voir' : 'Facturer')}
          {msg && <p className="text-xs text-gray-600 pt-1">{msg}</p>}
          <button type="button" onClick={onClose} className="w-full mt-2 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
        </div>
        {compteRendu && user && first.animal_id && (
          <CompteRenduExpressModal
            rdv={{ id: first.id, animal_id: first.animal_id ?? null, client_uid: first.client_uid, client_profile_id: first.client_profile_id, motif: first.motif, animaux_ids: first.animaux_ids }}
            animalNom={first.animalNom ?? ''} proUid={user.uid} proNom={nomPro}
            onClose={() => setCompteRendu(false)}
            onEnvoye={() => { setCompteRendu(false); onChanged?.(); onClose(); }} />
        )}
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-2 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>Demande acceptée ✓</h2>
        <p className="text-xs text-gray-600">
          {[first.animalNom, first.clientName, rdvs.length > 1 ? `${rdvs.length} passages` : '', total > 0 ? eur(total) : ''].filter(Boolean).join(' · ')}
        </p>
        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Contrat</p>
        {premium ? tuile('✍️', 'Envoyer le contrat de garde', 'Pré-rempli : prestation, dates, lieu, accès, tarif', contrat, 'contrat') : verrou}
        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Facturation</p>
        {premium ? (
          <>
            {tuile('📝', 'Envoyer un devis', total > 0 ? `Avant la garde — ${eur(total)}, à accepter par le client` : 'Avant la garde, à accepter par le client', devis)}
            {forfait?.aFacturer && tuile('🎁', `Facturer le forfait ${forfait.nom}`, `${eur(forfait.prix)} — ${Math.max(0, forfait.total - forfait.utilises)} ${uniteForfaitGarde(forfait.type)} restants ensuite`, facturerForfait)}
            {tuile('🧾', 'Facturer maintenant', total > 0 ? `Paiement d'avance — ${eur(total)}` : "Paiement d'avance (tarif à compléter)", () => facturer(false))}
            {tuile('💶', 'Demander un acompte', total > 0 ? `30 % — ${eur(total * 0.3)} (modifiable)` : 'Montant à saisir', () => facturer(true))}
          </>
        ) : verrou}
        {tuile('🕒', 'Facturer après la prestation', 'Depuis le registre ou le RDV une fois terminé', onClose)}
        {first.acces_logement === 'remise_cles' && (
          <>
            <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Clés</p>
            {tuile('🔑', 'Enregistrer la clé du client', 'Le client vous remet ses clés', cle, 'cle')}
          </>
        )}
        {msg && <p className="text-xs text-gray-600 pt-1">{msg}</p>}
        <button type="button" onClick={onClose} className="w-full mt-2 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
    </div>
  );
}
