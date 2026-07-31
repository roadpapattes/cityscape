# CityScape — Roadmap

Document de suivi vivant. On coche au fur et à mesure. Légende portée :
**back** = Django/API · **creator** = interface web créateur · **app** = application mobile Flutter (⇒ nécessite une nouvelle version / AAB).

---

## ✅ Terminé (mergé dans `main`)

- [x] **Migration SQLite → PostgreSQL** — config pilotée par env, script de bascule, sauvegardes cron, runbook *(PR #2)*
- [x] **Connexion Google** sur le web creator *(PR #3)*
- [x] **Surveys** — ajustements du questionnaire « application » + flag `hidden` + déplacement « Les indices » vers parcours *(PR #4)*
- [x] **Surveys** — notification e-mail à chaque nouvel avis *(PR #5)*
- [x] **Surveys** — correctif option « 1 » de `nb_parcours` *(PR #6)*
- [x] **Surveys** — impression PDF d'un avis *(PR #7)*
- [x] Ménage : `escape_db`/`escape_user` supprimés, branches nettoyées, VPS aligné sur `main`

---

## 🔨 Lot en cours — « UX + créateur » (un seul AAB à la fin)

### #3 — Catégorie d'âge (PEGI +3 / +12 / +18)
- [x] **back** : champ `age_rating` sur `EscapeGame` (+3/+12/+18) + migration
- [x] **back** : exposé en lecture/écriture dans `EscapeGameSerializer` + admin (filtre + formulaire)
- [ ] **creator** : sélecteur dans l'éditeur d'escape
- [ ] **app** : affichage sur la fiche + filtre au catalogue

### #4 — Icône « Historique » plus visible
- [ ] **app** : icône + libellé texte (ou coach-mark au 1ᵉʳ lancement) pour la rendre repérable

### #8a — Crédit créateur sur la fiche escape
- [x] **back** : champ `creator` (lecture seule) exposé dans `EscapeGameSerializer`
- [ ] **creator** : affichage du crédit
- [ ] **app** : afficher « Créé par … » sur la fiche descriptive

### #7 — Rejouer un escape terminé
- [ ] **décision** : un replay est-il comptabilisé dans les stats/notes ? (proposition : non → « mode entraînement »)
- [ ] **back** : autoriser une nouvelle `PlaySession` sur un escape déjà terminé
- [ ] **app** : réactiver le bouton « Démarrer » avec libellé « Rejouer »

---

## 🗓️ Backlog (priorisé)

### Moyens
- [ ] **#1 — Guidage carte in-app** : tracer l'itinéraire piéton (Directions API) sur la carte déjà intégrée, avec position live. *(≠ navigation vocale, payante.)* Prévoir un **cache d'itinéraire par escape**. Nécessite une clé API + compte de facturation Google.
- [ ] **#2 — Fond sonore** : champ `audio_url` + lib audio Flutter. Format conseillé **AAC/`.m4a`** ~96–128 kbps.
- [ ] **#8b — Crédit par image** : aujourd'hui une image = juste une URL. Ajouter un crédit par image (champs parallèles ou petit modèle `Image {url, credit}`).

### Gros — nouveaux types d'énigmes (`GameStep.answer_type`)
- [ ] **#5 — Code de César** : nouveau type + champs (message, décalage, sens) + validation moteur + **widget roue à décaler** (app).
- [ ] **#6 — Mots fléchés / casés / rébus** : rébus simple (réutilise `text`) ; grilles = gros widget de saisie. À faire après #5.

### À cadrer (session dédiée)
- [ ] **#9 — Monétisation** : achat à l'unité / abonnement / freemium ; part reversée aux créateurs ; **contrainte commission IAP** (Google Play 15 % < 1 M$/an puis 30 % ; Apple 30 %, 15 % *Small Business*). Surveiller DMA (UE) / Epic-Apple (US).

### Optionnel / futur
- [ ] **PostGIS** : passer les requêtes `nearby` de Haversine (Python) à des requêtes indexées en base (extension déjà présente sur le serveur). Rejoint le géospatial du #1.
- [ ] Archiver `db.sqlite3.backup-*` (recul suffisant).

---

## 📎 Notes de référence

- **Google Directions API** : ~5 $ / 1 000 appels au-delà du palier gratuit (~10 000 appels/mois/API, à revérifier). Affichage de la carte mobile (`google_maps_flutter`) = gratuit. Le cache d'itinéraire par escape rend le coût quasi nul à notre échelle.
- **Commissions IAP** (contenu numérique) : Google Play 15 % (< 1 M$/an) / 30 % au-delà ; Apple 30 % (15 % *Small Business Program*). Ex. escape à 10 € → ~1,50 € de commission.
