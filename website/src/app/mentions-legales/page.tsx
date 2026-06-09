import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Mentions légales — PetsMatch',
  robots: { index: false },
};

export default function MentionsLegalesPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-8" style={{ fontFamily: 'Galey, sans-serif' }}>
        Mentions légales
      </h1>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-[#0C5C6C] mb-3">Éditeur du site</h2>
        <p className="text-sm text-gray-700 leading-relaxed">
          <strong>PetsMatch</strong><br />
          Responsable de la publication : Angélique Bégrand<br />
          Email : <a href="mailto:contact@petsmatch.fr" className="text-[#0C5C6C] underline">contact@petsmatch.fr</a>
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-[#0C5C6C] mb-3">Hébergement</h2>
        <p className="text-sm text-gray-700 leading-relaxed">
          <strong>Site web :</strong> Vercel Inc., 340 Pine Street Suite 701, San Francisco, CA 94104, États-Unis<br />
          <strong>Base de données :</strong> Supabase Inc., 970 Toa Payoh North #07-04, Singapour<br />
          <strong>Authentification &amp; notifications :</strong> Google Firebase (Google LLC, 1600 Amphitheatre Parkway, Mountain View, CA 94043, États-Unis)
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-[#0C5C6C] mb-3">Propriété intellectuelle</h2>
        <p className="text-sm text-gray-700 leading-relaxed">
          L'ensemble du contenu de ce site (textes, images, logo, charte graphique) est la propriété exclusive de PetsMatch.
          Toute reproduction, représentation, modification ou exploitation, totale ou partielle, est interdite sans autorisation préalable écrite.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-[#0C5C6C] mb-3">Responsabilité</h2>
        <p className="text-sm text-gray-700 leading-relaxed">
          PetsMatch s'efforce de maintenir les informations publiées exactes et à jour, mais ne saurait être tenu responsable
          des erreurs ou omissions, ni de l'utilisation faite par des tiers des informations publiées sur la plateforme.
          Les annonces et profils publiés par les utilisateurs sont sous leur entière responsabilité.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-[#0C5C6C] mb-3">Contact</h2>
        <p className="text-sm text-gray-700 leading-relaxed">
          Pour toute question relative à ces mentions légales :{' '}
          <a href="mailto:contact@petsmatch.fr" className="text-[#0C5C6C] underline">contact@petsmatch.fr</a>
        </p>
      </section>

      <p className="text-xs text-gray-400 mt-12">Dernière mise à jour : juin 2026</p>
    </div>
  );
}
