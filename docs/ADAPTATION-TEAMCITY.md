# Atelier CI/CD : adaptation pour TeamCity

Ce document adapte l'atelier aux BU qui utilisent TeamCity (JetBrains).
L'application, les scripts `ci/*.sh` et `ci/windows/*.ps1`, les étapes et
les objectifs sont ceux du guide participant (`ATELIER.md` à la racine du
dépôt modèle) : on
ne réécrit que la description du pipeline, en Kotlin DSL, dans le fichier
`.teamcity/settings.kts`.

Lisez chaque étape du guide participant pour les objectifs, les notions et
les questions ; revenez ici pour le "comment" dans TeamCity.

Corrigé complet (toutes les étapes, variante Windows comprise) :
`ports/teamcity/settings.kts` dans la branche `corrige` du dépôt modèle,
https://github.com/thy69/atelier-cicd/tree/corrige/ports/teamcity

## Ce qui change avec TeamCity

| Notion | GitHub Actions | TeamCity |
|---|---|---|
| Fichier du pipeline | `.github/workflows/pipeline.yml` (YAML) | `.teamcity/settings.kts` (Kotlin DSL), chargé via les "Versioned settings" |
| Pipeline | workflow | projet contenant une chaîne de builds ("build chain") |
| Job | job | build configuration (`BuildType`) |
| `needs:` | dépendance entre jobs | dépendance "snapshot" : même commit garanti pour toute la chaîne |
| Artefacts entre jobs | `upload-artifact` / `download-artifact` | `artifactRules` + dépendance "artifacts" |
| Sortie d'un job | `$GITHUB_OUTPUT` | `##teamcity[setParameter ...]`, lu par `%dep.<build>.<paramètre>%` |
| Déclencheur | `on: push` sur le workflow | trigger VCS **sur le dernier build de la chaîne** ; TeamCity lance les dépendances |
| Condition sur la branche | `if: github.ref == ...` | `branchFilter` de la build configuration ou du trigger |
| Machine | `runs-on:` | `requirements` : contraintes sur les agents (OS, Docker, outils) |
| Secret | `secrets.X` | paramètre `password(...)` avec un jeton `credentialsJSON:...` |
| Environnement + approbation | `environment:` + règle sur l'environnement | build configuration de type `DEPLOYMENT` + build feature `approval` |
| Un déploiement à la fois | `concurrency:` | `maxRunningBuilds = 1` (ou build feature "Shared resources") |
| Registre d'images | GHCR intégré | aucun : registre de l'entreprise (Nexus, Harbor, Artifactory...) |
| Release | release GitHub | build épinglé et taggé, avec ses artefacts |
| Protection de branche | rulesets GitHub | statut publié par TeamCity (Commit Status Publisher) + règle côté hébergeur Git |

Le point qui surprend le plus : **on déclenche la fin de la chaîne, pas le
début**. Un trigger posé sur "Déploiement production" fait tourner tout ce
dont il dépend (tests, build, sécurité, publication, staging) sur le même
commit. Sur GitHub, on déclenche le workflow et les jobs s'enchaînent ;
sur TeamCity, on demande le résultat final et TeamCity remonte la chaîne.

## Prérequis

- Un serveur TeamCity : celui de la BU (un projet de test par participant
  ou par binôme), ou une instance locale (voir ci-dessous).
- Un agent **Linux avec Docker** pour le parcours principal.
- Pour la variante Windows : un agent **Windows avec Python 3.12** dans le
  PATH.
- Un dépôt Git créé à partir du dépôt modèle, sur l'hébergeur de la BU
  (GitHub, GitLab, Azure Repos, Bitbucket) : importer
  https://github.com/thy69/atelier-cicd (branche `main`).
- Pour l'étape 4 : un registre d'images où pousser (registre de la BU, ou
  GHCR avec un jeton personnel ayant le droit `write:packages`).

### Instance locale (facultatif)

La licence TeamCity Professional, gratuite, suffit pour l'atelier
(nombre limité de build configurations et d'agents : vérifier les
conditions en vigueur). Avec Docker :

```bash
docker network create teamcity
docker run -d --name teamcity-server --network teamcity -p 8111:8111 \
  -v teamcity-data:/data/teamcity_server/datadir \
  -v teamcity-logs:/opt/teamcity/logs \
  jetbrains/teamcity-server:2026.2.1
# Agent Linux avec Docker intégré (Docker-in-Docker, d'où --privileged)
docker run -d --name teamcity-agent --network teamcity --privileged \
  -e SERVER_URL=http://teamcity-server:8111 \
  -e DOCKER_IN_DOCKER=start \
  jetbrains/teamcity-agent:2026.2.1-linux-sudo
```

Ouvrir http://localhost:8111, suivre l'assistant (base de données interne
pour un test), créer le compte administrateur, puis autoriser l'agent :
Agents > Unauthorized > Authorize.

---

## Étape 0 : créer le projet (15 min)

1. Créez votre dépôt à partir du dépôt modèle (voir prérequis).
2. Dans TeamCity : Projects > "Create project" > "From a repository URL".
   Indiquez l'URL du dépôt et un identifiant de lecture.
3. TeamCity propose de créer des build configurations détectées
   automatiquement : **refusez** (vous allez les écrire vous-même).
4. Éditez la racine VCS du projet (Project Settings > VCS Roots) :
   - Default branch : `refs/heads/main`
   - Branch specification :

     ```
     +:refs/heads/*
     +:refs/tags/(v*)
     ```

   - cochez "Use tags as branches".

   Les parenthèses gardent le `v` dans le nom de branche logique : un tag
   `v1.0.0` devient la branche `v1.0.0`, que les filtres de branches
   utiliseront.
5. Project Settings > Versioned Settings : "Synchronization enabled",
   format **Kotlin**, "Use settings from VCS". TeamCity lira désormais
   `.teamcity/settings.kts` dans votre dépôt.

À partir de là, la configuration se fait **en modifiant le fichier dans le
dépôt**, pas dans l'interface : c'est l'équivalent du YAML de GitHub. Les
écrans d'édition de TeamCity indiquent que les réglages viennent du VCS.

Astuce : pour trouver la syntaxe d'un réglage, faites-le dans l'interface
d'un projet de brouillon (sans versioned settings), puis "View DSL" en haut
à droite de l'écran d'édition.

---

## Étape 1 : premier pipeline (20 min)

Créez `.teamcity/settings.kts` :

```kotlin
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

version = "2025.11"

project {
    buildType(Test)
}

object Test : BuildType({
    name = "1. Lint et tests"

    vcs { root(DslContext.settingsRoot) }

    steps {
        script {
            name = "Lint et tests unitaires"
            scriptContent = "bash ci/lint-test.sh"
        }
    }

    triggers {
        vcs { branchFilter = "+:*" }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})
```

Si le serveur est plus ancien que 2025.11, abaissez `version` (par exemple
`"2024.12"`).

Vérifier : après le commit, TeamCity recharge les réglages (bandeau en haut
du projet), crée la build configuration "1. Lint et tests" et la lance.
Ouvrez le build, onglet "Build Log" : `7 passed`.

Puis cassez et réparez un test, comme dans le guide participant (1.3).

---

## Étape 2 : build et artefact (20 min)

À vous : ajoutez une build configuration `Build` qui

- dépend de `Test` par une dépendance snapshot ;
- lance `bash ci/build.sh` puis `bash ci/smoke-test.sh` ;
- publie `out/image.tar` comme artefact (`artifactRules`).

Déplacez le trigger VCS de `Test` vers `Build` : on déclenche la fin de la
chaîne. Ajoutez au projet le paramètre `env.IMAGE_NAME` (nom de l'image
dans votre registre).

<details>
<summary>Solution</summary>

```kotlin
project {
    params {
        param("env.IMAGE_NAME", "registry.example.com/atelier-cicd")
    }
    buildType(Test)
    buildType(Build)
}

object Build : BuildType({
    name = "2. Build de l'image"

    vcs { root(DslContext.settingsRoot) }

    artifactRules = "out/image.tar"

    steps {
        script {
            name = "Construire l'image"
            scriptContent = "bash ci/build.sh"
        }
        script {
            name = "Smoke test"
            scriptContent = "bash ci/smoke-test.sh"
        }
    }

    dependencies {
        snapshot(Test) { onDependencyFailure = FailureAction.FAIL_TO_START }
    }

    triggers {
        vcs { branchFilter = "+:*" }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})
```

(et retirer le bloc `triggers` de `Test`)
</details>

Vérifier : un commit lance `Test` puis `Build` ; l'onglet "Dependencies"
du build montre la chaîne ; l'onglet "Artifacts" contient `image.tar`.

---

## Étape 3 : SBOM et scan (25 min)

À vous : build configuration `Securite` qui récupère l'artefact de `Build`
dans `out/`, lance `ci/sbom.sh` puis `ci/scan.sh`, et publie
`out/sbom.*` et `out/vulnerabilites.txt` comme artefacts. Le trigger
passe sur `Securite`.

<details>
<summary>Solution</summary>

```kotlin
object Securite : BuildType({
    name = "3. SBOM et vulnérabilités"

    vcs { root(DslContext.settingsRoot) }

    artifactRules = """
        out/sbom.cdx.json
        out/sbom.spdx.json
        out/sbom.txt
        out/vulnerabilites.txt
    """.trimIndent()

    steps {
        script {
            name = "Générer la SBOM"
            scriptContent = "bash ci/sbom.sh"
        }
        script {
            name = "Scanner les vulnérabilités"
            scriptContent = "bash ci/scan.sh"
        }
    }

    dependencies {
        dependency(Build) {
            snapshot { onDependencyFailure = FailureAction.FAIL_TO_START }
            artifacts { artifactRules = "image.tar => out" }
        }
    }

    triggers {
        vcs { branchFilter = "+:*" }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})
```
</details>

Vérifier : `Securite` échoue, le tableau de Grype est dans le Build Log,
`vulnerabilites.txt` est dans les artefacts (TeamCity publie les
artefacts même quand le build échoue). Corrigez `requirements.txt` comme
dans le guide participant (3.3).

---

## Étape 4 : publication (15 min)

1. Créez le jeton du mot de passe du registre : Project Settings >
   Versioned Settings > "Tokens" > "Generate token for a secure value".
   Collez le mot de passe, récupérez une valeur `credentialsJSON:...`.
2. Ajoutez au projet :

   ```kotlin
   params {
       param("env.IMAGE_NAME", "registry.example.com/atelier-cicd")
       param("env.REGISTRY", "registry.example.com")
       param("env.REGISTRY_USER", "atelier-ci")
       password("env.REGISTRY_PASSWORD", "credentialsJSON:...")
   }
   ```

   Le secret n'apparaît jamais en clair, ni dans le dépôt ni dans les logs.
3. À vous : build configuration `Publish` qui

   - ne tourne que sur `main` et les tags :
     `vcs { branchFilter = "+:<default>\n+:v*" }` ;
   - dépend de `Securite` (snapshot) et récupère `image.tar` de `Build` ;
   - lance `ci/publish.sh` (argument `main`, ou `latest` sur un tag) ;
   - expose la référence de l'image publiée avec le service message
     `##teamcity[setParameter name='env.IMAGE_REF' value='...']`.

<details>
<summary>Solution</summary>

```kotlin
object Publish : BuildType({
    name = "4. Publication de l'image"

    vcs {
        root(DslContext.settingsRoot)
        branchFilter = """
            +:<default>
            +:v*
        """.trimIndent()
    }

    steps {
        script {
            name = "Publier dans le registre"
            scriptContent = """
                set -e
                branch="%teamcity.build.branch%"
                case "${'$'}branch" in
                  v*) export APP_VERSION="${'$'}branch" IMAGE_TAG="${'$'}branch"; extra=latest ;;
                  *)  extra=main ;;
                esac
                bash ci/publish.sh "${'$'}extra"
                echo "##teamcity[setParameter name='env.IMAGE_REF' value='${'$'}(cat out/image-digest.txt)']"
            """.trimIndent()
        }
    }

    dependencies {
        snapshot(Securite) { onDependencyFailure = FailureAction.FAIL_TO_START }
        dependency(Build) {
            snapshot { onDependencyFailure = FailureAction.FAIL_TO_START }
            artifacts { artifactRules = "image.tar => out" }
        }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})
```

`${'$'}` est la façon d'écrire un `$` littéral dans une chaîne Kotlin.
</details>

Ajustez les triggers : sur `Securite`, limitez aux branches de travail
(`+:*`, `-:<default>`, `-:v*`) ; `main` et les tags seront déclenchés
plus loin dans la chaîne (étapes 6 et 7). En attendant, lancez `Publish`
à la main sur `main` (bouton "Run").

Vérifier : l'image et ses tags sont dans le registre ; l'onglet
"Parameters" du build `Publish` montre `env.IMAGE_REF`.

---

## Étape 5 : protéger la branche principale (15 min)

TeamCity ne gère pas les branches : la protection se règle sur
l'hébergeur Git. Le rôle de TeamCity est de publier le statut des builds
sur chaque commit et chaque pull request.

1. Dans un projet de brouillon (sans versioned settings), ajoutez à une
   build configuration les build features "Pull Requests" et "Commit
   status publisher" pour votre hébergeur, puis "View DSL" : copiez le
   code dans `features { }` de `Securite`, avec des jetons
   `credentialsJSON:...` à la place des mots de passe.
2. Sur l'hébergeur Git, rendez obligatoire le statut publié par
   TeamCity pour fusionner sur `main` (GitHub : ruleset ; GitLab :
   "Pipelines must succeed" avec un pipeline externe ; Azure Repos :
   branch policy "Status check" ; Bitbucket : "Minimum successful builds").
3. Testez avec une pull request qui casse un test (guide participant, 5.2).

---

## Étape 6 : déploiements (25 min)

À vous : deux build configurations de type `DEPLOYMENT`.

- `DeployStaging` : sur `<default>` uniquement, dépend de `Publish`,
  lance `bash ci/deploy.sh staging "$IMAGE_REF"`. La valeur vient de
  `Publish` : `param("env.IMAGE_REF", "${Publish.depParamRefs["env.IMAGE_REF"]}")`.
- `DeployProduction` : idem avec `production`, dépend de `DeployStaging`
  et de `Publish`, et porte la build feature `approval`.
- Le trigger VCS de `main` se pose sur `DeployProduction`.

<details>
<summary>Solution</summary>

```kotlin
import jetbrains.buildServer.configs.kotlin.buildFeatures.approval

object DeployStaging : BuildType({
    name = "5. Déploiement staging"
    type = BuildTypeSettings.Type.DEPLOYMENT
    maxRunningBuilds = 1

    vcs {
        root(DslContext.settingsRoot)
        branchFilter = "+:<default>"
    }

    params {
        param("env.IMAGE_REF", "${Publish.depParamRefs["env.IMAGE_REF"]}")
    }

    steps {
        script {
            name = "Déployer sur staging"
            scriptContent = "bash ci/deploy.sh staging \"${'$'}IMAGE_REF\""
        }
    }

    dependencies {
        snapshot(Publish) { onDependencyFailure = FailureAction.FAIL_TO_START }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

object DeployProduction : BuildType({
    name = "6. Déploiement production"
    type = BuildTypeSettings.Type.DEPLOYMENT
    maxRunningBuilds = 1

    vcs {
        root(DslContext.settingsRoot)
        branchFilter = "+:<default>"
    }

    params {
        param("env.IMAGE_REF", "${Publish.depParamRefs["env.IMAGE_REF"]}")
    }

    steps {
        script {
            name = "Déployer en production"
            scriptContent = "bash ci/deploy.sh production \"${'$'}IMAGE_REF\""
        }
    }

    features {
        approval {
            approvalRules = "user:VOTRE_LOGIN"
        }
    }

    dependencies {
        snapshot(DeployStaging) { onDependencyFailure = FailureAction.FAIL_TO_START }
        snapshot(Publish) { onDependencyFailure = FailureAction.FAIL_TO_START }
    }

    triggers {
        vcs { branchFilter = "+:<default>" }
    }

    requirements {
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})
```
</details>

Vérifier : un commit sur `main` fait tourner toute la chaîne jusqu'à
staging ; le build de production attend dans la file avec le statut
"waiting for approval". Approuvez-le depuis la file d'attente. Comparez
l'image déployée dans les deux logs : même digest. Les builds de type
"Deployment" apparaissent avec un historique dédié.

Les règles d'approbation acceptent `user:<login>` (une ligne par
utilisateur) ou `group:<CLE_DU_GROUPE>:<nombre d'approbations>`.

---

## Étape 7 : release (10 min)

À vous : build configuration `Release` déclenchée sur les tags
(`branchFilter = "+:v*"` pour la vcs et le trigger), qui dépend de
`Publish` et récupère la SBOM de `Securite` comme artefacts.

Corrigé : objet `Release` de `ports/teamcity/settings.kts`.

Posez un tag `v1.0.0` sur `main` et poussez-le. Vérifier : la chaîne
tourne sur la branche logique `v1.0.0`, l'image porte les tags `v1.0.0` et
`latest`, le build `Release` contient la SBOM. Épinglez-le ("Pin") et
ajoutez-lui un tag `release` : il échappe ainsi au nettoyage automatique.

---

## Variante Windows (30 min)

Prérequis : un agent Windows avec Python 3.12 dans le PATH. Sur TeamCity,
pas d'équivalent de `actions/setup-python` : c'est l'agent qui fournit la
toolchain. C'est le cas typique de "l'agent outillé" de la présentation :
l'agent doit être construit par script, et déclarer ce qu'il sait faire.

Bonne pratique : ajouter dans `buildAgent.properties` de l'agent une
propriété, par exemple `python.version=3.12`, et l'exiger dans le DSL
avec `equals("python.version", "3.12")` dans `requirements`.

Corrigé : objets `WindowsTest`, `WindowsPaquet` et `WindowsSecurite` de
`ports/teamcity/settings.kts`. Les étapes utilisent le runner
`powerShell` avec `scriptMode = file { path = "ci/windows/test.ps1" }`.

---

## Pièges fréquents

| Symptôme | Cause | Solution |
|---|---|---|
| Les réglages ne se chargent pas, bandeau rouge sur le projet | erreur de compilation du DSL | lire le détail du bandeau ; vérifier les imports et la valeur de `version` |
| `Unsupported DSL version` | `version` plus récente que le serveur | abaisser `version` |
| Aucun build ne part après un commit | trigger absent, ou posé sur un build dont le filtre exclut la branche | un trigger sur la fin de chaque chaîne, avec le bon `branchFilter` |
| `Publish` ou les déploiements ne tournent jamais sur un tag | branche logique sans le `v` | branch specification `+:refs/tags/(v*)` avec parenthèses, et "Use tags as branches" |
| Le build reste "waiting for approval" sans possibilité d'approuver | l'utilisateur n'est pas dans les règles, ou n'a pas le droit "Run build" | corriger `approvalRules` ; rôle "Project developer" au minimum |
| `image.tar` introuvable dans `Securite` | règle d'artefact différente entre publication et dépendance | `artifactRules = "out/image.tar"` d'un côté, `"image.tar => out"` de l'autre |
| `docker: command not found` ou démon inaccessible | build parti sur un agent sans Docker | `requirements` ; agent `-linux-sudo` lancé avec `--privileged` et `DOCKER_IN_DOCKER=start` |
| Le mot de passe du registre apparaît comme `credentialsJSON:...` dans le script | jeton généré dans un autre projet | générer le jeton dans ce projet (Versioned Settings > Tokens) |
| Une modification faite dans l'interface disparaît | les réglages viennent du dépôt | modifier `settings.kts`, pas l'interface |
