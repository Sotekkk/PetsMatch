import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: "Conditions générales d'utilisation — PetsMatch",
};

export default function CguPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
        Conditions générales d&apos;utilisation
      </h1>
      <p className="text-sm text-gray-400 mb-8">En vigueur au 1er juin 2026</p>

      <Section title="1. Objet">
        <p>
          Les présentes Conditions Générales d&apos;Utilisation (CGU) régissent l&apos;accès et l&apos;utilisation de la
          plateforme PetsMatch, disponible via l&apos;application mobile et le site web, éditée par PetsMatch
          (ci-après « PetsMatch » ou « nous »).
        </p>
        <p className="mt-2">
          En créant un compte ou en utilisant la plateforme, vous acceptez sans réserve les présentes CGU.
          Si vous n&apos;acceptez pas ces conditions, veuillez ne pas utiliser la plateforme.
        </p>
      </Section>

      <Section title="2. Accès à la plateforme">
        <p>PetsMatch est accessible gratuitement à toute personne physique majeure (18 ans révolus) ou morale.</p>
        <p className="mt-2">
          L&apos;inscription requiert la création d&apos;un compte avec une adresse email valide et un mot de passe sécurisé,
          ou via Google OAuth. Vous êtes responsable de la confidentialité de vos identifiants.
        </p>
      </Section>

      <Section title="3. Description des services">
        <p>PetsMatch propose notamment :</p>
        <ul className="list-disc list-inside mt-2 space-y-1">
          <li>La mise en relation entre éleveurs certifiés et particuliers souhaitant acquérir un animal</li>
          <li>Un annuaire de professionnels animaliers (vétérinaires, toiletteurs, pensions, éducateurs...)</li>
          <li>Un outil de gestion de carnet de santé animal numérique</li>
          <li>Un système de signalement d&apos;animaux perdus ou trouvés</li>
          <li>Un agenda de rendez-vous entre particuliers/éleveurs et professionnels</li>
        </ul>
      </Section>

      <Section title="4. Obligations des utilisateurs">
        <p>En utilisant PetsMatch, vous vous engagez à :</p>
        <ul className="list-disc list-inside mt-2 space-y-1">
          <li>Fournir des informations exactes et à jour lors de votre inscription</li>
          <li>Ne pas publier de contenu illicite, trompeur, diffamatoire ou portant atteinte aux droits d&apos;autrui</li>
          <li>Ne pas usurper l&apos;identité d&apos;un tiers</li>
          <li>Respecter la réglementation en vigueur sur la cession d&apos;animaux (loi 1999, loi Drouin 2021)</li>
          <li>Ne pas contacter d&apos;autres utilisateurs à des fins commerciales non autorisées</li>
          <li>Signaler tout contenu suspect via le bouton de signalement</li>
        </ul>
      </Section>

      <Section title="5. Annonces éleveurs">
        <p>
          Les annonces publiées par les éleveurs doivent respecter la réglementation française en vigueur,
          notamment l&apos;obligation de mentionner le numéro SIREN/SIRET, le numéro d&apos;identification de l&apos;animal,
          le certificat de cession et les conditions de naissance. PetsMatch se réserve le droit de
          supprimer toute annonce ne respectant pas ces obligations.
        </p>
      </Section>

      <Section title="6. Contenu utilisateur">
        <p>
          En publiant du contenu (photos, textes, annonces, avis) sur PetsMatch, vous accordez à PetsMatch
          une licence non exclusive, mondiale et gratuite pour utiliser, reproduire et afficher ce contenu
          dans le cadre du fonctionnement de la plateforme.
        </p>
        <p className="mt-2">
          PetsMatch ne saurait être tenu responsable du contenu publié par les utilisateurs.
        </p>
      </Section>

      <Section title="7. Modération">
        <p>
          PetsMatch se réserve le droit de supprimer tout contenu ou de suspendre/bannir tout compte
          ne respectant pas les présentes CGU, sans préavis ni indemnisation. Les décisions de modération
          peuvent être contestées en contactant <a href="mailto:contact@petsmatch.fr" className="text-[#0C5C6C] underline">contact@petsmatch.fr</a>.
        </p>
      </Section>

      <Section title="8. Données personnelles">
        <p>
          La collecte et le traitement de vos données personnelles sont régis par notre{' '}
          <a href="/confidentialite" className="text-[#0C5C6C] underline">Politique de confidentialité</a>.
          Conformément au RGPD, vous disposez d&apos;un droit d&apos;accès, de rectification, d&apos;effacement,
          de portabilité et d&apos;opposition sur vos données.
        </p>
      </Section>

      <Section title="9. Responsabilité">
        <p>
          PetsMatch est une plateforme de mise en relation. PetsMatch n&apos;est pas partie aux transactions
          effectuées entre utilisateurs et n&apos;est pas responsable des actes, omissions ou défaillances des
          utilisateurs. PetsMatch ne garantit pas la continuité du service et peut le suspendre pour maintenance.
        </p>
      </Section>

      <Section title="10. Propriété intellectuelle">
        <p>
          La marque PetsMatch, le logo, la charte graphique et l&apos;ensemble des éléments de la plateforme
          sont la propriété exclusive de PetsMatch. Toute utilisation non autorisée est interdite.
        </p>
      </Section>

      <Section title="11. Modification des CGU">
        <p>
          PetsMatch se réserve le droit de modifier les présentes CGU à tout moment. Les utilisateurs seront
          informés par email ou notification push. La poursuite de l&apos;utilisation après modification vaut acceptation.
        </p>
      </Section>

      <Section title="12. Droit applicable">
        <p>
          Les présentes CGU sont régies par le droit français. Tout litige relève de la compétence
          exclusive des tribunaux français compétents.
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
