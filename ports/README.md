# Portages du pipeline

Le même pipeline (état final de l'atelier, étape 7) écrit pour trois autres
outils. Les scripts `ci/*.sh` ne changent pas : seul le fichier qui décrit
l'enchaînement des étapes est réécrit.

| Outil | Fichier | Où le mettre |
|---|---|---|
| GitLab CI | `gitlab/.gitlab-ci.yml` | racine du dépôt GitLab |
| Azure DevOps | `azure-devops/azure-pipelines.yml` | racine du dépôt, puis Pipelines > New pipeline > "Existing Azure Pipelines YAML file" |
| Jenkins | `jenkins/Jenkinsfile` | racine du dépôt, job "Multibranch Pipeline" |
| TeamCity | `teamcity/settings.kts` | `.teamcity/settings.kts`, projet en "Versioned settings" Kotlin (voir `docs/ADAPTATION-TEAMCITY.md`) |

Ces fichiers sont des points de départ commentés, à adapter (nom du
registre, identifiants, labels d'agents). La table de correspondance des
concepts est dans [docs/PORTAGE.md](../docs/PORTAGE.md).

Pour GitLab.com : les runners partagés demandent une vérification du compte
(téléphone ou carte bancaire) avant le premier pipeline.
