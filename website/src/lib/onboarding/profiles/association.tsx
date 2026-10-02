import { useState } from 'react';
import { OnboardingActionStep } from '@/components/onboarding/OnboardingActionStep';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { onboardingRegistry } from '../registry';
import type { OnboardingStepDef } from '../types';

// Onboarding association — docs/PetsMatch_Specs_Onboarding_Anatomie.md §4.

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

const SORTIES = ['adopte', 'transfere', 'decede'];

interface AnimalAPlacer { id: string; nom: string | null; espece: string | null }

/** Étape 3 — parcours guidé (miroir de l'appli, hebergement_guide.dart) :
 *  créer le premier hébergement / la première famille d'accueil et y placer
 *  un animal du refuge, sans quitter la configuration. */
function ChenilOuFaStep({ onNext, onSkip }: { onNext: () => void; onSkip: () => void }) {
  const { user, activeProfileId } = useAuth();
  const [mode, setMode] = useState<'choix' | 'chenil' | 'fa' | 'placer'>('choix');
  const [nom, setNom] = useState('Box 1');
  const [type, setType] = useState('box');
  const [capacite, setCapacite] = useState(1);
  const [prenomFa, setPrenomFa] = useState('');
  const [nomFa, setNomFa] = useState('');
  const [telFa, setTelFa] = useState('');
  const [emailFa, setEmailFa] = useState('');
  const [cible, setCible] = useState<{ kind: 'enclos' | 'fa'; id: string; lieu: string; max: number } | null>(null);
  const [animaux, setAnimaux] = useState<AnimalAPlacer[]>([]);
  const [choisis, setChoisis] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function chargerAnimaux() {
    if (!user) return [];
    const { data } = await supabase.from('animaux').select('id, nom, espece, statut')
      .eq('uid_eleveur', user.uid).eq('is_association', true)
      .is('enclos_id', null).is('fa_id', null).order('nom', { ascending: true });
    return ((data ?? []) as (AnimalAPlacer & { statut: string | null })[]).filter(a => !SORTIES.includes(a.statut ?? ''));
  }

  async function creerChenil() {
    if (!user || !nom.trim()) return;
    setBusy(true); setErreur(null);
    const { data, error } = await supabase.from('enclos_chenil').insert({
      nom: nom.trim(), type, capacite, uid_eleveur: user.uid,
      profile_id: activeProfileId || null, is_association: true,
    }).select('id').single();
    setBusy(false);
    if (error || !data) { setErreur(error?.message ?? 'Erreur'); return; }
    const liste = await chargerAnimaux();
    if (!liste.length) { onNext(); return; }
    setAnimaux(liste); setChoisis([]);
    setCible({ kind: 'enclos', id: data.id as string, lieu: nom.trim(), max: capacite });
    setMode('placer');
  }

  async function creerFa() {
    if (!user || !nomFa.trim()) return;
    setBusy(true); setErreur(null);
    const { data, error } = await supabase.from('familles_accueil').insert({
      association_uid: user.uid,
      ...(activeProfileId ? { association_profile_id: activeProfileId } : {}),
      prenom: prenomFa.trim(), nom: nomFa.trim(),
      telephone: telFa.trim() || null, email: emailFa.trim() || null,
      capacite_max: 1, actif: true,
    }).select('id').single();
    setBusy(false);
    if (error || !data) { setErreur(error?.message ?? 'Erreur'); return; }
    const liste = await chargerAnimaux();
    if (!liste.length) { onNext(); return; }
    setAnimaux(liste); setChoisis([]);
    setCible({ kind: 'fa', id: data.id as string, lieu: `${prenomFa} ${nomFa}`.trim(), max: 1 });
    setMode('placer');
  }

  async function placer() {
    if (!cible) return;
    setBusy(true);
    for (const id of choisis) {
      await supabase.from('animaux').update(cible.kind === 'enclos'
        ? { enclos_id: cible.id, fa_id: null }
        : { fa_id: cible.id, enclos_id: null, date_entree: new Date().toISOString().slice(0, 10) }).eq('id', id);
    }
    setBusy(false);
    onNext();
  }

  const inp = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  const btn = 'w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-semibold disabled:opacity-50';

  if (mode === 'chenil') return (
    <div className="flex flex-col gap-3 w-full max-w-md mx-auto text-left">
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E] text-center">Votre premier hébergement</h2>
      <p className="text-sm text-gray-600 text-center">Box, enclos, chatterie… vous pourrez en ajouter d&apos;autres ensuite.</p>
      <input value={nom} onChange={e => setNom(e.target.value)} className={inp} placeholder="Nom (ex : Box 1, Chatterie A)" />
      <select value={type} onChange={e => setType(e.target.value)} className={inp}>
        <option value="box">🏠 Box</option><option value="enclos">🌿 Enclos</option>
        <option value="chatterie">🐈 Chatterie</option><option value="cage">🔲 Cage</option>
      </select>
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold text-[#1F2A2E]">Capacité</span>
        <div className="flex items-center gap-3">
          <button type="button" onClick={() => setCapacite(c => Math.max(1, c - 1))} className="w-8 h-8 rounded-full border text-[#0C5C6C]">−</button>
          <span className="font-bold w-6 text-center">{capacite}</span>
          <button type="button" onClick={() => setCapacite(c => c + 1)} className="w-8 h-8 rounded-full border text-[#0C5C6C]">+</button>
        </div>
      </div>
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      <button onClick={creerChenil} disabled={busy || !nom.trim()} className={btn}>{busy ? 'Création…' : "Créer l'hébergement"}</button>
      <button onClick={() => setMode('choix')} className="text-sm text-gray-400">← Retour</button>
    </div>
  );

  if (mode === 'fa') return (
    <div className="flex flex-col gap-3 w-full max-w-md mx-auto text-left">
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E] text-center">Votre première famille d&apos;accueil</h2>
      <p className="text-sm text-gray-600 text-center">Vous pourrez la lier à un compte PetsMatch et la compléter ensuite.</p>
      <div className="flex gap-2">
        <input value={prenomFa} onChange={e => setPrenomFa(e.target.value)} className={inp} placeholder="Prénom" />
        <input value={nomFa} onChange={e => setNomFa(e.target.value)} className={inp} placeholder="Nom *" />
      </div>
      <input value={telFa} onChange={e => setTelFa(e.target.value)} className={inp} placeholder="Téléphone" type="tel" />
      <input value={emailFa} onChange={e => setEmailFa(e.target.value)} className={inp} placeholder="E-mail" type="email" />
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      <button onClick={creerFa} disabled={busy || !nomFa.trim()} className={btn}>{busy ? 'Création…' : "Créer la famille d'accueil"}</button>
      <button onClick={() => setMode('choix')} className="text-sm text-gray-400">← Retour</button>
    </div>
  );

  if (mode === 'placer' && cible) return (
    <div className="flex flex-col gap-3 w-full max-w-md mx-auto text-left">
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E] text-center">Placer un animal dans « {cible.lieu} » ?</h2>
      <p className="text-sm text-gray-600 text-center">{cible.max > 1 ? `Jusqu'à ${cible.max} animaux.` : 'Un animal.'}</p>
      <div className="max-h-64 overflow-y-auto divide-y border rounded-xl">
        {animaux.map(a => {
          const coche = choisis.includes(a.id);
          return (
            <label key={a.id} className="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-gray-50">
              <input type="checkbox" checked={coche} className="accent-[#0C5C6C]"
                onChange={() => setChoisis(c => coche ? c.filter(x => x !== a.id) : (c.length < cible.max ? [...c, a.id] : c))} />
              <span className="text-sm font-semibold text-[#1F2A2E]">{a.nom ?? 'Animal'}</span>
              <span className="text-xs text-gray-500">{a.espece}</span>
            </label>
          );
        })}
      </div>
      <button onClick={placer} disabled={busy || choisis.length === 0} className={btn}>{busy ? 'Placement…' : 'Placer'}</button>
      <button onClick={onNext} className="text-sm text-gray-400">Plus tard</button>
    </div>
  );

  return (
    <div className="flex flex-col items-center text-center gap-1 w-full max-w-md mx-auto">
      <div className="w-24 h-24 rounded-full flex items-center justify-center text-4xl mb-3" style={{ backgroundColor: `${TEAL}1A` }}>
        🏠
      </div>
      <h2 className="font-['Galey'] text-xl font-bold text-[#1F2A2E]">Comment gérez-vous vos animaux ?</h2>
      <p className="text-sm text-gray-600 leading-relaxed">
        Entre le refuge et les adoptants, familles d&apos;accueil et chenil / enclos.
      </p>
      <div className="w-full flex flex-col gap-3 mt-6">
        <button
          onClick={() => setMode('fa')}
          className="flex items-center gap-3 bg-[#6E9E571A] border border-[#6E9E57]/30 rounded-2xl p-4 text-left hover:shadow-md transition-shadow"
        >
          <span className="text-2xl">🏠</span>
          <div className="flex-1">
            <div className="font-bold text-sm text-[#6E9E57]">Familles d&apos;accueil</div>
            <div className="text-xs text-gray-600">Créer une famille d&apos;accueil et y placer un animal</div>
          </div>
          <span className="text-[#6E9E57]">→</span>
        </button>
        <button
          onClick={() => setMode('chenil')}
          className="flex items-center gap-3 bg-[#0C5C6C1A] border border-[#0C5C6C]/30 rounded-2xl p-4 text-left hover:shadow-md transition-shadow"
        >
          <span className="text-2xl">🏢</span>
          <div className="flex-1">
            <div className="font-bold text-sm text-[#0C5C6C]">Chenil / Enclos</div>
            <div className="text-xs text-gray-600">Créer un hébergement et y placer un animal</div>
          </div>
          <span className="text-[#0C5C6C]">→</span>
        </button>
        <button onClick={onNext} className="text-sm text-[#0C5C6C] font-semibold hover:underline">
          Les deux — je configure plus tard →
        </button>
        <button onClick={onSkip} className="text-sm text-gray-400 font-medium hover:text-gray-600">
          Passer pour l&apos;instant
        </button>
      </div>
    </div>
  );
}

const steps: OnboardingStepDef[] = [
  {
    key: 'profil',
    label: 'Profil',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="❤️"
        color={TEAL}
        title="Complétez votre profil association"
        description="Nom, numéro RNA, agrément préfectoral, espèces accueillies, capacité d'accueil... votre profil sera vérifié par l'équipe PetsMatch sous 48h, vous pouvez utiliser l'app pendant ce délai."
        primaryLabel="Compléter mon profil →"
        href="/profil"
        onNext={onNext}
        onSkip={onSkip}
      />
    ),
  },
  {
    key: 'animal',
    label: 'Premier animal',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="🐾"
        color={GREEN}
        title="Ajoutez un premier animal au refuge"
        description="Nom, espèce, race ou croisé, sexe, âge estimé, statut (en soin, disponible à l'adoption, en famille d'accueil)... Vous pourrez compléter sa fiche plus tard."
        primaryLabel="Ajouter cet animal →"
        href="/association/animaux/nouveau"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Passer cette étape"
      />
    ),
  },
  {
    key: 'chenil_ou_fa',
    label: 'FA / Chenil',
    render: ({ onNext, onSkip }) => <ChenilOuFaStep onNext={onNext} onSkip={onSkip} />,
  },
  {
    key: 'benevole',
    label: 'Équipe',
    render: ({ onNext, onSkip }) => (
      <OnboardingActionStep
        icon="👥"
        color={TEAL}
        title="Votre équipe peut accéder à PetsMatch"
        description="Ajoutez un bénévole ou un employé pour qu'il puisse voir les animaux et valider ses tâches."
        primaryLabel="Ajouter un bénévole →"
        href="/association/benevoles"
        onNext={onNext}
        onSkip={onSkip}
        secondaryLabel="Plus tard"
      />
    ),
  },
];

export function registerAssociationOnboarding() {
  onboardingRegistry.association = steps;
}
