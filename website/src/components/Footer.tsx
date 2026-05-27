import Link from 'next/link';
import Image from 'next/image';

export default function Footer() {
  return (
    <footer className="bg-[#1F2A2E] text-white/70 mt-16">
      <div className="max-w-6xl mx-auto px-4 py-12 grid grid-cols-1 md:grid-cols-4 gap-8">
        <div className="md:col-span-1">
          <div className="flex items-center gap-3 mb-4">
            <Image src="/Logo_pets_match_sans_fond.png" alt="PetsMatch" width={36} height={36} className="object-contain" />
            <span className="text-white font-semibold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>PetsMatch</span>
          </div>
          <p className="text-sm leading-relaxed">Connecter · Prendre soin · Partager</p>
          <p className="text-xs mt-3 text-white/40">La communauté des passionnés d'animaux</p>
        </div>

        <div>
          <h4 className="text-white font-semibold mb-3 text-sm uppercase tracking-wider">Explorer</h4>
          <ul className="space-y-2 text-sm">
            <li><Link href="/annonces" className="hover:text-white transition-colors">Annonces</Link></li>
            <li><Link href="/elevages" className="hover:text-white transition-colors">Élevages</Link></li>
            <li><Link href="/animaux-perdus" className="hover:text-white transition-colors">Animaux perdus</Link></li>
          </ul>
        </div>

        <div>
          <h4 className="text-white font-semibold mb-3 text-sm uppercase tracking-wider">Compte</h4>
          <ul className="space-y-2 text-sm">
            <li><Link href="/connexion" className="hover:text-white transition-colors">Se connecter</Link></li>
            <li><Link href="/inscription" className="hover:text-white transition-colors">S'inscrire</Link></li>
          </ul>
        </div>

        <div>
          <h4 className="text-white font-semibold mb-3 text-sm uppercase tracking-wider">Télécharger l'app</h4>
          <p className="text-sm mb-3">Disponible sur Android et iOS</p>
          <div className="flex flex-col gap-2">
            <a href="#" className="text-xs bg-white/10 hover:bg-white/20 px-3 py-2 rounded-lg transition-colors text-center">
              Google Play
            </a>
            <a href="#" className="text-xs bg-white/10 hover:bg-white/20 px-3 py-2 rounded-lg transition-colors text-center">
              App Store
            </a>
          </div>
        </div>
      </div>

      <div className="border-t border-white/10 py-4 px-4 text-center text-xs text-white/30">
        © {new Date().getFullYear()} PetsMatch. Tous droits réservés.
      </div>
    </footer>
  );
}
