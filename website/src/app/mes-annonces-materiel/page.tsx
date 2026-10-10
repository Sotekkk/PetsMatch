import { redirect } from 'next/navigation';

// Ancien lien « Mes annonces matériel » : les annonces de matériel &
// équipements sont désormais dans « Mes annonces » (filtre Matériel).
export default function MesAnnoncesMaterielRedirect() {
  redirect('/mes-annonces?type=materiel');
}
