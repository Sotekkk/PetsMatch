---
name: project-s01-s04-done
description: État d'avancement Services & Communauté — S01 à S04 terminés et pushés le 2026-05-27
metadata:
  type: project
---

S01–S04 terminés, commités et pushés sur `feature/v2-updates` le 2026-05-27.

**S01** — Profil pro : `pro_profile_edit.dart` (nouveaux champs), `main.dart` (User_Info.isPro), auto-inférence `cat_pro` + `is_pro=true` à la sauvegarde.

**S02** — Annuaire : `service_list_page.dart`, `service_detail_page.dart` (NestedScrollView + tabs), `veterinaires_page.dart` (6 catégories).

**S03** — Web : `website/src/app/services/page.tsx`, `Header.tsx` mis à jour.

**S04** — Agenda RDV : `pro_agenda.dart` (3 onglets, notes via TextFormField — pas de TextEditingController pour éviter dispose-crash), `rdv_booking_page.dart` (réservation client).

**Fix crashs notés** :
- `service_detail_page.dart` : NestedScrollView au lieu de SliverFillRemaining+TabBarView (freeze layout)
- `pro_agenda.dart` : notes dialog — TextFormField+onChanged au lieu de TextEditingController (dispose après close animation = crash)
- Casts Supabase : `num?.toInt()` pour duree_minutes, `?.toString()` pour les champs texte

**Prochain** : S05 — Accès carnet santé animal (permissions pro), table `animal_acces_pro` à créer dans Supabase.

**Why:** Session de développement intensive, tout testé sur téléphone physique.
**How to apply:** Reprendre à S05 au prochain démarrage.
