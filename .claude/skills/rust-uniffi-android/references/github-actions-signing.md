# GitHub Actions : APK Rust/UniFFI et signature stable

## Choisir et adapter le workflow

Lire `AGENTS.md`, les scripts, `Cargo.lock`, le catalogue Gradle et le wrapper avant
adaptation. [../assets/heos-apk.yml](../assets/heos-apk.yml) est un exemple complet
issu de HEOS Fader, pas une spécification universelle. Il dépend des scripts du
projet : `scripts/build-android.sh`, `scripts/gen-kotlin.sh`, `scripts/verify-apk.py`.
Ces fichiers doivent exister dans le projet cible ; adapter aussi le préfixe des
variables/secrets `HEOS_*`, le module `:app` et tous les chemins de filtre/artéfact.
Ne pas supposer que le projet est à la racine d'un monorepo.

Versions validées pour cet exemple en novembre 2026 : JDK 21, API/build-tools 36,
NDK `30.0.16248370`, cargo-ndk `4.1.2`, Gradle `9.8.1`. Ce sont des versions connues,
pas une invitation à mettre à jour celles d'un autre projet. Les actions sont
épinglées par SHA ; vérifier leurs entrées et leur disponibilité avant de les remplacer.
Le cache Rust ne remplace pas l'installation des cibles et du NDK. Ne pas ajouter
un cache NDK sans bénéfice mesuré.

La séquence de build est :

1. Checkout ; JDK ; SDK, build-tools et NDK ; Rust avec les cibles Android.
2. Définir `ANDROID_NDK_HOME=$ANDROID_HOME/ndk/$NDK_VERSION` et écrire
   `android/local.properties` avec `sdk.dir`. Ne pas le versionner.
3. Restaurer les caches Rust/Gradle (écriture sur push, lecture seule sur PR).
   `GRADLE_ENCRYPTION_KEY` n'est nécessaire que pour conserver un configuration
   cache chiffré, pas pour signer un APK ; ne pas confondre ces clés.
4. `cargo test --workspace --locked` contre des faux serveurs, sans matériel réel.
5. `scripts/build-android.sh` : `cargo ndk -t arm64-v8a -t x86_64 ...`, puis génération
   Kotlin depuis la bibliothèque **hôte** (`.so` sous Linux, `.dylib` sous macOS).
   Ne pas générer les bindings depuis une vieille bibliothèque, ni modifier les
   fichiers générés à la main. Les ABIs doivent correspondre aux `abiFilters`.
6. Restaurer le keystore dans `$RUNNER_TEMP` avec `umask 077`, puis
   `./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain`.
7. Vérifier les bibliothèques et le certificat, nettoyer le keystore avec `if: always()`,
   publier l'APK (rétention explicite, `if-no-files-found: error`).

Déclencheurs usuels : PR, push sur la branche d'intégration, `workflow_dispatch`.
Inclure Cargo, scripts, Android et le workflow dans les filtres de chemins. Ne pas
bloquer un check obligatoire par un filtre incompatible avec la protection de branche.
`workflow_dispatch` devient disponible dans l'interface une fois le fichier présent
sur la branche par défaut. Utiliser `permissions: contents: read` et une concurrence
par `github.ref`, avec annulation des anciens runs.

## Identité Android : ne pas casser les mises à jour

Pour mettre à jour une installation, conserver son `applicationId`, son certificat
de signature et un `versionCode` non inférieur (l'augmenter pour les versions publiées).
Une clé générée sur chaque runner produit des APK qui ne s'installent pas par-dessus
ceux d'un autre runner ou de la machine locale. Le certificat est public ; le keystore
contient la clé privée. Base64 est un encodage, pas un chiffrement.

Pour une app déjà installée depuis un build debug local, réutiliser le fichier qui
l'a signée, souvent `~/.android/debug.keystore` (alias `androiddebugkey`, mot de passe
standard `android`). Vérifier d'abord le certificat de l'APK avec `apksigner verify
--print-certs` : l'existence du fichier ne prouve pas qu'il a signé l'app actuelle.
Cette réutilisation convient au prototype ; une clé debug au mot de passe connu
n'est pas une nouvelle identité de production. Ne pas la changer silencieusement.
Pour Google Play, distinguer clé d'upload et clé de signature gérée par Play : la clé
d'upload seule ne permet pas de signer un APK compatible avec une installation Play.

Pour une app neuve seulement, si aucune identité ne doit être conservée, générer
une fois un keystore dédié hors dépôt (exemple Bash, JDK disponible dans le PATH) :

```bash
umask 077
mkdir -p "$HOME/.config/my-app"
test ! -e "$HOME/.config/my-app/signing.keystore" || exit 1
export HEOS_KEYSTORE_PASSWORD=$(openssl rand -hex 32)
keytool -genkeypair -noprompt -storetype PKCS12 \
  -keystore "$HOME/.config/my-app/signing.keystore" -alias myapp \
  -storepass:env HEOS_KEYSTORE_PASSWORD -keypass:env HEOS_KEYSTORE_PASSWORD \
  -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=My Android App'
```

Sauvegarder le fichier ET le mot de passe dans le gestionnaire de secrets choisi
avant de fermer le shell. Ne pas exécuter cette génération pour une app existante.
Ne jamais committer `*.jks`, `*.keystore` ou un fichier d'environnement contenant
les mots de passe. Ne pas afficher les secrets dans les logs ni utiliser `set -x`.

## Envoyer une identité existante depuis le Mac avec gh

Configurer `JAVA_HOME` sur le JDK de build, avec `keytool` dans le PATH. Le script
ci-dessous tourne sur le Mac qui possède déjà la clé ; aucun SSH ni setup Termux
n'est nécessaire. Adapter le dépôt, le chemin et l'alias AVANT exécution. Il ne crée
pas de clé et n'écrit rien dans le dépôt.

```bash
set -euo pipefail
umask 077
signing_repo=azman0101/heos-uniffi
export HEOS_KEYSTORE_FILE="$HOME/.android/debug.keystore"
export HEOS_KEY_ALIAS=androiddebugkey
export HEOS_KEYSTORE_PASSWORD=android # uniquement pour ce debug keystore existant
# Si le mot de passe de clé diffère de celui du keystore, définir HEOS_KEY_PASSWORD.
test -f "$HEOS_KEYSTORE_FILE"
cert_file=$(mktemp)
trap 'rm -f "$cert_file"' EXIT
keytool -exportcert -keystore "$HEOS_KEYSTORE_FILE" -alias "$HEOS_KEY_ALIAS" \
  -storepass:env HEOS_KEYSTORE_PASSWORD > "$cert_file"
cert_sha256=$(shasum -a 256 "$cert_file" | awk '{print $1}')
base64 < "$HEOS_KEYSTORE_FILE" | gh secret set HEOS_KEYSTORE_BASE64 --repo "$signing_repo"
printf '%s' "$HEOS_KEYSTORE_PASSWORD" | gh secret set HEOS_KEYSTORE_PASSWORD --repo "$signing_repo"
printf '%s' "$HEOS_KEY_ALIAS" | gh secret set HEOS_KEY_ALIAS --repo "$signing_repo"
printf '%s' "$cert_sha256" | gh secret set HEOS_CERT_SHA256 --repo "$signing_repo"
if [ -n "${HEOS_KEY_PASSWORD:-}" ]; then
  printf '%s' "$HEOS_KEY_PASSWORD" | gh secret set HEOS_KEY_PASSWORD --repo "$signing_repo"
fi
```

`gh secret list --repo ...` vérifie les noms, jamais les valeurs. Conserver une
sauvegarde indépendante : GitHub ne permet pas de récupérer les secrets en clair.
L'export du certificat valide le mot de passe du keystore, pas nécessairement celui
de la clé privée ; confirmer avec un vrai build signé. Si un ancien secret optionnel
`HEOS_KEY_PASSWORD` est obsolète, le corriger ou le supprimer explicitement.

## Même configuration Gradle en local et dans CI

Dans le bloc `android` de `app/build.gradle.kts` :

```kotlin
val signingPath = System.getenv("HEOS_KEYSTORE_FILE")
if (!signingPath.isNullOrBlank()) {
    val shared = signingConfigs.create("shared") {
        storeFile = file(signingPath) // fournir un chemin absolu
        storePassword = requireNotNull(System.getenv("HEOS_KEYSTORE_PASSWORD"))
        keyAlias = requireNotNull(System.getenv("HEOS_KEY_ALIAS"))
        keyPassword = System.getenv("HEOS_KEY_PASSWORD")
            ?.takeIf { it.isNotBlank() } ?: storePassword
    }
    buildTypes.getByName("debug").signingConfig = shared
}
```

Piège réel : un secret GitHub absent, injecté via `env`, devient une chaîne vide.
`System.getenv("HEOS_KEY_PASSWORD") ?: storePassword` ne suffit donc pas : il cause
`Get Key failed` / `Given final block not properly padded`. Utiliser `takeIf` comme
ci-dessus. Les variables locales doivent pointer sur le même keystore et alias
que les secrets CI. Garder ce chemin explicite si une autre machine sert au build.
Pour un build release, configurer sa signingConfig explicitement ; ce bloc ne signe
que `debug` et ne transforme pas une clé debug en clé de production.

## Frontière de confiance et vérifications

Le workflow HEOS joint illustre une identité debug partagée. Ne pas exposer une
clé de distribution à du code de PR non approuvé. Pour une vraie clé de production,
séparer la compilation sans secrets et la signature sur une référence approuvée
(push protégé ou environnement avec approbation). Ne pas employer
`pull_request_target` pour exécuter le code d'une PR avec les secrets.
Une PR du même dépôt peut recevoir les secrets ; les forks et Dependabot n'en
reçoivent généralement pas. Sans secrets, publier seulement un artefact nommé
`temporary`, clairement impropre à remplacer l'installation signée avec la clé partagée.
Pour une livraison attendue comme signée, une absence de clé doit échouer, pas
silencieusement substituer une nouvelle identité. Ne pas mettre les clés dans les
caches Gradle/Rust ni dans les artefacts ; supprimer le fichier restauré même en échec.

Le vérificateur ZIP doit exiger des entrées non vides pour **chaque** ABI :
`lib/<abi>/lib<crate>.so` et `lib/<abi>/libjnidispatch.so` (JNA en AAR).
Ne pas se contenter de trouver un seul `.so` dans l'APK. Pour le certificat :

```bash
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs app-debug.apk
```

Comparer le SHA-256 du certificat DER à `HEOS_CERT_SHA256` (normaliser casse et
séparateurs si besoin). L'empreinte du certificat n'est pas celle du fichier APK.
Télécharger l'artefact et utiliser `adb install -r` pour valider la mise à jour et
la conservation des données, lorsque le téléphone est disponible et l'installation
autorisée. Un build vert ne prouve pas le rendu ou le comportement matériel.

Pour publier un workflow via un token OAuth `gh`, le scope `workflow` est requis :
`gh auth refresh --hostname github.com --scopes workflow`. Cette permission est
indépendante des secrets APK ; ne pas créer de nouvelle clé pour résoudre ce refus.
Surveiller le run (`gh run view ... --log-failed` en échec), corriger et relancer,
puis livrer le lien de l'artefact avec le résultat des checks.
