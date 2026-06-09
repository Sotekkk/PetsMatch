# Registre des activités de traitement — PetsMatch
### Article 30 du Règlement Général sur la Protection des Données (RGPD UE 2016/679)

---

## Informations sur le responsable de traitement

| Champ | Valeur |
|---|---|
| **Dénomination** | PetsMatch (SAS — statuts en cours de refonte, 4 actionnaires) |
| **Siège social** | *(à compléter après refonte des statuts)* |
| **SIRET** | *(à compléter — ancienne entité : RCS 931 344 816)* |
| **Représentant légal** | *(à compléter — Directeur/Président à désigner dans les nouveaux statuts)* |
| **Contact RGPD** | contact@petsmatch.fr |
| **DPO (Délégué Protection Données)** | Non désigné *(obligatoire si traitement à grande échelle de données sensibles — à évaluer)* |
| **Dernière mise à jour** | Juin 2026 — **BROUILLON** |

> **Note :** Ce registre doit être tenu à jour et présenté à la CNIL sur demande. Il est confidentiel (usage interne uniquement).

---

## Activités de traitement

---

### 1. Gestion des comptes utilisateurs

| Champ | Détail |
|---|---|
| **Finalité** | Création et gestion de comptes, authentification, communication avec les utilisateurs |
| **Base légale** | Exécution d'un contrat (art. 6.1.b RGPD) |
| **Personnes concernées** | Particuliers, éleveurs, professionnels inscrits sur PetsMatch |
| **Catégories de données** | Nom, prénom, date de naissance, adresse email, mot de passe (haché par Firebase), numéro de téléphone, adresse postale, photo de profil, rôle (particulier/éleveur/pro), `cgu_accepted_at` |
| **Destinataires** | Équipe PetsMatch (admin), sous-traitants Firebase et Supabase |
| **Transferts hors UE** | Firebase (Google LLC, USA) — clauses contractuelles types |
| **Durée de conservation** | Durée du compte + 3 ans après clôture |
| **Mesures de sécurité** | Authentification Firebase, hachage mot de passe, HTTPS, RLS Supabase |

---

### 2. Publication et gestion d'annonces éleveurs

| Champ | Détail |
|---|---|
| **Finalité** | Permettre aux éleveurs de publier des annonces de cession d'animaux et aux particuliers de les consulter |
| **Base légale** | Exécution d'un contrat (art. 6.1.b) |
| **Personnes concernées** | Éleveurs inscrits |
| **Catégories de données** | Nom de l'élevage, SIRET, localisation (ville/département), espèces et races proposées, photos des animaux, prix, description, coordonnées de contact |
| **Destinataires** | Public (annonces visibles sans compte), équipe PetsMatch |
| **Transferts hors UE** | Supabase (stockage données) — décision d'adéquation ou clauses types |
| **Durée de conservation** | Durée de publication + 1 an après expiration de l'annonce |
| **Mesures de sécurité** | Modération des contenus, HTTPS |

---

### 3. Messagerie entre utilisateurs

| Champ | Détail |
|---|---|
| **Finalité** | Permettre la communication directe entre acheteurs/vendeurs et entre clients et professionnels |
| **Base légale** | Exécution d'un contrat (art. 6.1.b) |
| **Personnes concernées** | Tous les utilisateurs inscrits |
| **Catégories de données** | Contenu des messages, horodatage, identifiants des participants |
| **Destinataires** | Émetteur et destinataire du message uniquement ; équipe admin en cas de signalement |
| **Transferts hors UE** | Firebase Firestore (Google LLC, USA) — clauses contractuelles types |
| **Durée de conservation** | 3 ans après le dernier message ou clôture du compte |
| **Mesures de sécurité** | Accès restreint par règles Firestore (uid), HTTPS |

---

### 4. Carnet de santé animal

| Champ | Détail |
|---|---|
| **Finalité** | Permettre aux propriétaires/éleveurs de tenir un carnet de santé numérique pour leurs animaux et d'en partager l'accès à des vétérinaires autorisés |
| **Base légale** | Exécution d'un contrat (art. 6.1.b) ; consentement pour le partage avec le vétérinaire (art. 6.1.a) |
| **Personnes concernées** | Éleveurs, particuliers propriétaires d'animaux ; vétérinaires autorisés |
| **Catégories de données** | Données de l'animal (nom, espèce, race, sexe, identification/puce, date de naissance) ; données de santé (vaccinations, traitements, visites, vermifuges, antiparasitaires, allergies, poids) ; nom du vétérinaire intervenant ; ordonnances (PDF) |
| **Destinataires** | Propriétaire de l'animal ; vétérinaires explicitement autorisés (`vet_access_grants`) ; équipe PetsMatch (admin) |
| **Transferts hors UE** | Supabase (données) ; Firebase Storage (PDFs) — clauses contractuelles types |
| **Durée de conservation** | Durée du compte + 5 ans (valeur légale du carnet de santé) |
| **Mesures de sécurité** | RLS Supabase par `uid`, accès vétérinaire soumis à autorisation explicite du propriétaire, token 72h pour accès temporaire |

> ⚠️ **Attention :** Les données de santé des animaux ne sont pas des données de santé humaines au sens du RGPD (art. 9). Cependant, le nom du vétérinaire et les pathologies peuvent indirectement concerner des personnes physiques — traiter avec précaution.

---

### 5. Signalement d'animaux perdus / trouvés

| Champ | Détail |
|---|---|
| **Finalité** | Permettre aux utilisateurs de signaler des animaux perdus ou trouvés et de les localiser |
| **Base légale** | Intérêt légitime (art. 6.1.f) — aide aux animaux perdus |
| **Personnes concernées** | Utilisateurs signalant un animal (perdus/trouvés) |
| **Catégories de données** | Photo de l'animal, localisation approximative (commune/département), description, coordonnées de contact de la personne signalant |
| **Destinataires** | Tous les utilisateurs de la zone géographique concernée (notification) ; équipe PetsMatch |
| **Transferts hors UE** | Firebase (notifications) — clauses contractuelles types |
| **Durée de conservation** | Jusqu'à clôture de l'alerte par l'utilisateur + 1 an |
| **Mesures de sécurité** | Localisation floue (commune, pas de coordonnées GPS exactes publiées) |

---

### 6. Agenda et rendez-vous avec professionnels

| Champ | Détail |
|---|---|
| **Finalité** | Permettre la prise de rendez-vous entre particuliers/éleveurs et professionnels (vétérinaires, toiletteurs, pensions…) |
| **Base légale** | Exécution d'un contrat (art. 6.1.b) |
| **Personnes concernées** | Utilisateurs demandant un RDV ; professionnels recevant la demande |
| **Catégories de données** | Date/heure du RDV, motif, statut (confirmé/annulé/terminé), identifiants des parties, animal concerné |
| **Destinataires** | Les deux parties au RDV ; équipe PetsMatch (admin) |
| **Transferts hors UE** | Supabase — clauses contractuelles types |
| **Durée de conservation** | 3 ans après la date du RDV |
| **Mesures de sécurité** | RLS par uid, notifications push chiffrées |

---

### 7. Paiements et facturation

| Champ | Détail |
|---|---|
| **Finalité** | Traitement des abonnements pro/éleveur et des achats ponctuels (boosts, mises en avant) |
| **Base légale** | Exécution d'un contrat (art. 6.1.b) ; obligation légale pour la facturation (art. 6.1.c) |
| **Personnes concernées** | Utilisateurs payants (éleveurs PRO/PREMIUM, professionnels abonnés) |
| **Catégories de données** | Nom, email, montant payé, référence de transaction Stripe, numéro de facture, date ; **aucune donnée bancaire stockée par PetsMatch** (gérée intégralement par Stripe) |
| **Destinataires** | Stripe Inc. (prestataire paiement) ; expert-comptable PetsMatch |
| **Transferts hors UE** | Stripe (USA) — clauses contractuelles types + Privacy Shield successeur |
| **Durée de conservation** | 10 ans (obligation comptable légale) |
| **Mesures de sécurité** | Aucune donnée bancaire ne transite ni n'est stockée par PetsMatch ; tokenisation Stripe |

---

### 8. Notifications push

| Champ | Détail |
|---|---|
| **Finalité** | Envoyer des alertes aux utilisateurs (rappels de vaccin, nouveaux messages, alertes animaux perdus, confirmation RDV) |
| **Base légale** | Consentement (art. 6.1.a) — l'utilisateur autorise les notifications dans l'app |
| **Personnes concernées** | Utilisateurs ayant activé les notifications |
| **Catégories de données** | Token FCM (identifiant d'appareil), contenu de la notification, horodatage |
| **Destinataires** | Google Firebase Cloud Messaging (FCM) |
| **Transferts hors UE** | Firebase (Google LLC, USA) — clauses contractuelles types |
| **Durée de conservation** | Token FCM conservé jusqu'à déconnexion ou désactivation des notifications |
| **Mesures de sécurité** | Token stocké dans Firestore, accès restreint par règles de sécurité |

---

### 9. Géolocalisation pour la recherche de services

| Champ | Détail |
|---|---|
| **Finalité** | Permettre aux utilisateurs de trouver des éleveurs/professionnels à proximité |
| **Base légale** | Consentement (art. 6.1.a) — permission géolocalisation demandée par l'app |
| **Personnes concernées** | Utilisateurs recherchant des services à proximité |
| **Catégories de données** | Coordonnées GPS approximatives (commune/département — jamais stockées précisément), rayon de recherche |
| **Destinataires** | PetsMatch uniquement pour le filtrage ; Google Maps API pour l'affichage |
| **Transferts hors UE** | Google LLC (USA) pour Maps API — clauses contractuelles types |
| **Durée de conservation** | Non conservée — traitement à la volée, non persisté |
| **Mesures de sécurité** | Géolocalisation demandée uniquement si nécessaire ; granularité limitée à la commune |

---

### 10. Cookies et mesure d'audience

| Champ | Détail |
|---|---|
| **Finalité** | Mesure de l'audience du site web, amélioration de l'expérience utilisateur |
| **Base légale** | Consentement (art. 6.1.a) — bandeau cookies, opt-in explicite |
| **Personnes concernées** | Visiteurs du site web PetsMatch |
| **Catégories de données** | Identifiant de cookie analytics (`_ga`), pages visitées, durée de session, type d'appareil, pays |
| **Destinataires** | Google Analytics (Google LLC, USA) ; Firebase Analytics |
| **Transferts hors UE** | Google LLC (USA) — clauses contractuelles types |
| **Durée de conservation** | 13 mois (cookies analytics), 90 jours (Firebase) |
| **Mesures de sécurité** | Consentement stocké dans `localStorage` (`pm_cookie_consent`) ; aucun cookie analytics déposé sans consentement |

---

### 11. Administration et modération

| Champ | Détail |
|---|---|
| **Finalité** | Permettre à l'équipe PetsMatch de gérer les profils pros, valider les comptes éleveurs, traiter les signalements |
| **Base légale** | Intérêt légitime (art. 6.1.f) — sécurité et intégrité de la plateforme |
| **Personnes concernées** | Tous les utilisateurs inscrits |
| **Catégories de données** | Toutes les données du compte ; logs d'actions admin (`audit_logs` — à implémenter SEC06) |
| **Destinataires** | Équipe admin PetsMatch uniquement |
| **Transferts hors UE** | Supabase, Firebase — clauses contractuelles types |
| **Durée de conservation** | Logs admin : 12 mois. Données utilisateur : durée du compte + délais légaux |
| **Mesures de sécurité** | Accès admin restreint par rôle `is_admin`, authentification renforcée recommandée |

---

## Sous-traitants (article 28 RGPD)

| Sous-traitant | Rôle | Pays | Base transfert | Lien DPA |
|---|---|---|---|---|
| **Google Firebase** | Auth, Firestore, Storage, FCM, Analytics | USA | Clauses contractuelles types | [firebase.google.com/support/privacy](https://firebase.google.com/support/privacy) |
| **Supabase Inc.** | Base de données PostgreSQL, Storage | Singapour / UE | Clauses contractuelles types | [supabase.com/privacy](https://supabase.com/privacy) |
| **Vercel Inc.** | Hébergement site web Next.js | USA | Clauses contractuelles types | [vercel.com/legal/privacy-policy](https://vercel.com/legal/privacy-policy) |
| **Stripe Inc.** | Traitement des paiements | USA | Clauses contractuelles types | [stripe.com/fr/privacy](https://stripe.com/fr/privacy) |
| **Google Maps / Places API** | Autocomplétion adresse, affichage carte | USA | Clauses contractuelles types | [policies.google.com/privacy](https://policies.google.com/privacy) |

---

## Droits des personnes concernées — procédure interne

| Droit | Délai | Procédure |
|---|---|---|
| Accès (art. 15) | 30 jours | Email à contact@petsmatch.fr → export manuel depuis Supabase/Firebase |
| Rectification (art. 16) | 30 jours | L'utilisateur peut modifier ses données depuis son profil ; sinon email |
| Effacement (art. 17) | 30 jours | Suppression compte → à implémenter RGPD07 (cascade Firebase + Supabase + Storage) |
| Portabilité (art. 20) | 30 jours | Export JSON → à implémenter RGPD06 |
| Opposition (art. 21) | Immédiat | Désactivation analytics via bandeau cookies ; notifications désactivables dans l'app |
| Réclamation | — | CNIL — [cnil.fr](https://www.cnil.fr/fr/plaintes) |

---

## À compléter après refonte des statuts

- [ ] **Dénomination exacte et forme juridique** de la nouvelle structure (SAS à 4 actionnaires)
- [ ] **SIRET** de la nouvelle entité
- [ ] **Adresse du siège social**
- [ ] **Représentant légal / Président** désigné dans les statuts
- [ ] **Désignation d'un DPO** (optionnel pour une PME, obligatoire si traitement à grande échelle)
- [ ] **Numéro d'enregistrement CNIL** (si applicable)
- [ ] Mettre à jour les pages `/mentions-legales`, `/cgu`, `/confidentialite` du site web avec les infos définitives
- [ ] Signature et date de validation du registre par le représentant légal

---

*Document confidentiel — usage interne — ne pas diffuser publiquement*
*Tenu à jour conformément à l'article 30 du RGPD — version juin 2026*
