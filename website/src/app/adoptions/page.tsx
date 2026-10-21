import { redirect } from 'next/navigation';

// Ancien lien « Adoptions » : les annonces d'adoption des associations sont
// dans « Trouver un animal », onglet Animaux, type Adoption.
export default function AdoptionsRedirect() {
  redirect('/annonces?type=adoption');
}
