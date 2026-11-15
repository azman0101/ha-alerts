---
tags: [rust-uniffi-android]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

./gradlew :app:assembleDebug échoue : "Dependency 'androidx.lifecycle:lifecycle-runtime-compose-android:2.11.0' requires libraries and applications that depend on it to compile against version 37 or later of the Android APIs. :app is currently compiled against android-36." Mon SDK n'a que la plateforme android-36 (sdkmanager --list_installed). Dis-moi quoi faire, dans ANSWER.md, sans rien exécuter.
