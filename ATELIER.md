# Atelier CI/CD : construire une usine logicielle pas à pas

Durée : 2 h 30, pause de 10 minutes comprise.
Outil : GitHub Actions, compte gratuit.
Pas besoin de connaître Python : l'application tient en quelques lignes et
ne sert que de prétexte.

## Ce que vous allez construire

À la fin de l'atelier, chaque modification du code déclenchera
automatiquement la chaîne suivante :

```
 commit / PR
     |
     v
 [test] lint + tests unitaires
     |
     v
 [build] image Docker + smoke test ---> artefact "image"
     |
     v
 [securite] SBOM + scan de vulnérabilités ---> artefacts "sbom", "vulnerabilites"
     |
     v  (sur main ou sur un tag uniquement)
 [publish] image poussée dans GitHub Container Registry
     |
     +--> [deploy-staging] automatique (sur main)
     |         |
     |         v
     |    [deploy-production] après approbation manuelle
     |
     +--> [release] release GitHub + SBOM jointe (sur un tag v*)
```

## Déroulé

| Étape | Durée | Sujet |
|---|---|---|
| 0 | 10 min | Préparer son dépôt |
| 1 | 20 min | Premier pipeline : lint et tests |
| 2 | 20 min | Construire l'image, la tester, la conserver comme artefact |
| 3 | 25 min | SBOM et scan de vulnérabilités |
| | 10 min | Pause |
| 4 | 15 min | Publier l'image dans un registre |
| 5 | 15 min | Protéger la branche main |
| 6 | 25 min | Déployer sur staging puis en production |
| 7 | 10 min | Livrer une version |
| Variante Windows | 30 min | Le même pipeline sans Docker, sur un agent Windows |
| Bonus | | Pour ceux qui ont fini en avance |

Votre BU livre surtout du client lourd Windows, de l'on-premise ou du
mobile ? Faites les étapes 0 à 3, puis la variante Windows, puis reprenez
à l'étape 4 si le temps le permet. La variante est un fichier de workflow
séparé : elle ne gêne pas le reste.

## Avant de commencer

Il vous faut :

- un compte GitHub (gratuit), connecté ;
- un navigateur. Tout l'atelier peut se faire dans l'interface web de
  GitHub. Si vous préférez votre éditeur et un terminal, clonez votre dépôt
  et travaillez comme d'habitude.

Conventions de ce guide :

- `REPO_MODELE` désigne le dépôt modèle :
  https://github.com/thy69/atelier-cicd
- "Vérifier" décrit ce que vous devez voir si tout va bien.
- Les blocs "Solution" sont repliés. Essayez d'abord, dépliez ensuite.
- Les encadrés "Et chez vous ?" donnent l'équivalent dans GitLab CI,
  Azure DevOps et Jenkins. La table complète, TeamCity compris, est dans
  [docs/PORTAGE.md](docs/PORTAGE.md).
- Votre BU utilise TeamCity ? Suivez ce guide pour les objectifs, et
  [docs/ADAPTATION-TEAMCITY.md](docs/ADAPTATION-TEAMCITY.md) pour la
  syntaxe : même atelier, pipeline écrit en Kotlin DSL.

### Si vous êtes en retard

Le corrigé de chaque étape est taggé dans le dépôt modèle. Pour rattraper :

1. ouvrez `REPO_MODELE/blob/etape-N/.github/workflows/pipeline.yml`
   (remplacez N par le numéro de l'étape) ;
2. copiez son contenu dans votre propre `.github/workflows/pipeline.yml` ;
3. faites les réglages manuels de l'étape s'il y en a (environnements,
   règles de branche).

Pour voir exactement ce qu'une étape a changé :
`REPO_MODELE/compare/etape-2...etape-3`

### Éditer un fichier dans l'interface GitHub

- Créer un fichier : bouton "Add file" > "Create new file". Taper le chemin
  complet dans le nom, par exemple `.github/workflows/pipeline.yml` : les
  `/` créent les dossiers.
- Modifier un fichier : ouvrir le fichier, icône crayon.
- Enregistrer : bouton "Commit changes...". Choisir "Commit directly to the
  main branch" ou "Create a new branch" (à partir de l'étape 5).
- Pour un vrai éditeur dans le navigateur, appuyer sur la touche `.` depuis
  la page du dépôt : github.dev s'ouvre.

---

## Étape 0 : préparer son dépôt (10 min)

Objectif : avoir votre propre copie du dépôt, et comprendre ce qu'il contient.

1. Ouvrez `REPO_MODELE`.
2. Cliquez sur "Use this template" > "Create a new repository".
3. Owner : votre compte. Nom : `atelier-cicd`.
4. Visibilité : **Public**. Sur un compte gratuit, les règles d'approbation
   des environnements (étape 6) et les règles de branche (étape 5) ne
   fonctionnent que sur un dépôt public. Le code de l'atelier n'a rien de
   confidentiel.
5. Laissez "Include all branches" décoché.
6. "Create repository".

Prenez 5 minutes pour lire :

- `README.md` : le rôle de chaque fichier ;
- `Dockerfile` : trois étages, `base`, `test`, `runtime` ;
- `ci/` : un script par étape du pipeline. Ouvrez `ci/lint-test.sh` et
  `ci/build.sh` : ce ne sont que quelques commandes `docker`.

Vérifier : l'onglet "Actions" de votre dépôt indique qu'aucun workflow
n'existe encore.

Questions pour comprendre :

- Le pipeline aura-t-il besoin de Python sur la machine qui l'exécute ?
  (Non : tout se passe dans Docker. Regardez le stage `test` du Dockerfile.)
- Qu'est-ce qui changerait si l'application était en Java ?
  (Le Dockerfile. Ni les scripts, ni le pipeline.)

---

## Étape 1 : premier pipeline, lint et tests (20 min)

Objectif : à chaque commit sur `main` et à chaque pull request, lancer
automatiquement le lint et les tests unitaires.

Notions : workflow, déclencheur (trigger), job, step, runner.

### 1.1 Créer le workflow

Créez le fichier `.github/workflows/pipeline.yml` avec ce contenu :

```yaml
name: pipeline

# Déclencheurs : quand le pipeline tourne-t-il ?
on:
  push:
    branches: [main]        # chaque commit sur main
  pull_request:
    branches: [main]        # chaque PR qui vise main
  workflow_dispatch:        # bouton "Run workflow" (lancement manuel)

# Moindre privilège : le jeton du pipeline ne peut que lire le code.
permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Lint et tests unitaires
        run: bash ci/lint-test.sh
```

Commitez directement sur `main`.

Lecture du fichier :

- `on:` liste les événements qui déclenchent le pipeline.
- `jobs:` contient un job, `test`. Un job tourne sur une machine neuve
  (le runner), ici une VM Ubuntu fournie par GitHub, détruite après usage.
- `steps:` s'exécutent dans l'ordre, sur cette machine. `uses:` appelle une
  action toute faite (ici : cloner le dépôt), `run:` lance une commande.

### 1.2 Regarder le pipeline tourner

Onglet "Actions" > cliquez sur le run en cours > job `test`. Dépliez les
étapes et lisez les logs : construction de l'image de test, puis
`ruff check` et `pytest`.

Vérifier : le run passe au vert en 1 à 2 minutes ; on voit
`7 passed` dans les logs.

### 1.3 Casser le build (volontairement)

1. Modifiez `app/greeting.py` : remplacez `Bonjour` par `Salut` dans la
   dernière ligne (`return f"Salut {cleaned} !"`).
2. Commitez sur `main`.
3. Observez : le run passe au rouge. Trouvez dans les logs quel test
   échoue et pourquoi.
4. Réparez : soit vous remettez `Bonjour`, soit vous mettez à jour les tests
   dans `tests/test_greeting.py` et `tests/test_api.py`. Commitez.

Vérifier : le dernier run est vert. GitHub vous a peut-être envoyé un mail
pour le run en échec : c'est la boucle de retour rapide de l'intégration
continue.

Questions pour comprendre :

- Le lint et les tests tournent dans un conteneur. Quel intérêt, quand le
  développeur a déjà Python sur son poste ?
- Que se passerait-il si on lançait les tests une fois par semaine au lieu
  de les lancer à chaque commit ?

> **Et chez vous ?**
> GitLab : fichier `.gitlab-ci.yml`, un job avec `script: - bash ci/lint-test.sh`.
> Azure DevOps : `azure-pipelines.yml`, `trigger:` + un `script:`.
> Jenkins : `Jenkinsfile`, `stage('test') { steps { sh 'bash ci/lint-test.sh' } }`.

---

## Étape 2 : construire l'image et la conserver (20 min)

Objectif : si les tests passent, construire l'image Docker finale, vérifier
qu'elle démarre, et la conserver comme artefact du pipeline.

Notions : dépendance entre jobs, artefact, rétention, smoke test.

### 2.1 À vous

Ajoutez dans `pipeline.yml` :

1. au niveau racine (à côté de `permissions:`), une section `env:` qui
   définit `IMAGE_NAME: ghcr.io/${{ github.repository }}`. Les scripts
   utilisent cette variable pour nommer l'image ;
2. un second job `build` qui :
   - ne démarre que si `test` a réussi (mot-clé `needs:`) ;
   - récupère le code ;
   - lance `bash ci/build.sh` (produit `out/image.tar`) ;
   - lance `bash ci/smoke-test.sh` (démarre l'image et appelle `/health`) ;
   - téléverse `out/image.tar` comme artefact nommé `image`, conservé 3 jours,
     avec l'action `actions/upload-artifact@v7`.

Indices :

- `needs: test` se place au même niveau que `runs-on:`.
- L'action d'upload prend ses paramètres sous `with:` : `name`, `path`,
  `retention-days`.

<details>
<summary>Solution</summary>

```yaml
env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}

jobs:
  test:
    # ... inchangé ...

  build:
    needs: test               # ne démarre que si "test" est vert
    runs-on: ubuntu-latest
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Construire l'image
        run: bash ci/build.sh

      - name: Smoke test
        run: bash ci/smoke-test.sh

      - name: Conserver l'image comme artefact
        uses: actions/upload-artifact@v7
        with:
          name: image
          path: out/image.tar
          retention-days: 3   # rétention courte : l'image sera dans le registre
```

Fichier complet : `REPO_MODELE/blob/etape-2/.github/workflows/pipeline.yml`
</details>

### 2.2 Vérifier

- La page du run affiche un graphe `test` puis `build`.
- Dans les logs de `Smoke test`, on lit les réponses de `/health`,
  `/version` et `/`. Dans `/version`, le champ `commit` contient le début du
  SHA de votre commit : la version est injectée au build.
- En bas de la page du run, section "Artifacts", l'artefact `image` est
  présent (quelques dizaines de Mo).

Questions pour comprendre :

- Pourquoi le job `build` refait-il un `checkout` alors que `test` l'a déjà
  fait ? (Chaque job tourne sur une machine neuve.)
- Pourquoi une rétention de 3 jours seulement ? Combien coûterait une image
  conservée à chaque commit pendant un an ?
- À quoi sert le smoke test, alors que les tests unitaires sont verts ?

> **Et chez vous ?**
> GitLab : `needs: [test]` et `artifacts: paths: [out/image.tar]`, `expire_in: 3 days`.
> Azure DevOps : `dependsOn: test` et une étape `publish: out/image.tar`.
> Jenkins : stages séquentiels ; `stash` / `archiveArtifacts`.

---

## Étape 3 : SBOM et scan de vulnérabilités (25 min)

Objectif : savoir exactement ce que contient l'image (SBOM) et bloquer le
pipeline si elle contient une vulnérabilité grave qu'on sait corriger.

Notions : SBOM, quality gate, artefact consommé par un autre job.

Une SBOM (Software Bill of Materials) est la liste de tous les composants
d'un logiciel, avec leurs versions : paquets du système, bibliothèques,
dépendances indirectes. Le jour où une faille est publiée sur un composant,
la SBOM répond en quelques secondes à la question "sommes-nous touchés ?".

Outils utilisés (dans des conteneurs, rien à installer) :

- Syft génère la SBOM, aux formats standards CycloneDX et SPDX ;
- Grype compare la SBOM à une base de vulnérabilités connues.

### 3.1 À vous

Ajoutez un troisième job `securite` qui :

1. démarre après `build` ;
2. récupère le code ;
3. récupère l'artefact `image` dans le dossier `out`
   (action `actions/download-artifact@v8`, paramètres `name` et `path`) ;
4. lance `bash ci/sbom.sh` ;
5. téléverse la SBOM comme artefact `sbom` (fichiers `out/sbom.cdx.json`,
   `out/sbom.spdx.json`, `out/sbom.txt`), conservée 30 jours ;
6. lance `bash ci/scan.sh` ;
7. téléverse `out/vulnerabilites.txt` comme artefact `vulnerabilites`,
   **même si le scan a échoué** (indice : `if: always()`).

<details>
<summary>Solution</summary>

```yaml
  securite:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      # On analyse l'image construite par le job "build", pas une nouvelle.
      - name: Récupérer l'image (artefact du job build)
        uses: actions/download-artifact@v8
        with:
          name: image
          path: out

      - name: Générer la SBOM
        run: bash ci/sbom.sh

      - name: Conserver la SBOM
        uses: actions/upload-artifact@v7
        with:
          name: sbom
          path: |
            out/sbom.cdx.json
            out/sbom.spdx.json
            out/sbom.txt
          retention-days: 30

      - name: Scanner les vulnérabilités
        run: bash ci/scan.sh

      - name: Conserver le rapport de vulnérabilités
        if: always()          # même (surtout) si le scan a échoué
        uses: actions/upload-artifact@v7
        with:
          name: vulnerabilites
          path: out/vulnerabilites.txt
          retention-days: 30
```

Fichier complet : `REPO_MODELE/blob/etape-3-rouge/.github/workflows/pipeline.yml`
</details>

### 3.2 Constater l'échec

Le job `securite` doit passer **au rouge**. C'est voulu : les dépendances
de `requirements.txt` ont été choisies anciennes.

Dans les logs de l'étape "Scanner les vulnérabilités", lisez le tableau :

| Colonne | Signification |
|---|---|
| `NAME` | composant vulnérable |
| `INSTALLED` | version présente dans l'image |
| `FIXED IN` | version qui corrige la faille |
| `TYPE` | `python` (dépendance de l'application), `deb` (paquet du système de l'image de base) ou `binary` (exécutable reconnu dans l'image, par exemple l'interpréteur Python lui-même) |
| `VULNERABILITY` | identifiant (CVE, GHSA) |
| `SEVERITY` | gravité |
| `EPSS` | probabilité estimée d'exploitation dans les 30 jours (et rang centile) |
| `RISK` | score combinant gravité et probabilité : utile pour prioriser |

Téléchargez l'artefact `sbom`, ouvrez `sbom.txt` : retrouvez `werkzeug` et
sa version. Ouvrez `sbom.cdx.json` : c'est le même inventaire, dans un
format standard lisible par les outils (Dependency-Track, outils des
clients, autorités).

### 3.3 Corriger

Mettez à jour `requirements.txt` en vous aidant de la colonne `FIXED IN`.
Pour gagner du temps, voici un jeu de versions corrigées :

```
flask==3.1.3
werkzeug==3.1.9
jinja2==3.1.6
markupsafe==3.0.3
itsdangerous==2.2.0
click==8.5.0
blinker==1.9.0
gunicorn==26.2.0
packaging==26.3
```

Commitez. Le pipeline relance tout : les tests vérifient que la mise à jour
ne casse rien, puis le scan repasse.

Vérifier : les trois jobs sont verts.

Après la correction, des lignes `binary` (Python) et `pip` peuvent rester
affichées en gravité Medium : elles ne bloquent pas, puisque la politique
ne bloque qu'à partir de High.

Si le scan reste rouge avec uniquement des lignes de `TYPE` `deb` ou
`binary` : la faille est dans l'image de base Python, publiée entre-temps. Prévenez
l'animateur. En attendant, vous pouvez assouplir la politique en ajoutant
`SCAN_FAIL_ON: critical` dans la section `env:` du workflow.

Questions pour comprendre :

- Pourquoi `scan.sh` ne bloque-t-il que les vulnérabilités qui ont un
  correctif (`--only-fixed`) ?
- Le scan d'aujourd'hui est vert. Le sera-t-il dans trois mois, sans
  aucune modification du code ? Que faut-il en déduire ?
- Qui, chez vous, pourrait vous demander une SBOM ?

> **Et chez vous ?**
> Les scripts sont identiques partout. GitLab propose aussi ses propres
> scanners (Container Scanning, intégrés aux offres payantes) ; Azure DevOps
> via les extensions (Microsoft Defender for DevOps, Trivy...) ; Jenkins via
> plugins ou, plus simplement, ces mêmes scripts.

---

## Pause (10 min)

---

## Étape 4 : publier l'image dans un registre (15 min)

Objectif : sur `main` et sur les tags de version, pousser l'image dans
GitHub Container Registry (ghcr.io). Jamais depuis une pull request.

Notions : registre, tag d'image, digest, droits du jeton.

### 4.1 Versionner

Remplacez la section `env:` et les déclencheurs par :

```yaml
on:
  push:
    branches: [main]
    tags: ["v*"]            # un tag git v1.2.0 produit l'image :v1.2.0
  pull_request:
    branches: [main]
  workflow_dispatch:

env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}
  SOURCE_URL: ${{ github.server_url }}/${{ github.repository }}
  # Sur un tag git : version = nom du tag. Sinon : version de développement
  # et tag d'image calculé à partir du commit (sha-xxxxxxxx, cf. ci/common.sh).
  APP_VERSION: ${{ github.ref_type == 'tag' && github.ref_name || '0.0.0-dev' }}
  IMAGE_TAG: ${{ github.ref_type == 'tag' && github.ref_name || '' }}
```

### 4.2 À vous

Ajoutez un job `publish` qui :

1. démarre après `securite`, et seulement sur un `push`
   (`if: github.event_name == 'push'`) ;
2. a le droit d'écrire dans le registre : bloc `permissions:` du job avec
   `contents: read` et `packages: write` ;
3. récupère le code et l'artefact `image` (dans `out`) ;
4. lance `ci/publish.sh` avec les variables d'environnement
   `REGISTRY: ghcr.io`, `REGISTRY_USER: ${{ github.actor }}`,
   `REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}`.
   Argument du script : `main` sur la branche main, `latest` sur un tag ;
5. expose la référence de l'image publiée (contenu de
   `out/image-digest.txt`) comme sortie du job, nommée `image`.

Le `GITHUB_TOKEN` est un jeton créé par GitHub pour chaque run, valable
quelques heures. Aucun secret à créer.

<details>
<summary>Solution</summary>

```yaml
  publish:
    needs: securite
    if: github.event_name == 'push'   # jamais depuis une PR
    runs-on: ubuntu-latest
    # Seul ce job a le droit d'écrire dans le registre.
    permissions:
      contents: read
      packages: write
    outputs:
      image: ${{ steps.push.outputs.image }}
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Récupérer l'image (artefact du job build)
        uses: actions/download-artifact@v8
        with:
          name: image
          path: out

      - name: Publier dans GitHub Container Registry
        id: push
        env:
          REGISTRY: ghcr.io
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if [ "$GITHUB_REF_TYPE" = "tag" ]; then
            bash ci/publish.sh latest
          else
            bash ci/publish.sh main
          fi
          echo "image=$(cat out/image-digest.txt)" >> "$GITHUB_OUTPUT"
```

Fichier complet : `REPO_MODELE/blob/etape-4/.github/workflows/pipeline.yml`
</details>

### 4.3 Vérifier

- Le job `publish` est vert. Ses logs se terminent par
  `Image publiée : ghcr.io/<vous>/atelier-cicd@sha256:...`.
- Sur la page d'accueil du dépôt, colonne de droite, rubrique "Packages" :
  le package `atelier-cicd` apparaît. Ouvrez-le : deux tags, `sha-xxxxxxxx`
  et `main`, pointent vers le même digest.

Questions pour comprendre :

- Le tag `main` bougera au prochain commit. Le tag `sha-xxxxxxxx`, jamais.
  Le digest `sha256:...`, par construction, jamais. Lequel utiliser pour
  déployer ?
- Pourquoi `packages: write` est-il donné au seul job `publish`, et pas en
  haut du fichier ?
- Pourquoi ne jamais publier depuis une pull request ?

> **Et chez vous ?**
> GitLab : registre intégré, identifiants fournis (`$CI_REGISTRY_USER`, `$CI_REGISTRY_PASSWORD`).
> Azure DevOps : Azure Container Registry, identifiants dans un variable group secret ou une service connection.
> Jenkins : Nexus, Harbor ou Artifactory, identifiants dans les Credentials.

---

## Étape 5 : protéger la branche main (15 min)

Objectif : plus personne ne pousse directement sur `main`. Toute
modification passe par une pull request, qui ne peut être fusionnée que si
le pipeline est vert.

Notions : pull request, statuts obligatoires, ruleset.

### 5.1 Créer la règle

Settings > Rules > Rulesets > "New ruleset" > "New branch ruleset".

- Ruleset name : `protection-main`
- Enforcement status : `Active`
- Target branches : "Add target" > "Include default branch"
- Cochez :
  - "Restrict deletions"
  - "Require a pull request before merging" (laissez 0 approbation
    requise : vous êtes seul sur votre dépôt)
  - "Require status checks to pass", puis "Add checks" : ajoutez `test`,
    `build` et `securite`
  - "Block force pushes"
- "Create".

Les noms de checks ne sont proposés que s'ils ont déjà tourné au moins une
fois : c'est le cas depuis l'étape 3.

Alternative : "New ruleset" > "Import a ruleset", avec le fichier
`REPO_MODELE/blob/etape-5/.github/rulesets/main.json`.

### 5.2 Tester avec une pull request

1. Modifiez `app/greeting.py` (par exemple `Bonjour` devient `Bienvenue`),
   **sans** mettre à jour les tests.
2. Au moment de committer, choisissez "Create a new branch" (nom :
   `bienvenue`), puis "Propose changes" et "Create pull request".
3. Observez la PR : les checks tournent, `test` échoue, le bouton de fusion
   est bloqué.
4. Sur la même branche, corrigez les tests (`tests/test_greeting.py` et
   `tests/test_api.py`). Les checks repartent et passent au vert.
5. Fusionnez la PR ("Merge pull request").

Vérifier :

- sur la PR, les jobs `publish` et suivants n'apparaissent pas ou sont
  marqués "skipped" : on ne publie rien depuis une PR ;
- après la fusion, un run démarre sur `main` et va jusqu'à `publish`.

**À partir de maintenant, toutes vos modifications passent par une branche
et une pull request.**

Questions pour comprendre :

- Qu'apporte la PR par rapport à un commit direct, quand on travaille seul ?
  Et à dix ?
- L'option "Require branches to be up to date before merging" : quel
  problème résout-elle ?

> **Et chez vous ?**
> GitLab : Settings > Repository > Protected branches, et "Pipelines must succeed" dans les réglages des merge requests.
> Azure DevOps : Repos > Branches > Branch policies > Build validation.
> Jenkins : la protection se règle sur l'hébergeur Git (GitHub, GitLab, Bitbucket) ; Jenkins remonte le statut.

---

## Étape 6 : déployer sur staging puis en production (25 min)

Objectif : chaque fusion sur `main` déploie automatiquement sur `staging`.
La même image part en `production` après une approbation humaine.

Notions : environnement, approbation, promotion, "build once, deploy many".

Le déploiement est simulé : `ci/deploy.sh` récupère l'image depuis le
registre, la démarre avec la configuration de l'environnement et vérifie
qu'elle répond. Lisez l'en-tête du script : il indique ce que serait la
vraie commande selon la cible (Kubernetes, Azure, serveur avec Docker
Compose). Le reste du pipeline serait identique.

### 6.1 Créer les environnements

Settings > Environments > "New environment".

1. `staging` : aucune règle. "Configure environment" puis "Save protection
   rules".
2. `production` : cochez "Required reviewers", ajoutez-vous comme
   approbateur. Si l'option "Prevent self-review" est présente, laissez-la
   décochée (vous êtes seul). "Save protection rules".

### 6.2 À vous

Sur une nouvelle branche, ajoutez deux jobs :

`deploy-staging` :

- démarre après `publish`, seulement sur main
  (`if: github.ref == 'refs/heads/main'`) ;
- `environment:` avec `name: staging` ;
- droits : `contents: read`, `packages: read` ;
- récupère le code, puis lance
  `bash ci/deploy.sh staging "$IMAGE_REF"` avec les mêmes variables
  `REGISTRY*` qu'à l'étape 4, plus
  `IMAGE_REF: ${{ needs.publish.outputs.image }}`.

`deploy-production` :

- démarre après `publish` et `deploy-staging` ;
- `environment:` avec `name: production` ;
- même contenu, avec `production` au lieu de `staging`.

Bonnes pratiques à appliquer :

- passer l'image par une variable d'environnement (`env:`) et l'utiliser
  comme `"$IMAGE_REF"` dans le script, plutôt que d'écrire
  `${{ needs.publish.outputs.image }}` directement dans `run:`. C'est la
  protection standard contre l'injection de commandes dans les workflows ;
- empêcher deux déploiements simultanés sur le même environnement :
  `concurrency:` avec `group: deploy-staging` et
  `cancel-in-progress: false` ;
- écrire une ligne dans le résumé du run :
  `echo "Déployé sur **staging** : \`$IMAGE_REF\`" >> "$GITHUB_STEP_SUMMARY"`.

<details>
<summary>Solution</summary>

```yaml
  # Staging : déploiement automatique à chaque commit sur main.
  deploy-staging:
    needs: publish
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: staging
    concurrency:
      group: deploy-staging   # jamais deux déploiements staging en parallèle
      cancel-in-progress: false
    permissions:
      contents: read
      packages: read
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      # L'image est passée par variable d'environnement, jamais interpolée
      # directement dans le script (protection contre l'injection).
      - name: Déployer sur staging
        env:
          REGISTRY: ghcr.io
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
          IMAGE_REF: ${{ needs.publish.outputs.image }}
        run: |
          bash ci/deploy.sh staging "$IMAGE_REF"
          echo "Déployé sur **staging** : \`$IMAGE_REF\`" >> "$GITHUB_STEP_SUMMARY"

  # Production : MÊME image (même digest) que staging, après approbation
  # manuelle. La règle d'approbation est portée par l'environnement
  # "production" (Settings > Environments), pas par ce fichier.
  deploy-production:
    needs: [publish, deploy-staging]
    runs-on: ubuntu-latest
    environment:
      name: production
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    permissions:
      contents: read
      packages: read
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Déployer en production
        env:
          REGISTRY: ghcr.io
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
          IMAGE_REF: ${{ needs.publish.outputs.image }}
        run: |
          bash ci/deploy.sh production "$IMAGE_REF"
          echo "Déployé en **production** : \`$IMAGE_REF\`" >> "$GITHUB_STEP_SUMMARY"
```

Fichier complet : `REPO_MODELE/blob/etape-6/.github/workflows/pipeline.yml`
</details>

### 6.3 Vérifier

1. Ouvrez la PR, attendez le vert, fusionnez.
2. Sur le run de `main` : `deploy-staging` passe au vert tout seul, puis
   `deploy-production` attend ("Waiting for review").
3. Cliquez sur "Review deployments", cochez `production`, "Approve and
   deploy".
4. Le résumé du run affiche les deux déploiements : comparez les deux
   références d'image. Le digest `sha256:...` est identique.
5. Page d'accueil du dépôt, colonne de droite : rubrique "Deployments",
   avec l'historique par environnement.

Questions pour comprendre :

- Pourquoi déployer en production l'image déjà testée sur staging, plutôt
  que de la reconstruire ?
- Qu'est-ce qui distingue staging de production dans ce pipeline ?
  (La variable `APP_ENV`. Dans la vraie vie : la configuration et les
  secrets de chaque environnement, jamais l'image.)
- Continuous Delivery ou Continuous Deployment : lequel avez-vous
  construit ? Que faudrait-il changer pour avoir l'autre ?

> **Et chez vous ?**
> GitLab : `environment: name: production` + `when: manual` (ou Protected environments, offres payantes).
> Azure DevOps : job `deployment` avec `environment: production`, approbation réglée dans Pipelines > Environments > Approvals and checks.
> Jenkins : un stage avec `input`.

---

## Étape 7 : livrer une version (10 min)

Objectif : poser un tag `v1.0.0` produit une image versionnée et une
release GitHub, avec la SBOM jointe.

### 7.1 À vous

Sur une nouvelle branche, ajoutez un job `release` qui :

- démarre après `securite` et `publish`, seulement sur un tag
  (`if: github.ref_type == 'tag'`) ;
- a le droit `contents: write` (créer une release) ;
- récupère l'artefact `sbom` dans `out` (pas besoin du code) ;
- crée la release avec la commande `gh` (préinstallée sur les runners),
  en lui passant `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`.

<details>
<summary>Solution</summary>

```yaml
  # Release : sur un tag git v*, publie une release GitHub avec la SBOM.
  release:
    needs: [securite, publish]
    if: github.ref_type == 'tag'
    runs-on: ubuntu-latest
    permissions:
      contents: write         # nécessaire pour créer la release
    steps:
      - name: Récupérer la SBOM (artefact du job securite)
        uses: actions/download-artifact@v8
        with:
          name: sbom
          path: out

      # Si la release a été créée depuis l'interface (ce qui crée aussi le
      # tag), on y joint simplement la SBOM. Sinon on la crée.
      - name: Créer la release (ou la compléter)
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          IMAGE_REF: ${{ needs.publish.outputs.image }}
        run: |
          if gh release view "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
            gh release upload "$GITHUB_REF_NAME" \
              out/sbom.cdx.json out/sbom.spdx.json \
              --repo "$GITHUB_REPOSITORY" --clobber
          else
            gh release create "$GITHUB_REF_NAME" \
              out/sbom.cdx.json out/sbom.spdx.json \
              --repo "$GITHUB_REPOSITORY" \
              --title "$GITHUB_REF_NAME" \
              --notes "Image : \`$IMAGE_REF\`" \
              --generate-notes
          fi
```

Fichier complet : `REPO_MODELE/blob/etape-7/.github/workflows/pipeline.yml`
</details>

Fusionnez la PR.

### 7.2 Poser le tag

Avec un terminal (clone local) :

```bash
git checkout main && git pull
git tag v1.0.0
git push origin v1.0.0
```

Sans terminal : page du dépôt > "Releases" > "Create a new release" >
"Choose a tag", tapez `v1.0.0`, "Create new tag on publish", cible `main`,
titre `v1.0.0`, "Publish release". Le pipeline démarre sur ce tag et joint
la SBOM à la release.

### 7.3 Vérifier

- Un run démarre sur `v1.0.0` : `test`, `build`, `securite`, `publish`,
  `release`. Les déploiements sont ignorés (ils ne concernent que `main`).
- Le package porte maintenant les tags `v1.0.0` et `latest`.
- La release `v1.0.0` contient `sbom.cdx.json` et `sbom.spdx.json`.
- Le `/version` de cette image renverrait `"version": "v1.0.0"`.

Bravo : vous avez une usine logicielle complète.

---

## Variante Windows : le même pipeline sans Docker (30 min)

Objectif : construire, tester, empaqueter et analyser l'application sur un
agent Windows, sans Docker, comme on le ferait pour un client lourd ou un
produit installé on-premise.

Notions : agent Windows, toolchain épinglée, paquet livrable, SBOM d'un
paquet.

Docker ne convient pas à tout : un client lourd WPF, une application
.NET Framework ou un outil d'installation sous licence se construisent
sur un agent Windows. Les principes restent les mêmes ; seuls changent
l'environnement d'exécution et la forme du livrable.

| | Parcours principal | Variante Windows |
|---|---|---|
| Agent | `ubuntu-latest` | `windows-2025` (version épinglée) |
| Toolchain | dans l'image Docker | installée par la CI, version fixée dans `.python-version` |
| Scripts | `ci/*.sh` (bash) | `ci/windows/*.ps1` (PowerShell) |
| Livrable | image Docker | paquet zip autonome (un MSI dans un vrai projet) |
| Smoke test | démarrer le conteneur | décompresser le paquet dans un dossier vierge, le démarrer |
| SBOM et scan | Syft et Grype en conteneurs | Syft et Grype en exécutables Windows |

### V.1 Lire les scripts

Ouvrez `ci/windows/`. Chaque script correspond à un script bash du
parcours principal : `test.ps1`, `package.ps1`, `smoke-test.ps1`,
`sbom.ps1`, `scan.ps1`. Lisez l'en-tête de `package.ps1` : il décrit le
contenu du paquet.

Ouvrez `.python-version` : c'est la toolchain épinglée dans le dépôt.

### V.2 À vous

Créez un second workflow, `.github/workflows/windows.yml`, avec trois
jobs :

1. `windows-test` : récupère le code, installe Python, lance
   `./ci/windows/test.ps1` ;
2. `windows-paquet` (après le test) : récupère le code, installe Python,
   lance `./ci/windows/package.ps1` puis `./ci/windows/smoke-test.ps1`,
   et conserve `out/atelier-cicd-*-win-x64.zip` comme artefact
   `paquet-windows` ;
3. `windows-securite` (après le paquet) : récupère le code et l'artefact
   `paquet-windows` dans `out`, lance `./ci/windows/sbom.ps1`, conserve la
   SBOM (artefact `sbom-windows`), lance `./ci/windows/scan.ps1`.

Indices :

- `runs-on: windows-2025` ;
- pour que toutes les commandes `run:` passent par PowerShell 7, ajoutez
  au niveau racine :

  ```yaml
  defaults:
    run:
      shell: pwsh
  ```

- installer Python à la version du dépôt :

  ```yaml
  - uses: actions/setup-python@v7
    with:
      python-version-file: .python-version
  ```

<details>
<summary>Solution</summary>

```yaml
name: pipeline-windows

on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

env:
  APP_VERSION: ${{ github.ref_type == 'tag' && github.ref_name || '0.0.0-dev' }}

defaults:
  run:
    shell: pwsh

jobs:
  windows-test:
    runs-on: windows-2025
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Installer Python (version fixée dans .python-version)
        uses: actions/setup-python@v7
        with:
          python-version-file: .python-version

      - name: Lint et tests unitaires
        run: ./ci/windows/test.ps1

  windows-paquet:
    needs: windows-test
    runs-on: windows-2025
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Installer Python (version fixée dans .python-version)
        uses: actions/setup-python@v7
        with:
          python-version-file: .python-version

      - name: Construire le paquet
        run: ./ci/windows/package.ps1

      - name: Smoke test du paquet
        run: ./ci/windows/smoke-test.ps1

      - name: Conserver le paquet comme artefact
        uses: actions/upload-artifact@v7
        with:
          name: paquet-windows
          path: out/atelier-cicd-*-win-x64.zip
          retention-days: 7

  windows-securite:
    needs: windows-paquet
    runs-on: windows-2025
    steps:
      - name: Récupérer le code
        uses: actions/checkout@v7

      - name: Récupérer le paquet
        uses: actions/download-artifact@v8
        with:
          name: paquet-windows
          path: out

      - name: Générer la SBOM du paquet
        run: ./ci/windows/sbom.ps1

      - name: Conserver la SBOM
        uses: actions/upload-artifact@v7
        with:
          name: sbom-windows
          path: |
            out/sbom.cdx.json
            out/sbom.spdx.json
            out/sbom.txt
          retention-days: 30

      - name: Scanner les vulnérabilités
        run: ./ci/windows/scan.ps1
```

Fichier complet, avec en plus la conservation des rapports et un job qui
joint le paquet à la release sur un tag :
`REPO_MODELE/blob/variante-windows/.github/workflows/windows.yml`
</details>

### V.3 Vérifier

- Deux workflows tournent maintenant sur chaque commit : `pipeline` et
  `pipeline-windows`. Comparez leurs durées : un agent Windows démarre
  plus lentement et coûte plus cher (en minutes facturées sur un dépôt
  privé).
- Téléchargez l'artefact `paquet-windows` et ouvrez le zip : `app\`,
  `lib\` (les dépendances), `version.json`, `lancer.ps1`.
- Comparez `sbom.txt` des deux pipelines. La SBOM Windows ne contient que
  les paquets Python : pas de paquets `deb`, puisqu'il n'y a pas d'image
  Linux. Mais elle ne contient pas non plus Python lui-même, que le
  paquet suppose installé sur le poste.

Questions pour comprendre :

- Python n'est pas dans le paquet, donc pas dans la SBOM. Qui est
  responsable de ses failles ? Comment le déclarer au client ?
- Le job `windows-test` installe Python à chaque run. Quelle différence
  avec un agent sur lequel Python aurait été installé à la main il y a
  deux ans ?
- Le zip n'est pas signé. Qu'en penserait le poste d'un client (alertes
  SmartScreen, politiques de sécurité) ?

### Et pour un vrai client lourd .NET ?

Le pipeline garde la même forme. Seul le contenu des scripts change :

| Script de l'atelier | Équivalent pour une application .NET (WPF, WinForms) |
|---|---|
| `.python-version` | `global.json` (version du SDK .NET), lock files NuGet |
| `test.ps1` | `dotnet test` (ou `msbuild` + `vstest.console` pour .NET Framework) |
| `package.ps1` | `dotnet publish -c Release -r win-x64`, puis MSI avec WiX (`wix build`) ou paquet MSIX |
| (nouveau) signature | `signtool sign /fd SHA256 /tr <horodatage> ...` avec un certificat en HSM, Azure Key Vault ou Azure Artifact Signing |
| `smoke-test.ps1` | `msiexec /i app.msi /qn /l*v install.log` sur une VM propre, lancement de l'exe, puis `msiexec /x` |
| `sbom.ps1` | `dotnet CycloneDX` sur la solution, ou Syft sur le dossier publié |
| `scan.ps1` | Grype sur la SBOM, ou `dotnet list package --vulnerable --include-transitive` |

---

## Bonus

Pour ceux qui ont fini en avance, dans l'ordre que vous voulez. Chaque
bonus se fait sur une branche, avec une PR.

### B1. Matrice : tester sur plusieurs versions de Python

Le Dockerfile accepte `PYTHON_VERSION` en argument. Faites tourner `test`
sur 3.12 et 3.13 en parallèle :

```yaml
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python: ["3.12", "3.13"]
    env:
      PYTHON_VERSION: ${{ matrix.python }}
    steps:
      # ... inchangé ...
```

Attention : les checks obligatoires de l'étape 5 s'appellent maintenant
`test (3.12)` et `test (3.13)`. Mettez le ruleset à jour.

### B2. Dependabot : tenir les dépendances à jour

Créez `.github/dependabot.yml` :

```yaml
version: 2
updates:
  - package-ecosystem: pip
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: docker
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
```

Dependabot ouvrira des PR de mise à jour ; votre pipeline les validera.
Activez aussi Settings > Advanced Security > "Dependabot alerts".

### B3. Détecter les secrets commités

Ajoutez une étape au job `test` (ou un job dédié) :

```yaml
      - name: Recherche de secrets
        run: docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.30.1 dir /repo -v
```

Testez : sur une branche, ajoutez un fichier `config.env` contenant
`GITHUB_TOKEN=ghp_` suivi de 36 lettres et chiffres tapés au hasard.
Le job doit échouer. Si GitHub refuse même le commit, c'est la "push
protection" de GitHub qui a fonctionné avant votre pipeline : elle se
règle dans Settings > Advanced Security (gratuite sur les dépôts publics).

### B4. Attestation de provenance (SLSA)

Prouvez que l'image a été produite par votre pipeline. Dans le job
`publish`, ajoutez aux permissions `id-token: write` et
`attestations: write`, puis après la publication :

```yaml
      - name: Extraire le digest
        id: digest
        run: echo "digest=$(cut -d@ -f2 out/image-digest.txt)" >> "$GITHUB_OUTPUT"

      - name: Attester la provenance
        uses: actions/attest-build-provenance@v4
        with:
          subject-name: ghcr.io/${{ github.repository }}
          subject-digest: ${{ steps.digest.outputs.digest }}
          push-to-registry: true
```

Vérifiez ensuite depuis un terminal :
`gh attestation verify oci://ghcr.io/<vous>/atelier-cicd:main --owner <vous>`.

### B5. Épingler les actions par SHA

`actions/checkout@v7` désigne un tag, que son auteur peut déplacer. En mars
2025, l'action populaire `tj-actions/changed-files` a été compromise ainsi :
ses tags pointaient vers un code qui affichait les secrets dans les logs.
Remplacez chaque `@v7` par le SHA complet du commit correspondant
(`uses: actions/checkout@<sha> # v7.0.1`). Dependabot (B2) sait les mettre
à jour.

### B6. Factoriser le déploiement

Les deux jobs de déploiement sont presque identiques. Créez un workflow
réutilisable `.github/workflows/deploy.yml` (déclencheur `workflow_call`,
entrées `environment` et `image`) et appelez-le deux fois depuis
`pipeline.yml` avec `uses: ./.github/workflows/deploy.yml`.

### B7. Porter le pipeline

Lisez [docs/PORTAGE.md](docs/PORTAGE.md), puis comparez votre
`pipeline.yml` avec `REPO_MODELE/tree/corrige/ports` : le même pipeline
pour GitLab CI, Azure DevOps, Jenkins et TeamCity. Si vous avez un compte GitLab.com,
importez votre dépôt ("New project" > "Import project" > "Repository by
URL") et copiez `ports/gitlab/.gitlab-ci.yml` à la racine.

### B8. Badge de statut

Ajoutez en tête du `README.md` :

```markdown
![pipeline](https://github.com/<vous>/atelier-cicd/actions/workflows/pipeline.yml/badge.svg)
```

---

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Aucun run ne démarre après le commit du workflow | fichier mal placé ou YAML invalide | vérifier le chemin exact `.github/workflows/pipeline.yml` ; l'onglet Actions signale les erreurs de syntaxe |
| `Invalid workflow file` | indentation | YAML : espaces uniquement, jamais de tabulation ; les jobs sont au même niveau que `test:` |
| `/usr/bin/env: 'bash\r': No such file or directory` | fins de ligne Windows sur un script | le `.gitattributes` force LF ; si vous avez copié un script depuis Windows, re-committez-le |
| `Artifact not found for name: image` | `needs:` manquant, ou nom d'artefact différent | le job qui télécharge doit dépendre (directement ou non) du job qui téléverse ; même `name` des deux côtés |
| `denied: installation not allowed to Create organization package` ou `permission_denied: write_package` | `packages: write` manquant dans le job `publish` | ajouter le bloc `permissions:` au job |
| `denied` au push alors que les droits sont bons | un package du même nom existe déjà, lié à un autre dépôt | page du package > "Package settings" > "Manage Actions access" : ajouter votre dépôt avec le rôle Write |
| `Resource not accessible by integration` | droits du jeton insuffisants | vérifier `permissions:` du job (ex. `contents: write` pour la release) |
| `toomanyrequests: You have reached your pull rate limit` | limite de téléchargement anonyme de Docker Hub | relancer le job un peu plus tard ("Re-run failed jobs") |
| Le scan reste rouge après la mise à jour de `requirements.txt` | vulnérabilité dans l'image de base (`TYPE` `deb`) | prévenir l'animateur ; provisoirement `SCAN_FAIL_ON: critical` dans `env:` |
| Pas de bouton d'approbation pour la production | dépôt privé, ou règle non enregistrée | le dépôt doit être public sur un compte gratuit ; vérifier Settings > Environments > production |
| Les checks ne sont pas proposés dans le ruleset | ils n'ont jamais tourné | lancer au moins un run complet, puis revenir dans le ruleset |
| Push refusé sur `main` après l'étape 5 | c'est la règle qui fonctionne | passer par une branche et une PR |
| Variante Windows, en local : `l'exécution de scripts est désactivée sur ce système` | politique d'exécution PowerShell | `powershell -ExecutionPolicy Bypass -File ci\windows\test.ps1` |
| Variante Windows, en local : smoke test en échec avec "socket interdit" | port 8080 réservé sur le poste (Hyper-V, WSL) | `$env:SMOKE_PORT = '18080'` avant de relancer |
| Variante Windows : `python` introuvable | étape `setup-python` absente du job | chaque job Windows qui appelle Python doit l'installer |
| Le job release ne démarre pas | le tag ne commence pas par `v`, ou le job `release` n'était pas encore fusionné au moment du tag | supprimer et recréer le tag après la fusion |

## Pour aller plus loin

- Documentation GitHub Actions : https://docs.github.com/actions
- Documentation GitLab CI : https://docs.gitlab.com/ci/
- Documentation Azure Pipelines : https://learn.microsoft.com/azure/devops/pipelines/
- Documentation Jenkins Pipeline : https://www.jenkins.io/doc/book/pipeline/
- Syft et Grype : https://github.com/anchore/syft et https://github.com/anchore/grype
- CycloneDX (format de SBOM) : https://cyclonedx.org
- SLSA (niveaux de sécurité de la chaîne de production) : https://slsa.dev
- OpenSSF Scorecard (évaluer la sécurité d'un dépôt) : https://scorecard.dev
