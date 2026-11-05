// Fiche créée par un pro (patient de clinique, pensionnaire, client sans compte) :
// uid_eleveur est le pro, qui n'est pas le propriétaire. Les notifications liées à
// l'animal vont au vrai propriétaire une fois la fiche récupérée, sinon à personne.
// Miroir site : website/src/lib/animal-proprietaire.ts.

const estFichePro = (a) => !!(a && (a.cree_par_pro_profile_id || a.client_clinique_id));

/**
 * Animal à utiliser pour un rappel : inchangé, ou avec le propriétaire réel à la
 * place du pro dans uid_eleveur ; null si la fiche de pro n'a pas de propriétaire.
 * @param {object|null|undefined} a ligne `animaux`
 * @return {object|null}
 */
function animalPourRappel(a) {
    if (!a) return null;
    if (!estFichePro(a)) return a;
    if (!a.uid_proprietaire) return null;
    return {...a, uid_eleveur: a.uid_proprietaire};
}

module.exports = {estFichePro, animalPourRappel};
