'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Cert {
  id: string;
  nom_animal: string;
  espece: string;
  race: string;
  date_naissance_animal: string;
  num_identification: string;
  acquereur_nom: string;
  acquereur_prenom: string;
  acquereur_email: string;
  acquereur_telephone: string;
  acquereur_adresse: string;
  modalite_cession: string;
  prix: number | string | null;
  date_remise: string;
  date_limite_signature: string | null;
  date_signature_acquereur: string | null;
  statut: string;
  token_signature: string;
  notes: string;
  cedant_uid: string;
}

interface Cedant {
  name_elevage: string;
  firstname: string;
  lastname: string;
  siret: string;
  phone_number: string;
  numero_elevage: string;
  rue_elevage: string;
  ville_elevage: string;
  code_postal_elevage: string;
  rue: string;
  ville: string;
  code_postal: string;
  is_elevage: boolean;
  is_pro: boolean;
  cat_pro: string;
}

// ── Contenu espèce-spécifique ─────────────────────────────────────────────────

interface SpeciesContent {
  intro: string;
  physio: { titre: string; contenu: string }[];
  psycho: { titre: string; contenu: string }[];
  sante: string[];
  documents: string[];
  budget: { poste: string; montant: string }[];
  identNote: string;
}

const CONTENT: Record<string, SpeciesContent> = {
  chien: {
    intro: `Ce certificat a pour objectif de vous donner toutes les informations pour accueillir votre chien au mieux, et de vous engager à respecter ses besoins. Il est établi conformément à la Loi n° 2021-1539 et au décret n° 2022-1012 du 18 juillet 2022.`,
    physio: [
      { titre: 'Boire', contenu: `Votre animal doit avoir en permanence de l'eau fraîche et propre à sa disposition. Adaptez la hauteur et la forme des gamelles à la taille de votre chien.` },
      { titre: 'Dormir', contenu: `Un chien dort en moyenne 12h/jour en discontinu. Prévoyez-lui un coin calme et sécurisé (panier, coussin) où il sera respecté dans son repos.` },
      { titre: 'Manger', contenu: `Le chien est carnivore. Prévoyez une alimentation adaptée à son âge, son poids et sa dépense physique. Deux repas par jour minimum sont recommandés pour limiter le risque de torsion d'estomac. Consultez votre vétérinaire pour toute transition alimentaire.` },
    ],
    psycho: [
      { titre: 'Mastiquer et renifler', contenu: `Ces comportements instinctifs permettent au chien de canaliser son énergie et de réduire son stress. Encouragez-les avec des promenades variées, tapis de fouille, jouets et friandises naturelles.` },
      { titre: 'Socialiser', contenu: `Le chien est une espèce sociale. Il a besoin d'interactions positives avec d'autres chiens et avec des humains tout au long de sa vie. Un chiot exposé à des environnements variés dès ses premiers mois sera plus équilibré.` },
      { titre: 'Sortir et se dépenser', contenu: `Au-delà de la dépense physique quotidienne indispensable, le chien a besoin de stimulation mentale. Jouets, jeux de recherche, éducation positive : variez les activités pour prévenir l'ennui.` },
      { titre: 'Éducation', contenu: `Instaurez des règles cohérentes dès l'arrivée du chien. Les commandements essentiels (stop, rappel) sont indispensables pour sa sécurité. Évitez toute méthode coercitive (art. R214-24 du Code rural).` },
    ],
    sante: [
      `Vaccination : première injection dès 7-8 semaines, rappels annuels selon le protocole vétérinaire.`,
      `Visite annuelle chez le vétérinaire même en l'absence de problèmes apparents.`,
      `Nettoyage régulier des oreilles et des yeux avec des produits adaptés à l'espèce.`,
      `Entretien du pelage adapté au type de poil (brossage, tonte si nécessaire).`,
      `Contrôle du tartre dentaire ; brossage, friandises à mâcher recommandés.`,
      `Vérification et taille des griffes si elles ne s'usent pas naturellement.`,
      `Antiparasitaires (puces, tiques, vers) selon les recommandations de votre vétérinaire.`,
      `Stérilisation recommandée sauf projet d'élevage (à discuter avec votre vétérinaire).`,
    ],
    documents: [
      `Carnet de santé à jour avec les vaccinations effectuées`,
      `Certificat de cession (présent document)`,
      `Justificatif d'identification (puce électronique ou tatouage — obligatoire avant cession)`,
      `Certificat de naissance / livre des origines si chien de race inscrit au LOF`,
      `Passeport européen si déplacements à l'étranger prévus`,
    ],
    budget: [
      { poste: 'Alimentation', montant: '50 à 150 € / mois selon la taille' },
      { poste: 'Soins vétérinaires (suivi courant)', montant: '200 € / an minimum' },
      { poste: 'Antiparasitaires & vaccins', montant: '100 à 200 € / an' },
      { poste: 'Matériel (panier, laisse, jouets)', montant: '150 à 300 € à l\'arrivée' },
      { poste: 'Assurance santé animale', montant: '20 à 60 € / mois (recommandée)' },
      { poste: 'Toilettage (selon la race)', montant: '30 à 80 € toutes les 6 à 8 semaines' },
    ],
    identNote: `En cas de changement d'adresse ou de propriétaire, signalez-le à I-CAD : 09 77 40 30 77 ou i-cad.fr`,
  },
  chat: {
    intro: `Ce certificat a pour objectif de vous donner toutes les informations pour accueillir votre chat au mieux, et de vous engager à respecter ses besoins. Il est établi conformément à la Loi n° 2021-1539 et au décret n° 2022-1012 du 18 juillet 2022.`,
    physio: [
      { titre: 'Boire', contenu: `Le chat boit peu et préfère l'eau courante ou une fontaine. Éloignez la gamelle d'eau de la gamelle de nourriture. Une alimentation humide (pâtée) contribue à son hydratation.` },
      { titre: 'Dormir', contenu: `Le chat dort entre 12 et 16h par jour. Prévoyez plusieurs zones de repos en hauteur où il se sentira en sécurité. Respectez ses périodes de sommeil.` },
      { titre: 'Manger', contenu: `Le chat est un carnivore strict. Son alimentation doit être riche en protéines animales. Plusieurs petits repas par jour sont préférables. Évitez les aliments interdits (oignon, ail, chocolat, raisins).` },
    ],
    psycho: [
      { titre: 'Chasser et jouer', contenu: `L'instinct de chasse est fondamental chez le chat. Prévoyez des sessions de jeu quotidiennes avec des jouets stimulant cet instinct (cannes à plumes, souris). Cela prévient l'ennui et l'obésité.` },
      { titre: 'Griffer', contenu: `Le griffage est un besoin naturel permettant de marquer son territoire et d'entretenir ses griffes. Mettez à disposition des griffoirs adaptés à la taille de votre chat.` },
      { titre: 'Environnement enrichi', contenu: `Le chat a besoin d'explorer, grimper et se cacher. Arbres à chat, cachettes, fenêtres accessibles sont essentiels. Pour un chat d'intérieur, l'enrichissement est encore plus important.` },
      { titre: 'Socialisation', contenu: `L'exposition à l'humain dès les premières semaines de vie est déterminante pour son sociabilité. Respectez son rythme et évitez de le forcer à des interactions non désirées.` },
    ],
    sante: [
      `Vaccination : typhus, coryza, leucose (typo coryza leucose rage si sorties) — rappels annuels.`,
      `Visite vétérinaire annuelle, plus fréquente à partir de 7 ans (chat senior).`,
      `Nettoyage des oreilles et des yeux si nécessaire (sécrétions, cérumen).`,
      `Entretien du pelage (brossage régulier, surtout pour les chats à poils longs).`,
      `Contrôle dentaire ; tartres fréquents chez le chat.`,
      `Antiparasitaires (puces, tiques, vers intestinaux) selon protocole vétérinaire.`,
      `Stérilisation recommandée entre 4 et 6 mois sauf projet d'élevage.`,
    ],
    documents: [
      `Carnet de santé avec vaccinations à jour`,
      `Certificat de cession (présent document)`,
      `Justificatif d'identification (puce ou tatouage — obligatoire avant cession)`,
      `Pedigree LOOF si chat de race`,
    ],
    budget: [
      { poste: 'Alimentation', montant: '30 à 80 € / mois' },
      { poste: 'Soins vétérinaires (suivi courant)', montant: '150 à 300 € / an' },
      { poste: 'Litière', montant: '20 à 50 € / mois' },
      { poste: 'Matériel (griffoir, jouets, arbre à chat)', montant: '100 à 250 € à l\'arrivée' },
      { poste: 'Assurance santé animale', montant: '15 à 40 € / mois' },
    ],
    identNote: `En cas de changement de propriétaire, signalez-le à I-CAD : 09 77 40 30 77 ou i-cad.fr`,
  },
  lapin: {
    intro: `Ce certificat vous informe des besoins essentiels de votre lapin et formalise vos engagements envers son bien-être, conformément à la Loi n° 2021-1539.`,
    physio: [
      { titre: 'Alimentation', contenu: `Le lapin est herbivore strict. Le foin doit représenter 80% de son alimentation (disponible à volonté). Complétez avec des légumes verts frais (persil, roquette, endive) et limitez les granulés. Évitez les laitues iceberg, les choux en grande quantité et tout aliment sucré.` },
      { titre: 'Eau', contenu: `Eau fraîche disponible en permanence. Le biberon ou la gamelle sont tous deux adaptés ; nettoyez-les quotidiennement.` },
      { titre: 'Espace', contenu: `Un lapin a besoin d'un minimum de 4 m² d'espace de vie. Le confinement permanent dans une cage est contraire à son bien-être. Prévoyez des sorties quotidiennes dans un espace sécurisé.` },
    ],
    psycho: [
      { titre: 'Enrichissement', contenu: `Le lapin a besoin de mâcher, creuser et explorer. Mettez à sa disposition des jouets adaptés (blocs de bois non traité, tunnels, cartons). Cela prévient les stéréotypies.` },
      { titre: 'Vie en duo', contenu: `Le lapin est grégaire. Il souffre de la solitude. Il est fortement recommandé d'adopter des lapins par paires (stérilisés ou de même sexe).` },
    ],
    sante: [
      `Vaccination contre la myxomatose et la VHD (VHD1 + VHD2) — rappels annuels obligatoires.`,
      `Visite vétérinaire annuelle et en urgence à la moindre modification du transit intestinal.`,
      `Stérilisation recommandée (prévient les cancers de l'utérus chez la femelle, fréquents après 4 ans).`,
      `Contrôle des dents (les incisives et molaires poussent en continu ; le foin les use naturellement).`,
      `Entretien des griffes toutes les 4 à 8 semaines.`,
    ],
    documents: [
      `Certificat de cession (présent document)`,
      `Carnet de santé avec vaccinations si débutées`,
    ],
    budget: [
      { poste: 'Alimentation (foin, légumes, granulés)', montant: '20 à 40 € / mois' },
      { poste: 'Soins vétérinaires + vaccins', montant: '100 à 200 € / an' },
      { poste: 'Litière', montant: '15 à 30 € / mois' },
      { poste: 'Matériel (cage, jouets, accessoires)', montant: '100 à 200 € à l\'arrivée' },
    ],
    identNote: ``,
  },
  default: {
    intro: `Ce certificat vous informe des besoins essentiels de votre animal et formalise vos engagements envers son bien-être, conformément à la Loi n° 2021-1539 du 30 novembre 2021.`,
    physio: [
      { titre: 'Alimentation', contenu: `Fournissez une alimentation adaptée à l'espèce, à l'âge et au poids de l'animal. Consultez un vétérinaire ou un spécialiste pour établir une ration équilibrée.` },
      { titre: 'Eau', contenu: `Eau fraîche disponible en permanence, renouvelée quotidiennement.` },
      { titre: 'Espace et logement', contenu: `Prévoyez un espace de vie suffisant et adapté aux besoins spécifiques de l'espèce (temperature, humidité, lumière).` },
    ],
    psycho: [
      { titre: 'Enrichissement', contenu: `Offrez à votre animal des stimulations adaptées à son espèce : jeux, exploration, activité physique. L'ennui peut générer des troubles comportementaux.` },
      { titre: 'Socialisation', contenu: `Respectez les besoins sociaux propres à l'espèce. Certains animaux vivent en groupe, d'autres sont solitaires. Renseignez-vous auprès d'un spécialiste.` },
    ],
    sante: [
      `Consultez un vétérinaire spécialisé dans l'espèce dès l'arrivée de l'animal et au minimum une fois par an.`,
      `Respectez le protocole de vaccination et de vermifugation adapté à l'espèce.`,
      `Surveillez tout changement de comportement, d'appétit ou d'aspect physique.`,
      `Prévenez ou faites traiter tout parasitisme interne ou externe.`,
    ],
    documents: [
      `Certificat de cession (présent document)`,
      `Carnet de santé ou document sanitaire si disponible`,
    ],
    budget: [
      { poste: 'Alimentation', montant: 'Variable selon l\'espèce' },
      { poste: 'Soins vétérinaires', montant: '100 à 300 € / an minimum' },
      { poste: 'Matériel et logement', montant: 'Variable selon l\'espèce' },
    ],
    identNote: ``,
  },
};

function getContent(espece: string): SpeciesContent {
  const key = (espece ?? '').toLowerCase();
  return CONTENT[key] ?? CONTENT.default;
}

function fmtDate(d: string | null | undefined) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('fr-FR');
}

function fmtPrix(p: number | string | null | undefined) {
  if (p == null || p === '') return null;
  const n = typeof p === 'string' ? parseFloat(p) : p;
  if (isNaN(n)) return null;
  return n % 1 === 0 ? `${n.toFixed(0)} €` : `${n.toFixed(2).replace('.', ',')} €`;
}

export default function CertificatPublicPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [cert, setCert] = useState<Cert | null>(null);
  const [cedant, setCedant] = useState<Cedant | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [action, setAction] = useState<'idle' | 'signing' | 'refusing' | 'done_sign' | 'done_refuse' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  const [delaiBloq, setDelaiBloq] = useState(false);
  const [joursRestants, setJoursRestants] = useState(0);

  useEffect(() => {
    supabase.from('certificats_engagement').select('*').eq('token_signature', token).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setCert(data as Cert);
        if (data.statut === 'envoye') {
          await fetch('/api/certificat/sign', { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token, action: 'lu' }) });
        }
        if (data.date_limite_signature) {
          const now = new Date();
          const limite = new Date(data.date_limite_signature);
          if (now < limite) { setDelaiBloq(true); setJoursRestants(Math.ceil((limite.getTime() - now.getTime()) / 86400_000)); }
        }
        const { data: ced } = await supabase.from('users')
          .select('name_elevage,firstname,lastname,siret,phone_number,numero_elevage,rue_elevage,ville_elevage,code_postal_elevage,rue,ville,code_postal,is_elevage,is_pro,cat_pro')
          .eq('uid', data.cedant_uid).maybeSingle();
        setCedant(ced as Cedant | null);
        setLoading(false);
      });
  }, [token]);

  async function handleSign(actionType: 'signe' | 'refuse') {
    setAction(actionType === 'signe' ? 'signing' : 'refusing');
    const res = await fetch('/api/certificat/sign', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, action: actionType }) });
    const json = await res.json();
    if (!res.ok) { setErrorMsg(json.error ?? 'Erreur'); setAction('error'); }
    else { setAction(actionType === 'signe' ? 'done_sign' : 'done_refuse');
      setCert(prev => prev ? { ...prev, statut: actionType, date_signature_acquereur: actionType === 'signe' ? new Date().toISOString() : prev.date_signature_acquereur } : prev); }
  }

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (notFound) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <span className="text-5xl">🔍</span>
      <p className="font-semibold text-gray-700">Certificat introuvable ou lien expiré.</p>
    </div>
  );

  const content = getContent(cert!.espece);
  const isSigned = cert!.statut === 'signe';
  const isRefused = cert!.statut === 'refuse';
  const isDone = isSigned || isRefused || action === 'done_sign' || action === 'done_refuse';

  // Désignation cédant
  const nomCedant = cedant?.name_elevage?.trim()
    || `${cedant?.firstname ?? ''} ${cedant?.lastname ?? ''}`.trim()
    || '—';
  const adresseCedant = [cedant?.rue_elevage || cedant?.rue, cedant?.code_postal_elevage || cedant?.code_postal, cedant?.ville_elevage || cedant?.ville].filter(Boolean).join(', ');
  const qualiteCedant = cedant?.is_pro && cedant?.cat_pro ? cedant.cat_pro : (cedant?.is_elevage ? 'Éleveur professionnel' : 'Particulier');
  // Téléphone : numero_elevage pour les éleveurs, phone_number sinon (évite d'afficher "0000000000")
  const telCedant = (() => {
    const tel = cedant?.is_elevage ? (cedant.numero_elevage || cedant.phone_number) : cedant?.phone_number;
    return tel && tel !== '0000000000' && tel !== '000000' && tel.trim() !== '' ? tel : null;
  })();

  const especeLabel = cert!.espece ? cert!.espece.charAt(0).toUpperCase() + cert!.espece.slice(1) : '—';
  const dateRemise = fmtDate(cert!.date_remise);

  function handlePrint() {
    const el = document.getElementById('cert-print-content');
    if (!el) return;
    const win = window.open('', '_blank', 'width=900,height=1200');
    if (!win) return;
    win.document.write(`<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Certificat d'engagement PetsMatch — ${cert!.nom_animal}</title>
  <script src="https://cdn.tailwindcss.com"><\/script>
  <style>
    @page { size: A4; margin: 0; }
    *, *::before, *::after { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: white; font-family: system-ui, -apple-system, sans-serif; }
    .print-page { padding: 12mm 14mm 14mm 14mm; max-width: 210mm; margin: 0 auto; }

    /* ── Contrôle des sauts de page ── */
    .no-break { break-inside: avoid; page-break-inside: avoid; }
    .keep-next { break-after: avoid; page-break-after: avoid; }
    section.no-break.border-t { break-before: auto; }
    section { break-before: auto; }
    p { orphans: 3; widows: 3; }
    .rounded-xl { border-radius: 0.75rem !important; }
    .text-center.border-b { break-inside: avoid; page-break-inside: avoid; }

    /* ── Zone signatures — ne jamais couper ── */
    .grid.grid-cols-2 { page-break-inside: avoid; break-inside: avoid; }
    /* Chaque colonne signature reste visible entière */
    .grid.grid-cols-2 > div { overflow: visible !important; }
    /* La ligne pointillée de signature ne doit jamais être coupée */
    .h-14 { height: 3.5rem; overflow: visible !important; page-break-inside: avoid; break-inside: avoid; }
    /* Empêche un saut juste avant le bloc signatures */
    section:last-of-type { break-before: avoid; page-break-before: avoid; }

    /* Corrige les hauteurs fixes qui peuvent rogner le contenu */
    [class*="h-"] { overflow: visible !important; }
    img { max-width: 100% !important; height: auto !important; object-fit: contain !important; }
  </style>
</head>
<body>
  <div class="print-page">
    ${el.outerHTML}
  </div>
  <script>
    window.addEventListener('load', function() {
      setTimeout(function() { window.print(); }, 1200);
    });
  <\/script>
</body>
</html>`);
    win.document.close();
  }

  return (
    <>
      <div className="print-wrapper max-w-3xl mx-auto px-4 py-8">

        {/* Header actions */}
        <div className="no-print flex items-center justify-between mb-6">
          <div>
            <h1 className="text-xl font-bold text-[#1F2A2E]">Certificat d'Engagement et de Connaissance</h1>
            <p className="text-xs text-gray-500 mt-0.5">Loi n° 2021-1539 · Décret n° 2022-1012 du 18 juillet 2022</p>
          </div>
          <button onClick={handlePrint} className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">🖨️ PDF</button>
        </div>

        {/* Statut banners */}
        {(isSigned || action === 'done_sign') && (
          <div className="no-print mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-medium">
            ✅ Ce certificat a été signé le {fmtDate(cert!.date_signature_acquereur)}.
          </div>
        )}
        {(isRefused || action === 'done_refuse') && (
          <div className="no-print mb-4 bg-red-50 border border-red-200 rounded-xl p-3 text-sm text-red-700 font-medium">
            ❌ Ce certificat a été refusé.
          </div>
        )}

        {/* Document */}
        <div id="cert-print-content" className="print-doc border border-gray-300 rounded-xl bg-white text-sm text-gray-800">

          {/* Couverture */}
          <div className="text-center border-b border-gray-200 px-8 py-6">
            <p className="text-xs font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">PetsMatch</p>
            <h2 className="text-xl font-bold text-[#1F2A2E] leading-tight">CERTIFICAT D'ENGAGEMENT<br/>ET DE CONNAISSANCE</h2>
            <p className="text-xs text-gray-400 mt-2">Référence : CERT-{cert!.id.substring(0,8).toUpperCase()}</p>
            <div className="mt-4 inline-block bg-[#E8F4F6] rounded-xl px-6 py-3">
              <p className="text-sm font-semibold text-[#0C5C6C]">
                Un {especeLabel.toLowerCase()} va bientôt faire partie de votre famille !
              </p>
            </div>
            <p className="text-xs text-gray-600 mt-4 max-w-xl mx-auto leading-relaxed">{content.intro}</p>
          </div>

          <div className="p-8 space-y-6">

            {/* A — Parties */}
            <section className="no-break grid grid-cols-2 gap-6">
              <div className="border border-gray-200 rounded-xl p-4">
                <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">Cédant</p>
                <p className="font-semibold text-sm">{nomCedant}</p>
                <p className="text-xs text-gray-500 mt-0.5">{qualiteCedant}</p>
                {cedant?.siret && <p className="text-xs text-gray-500">SIRET : {cedant.siret}</p>}
                {adresseCedant && <p className="text-xs text-gray-500 mt-1">{adresseCedant}</p>}
                {telCedant && <p className="text-xs text-gray-500">{telCedant}</p>}
                <p className="text-xs text-gray-400 mt-2">Date de remise : <strong>{dateRemise}</strong></p>
              </div>
              <div className="border border-gray-200 rounded-xl p-4">
                <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">Acquéreur</p>
                <p className="font-semibold text-sm">{cert!.acquereur_prenom} {cert!.acquereur_nom}</p>
                <p className="text-xs text-gray-500 mt-0.5">{cert!.acquereur_email}</p>
                {cert!.acquereur_telephone && <p className="text-xs text-gray-500">{cert!.acquereur_telephone}</p>}
                {cert!.acquereur_adresse && <p className="text-xs text-gray-500 mt-1">{cert!.acquereur_adresse}</p>}
              </div>
            </section>

            {/* B — Animal */}
            <section className="no-break border border-gray-200 rounded-xl p-4">
              <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-3">Animal concerné</p>
              <div className="grid grid-cols-3 gap-3 text-xs">
                <div><span className="text-gray-400 block">Nom</span><span className="font-medium">{cert!.nom_animal}</span></div>
                <div><span className="text-gray-400 block">Espèce</span><span className="font-medium">{especeLabel}</span></div>
                <div><span className="text-gray-400 block">Race</span><span className="font-medium">{cert!.race || '—'}</span></div>
                {cert!.date_naissance_animal && <div><span className="text-gray-400 block">Date de naissance</span><span className="font-medium">{fmtDate(cert!.date_naissance_animal)}</span></div>}
                {cert!.num_identification && <div><span className="text-gray-400 block">Identification</span><span className="font-medium">{cert!.num_identification}</span></div>}
                <div><span className="text-gray-400 block">Modalité</span><span className="font-medium capitalize">{cert!.modalite_cession === 'gratuit' ? 'Cession gratuite' : cert!.modalite_cession}</span></div>
                {fmtPrix(cert!.prix) && <div><span className="text-gray-400 block">Prix</span><span className="font-medium">{fmtPrix(cert!.prix)}</span></div>}
              </div>
            </section>

            {/* C — Besoins physiologiques */}
            <section>
              <h3 className="keep-next font-bold text-[#0C5C6C] text-sm mb-3 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">C</span>
                Besoins physiologiques
              </h3>
              <div className="space-y-3">
                {content.physio.map((item, i) => (
                  <div key={i} className="no-break flex gap-3">
                    <span className="font-semibold text-[#1F2A2E] w-28 flex-shrink-0 text-xs pt-0.5">{item.titre}</span>
                    <p className="text-xs text-gray-700 leading-relaxed">{item.contenu}</p>
                  </div>
                ))}
              </div>
            </section>

            {/* D — Besoins psychologiques */}
            <section>
              <h3 className="keep-next font-bold text-[#0C5C6C] text-sm mb-3 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">D</span>
                Besoins comportementaux et psychologiques
              </h3>
              <div className="space-y-3">
                {content.psycho.map((item, i) => (
                  <div key={i} className="no-break flex gap-3">
                    <span className="font-semibold text-[#1F2A2E] w-28 flex-shrink-0 text-xs pt-0.5">{item.titre}</span>
                    <p className="text-xs text-gray-700 leading-relaxed">{item.contenu}</p>
                  </div>
                ))}
              </div>
            </section>

            {/* E — Santé */}
            <section>
              <h3 className="keep-next font-bold text-[#0C5C6C] text-sm mb-3 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">E</span>
                Santé
              </h3>
              <ul className="space-y-1.5">
                {content.sante.map((item, i) => (
                  <li key={i} className="no-break flex gap-2 text-xs text-gray-700">
                    <span className="text-[#6E9E57] mt-0.5 flex-shrink-0">☑</span>
                    {item}
                  </li>
                ))}
              </ul>
            </section>

            {/* F — Budget */}
            <section>
              <h3 className="keep-next font-bold text-[#0C5C6C] text-sm mb-3 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">F</span>
                Dépenses à prévoir
              </h3>
              <div className="no-break border border-gray-200 rounded-xl overflow-hidden">
                {content.budget.map((item, i) => (
                  <div key={i} className={`flex items-center justify-between px-4 py-2 text-xs ${i % 2 === 0 ? 'bg-gray-50' : 'bg-white'}`}>
                    <span className="text-gray-700">{item.poste}</span>
                    <span className="font-medium text-[#1F2A2E]">{item.montant}</span>
                  </div>
                ))}
              </div>
              {content.identNote && (
                <p className="text-[10px] text-gray-500 mt-2 italic">{content.identNote}</p>
              )}
            </section>

            {/* G — Documents */}
            <section>
              <h3 className="keep-next font-bold text-[#0C5C6C] text-sm mb-3 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">G</span>
                Documents remis avec l'animal
              </h3>
              <ul className="space-y-1.5">
                {content.documents.map((doc, i) => (
                  <li key={i} className="no-break flex gap-2 text-xs text-gray-700">
                    <span className="text-[#0C5C6C] flex-shrink-0">□</span>
                    {doc}
                  </li>
                ))}
              </ul>
            </section>

            {/* H — Délai légal */}
            {cert!.date_limite_signature && (
              <section className="no-break bg-amber-50 border border-amber-200 rounded-xl p-4">
                <h3 className="font-bold text-amber-800 text-xs uppercase tracking-wide mb-2">H — Délai de réflexion légal ({especeLabel})</h3>
                <p className="text-xs text-amber-800 leading-relaxed">
                  Pour les <strong>{cert!.espece}s</strong>, l'acquéreur dispose de <strong>7 jours calendaires</strong> à compter de la remise du certificat (<strong>{dateRemise}</strong>) avant de pouvoir le signer. Signature possible à partir du <strong>{fmtDate(cert!.date_limite_signature)}</strong>. Aucune somme ne peut être perçue pendant ce délai.
                </p>
              </section>
            )}

            {/* I — Signatures */}
            <section className="no-break border-t pt-6">
              <h3 className="font-bold text-[#0C5C6C] text-sm mb-4 flex items-center gap-2">
                <span className="w-6 h-6 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center text-xs font-bold flex-shrink-0">I</span>
                Signatures
              </h3>
              <div className="grid grid-cols-2 gap-8">
                <div>
                  <p className="text-xs text-gray-500 mb-1">Cédant — {nomCedant}</p>
                  <p className="text-xs text-gray-600">Remis le <strong>{dateRemise}</strong></p>
                  <div className="mt-3 h-14 border-b-2 border-dashed border-gray-300 flex items-end pb-1">
                    <p className="text-[10px] text-gray-400">Signature électronique PetsMatch</p>
                  </div>
                </div>
                <div>
                  <p className="text-xs text-gray-500 mb-1">Acquéreur — {cert!.acquereur_prenom} {cert!.acquereur_nom}</p>
                  {isSigned || action === 'done_sign' ? (
                    <>
                      <p className="text-xs text-green-700">Signé le <strong>{fmtDate(cert!.date_signature_acquereur)}</strong></p>
                      <div className="mt-3 h-14 border-b-2 border-dashed border-green-300 flex items-end pb-1">
                        <p className="text-[10px] text-green-600 font-medium">✅ Signature électronique validée</p>
                      </div>
                      <p className="text-[10px] text-green-600 mt-2 italic">« Je m'engage à respecter les besoins de l'animal. »</p>
                    </>
                  ) : (
                    <>
                      <p className="text-xs text-gray-400">En attente de signature</p>
                      <div className="mt-3 h-14 border-b-2 border-dashed border-gray-200 flex items-end pb-1">
                        <p className="text-[10px] text-gray-400 italic">« Je m'engage à respecter les besoins de l'animal. »</p>
                      </div>
                    </>
                  )}
                </div>
              </div>
            </section>

            <p className="text-[10px] text-gray-400 text-center border-t pt-3">
              Document généré via PetsMatch · Réf. {cert!.id} · Loi n° 2021-1539 du 30 novembre 2021
            </p>
          </div>
        </div>

        {/* Boutons signature */}
        {!isDone && (
          <div className="no-print mt-6 bg-white border border-gray-200 rounded-xl p-5">
            {delaiBloq ? (
              <div className="text-center">
                <p className="text-sm font-semibold text-amber-700">⏳ Délai légal en cours</p>
                <p className="text-xs text-gray-500 mt-1">
                  Vous pourrez signer dans <strong>{joursRestants} jour(s)</strong> (à partir du {fmtDate(cert!.date_limite_signature)}). Ce délai est imposé par la loi.
                </p>
              </div>
            ) : (
              <>
                <p className="text-sm text-gray-700 mb-2 text-center font-medium">
                  En signant, vous déclarez :<br/>
                  <span className="italic text-gray-600">« Je m'engage à respecter les besoins de l'animal. »</span>
                </p>
                {action === 'error' && <p className="text-sm text-red-600 text-center mb-3">{errorMsg}</p>}
                <div className="flex gap-3 mt-4">
                  <button onClick={() => handleSign('refuse')} disabled={action === 'refusing'}
                    className="flex-1 border border-gray-200 text-gray-600 font-medium py-3 rounded-xl text-sm hover:bg-gray-50 disabled:opacity-50">
                    {action === 'refusing' ? 'Traitement…' : 'Refuser'}
                  </button>
                  <button onClick={() => handleSign('signe')} disabled={action === 'signing'}
                    className="flex-1 bg-[#6E9E57] hover:bg-[#5d8a49] disabled:opacity-50 text-white font-semibold py-3 rounded-xl text-sm">
                    {action === 'signing' ? 'Signature…' : '✍️ Je signe ce certificat'}
                  </button>
                </div>
              </>
            )}
          </div>
        )}
      </div>
    </>
  );
}
