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
- [x] **Fix** : `age_rating`/`creator` absents des endpoints publics `/api/escapes` et `/api/escapes/nearby` (bug affectant l'app mobile uniquement, creator-web était correct) *(PR #9)*

### Lot « UX + créateur » *(PR #8, #10, #11)*
- [x] **#3 — Âge conseillé (PEGI +3/+12/+18)** : back (`age_rating` + migration + admin), creator-web (sélecteur), app (badge sur la fiche **+ sélecteur dans l'éditeur in-app**, ajouté après coup — manquait initialement). Filtre au catalogue mobile pas encore fait.
- [x] **#4 — Icône Historique plus visible** : icône + libellé texte dans l'AppBar de la partie.
- [x] **#8a — Crédit créateur sur la fiche escape** : back (`creator` lecture seule), creator-web (« Créé par … »), app (`EscapeDetailsPage`).
- [x] **#7 — Rejouer un escape terminé** : replay écrase la partie existante (pas de migration, note conservée via `Rating`). Bouton « Rejouer » sur la fiche escape.
- [x] **#8b — Crédit par image** : champ `image_credit` optionnel sur `EscapeGame`/`GameStep`. Exposé back (serializers, admin, endpoints publics), creator-web (`ImageUploader`), app (modèles, affichage, éditeur in-app escape + step).

### Noter un escape *(PR #12, hors backlog initial — demande ajoutée en cours de route)*
- [x] Un joueur peut noter (ou **éditer sa note**) depuis la fiche escape dès que l'escape est terminé, plus seulement depuis l'écran de victoire. Back : `CanRateView` renvoie le statut détaillé (`can_rate`/`already_rated`/`my_rating`), `RatingsListCreateView` fait un upsert. App : dialogue de notation factorisé, réutilisé par l'écran de victoire et la fiche escape.

### #5 — Énigme « Code de César »
- [x] **back** : nouveau `answer_type='cesar'` (migration), traité comme `text` dans le moteur de réponse (`SessionAnswerView`) et côté écriture créateur (`views_creator.py`) — pas de champs dédiés décalage/sens : le créateur écrit le message chiffré dans l'énoncé et la réponse déchiffrée dans `answer_text`, comme pour « Texte libre » *(scope simplifié, décidé avec Damien — pas de widget roue à décaler, pas de champs `cesar_shift`/`cesar_direction`)*.
- [x] **creator** : option « Code de César » dans le sélecteur de type + aide contextuelle.
- [x] **app** : option dans l'éditeur in-app + **clavier alphabétique custom** (A→Z) affiché au tap du champ réponse à la place du clavier système, pour faciliter la saisie du message décodé.

---

## 🗓️ Backlog (priorisé)

### Moyens
- [ ] **#1 — Guidage carte in-app** : tracer l'itinéraire piéton (Directions API) sur la carte déjà intégrée, avec position live. *(≠ navigation vocale, payante.)* Prévoir un **cache d'itinéraire par escape**. Nécessite une clé API + compte de facturation Google.
- [ ] **#2 — Fond sonore** : champ `audio_url` + lib audio Flutter. Format conseillé **AAC/`.m4a`** ~96–128 kbps.

### Gros — nouveaux types d'énigmes (`GameStep.answer_type`)
- [ ] **#6 — Mots fléchés / casés / rébus** : rébus simple (réutilise `text`) ; grilles = gros widget de saisie.

### À cadrer (session dédiée)
- [ ] **#9 — Monétisation** : achat à l'unité / abonnement / freemium ; part reversée aux créateurs ; **contrainte commission IAP** (Google Play 15 % < 1 M$/an puis 30 % ; Apple 30 %, 15 % *Small Business*). Surveiller DMA (UE) / Epic-Apple (US).

### Optionnel / futur
- [ ] **PostGIS** : passer les requêtes `nearby` de Haversine (Python) à des requêtes indexées en base (extension déjà présente sur le serveur). Rejoint le géospatial du #1.
- [ ] Archiver `db.sqlite3.backup-*` (recul suffisant).

---

## 📎 Notes de référence

- **Google Directions API** : ~5 $ / 1 000 appels au-delà du palier gratuit (~10 000 appels/mois/API, à revérifier). Affichage de la carte mobile (`google_maps_flutter`) = gratuit. Le cache d'itinéraire par escape rend le coût quasi nul à notre échelle.
- **Commissions IAP** (contenu numérique) : Google Play 15 % (< 1 M$/an) / 30 % au-delà ; Apple 30 % (15 % *Small Business Program*). Ex. escape à 10 € → ~1,50 € de commission.
