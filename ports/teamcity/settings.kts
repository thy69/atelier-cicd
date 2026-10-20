// Portage TeamCity (Kotlin DSL) du pipeline de l'atelier
// (équivalent de l'étape 7 et de la variante Windows).
//
// Utilisation :
//   1. copier ce fichier dans .teamcity/settings.kts à la racine du dépôt ;
//   2. dans TeamCity : "New project" > "From a repository URL", puis
//      activer les "Versioned settings" au format Kotlin, en choisissant
//      "Use settings from VCS" (TeamCity lit alors ce fichier) ;
//   3. remplacer les jetons "credentialsJSON:A_REMPLACER" par de vrais
//      jetons : Project Settings > Versioned Settings > Tokens >
//      "Generate token for a secure value" ;
//   4. dans la racine VCS du projet, mettre la "Branch specification" à
//          +:refs/heads/*
//          +:refs/tags/(v*)
//      et cocher "Use tags as branches". Les parenthèses gardent le "v"
//      dans le nom de branche logique ("v1.2.0"), utilisé par les filtres.
//
// Si le serveur est plus ancien que la version ci-dessous, abaisser la
// valeur de "version" (par exemple "2024.12").
//
// Correspondances principales avec GitHub Actions :
//   workflow                -> projet
//   job                     -> build configuration (BuildType)
//   needs                   -> dépendance "snapshot" (même commit garanti)
//   upload/download-artifact -> artifactRules + dépendance "artifacts"
//   outputs d'un job        -> service message ##teamcity[setParameter ...]
//                              lu par %dep.<build>.<paramètre>%
//   if: github.ref == ...   -> branchFilter de la build configuration
//   on: push                -> trigger VCS, posé sur la FIN de la chaîne
//   environment + approbation -> build configuration de type DEPLOYMENT
//                              + build feature "approval"
//   runs-on                 -> requirements (contraintes sur l'agent)

import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.approval
import jetbrains.buildServer.configs.kotlin.buildSteps.powerShell
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.vcs

version = "2025.11"

project {
    description = "Atelier CI/CD : usine logicielle de démonstration"

    params {
        // Lus par les scripts ci/*.sh (cf. ci/common.sh)
        param("env.IMAGE_NAME", "registry.example.com/atelier-cicd")
        param("env.REGISTRY", "registry.example.com")
        param("env.REGISTRY_USER", "atelier-ci")
        password("env.REGISTRY_PASSWORD", "credentialsJSON:A_REMPLACER")
        param("env.SOURCE_URL", "%vcsroot.url%")
    }

    // Parcours principal (agent Linux avec Docker)
    buildType(Test)
    buildType(Build)
    buildType(Securite)
    buildType(Publish)
    buildType(DeployStaging)
    buildType(DeployProduction)
    buildType(Release)

    // Variante Windows (agent Windows, sans Docker)
    buildType(WindowsTest)
    buildType(WindowsPaquet)
    buildType(WindowsSecurite)

    // Ordre d'affichage dans l'interface
    buildTypesOrder = arrayListOf(
        Test, Build, Securite, Publish, DeployStaging, DeployProduction, Release,
        WindowsTest, WindowsPaquet, WindowsSecurite,
    )
}

// ---------------------------------------------------------------------------
// Parcours principal
// ---------------------------------------------------------------------------

object Test : BuildType({
    name = "1. Lint et tests"

    vcs { root(DslContext.settingsRoot) }

    steps {
        script {
            name = "Lint et tests unitaires"
            scriptContent = "bash ci/lint-test.sh"
        }
    }

    requirements {
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

object Build : BuildType({
    name = "2. Build de l'image"

    vcs { root(DslContext.settingsRoot) }

    // L'image exportée est l'artefact transmis aux étapes suivantes.
    artifactRules = "out/image.tar"

    steps {
        script {
            name = "Version"
            // Sur un tag, la version et le tag d'image prennent le nom du tag.
            scriptContent = """
                branch="%teamcity.build.branch%"
                case "${'$'}branch" in
                  v*) echo "##teamcity[setParameter name='env.APP_VERSION' value='${'$'}branch']"
                      echo "##teamcity[setParameter name='env.IMAGE_TAG' value='${'$'}branch']" ;;
                esac
            """.trimIndent()
        }
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

    requirements {
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

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
        // On analyse l'image construite par "Build", pas une nouvelle.
        dependency(Build) {
            snapshot { onDependencyFailure = FailureAction.FAIL_TO_START }
            artifacts { artifactRules = "image.tar => out" }
        }
    }

    // Branches et pull requests : la chaîne s'arrête ici.
    // (main et les tags sont déclenchés plus loin dans la chaîne.)
    triggers {
        vcs {
            branchFilter = """
                +:*
                -:<default>
                -:v*
            """.trimIndent()
        }
    }

    // Statut sur la pull request et branches protégées : voir le README.
    // Ajouter ici les build features "pullRequests" et
    // "commitStatusPublisher" (Edit > Build Features dans l'interface,
    // puis "View DSL" pour récupérer le code adapté à votre hébergeur Git).

    requirements {
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

object Publish : BuildType({
    name = "4. Publication de l'image"

    vcs {
        root(DslContext.settingsRoot)
        // Jamais depuis une branche de travail ou une pull request.
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
                # Sortie lue par les déploiements : %dep.<Publish>.env.IMAGE_REF%
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
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

object DeployStaging : BuildType({
    name = "5. Déploiement staging"
    type = BuildTypeSettings.Type.DEPLOYMENT
    // Un seul déploiement staging à la fois
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
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
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
        // MÊME image (même digest) que staging
        param("env.IMAGE_REF", "${Publish.depParamRefs["env.IMAGE_REF"]}")
    }

    steps {
        script {
            name = "Déployer en production"
            scriptContent = "bash ci/deploy.sh production \"${'$'}IMAGE_REF\""
        }
    }

    // Le build attend dans la file qu'un approbateur le valide.
    // Remplacer par un utilisateur ou un groupe réel :
    //   "user:<login>" ou "group:<CLE_DU_GROUPE>:<nombre d'approbations>"
    features {
        approval {
            approvalRules = "user:A_REMPLACER"
        }
    }

    dependencies {
        snapshot(DeployStaging) { onDependencyFailure = FailureAction.FAIL_TO_START }
        snapshot(Publish) { onDependencyFailure = FailureAction.FAIL_TO_START }
    }

    // Commit sur main : on déclenche la FIN de la chaîne. TeamCity lance
    // toutes les dépendances (test, build, securite, publish, staging) sur
    // le même commit, puis ce build attend l'approbation.
    triggers {
        vcs {
            branchFilter = "+:<default>"
        }
    }

    requirements {
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

object Release : BuildType({
    name = "7. Release"

    vcs {
        root(DslContext.settingsRoot)
        branchFilter = "+:v*"
    }

    // Une "release" TeamCity = un build épinglé et taggé, avec ses
    // artefacts : l'image (dans le registre) et la SBOM.
    artifactRules = "sbom/** => sbom"

    steps {
        script {
            name = "Résumé de la release"
            scriptContent = """
                echo "Release %teamcity.build.branch%"
                echo "Image : ${Publish.depParamRefs["env.IMAGE_REF"]}"
                ls -l sbom
            """.trimIndent()
        }
    }

    dependencies {
        snapshot(Publish) { onDependencyFailure = FailureAction.FAIL_TO_START }
        dependency(Securite) {
            snapshot { onDependencyFailure = FailureAction.FAIL_TO_START }
            artifacts { artifactRules = "sbom.* => sbom" }
        }
    }

    // Tag v* : on déclenche la fin de la chaîne "release".
    triggers {
        vcs {
            branchFilter = "+:v*"
        }
    }

    requirements {
        // Agent Linux avec Docker (équivalent de runs-on: ubuntu-latest)
        contains("teamcity.agent.jvm.os.name", "Linux")
        exists("docker.server.version")
    }
})

// ---------------------------------------------------------------------------
// Variante Windows (sans Docker)
// ---------------------------------------------------------------------------

object WindowsTest : BuildType({
    name = "W1. Lint et tests (Windows)"

    vcs { root(DslContext.settingsRoot) }

    artifactRules = "out/tests.xml"

    steps {
        powerShell {
            name = "Lint et tests unitaires"
            scriptMode = file { path = "ci/windows/test.ps1" }
        }
    }

    requirements {
        // Agent Windows outillé : Python 3.12 dans le PATH (cf. présentation)
        contains("teamcity.agent.jvm.os.name", "Windows")
    }
})

object WindowsPaquet : BuildType({
    name = "W2. Paquet Windows"

    vcs { root(DslContext.settingsRoot) }

    artifactRules = "out/atelier-cicd-*-win-x64.zip"

    steps {
        powerShell {
            name = "Version"
            scriptMode = script {
                content = """
                    ${'$'}branch = "%teamcity.build.branch%"
                    if (${'$'}branch -like 'v*') {
                        Write-Host "##teamcity[setParameter name='env.APP_VERSION' value='${'$'}branch']"
                    }
                """.trimIndent()
            }
        }
        powerShell {
            name = "Construire le paquet"
            scriptMode = file { path = "ci/windows/package.ps1" }
        }
        powerShell {
            name = "Smoke test du paquet"
            scriptMode = file { path = "ci/windows/smoke-test.ps1" }
        }
    }

    dependencies {
        snapshot(WindowsTest) { onDependencyFailure = FailureAction.FAIL_TO_START }
    }

    requirements {
        // Agent Windows outillé : Python 3.12 dans le PATH (cf. présentation)
        contains("teamcity.agent.jvm.os.name", "Windows")
    }
})

object WindowsSecurite : BuildType({
    name = "W3. SBOM et vulnérabilités (Windows)"

    vcs { root(DslContext.settingsRoot) }

    artifactRules = """
        out/sbom.cdx.json
        out/sbom.spdx.json
        out/sbom.txt
        out/vulnerabilites.txt
    """.trimIndent()

    steps {
        powerShell {
            name = "Générer la SBOM du paquet"
            scriptMode = file { path = "ci/windows/sbom.ps1" }
        }
        powerShell {
            name = "Scanner les vulnérabilités"
            scriptMode = file { path = "ci/windows/scan.ps1" }
        }
    }

    dependencies {
        dependency(WindowsPaquet) {
            snapshot { onDependencyFailure = FailureAction.FAIL_TO_START }
            artifacts { artifactRules = "atelier-cicd-*-win-x64.zip => out" }
        }
    }

    // Toutes les branches : la chaîne Windows s'arrête ici.
    triggers {
        vcs {
            branchFilter = "+:*"
        }
    }

    requirements {
        // Agent Windows outillé : Python 3.12 dans le PATH (cf. présentation)
        contains("teamcity.agent.jvm.os.name", "Windows")
    }
})
