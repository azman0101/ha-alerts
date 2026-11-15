# Pièges rencontrés (et corrections)

| Symptôme | Cause | Correction |
|---|---|---|
| `can't find crate for std` avec cargo-ndk | `cargo` Homebrew ≠ toolchain rustup (qui a les cibles Android) | `PATH=~/.rustup/toolchains/stable-*/bin:$PATH`, `ANDROID_NDK_HOME` défini |
| NDK absent | SDK ne contient que platforms/build-tools | `sdkmanager --sdk_root=<sdk> "ndk;<version stable>"` |
| `checkAarMetadata` : dépendance exige compileSdk 37 | BOM Compose / lifecycle trop récents pour la plateforme installée | rétrograder la BOM et lifecycle (ou installer la plateforme) |
| `This material API is experimental` | `Slider(thumb/track)` | `@OptIn(ExperimentalMaterial3Api::class)` |
| Contenu sous la barre d'état | edge-to-edge imposé (targetSdk 36) | `enableEdgeToEdge()` + `Modifier.safeDrawingPadding()` |
| App crash au lancement | `.so` ou `libjnidispatch.so` absent de l'APK | JNA en `aar`, `abiFilters` = ABIs buildées, relancer `build-android.sh` |
| `adb connect` « failed to connect » alors que le ping passe | port de connexion périmé ou hôte non appairé | `adb pair` avec le port/ code de la boîte « Associer », puis le port de l'écran principal |
| `adb: no such file` avec `$ADB -s …` | variable contenant commande + arguments en zsh | utiliser une fonction `adb(){ <chemin> -s IP:PORT "$@"; }` |
| Gradle : Java trop récent/ancien | JDK 26 par défaut | `JAVA_HOME` = JDK 21 |
| `Cannot add extension with name 'kotlin'` avec AGP 9+ | Plugin `org.jetbrains.kotlin.android` appliqué en plus de Kotlin intégré | Retirer ce plugin si Kotlin intégré est actif ; conserver le plugin Compose |

Versions utilisées (oct. 2026) : AGP 9.4.1, Kotlin 2.4.21, Gradle 9.8.1, UniFFI 0.32, JNA 5.19.1, NDK 30, compileSdk 36. Les revérifier (maven-metadata.xml) avant de les figer.

## AGP 9 et Kotlin intégré

[AGP 9 active Kotlin intégré par défaut](https://developer.android.com/build/migrate-to-built-in-kotlin).
Dans ce mode, appliquer `com.android.application` sans
`org.jetbrains.kotlin.android` (ni son alias `kotlin-android`). Pour Compose,
appliquer aussi [`org.jetbrains.kotlin.plugin.compose`](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler)
avec une version correspondant à Kotlin et activer `buildFeatures.compose = true`.
Le support Kotlin intégré remplace le plugin Android Kotlin, pas le compilateur
Compose. Pour AGP 8 ou un projet ayant explicitement désactivé Kotlin intégré,
vérifier la configuration existante avant de retirer le plugin Android Kotlin.

## CI APK et signature

Voir [github-actions-signing.md](github-actions-signing.md) et le workflow d'exemple.

| Symptôme | Cause à vérifier | Correction |
|---|---|---|
| `Get Key failed` / `Given final block not properly padded` dans CI seulement | Mot de passe de clé optionnel injecté comme chaîne vide | `System.getenv("APK_KEY_PASSWORD")?.takeIf { it.isNotBlank() } ?: storePassword` ; vérifier aussi les vrais mots de passe/alias |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Certificat différent de l'app installée | Réutiliser son keystore et vérifier les empreintes ; ne pas régénérer la clé ni désinstaller par défaut |
| Push de `.github/workflows/*` refusé par OAuth | Token `gh` sans scope `workflow` | `gh auth refresh --hostname github.com --scopes workflow` ; sans rapport avec la clé APK |
| APK CI sans JNA ou sans une ABI | Vérification limitée à un seul `.so` | Exiger Rust et `libjnidispatch.so` non vides pour chaque ABI |
| APK d'une PR fork non compatible avec l'installation locale | Secrets de signature indisponibles | Identifier clairement l'artefact comme `temporary` ; signer une référence approuvée avec la clé partagée |
