import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Politique de confidentialité — PetsMatch',
};

export default function ConfidentialitePage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
        Politique de confidentialité
      </h1>
      <p className="text-sm text-gray-400 mb-8">En vigueur au 1er juin 2026 — Conforme au RGPD (UE) 2016/679</p>

      <Section title="1. Responsable du traitement">
        <p>
          <strong>PetsMatch</strong> — Angélique Bégrand<br />
          Contact RGPD : <a href="mailto:rgpd@petsmatch.fr" className="text-[#0C5C6C] underline">rgpd@petsmatch.fr</a>
        </p>
      </Section>

      <Section title="2. Données collectées">
        <table className="w-full text-xs border-collapse mt-2">
          <thead>
            <tr className="bg-[#E8F4F6]">
              <th className="text-left p-2 border border-gray-200 font-semibold">Donnée</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Finalité</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Base légale</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Durée</th>
            </tr>
          </thead>
          <tbody className="text-gray-700">
            {[
              ['Nom, prénom, email', 'Création de compte, identification', 'Contrat', 'Durée du compte + 3 ans'],
              ['Date de naissance', 'Vérification majorité', 'Obligation légale', 'Durée du compte'],
              ['Adresse postale', 'Géolocalisation services, livraison', 'Contrat', 'Durée du compte'],
              ['Photo de profil', 'Identification visuelle', 'Consentement', 'Durée du compte'],
              ['Données animaux', 'Gestion carnet santé, annonces', 'Contrat', 'Durée du compte + 5 ans'],
              ['Token FCM (push)', 'Notifications push', 'Consentement', 'Jusqu\'à retrait'],
              ['Adresse IP', 'Sécurité, logs', 'Intérêt légitime', '12 mois'],
              ['Cookies analytics', 'Mesure d\'audience', 'Consentement', '13 mois'],
            ].map(([d, f, b, dur]) => (
              <tr key={d} className="even:bg-gray-50">
                <td className="p-2 border border-gray-200">{d}</td>
                <td className="p-2 border border-gray-200">{f}</td>
                <td className="p-2 border border-gray-200">{b}</td>
                <td className="p-2 border border-gray-200">{dur}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section title="3. Sous-traitants">
        <ul className="list-disc list-inside space-y-1">
          <li><strong>Google Firebase</strong> (authentification, push notifications, analytics) — États-Unis — <a href="https://firebase.google.com/support/privacy" className="text-[#0C5C6C] underline" target="_blank" rel="noopener noreferrer">Politique de confidentialité</a></li>
          <li><strong>Supabase</strong> (base de données) — Singapour / UE — <a href="https://supabase.com/privacy" className="text-[#0C5C6C] underline" target="_blank" rel="noopener noreferrer">Politique de confidentialité</a></li>
          <li><strong>Vercel</strong> (hébergement web) — États-Unis — <a href="https://vercel.com/legal/privacy-policy" className="text-[#0C5C6C] underline" target="_blank" rel="noopener noreferrer">Politique de confidentialité</a></li>
          <li><strong>Stripe</strong> (paiements) — États-Unis — <a href="https://stripe.com/fr/privacy" className="text-[#0C5C6C] underline" target="_blank" rel="noopener noreferrer">Politique de confidentialité</a></li>
        </ul>
        <p className="mt-2">
          Ces sous-traitants sont liés par des contrats de traitement de données conformes au RGPD
          (clauses contractuelles types ou décision d&apos;adéquation).
        </p>
      </Section>

      <Section title="4. Vos droits">
        <p>Conformément au RGPD, vous disposez des droits suivants :</p>
        <ul className="list-disc list-inside mt-2 space-y-1">
          <li><strong>Accès</strong> — obtenir une copie de vos données</li>
          <li><strong>Rectification</strong> — corriger des données inexactes</li>
          <li><strong>Effacement</strong> — demander la suppression de votre compte et vos données (art. 17)</li>
          <li><strong>Portabilité</strong> — recevoir vos données dans un format structuré (art. 20)</li>
          <li><strong>Opposition</strong> — vous opposer au traitement pour intérêt légitime</li>
          <li><strong>Limitation</strong> — limiter le traitement dans certains cas</li>
        </ul>
        <p className="mt-3">
          Pour exercer vos droits, contactez-nous à{' '}
          <a href="mailto:rgpd@petsmatch.fr" className="text-[#0C5C6C] underline">rgpd@petsmatch.fr</a>.
          Délai de réponse : 30 jours. Vous pouvez également introduire une réclamation auprès de la{' '}
          <a href="https://www.cnil.fr" className="text-[#0C5C6C] underline" target="_blank" rel="noopener noreferrer">CNIL</a>.
        </p>
      </Section>

      <Section title="5. Cookies">
        <p>
          Le site PetsMatch utilise des cookies pour le bon fonctionnement du service et la mesure d&apos;audience.
          Vous pouvez gérer vos préférences via le bandeau cookies affiché lors de votre première visite
          ou à tout moment via le lien &quot;Gestion des cookies&quot; en bas de page.
        </p>
        <table className="w-full text-xs border-collapse mt-3">
          <thead>
            <tr className="bg-[#E8F4F6]">
              <th className="text-left p-2 border border-gray-200 font-semibold">Cookie</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Type</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Durée</th>
              <th className="text-left p-2 border border-gray-200 font-semibold">Consentement requis</th>
            </tr>
          </thead>
          <tbody className="text-gray-700">
            {[
              ['Session Firebase Auth', 'Fonctionnel', 'Session', 'Non'],
              ['pm_cookie_consent', 'Préférence', '13 mois', 'Non'],
              ['_ga (Google Analytics)', 'Analytics', '13 mois', 'Oui'],
              ['_fbp (Firebase)', 'Analytics', '90 jours', 'Oui'],
            ].map(([n, t, d, c]) => (
              <tr key={n} className="even:bg-gray-50">
                <td className="p-2 border border-gray-200 font-mono">{n}</td>
                <td className="p-2 border border-gray-200">{t}</td>
                <td className="p-2 border border-gray-200">{d}</td>
                <td className="p-2 border border-gray-200">{c}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section title="6. Sécurité">
        <p>
          PetsMatch met en œuvre des mesures techniques et organisationnelles adaptées pour protéger vos données :
          chiffrement HTTPS, authentification Firebase, Row Level Security Supabase, accès restreint aux données
          par rôle. Aucun système n&apos;est infaillible ; en cas de violation de données, vous serez notifié
          conformément à l&apos;art. 34 du RGPD.
        </p>
      </Section>

      <Section title="7. Modifications">
        <p>
          Nous pouvons mettre à jour cette politique. La version en vigueur est toujours disponible sur cette page.
          Les modifications substantielles feront l&apos;objet d&apos;une notification par email.
        </p>
      </Section>

      <p className="text-xs text-gray-400 mt-12">Dernière mise à jour : juin 2026</p>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-7">
      <h2 className="text-base font-semibold text-[#0C5C6C] mb-2">{title}</h2>
      <div className="text-sm text-gray-700 leading-relaxed">{children}</div>
    </section>
  );
}
