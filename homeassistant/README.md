# Home Assistant : alerte fuite d'eau

[`automations/fuite_d_eau_alerte_critique.yaml`](automations/fuite_d_eau_alerte_critique.yaml)
alerte un téléphone Android (application Home Assistant) lorsqu'un détecteur de fuite
passe à `on`, y compris en mode Ne pas déranger.

## Comportement

Toutes les `intervalle_s` (15 s), pendant `duree_max_min` (10 min) au plus :

1. notification sur le canal Android **« Fuite d'eau »**, avec le bouton « J'ai vu – arrêter » ;
2. annonce vocale sur le flux alarme au volume maximum (`media_stream: alarm_stream_max`).

La boucle s'arrête :

- à l'appui sur « J'ai vu – arrêter » : annonce coupée (`stop_tts`), notification effacée,
  confirmation « Alerte fuite acquittée » ;
- automatiquement, quand plus aucun capteur de la variable `capteurs` n'est à `on` :
  notification « Plus d'eau détectée » sur un canal informatif ;
- au bout de `duree_max_min`.

Lancée à la main (⋮ → Exécuter les actions), elle passe en mode test : titre et annonce
préfixés « TEST », pas d'arrêt automatique. Chaque action lancée seule depuis l'éditeur
envoie aussi un texte de test au lieu d'un message vide.

## Installation

1. Paramètres → Automatisations → Créer → ⋮ → Modifier en YAML, coller le fichier.
2. Remplacer `notify.mobile_app_mon_telephone` par le service de votre téléphone.
3. Adapter la liste des capteurs dans `triggers` **et** dans la variable `capteurs`.
4. Lancer un test : le premier envoi crée le canal « Fuite d'eau » sur le téléphone.

## Réglages du téléphone

- Paramètres → Applications → Home Assistant → Notifications → **Fuite d'eau** :
  choisir la sonnerie, importance « Urgent », activer **« Ignorer Ne pas déranger »**.
- Dans les réglages Ne pas déranger, laisser les **alarmes** autorisées (annonce vocale).

## Limites

- Hors Wi-Fi, les notifications passent par le relais push de Home Assistant (limite
  quotidienne d'envois par appareil) : une alerte complète en envoie environ 80.
- Le bouton « J'ai vu » doit pouvoir joindre Home Assistant (réseau local, VPN, accès
  distant). Sinon l'alerte continue jusqu'à l'arrêt automatique ou la durée maximale.
- Home Assistant ne reçoit pas d'accusé de livraison des notifications.
