// Tests génétiques / dépistages héréditaires par espèce — miroir de
// `lib/data/genetic_tests.dart`. Partagé entre la vitrine reproducteurs et le
// détail d'annonce saillie.

export interface GeneticTest {
  code: string;
  nom: string;
  categorie: 'maladie' | 'adn' | 'robe' | 'aptitude';
  races?: string;
}

export interface TestGenetique {
  categorie?: string;
  code?: string | null;
  nom?: string;
  resultat?: string | null;
  genotype?: string | null;
}

export const GENETIC_TEST_CATEGORIES = ['maladie', 'adn', 'robe', 'aptitude', 'autre'];

export const GENETIC_TESTS: Record<string, GeneticTest[]> = {
  cheval: [
    { code: 'WFFS', nom: 'Warmblood Fragile Foal Syndrome', categorie: 'maladie', races: 'Chevaux de sport' },
    { code: 'PSSM1', nom: 'Myopathie à surcharge en polysaccharides type 1', categorie: 'maladie' },
    { code: 'PSSM2', nom: 'Myopathie type 2', categorie: 'maladie' },
    { code: 'SCID', nom: 'Immunodéficience combinée sévère', categorie: 'maladie', races: 'Arabe' },
    { code: 'CA', nom: 'Ataxie cérébelleuse', categorie: 'maladie', races: 'Arabe' },
    { code: 'LFS', nom: 'Lavender Foal Syndrome', categorie: 'maladie', races: 'Arabe' },
    { code: 'OAAM', nom: 'Malformation occipito-atlanto-axiale', categorie: 'maladie', races: 'Arabe' },
    { code: 'HERDA', nom: 'Asthénie cutanée régionale héréditaire', categorie: 'maladie', races: 'Quarter Horse' },
    { code: 'GBED', nom: 'Déficit en enzyme de branchement du glycogène', categorie: 'maladie', races: 'Quarter Horse' },
    { code: 'HYPP', nom: 'Paralysie périodique hyperkaliémique', categorie: 'maladie', races: 'Quarter Horse' },
    { code: 'MH', nom: 'Hyperthermie maligne', categorie: 'maladie', races: 'Quarter Horse' },
    { code: 'MYHM', nom: 'Myosite immuno-médiée (MYH1)', categorie: 'maladie', races: 'Quarter Horse' },
    { code: 'OLWS', nom: 'Syndrome du poulain blanc létal (frame overo)', categorie: 'maladie', races: 'Paint' },
    { code: 'JEB', nom: 'Épidermolyse bulleuse jonctionnelle', categorie: 'maladie', races: 'Traits' },
    { code: 'FIS', nom: 'Foal Immunodeficiency Syndrome', categorie: 'maladie', races: 'Fell / Dales' },
    { code: 'CSNB', nom: 'Cécité nocturne stationnaire congénitale', categorie: 'maladie', races: 'Appaloosa' },
    { code: 'ADN', nom: 'Profil ADN (typage / filiation)', categorie: 'adn' },
    { code: 'AGOUTI', nom: 'Agouti (A)', categorie: 'robe' },
    { code: 'EXT', nom: 'Extension (E)', categorie: 'robe' },
    { code: 'GREY', nom: 'Grey (G)', categorie: 'robe' },
    { code: 'CREAM', nom: 'Crème (Cr)', categorie: 'robe' },
    { code: 'TOBIANO', nom: 'Tobiano (TO)', categorie: 'robe' },
    { code: 'LP', nom: 'Léopard (LP)', categorie: 'robe' },
  ],
  chien: [
    { code: 'HD', nom: 'Dysplasie coxo-fémorale (hanches)', categorie: 'maladie' },
    { code: 'ED', nom: 'Dysplasie du coude', categorie: 'maladie' },
    { code: 'PRA', nom: 'Atrophie rétinienne progressive (APR)', categorie: 'maladie' },
    { code: 'MDR1', nom: 'Sensibilité médicamenteuse (MDR1 / ABCB1)', categorie: 'maladie', races: 'Colley, Berger australien…' },
    { code: 'DM', nom: 'Myélopathie dégénérative (SOD1)', categorie: 'maladie' },
    { code: 'VWD', nom: 'Maladie de Von Willebrand', categorie: 'maladie' },
    { code: 'PATELLA', nom: 'Luxation de la rotule', categorie: 'maladie' },
    { code: 'TARE_OCULAIRE', nom: 'Dépistage des tares oculaires (annuel)', categorie: 'maladie' },
    { code: 'CARDIO', nom: 'Dépistage cardiaque (échocardiographie)', categorie: 'maladie' },
    { code: 'DCM', nom: 'Cardiomyopathie dilatée', categorie: 'maladie' },
    { code: 'CEA', nom: "Anomalie de l'œil du Colley (CEA)", categorie: 'maladie' },
    { code: 'ADN', nom: 'Profil ADN (identification / filiation)', categorie: 'adn' },
  ],
  chat: [
    { code: 'PKD', nom: 'Polykystose rénale (PKD1)', categorie: 'maladie', races: 'Persan, British…' },
    { code: 'HCM', nom: 'Cardiomyopathie hypertrophique', categorie: 'maladie', races: 'Maine Coon, Ragdoll…' },
    { code: 'PK_DEF', nom: 'Déficit en pyruvate kinase (PK-Def)', categorie: 'maladie' },
    { code: 'SMA', nom: 'Amyotrophie spinale', categorie: 'maladie', races: 'Maine Coon' },
    { code: 'PRA', nom: 'Atrophie rétinienne progressive (rdAc)', categorie: 'maladie', races: 'Abyssin, Somali…' },
    { code: 'GROUPE_SANGUIN', nom: 'Groupe sanguin (A / B / AB)', categorie: 'aptitude' },
    { code: 'ADN', nom: 'Profil ADN (identification / filiation)', categorie: 'adn' },
  ],
};

export const RESULTAT_LABEL: Record<string, string> = {
  clair: 'Indemne (N/N)',
  porteur: 'Porteur (hétérozygote)',
  homozygote: 'Homozygote atteint',
  atteint: 'Atteint',
  etabli: 'Établi',
  indetermine: 'En attente / indéterminé',
};

export function especeHasGenetics(espece?: string | null): boolean {
  return espece === 'cheval' || espece === 'chien' || espece === 'chat';
}

export function offspringWord(espece?: string | null): string {
  switch (espece) {
    case 'cheval': return 'poulains';
    case 'chien': return 'chiots';
    case 'chat': return 'chatons';
    default: return 'petits';
  }
}

/** Classes Tailwind (fond + texte) pour une puce de résultat. */
export function resultatChipClass(resultat?: string | null): string {
  switch (resultat) {
    case 'clair':
    case 'etabli':
      return 'bg-[#EEF5EA] text-[#4d7a3c]';
    case 'porteur':
      return 'bg-[#FFF4E5] text-[#B45309]';
    case 'atteint':
    case 'homozygote':
      return 'bg-[#FDECEC] text-[#C0392B]';
    default:
      return 'bg-gray-100 text-gray-500';
  }
}

export function testChipLabel(t: TestGenetique): string {
  const nom = t.nom ?? 'Test';
  const geno = (t.genotype ?? '').trim();
  if (geno) return `${nom} (${geno})`;
  if (t.resultat) return `${nom} — ${RESULTAT_LABEL[t.resultat] ?? t.resultat}`;
  return nom;
}
