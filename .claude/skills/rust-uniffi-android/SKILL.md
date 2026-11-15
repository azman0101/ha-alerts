---
name: rust-uniffi-android
description: Construire une app Android Jetpack Compose avec cœur Rust et bindings UniFFI (proc-macros), compiler avec cargo-ndk, produire et signer les APK localement ou via GitHub Actions, puis installer avec adb sans fil. Utiliser pour Rust sur Android, UniFFI, génération de bindings Kotlin, build APK, CI Android et continuité de signature local/CI.
---

# Rust + UniFFI → APK Android → adb

Construire ou faire évoluer une app Android avec un cœur Rust, des bindings Kotlin UniFFI et une UI Compose. Lire [references/pitfalls.md](references/pitfalls.md) lorsqu’une étape échoue.

## 1. Cadrer avant de coder
- Lire `AGENTS.md`/README du dépôt et conserver ses conventions. Si l’app utilise une API ou un appareil externe, valider les formats par des lectures sans effet de bord ; ne pas supposer que toute app nécessite du matériel réseau.
- Vérifier les outils : `cargo`, `rustup target list --installed`, `cargo-ndk`, `$ANDROID_HOME`/SDK (`sdkmanager --list_installed`), JDK 21, `adb`.

## 2. Moteur Rust
- Workspace Cargo : crate `lib` en `crate-type = ["cdylib","lib"]` + petit crate `uniffi-bindgen` (`uniffi = {features=["cli"]}`, `main() { uniffi::uniffi_bindgen_main() }`). Ainsi la feature `cli` n'alourdit pas la lib Android.
- `uniffi = {version, features=["tokio"]}`, `uniffi::setup_scaffolding!()` dans `lib.rs`. **Jamais de `.udl`** sauf demande.
- Types : `#[derive(uniffi::Record|Enum|Object)]`, erreurs `#[derive(uniffi::Error, thiserror::Error)]` (pas de champ nommé `message`). Async : `#[uniffi::export(async_runtime = "tokio")]` → `suspend fun`. Callbacks Rust→Kotlin : `#[uniffi::export(callback_interface)]` (reçu en `Box<dyn T>`, convertir en `Arc`).
- Tester le cœur Rust indépendamment du téléphone. Pour une intégration réseau, utiliser un faux serveur local ; ajouter une sonde en lecture seule seulement si elle aide à valider une API externe.

## 3. Bindings + libs Android
- Bindings (sans NDK) : `cargo build -p <crate>` puis `cargo run --bin uniffi-bindgen generate --library target/debug/lib<crate>.dylib|.so --language kotlin --out-dir android/app/src/main/java`.
- Libs : `cargo ndk -t arm64-v8a -t x86_64 -o android/app/src/main/jniLibs build -p <crate> --release`.
- Mettre ces deux étapes dans `scripts/gen-kotlin.sh` et `scripts/build-android.sh` ; ignorer `jniLibs/` et les bindings générés dans `.gitignore`.
- Dans `NOTES.md`/README, **recopier les commandes complètes** (`cargo ndk …`, `uniffi-bindgen generate --library … --language kotlin …`), pas seulement « lance le script » : le lecteur les copie-colle, et un script peut être illisible hors contexte. Ajouter les prérequis (`rustup target add …`, `cargo install cargo-ndk`, `ANDROID_NDK_HOME`) et le piège cargo Homebrew vs rustup.

## 4. Projet Gradle / APK
Si Gradle échoue sur `checkAarMetadata` (dépendance qui exige compileSdk N+1) : ne pas monter compileSdk à l'aveugle, vérifier d'abord la plateforme installée (`sdkmanager --list_installed`) ; sinon rétrograder BOM Compose / lifecycle. Détails dans `references/pitfalls.md`.

- Dépendances : `net.java.dev.jna:jna:<v>` en **`artifact { type = "aar" }`**, `kotlinx-coroutines-android`, Compose (BOM), lifecycle. `abiFilters` = cibles de cargo-ndk.
- Wrapper : télécharger Gradle dans un dossier temporaire et lancer `gradle wrapper`, sans l'installer sur le système.
- Build : `JAVA_HOME=<jdk21> ./gradlew :app:assembleDebug`. Vérifier le contenu : `unzip -l app-debug.apk | grep '\.so'` doit montrer `lib<crate>.so` **et** `libjnidispatch.so`.
- UI : Compose Material3, état dans un `ViewModel` (`StateFlow`) ; le callback UniFFI arrive sur un thread Rust → n'y faire que `state.update`.

## 5. CI GitHub Actions et identité de signature
Pour créer ou modifier un workflow APK, lire [references/github-actions-signing.md](references/github-actions-signing.md).
L'exemple complet [assets/android-apk.yml](assets/android-apk.yml) utilise `app_core` comme nom de crate illustratif : adapter les chemins, noms, module Gradle, ABIs et versions au projet. Il reste un modèle, pas un workflow actif ni une dépendance à une application particulière.

- Faire tourner les mêmes scripts localement et dans CI ; si `build-android.sh` appelle déjà `gen-kotlin.sh`, ne pas lancer ce dernier deux fois.
- Avant de signer un APK destiné à remplacer une installation existante, identifier et réutiliser son keystore. Même `applicationId` et certificat, `versionCode` non inférieur ; ne pas générer une nouvelle clé pour corriger un problème CI.
- Préserver la clé hors Git, la sauvegarder, l'envoyer via `gh secret set` seulement dans le dépôt demandé et vérifier le certificat de l'APK avec `apksigner`. Les secrets GitHub ne constituent pas une sauvegarde récupérable.
- Vérifier les `.so` Rust **et JNA pour chaque ABI**, publier un artefact nommé explicitement `shared` ou `temporary`, vérifier le résultat du run et fournir le lien de téléchargement.
- Respecter le processus de revue du dépôt et les préférences de l’utilisateur ; lorsqu’une PR est demandée, sa création n’autorise pas sa fusion.

## 6. Installation sur smartphone (adb sans fil)
1. Sur le téléphone : Options développeur → Débogage sans fil. Deux ports distincts : **appairage** (code à 6 chiffres) et **connexion** (écran principal). Ils changent à chaque activation.
2. `adb pair IP:PORT_APPAIRAGE` puis `adb connect IP:PORT_CONNEXION`. Si `connect` échoue : port périmé ou jamais appairé → demander à l'utilisateur, ne pas deviner.
3. Plusieurs entrées dans `adb devices` (mDNS, offline) : toujours `adb -s IP:PORT …` (fonction shell, pas variable contenant des arguments).
4. `adb -s … install -r app-debug.apk` → `Success`, puis `am start -n <pkg>/.MainActivity`.
5. Vérifier : `pidof`, `logcat -d | grep -E "FATAL|UnsatisfiedLink"`, `uiautomator dump` (texte + bounds), `screencap`. **Avant tout `input tap`, vérifier quelle app est au premier plan** : l'utilisateur peut manipuler le téléphone en même temps.

## 7. Prudence sur le matériel réel
Pour les apps qui pilotent un appareil externe, privilégier les simulations et les diagnostics sans effet de bord. Ne pas déduire d’une demande de développement une autorisation de modifier ou redémarrer le matériel. Libérer les ressources et verrous ouverts. Distinguer les vérifications effectuées (tests, build, installation) de celles restant à faire (rendu et comportement réel).
