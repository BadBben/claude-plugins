---
name: setup
description: "Configure le dépôt git qui sert de mémoire partagée au plugin memoire, ou en change. À utiliser quand l'utilisateur demande de configurer, connecter, initialiser ou changer son dépôt mémoire, ou quand un autre skill memoire répond qu'aucun dépôt n'est configuré (code 10)."
argument-hint: "[url-du-depot]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *)
---

# Configurer le dépôt mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

Le plugin ne connaît aucun dépôt par défaut et ne stocke jamais de jeton : l'authentification GitHub est celle de git sur la machine, ou celle de l'app GitHub de Claude sur claude.ai.

## Dans Claude Code

La configuration est propre à l'appareil (`~/.claude/memoire/config.json`) et ne contient que l'URL du dépôt.

1. **URL.** Prends le premier argument. S'il manque, demande à l'utilisateur l'URL de son dépôt mémoire (HTTPS, SSH, ou `proprietaire/depot` pour GitHub). Ne la devine jamais.
2. **Existant.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --show`. Code 10 : rien n'est configuré, passe à l'étape 4. Sinon, si l'URL affichée est la même, dis-le et arrête-toi. Si elle diffère, explique les deux conséquences d'un remplacement : les marqueurs de synchro des mémoires locales viennent de l'ancien dépôt (le prochain pull fusionnera sans base, donc tout fichier différent sera signalé en conflit plutôt qu'écrasé), et la copie locale de la mémoire générale vient aussi de l'ancien dépôt. Pose une seule question avec AskUserQuestion : « Remplacer, garder la générale locale », « Remplacer, vider la générale locale », « Annuler ».
3. **Options.** Ajoute `--replace` si remplacement, et `--reset-general` si l'utilisateur a choisi de vider la copie locale.
4. **Exécution.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh "<url>" [--replace] [--reset-general]`.
   Code 2 : le clone a échoué. Montre le message. Causes habituelles : URL fausse, ou authentification GitHub absente sur cette machine (une fenêtre de connexion a pu s'ouvrir dans le navigateur ; sinon `gh auth login`, ou un gestionnaire d'identifiants git).
5. **Suite.** Le script liste les projets qui ont une mémoire partagée dans le dépôt et dit si une mémoire générale existe. Propose à l'utilisateur, en une question : charger la mémoire d'un de ces projets (skill pull), charger la mémoire générale (skill generale), ou rien pour l'instant. Si le setup a été déclenché par un autre skill qui a reçu le code 10, reprends ce skill là où il s'était arrêté.

## Sur claude.ai

Il n'y a pas de configuration persistante : le dépôt est fixé pour la conversation, par la variable d'environnement `CLAUDE_MEMOIRE_REPO` que les autres skills passent aux scripts.

1. **Trouver le dépôt**, dans cet ordre : les instructions ou les connaissances du Projet (une ligne « dépôt mémoire : proprietaire/depot », dans les instructions ou dans un document du Projet), la mémoire claude.ai de l'utilisateur (ce que Claude retient de lui entre les conversations, s'il y a noté son dépôt mémoire), ce que l'utilisateur dit dans la conversation, sinon la liste des dépôts accessibles par l'app GitHub de Claude (outil de listage des dépôts) où tu cherches un candidat plausible.
2. **Confirmer quand c'est deviné.** Un dépôt écrit par l'utilisateur (instructions ou connaissances du Projet, mémoire claude.ai, conversation) s'utilise sans question : dis juste lequel tu utilises. Un dépôt pris dans la liste des dépôts accessibles est une supposition : pose une question, « Utiliser `proprietaire/depot` comme dépôt mémoire ? », même avec un seul candidat. Ne pousse jamais vers un dépôt deviné sans cette confirmation.
3. **Attacher le dépôt à la session** avec l'outil d'ajout de dépôt (« Ajouter un dépôt », `add_repo`) : le proxy git du bac à sable n'autorise que les dépôts attachés, et un clone sans cela échoue en code 2 avec `could not read Username`. Ne clone pas toi-même : les scripts le font.
4. **Vérifier l'accès** avec un pull à blanc : `CLAUDE_MEMOIRE_REPO=<url> bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh <projet> /home/claude/memoire/<projet> --dry-run` (ou `generale.sh pull --dry-run`). Code 2 malgré l'attachement : l'app GitHub de Claude n'a pas accès à ce dépôt (page d'installation de l'app sur GitHub). Si le chemin du plugin n'est pas résolu, cherche `scripts/pull.sh` du plugin memoire dans le bac à sable.
5. **Suite.** Reprends le skill qui t'a amené ici avec `CLAUDE_MEMOIRE_REPO=<url>` sur chaque commande. Si le dépôt a été deviné puis confirmé, suggère à l'utilisateur, une fois, de l'enregistrer pour ne plus être interrogé : dans les instructions de son Projet (valable pour ce Projet), ou en demandant à Claude de retenir son dépôt mémoire (valable pour toutes ses conversations, via la mémoire claude.ai).
