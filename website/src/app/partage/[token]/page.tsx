'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { supabaseLien } from '@/lib/supabase';
import { SECTIONS_PARTAGE } from '@/components/animaux/PartageAnimalModal';

// Fiche d'un animal partagée par lien / QR code, en lecture seule : seuls les
// onglets choisis par le propriétaire (partage_animal.sections) sont affichés
// — et la base n'ouvre que ceux-là (migration_partage_sections.sql).

type Ligne = Record<string, unknown>;

interface Animal {
  id: string; nom?: string; espece?: string; race?: string; sexe?: string; date_naissance?: string;
  identification?: string; photo_url?: string; description?: string; couleur?: string; couleur_yeux?: string;
  poids?: number; taille?: number; sterilise?: boolean;
  documents?: { nom?: string; url?: string; categorie?: string; date_expiration?: string }[] | null;
  nom_pere?: string; race_pere?: string; puce_pere?: string; nom_pedigree_pere?: string;
  nom_mere?: string; race_mere?: string; puce_mere?: string; nom_pedigree_mere?: string;
  nom_pedigree?: string; pedigree_lof?: string; pedigree_numero?: string; club_registre?: string;
}

type Sante = { vaccinations: Ligne[]; traitements: Ligne[]; vermifuges: Ligne[]; antiparasitaires: Ligne[]; visites: Ligne[]; allergies: Ligne[]; chirurgies: Ligne[] };

type State =
  | { status: 'loading' }
  | { status: 'expired' }
  | { status: 'invalid' }
  | { status: 'ok'; animal: Animal; sections: string[]; sante: Sante | null; poids: Ligne[]; alimentation: Ligne | null };

const COLONNES = 'id, nom, espece, race, sexe, date_naissance, identification, photo_url, description, couleur, couleur_yeux, poids, taille, sterilise, documents, '
  + 'nom_pere, race_pere, puce_pere, nom_pedigree_pere, nom_mere, race_mere, puce_mere, nom_pedigree_mere, nom_pedigree, pedigree_lof, pedigree_numero, club_registre';

const jour = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString('fr-FR') : '');

export default function PartageAnimalPage() {
  const { token } = useParams<{ token: string }>();
  // Toutes les requêtes de la page portent le lien (en-tête x-pm-token).
  const supabase = supabaseLien(token);
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (!token) { setState({ status: 'invalid' }); return; }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  async function load() {
    try {
      const { data: partage, error } = await supabase.from('partage_animal')
        .select('*').eq('token', token).single(); // * : sections absent avant la migration → identité seule
      if (error || !partage) { setState({ status: 'invalid' }); return; }
      const row = partage as { animal_id: string; expire_at: string; actif: boolean; sections: string[] | null };
      if (!row.actif || new Date(row.expire_at) < new Date()) { setState({ status: 'expired' }); return; }
      const sections = row.sections?.length ? row.sections : ['identite'];

      const { data: animal, error: aErr } = await supabase.from('animaux').select(COLONNES).eq('id', row.animal_id).single();
      if (aErr || !animal) { setState({ status: 'invalid' }); return; }

      const lire = async (table: string, ordre = 'date') =>
        ((await supabase.from(table).select('*').eq('animal_id', row.animal_id).order(ordre, { ascending: false })).data ?? []) as Ligne[];

      let sante: Sante | null = null;
      if (sections.includes('sante')) {
        const [vaccinations, traitements, vermifuges, antiparasitaires, visites, allergies, chirurgies] = await Promise.all(
          ['vaccinations', 'traitements', 'vermifuges', 'antiparasitaires', 'visites', 'allergies', 'chirurgies'].map(t => lire(t)));
        sante = { vaccinations, traitements, vermifuges, antiparasitaires, visites, allergies, chirurgies };
      }
      const poids = sections.includes('poids') ? await lire('poids') : [];
      const alimentation = sections.includes('alimentation')
        ? (((await supabase.from('alimentations').select('*').eq('animal_id', row.animal_id).limit(1)).data ?? [])[0] as Ligne | undefined) ?? null
        : null;

      setState({ status: 'ok', animal: animal as unknown as Animal, sections, sante, poids, alimentation });
    } catch {
      setState({ status: 'invalid' });
    }
  }

  if (state.status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-green-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <p className="text-gray-500 font-medium">Chargement de la fiche…</p>
        </div>
      </div>
    );
  }
  if (state.status === 'expired') {
    return <PageErreur titre="Lien expiré" message="Ce lien de partage n'est plus valide. Demandez un nouveau lien à son propriétaire." />;
  }
  if (state.status === 'invalid') {
    return <PageErreur titre="Lien invalide" message="Ce lien de partage est introuvable ou a été désactivé." />;
  }

  const { animal, sections, sante, poids, alimentation } = state;
  const age = animal.date_naissance ? (() => {
    const diff = Date.now() - new Date(animal.date_naissance).getTime();
    const mois = Math.floor(diff / (1000 * 60 * 60 * 24 * 30.44));
    if (mois < 2) return `${Math.floor(diff / 86400000)} jours`;
    if (mois < 24) return `${mois} mois`;
    return `${Math.floor(mois / 12)} ans`;
  })() : null;
  const visibles = SECTIONS_PARTAGE.filter(([k]) => sections.includes(k)).map(([, l]) => l).join(' · ');

  return (
    <div className="min-h-screen bg-gradient-to-b from-green-50 to-white" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-2">
        <span className="text-xl font-bold text-green-700">PetsMatch</span>
        <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full ml-auto">Fiche partagée · lecture seule</span>
      </div>

      <div className="max-w-md mx-auto px-4 py-8 space-y-4">
        {/* Identité (toujours) */}
        <div className="bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden">
          {animal.photo_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={animal.photo_url} alt={animal.nom ?? 'Animal'} className="w-full h-56 object-cover" />
          )}
          <div className="p-5">
            <h1 className="text-2xl font-bold text-gray-900">{animal.nom ?? 'Sans nom'}</h1>
            {animal.race && <p className="text-green-700 font-medium text-sm">{animal.race}</p>}
            <div className="grid grid-cols-2 gap-3 mt-4">
              {animal.espece && <Info label="Espèce" value={capitale(animal.espece)} />}
              {animal.sexe && <Info label="Sexe" value={capitale(animal.sexe)} />}
              {age && <Info label="Âge" value={age} />}
              {animal.date_naissance && <Info label="Naissance" value={jour(animal.date_naissance)} />}
              {animal.couleur && <Info label="Couleur" value={animal.couleur} />}
              {animal.couleur_yeux && <Info label="Couleur des yeux" value={animal.couleur_yeux} />}
              {animal.taille && <Info label="Taille" value={`${animal.taille} cm`} />}
              {animal.sterilise != null && <Info label="Stérilisé(e)" value={animal.sterilise ? 'Oui' : 'Non'} />}
            </div>
            {animal.identification && (
              <p className="mt-4 text-xs text-gray-500">Identification : <span className="font-mono text-gray-800">{animal.identification}</span></p>
            )}
            {animal.description && <p className="mt-3 text-sm text-gray-700 leading-relaxed">{animal.description}</p>}
          </div>
        </div>

        {sante && (
          <Bloc titre="Carnet de santé">
            <Liste titre="Vaccins" lignes={sante.vaccinations}
              rendu={v => [String(v.vaccin ?? ''), jour(v.date), v.date_rappel ? `rappel ${jour(v.date_rappel)}` : ''].filter(Boolean).join(' · ')} />
            <Liste titre="Traitements" lignes={sante.traitements}
              rendu={t => [String(t.nom ?? ''), String(t.posologie ?? ''),
                t.date_fin ? `du ${jour(t.date)} au ${jour(t.date_fin)}` : t.date ? `depuis le ${jour(t.date)}` : ''].filter(Boolean).join(' · ')} />
            <Liste titre="Vermifuges" lignes={sante.vermifuges}
              rendu={v => [String(v.produit ?? ''), jour(v.date), v.date_rappel ? `rappel ${jour(v.date_rappel)}` : ''].filter(Boolean).join(' · ')} />
            <Liste titre="Antiparasitaires" lignes={sante.antiparasitaires}
              rendu={v => [String(v.produit ?? ''), jour(v.date), v.date_rappel ? `rappel ${jour(v.date_rappel)}` : ''].filter(Boolean).join(' · ')} />
            <Liste titre="Chirurgie / hospitalisation" lignes={sante.chirurgies}
              rendu={c => [String(c.intitule ?? ''), jour(c.date), c.statut === 'realise' ? 'réalisée' : c.statut === 'annule' ? 'annulée' : 'prévue'].filter(Boolean).join(' · ')} />
            <Liste titre="Visites" lignes={sante.visites}
              rendu={v => [String(v.motif ?? ''), jour(v.date), String(v.veterinaire ?? '')].filter(Boolean).join(' · ')} />
            <Liste titre="Allergies" lignes={sante.allergies}
              rendu={a => [String(a.description ?? ''), String(a.severite ?? '')].filter(Boolean).join(' · ')} />
          </Bloc>
        )}

        {sections.includes('poids') && (
          <Bloc titre="Poids">
            {poids.length === 0 ? <Vide /> : (
              <ul className="text-sm text-gray-700 space-y-1">
                {poids.slice(0, 12).map((p, i) => <li key={i}>{jour(p.date)} — <strong>{String(p.valeur)} kg</strong></li>)}
              </ul>
            )}
          </Bloc>
        )}

        {sections.includes('alimentation') && (
          <Bloc titre="Alimentation">
            {!alimentation ? <Vide /> : (
              <div className="text-sm text-gray-700 space-y-1">
                {alimentation.type_ration ? <p>Type de ration : <strong>{String(alimentation.type_ration)}</strong></p> : null}
                {alimentation.marque ? <p>Aliment : <strong>{[alimentation.marque, alimentation.gamme].filter(Boolean).join(' ')}</strong></p> : null}
                {alimentation.ration_grammes ? <p>Ration : <strong>{String(alimentation.ration_grammes)} g / jour</strong></p> : null}
                {alimentation.nb_repas ? <p>Repas : <strong>{String(alimentation.nb_repas)} par jour</strong></p> : null}
                {alimentation.notes ? <p className="text-gray-500">{String(alimentation.notes)}</p> : null}
              </div>
            )}
          </Bloc>
        )}

        {sections.includes('documents') && (
          <Bloc titre="Documents">
            {!animal.documents?.length ? <Vide /> : (
              <ul className="text-sm space-y-1.5">
                {animal.documents.map((d, i) => (
                  <li key={i}>
                    {d.url
                      ? <a href={d.url} target="_blank" rel="noopener noreferrer" className="text-[#0C5C6C] font-semibold underline">{d.nom ?? 'Document'}</a>
                      : <span>{d.nom ?? 'Document'}</span>}
                    {d.date_expiration && <span className="text-gray-400 text-xs"> · expire le {jour(d.date_expiration)}</span>}
                  </li>
                ))}
              </ul>
            )}
          </Bloc>
        )}

        {sections.includes('genealogie') && (
          <Bloc titre="Généalogie">
            <div className="grid grid-cols-2 gap-3">
              <Parent titre="Père" nom={animal.nom_pedigree_pere || animal.nom_pere} race={animal.race_pere} puce={animal.puce_pere} />
              <Parent titre="Mère" nom={animal.nom_pedigree_mere || animal.nom_mere} race={animal.race_mere} puce={animal.puce_mere} />
            </div>
            {(animal.nom_pedigree || animal.pedigree_lof || animal.pedigree_numero) && (
              <p className="text-xs text-gray-500 mt-3">
                Pedigree : {[animal.nom_pedigree, animal.club_registre, animal.pedigree_lof || animal.pedigree_numero].filter(Boolean).join(' · ')}
              </p>
            )}
          </Bloc>
        )}

        <p className="text-center text-xs text-gray-400 pt-2">Fiche partagée via PetsMatch · {visibles} · lecture seule</p>
      </div>
    </div>
  );
}

function Bloc({ titre, children }: { titre: string; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">{titre}</p>
      {children}
    </div>
  );
}

function Liste({ titre, lignes, rendu }: { titre: string; lignes: Ligne[]; rendu: (l: Ligne) => string }) {
  if (!lignes.length) return null;
  return (
    <div className="mb-3 last:mb-0">
      <p className="text-sm font-semibold text-[#1F2A2E] mb-1">{titre}</p>
      <ul className="text-sm text-gray-700 space-y-0.5">
        {lignes.slice(0, 20).map((l, i) => <li key={i}>{rendu(l)}</li>)}
      </ul>
    </div>
  );
}

function Parent({ titre, nom, race, puce }: { titre: string; nom?: string; race?: string; puce?: string }) {
  return (
    <div className="bg-gray-50 rounded-xl px-3 py-2">
      <p className="text-xs text-gray-400">{titre}</p>
      <p className="text-sm font-semibold text-gray-800">{nom || '—'}</p>
      {race && <p className="text-xs text-gray-500">{race}</p>}
      {puce && <p className="text-xs text-gray-500 font-mono">{puce}</p>}
    </div>
  );
}

function Vide() {
  return <p className="text-sm text-gray-400">Rien de renseigné.</p>;
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-gray-50 rounded-xl px-3 py-2">
      <p className="text-xs text-gray-400 font-medium">{label}</p>
      <p className="text-sm font-semibold text-gray-800">{value}</p>
    </div>
  );
}

function PageErreur({ titre, message }: { titre: string; message: string }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="text-center max-w-sm">
        <h1 className="text-xl font-bold text-gray-800 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{titre}</h1>
        <p className="text-gray-500 text-sm leading-relaxed">{message}</p>
        <a href="/" className="mt-6 inline-block bg-green-600 text-white px-6 py-2.5 rounded-full text-sm font-medium hover:bg-green-700 transition-colors">
          Retour à l&apos;accueil
        </a>
      </div>
    </div>
  );
}

function capitale(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
