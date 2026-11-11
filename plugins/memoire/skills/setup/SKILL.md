---
name: setup
description: "Configure le dépôt git qui sert de mémoire partagée au plugin memoire, le clone sur l'appareil, et branche un projet dessus pour que sa mémoire auto vive dans ce clone. À utiliser quand l'utilisateur demande de configurer, connecter, initialiser ou changer son dépôt mémoire, de brancher un projet sur sa mémoire partagée, ou quand un autre skill memoire répond qu'aucun dépôt n'est configuré (code 10)."
argument-hint: "[url-du-depot | nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *), Read, Write, Edit
---

# Configurer la mémoire partagée

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

Le plugin ne connaît aucun dépôt par défaut et ne stocke jamais de jeton : l'authentification GitHub est celle de git sur la machine, ou celle de l'app GitHub de Claude sur claude.ai.

## Dans Claude Code

Deux choses se règlent ici. Une fois par appareil : le dépôt et son clone (par défaut `~/claude-memory`). Une fois par projet et par appareil : le branchement du dossier de travail sur sa mémoire dans le clone.

1. **État.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --status`
   Code 10 : rien n'est configuré, passe à l'étape 2. Sinon le script affiche le dépôt, le chemin du clone, l'avance et le retard, et si une fusion est en cours. Si le dépôt est déjà le bon et que l'utilisateur voulait seulement brancher un projet, passe à l'étape 3.
2. **Dépôt et clone.** Prends l'URL en argument. Si elle manque, demande à l'utilisateur l'URL de son dépôt mémoire (HTTPS, SSH, ou `proprietaire/depot` pour GitHub). Ne la devine jamais. Puis `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh "<url>"` : il clone le dépôt s'il n'est pas encore sur l'appareil, écrit la configuration, et liste les projets et la mémoire générale.
   Code 11 : un autre dépôt est configuré, ou le clone en place appartient à un autre dépôt. Explique-le. `--replace` change le dépôt configuré, mais un clone n'est jamais supprimé ni remplacé par le script : c'est à l'utilisateur de déplacer ou renommer le dossier, puis on relance.
   Code 2 : le clone a échoué, ou un dossier qui n'est pas un clone git occupe l'emplacement. Montre le message. Causes habituelles du premier cas : URL fausse, ou authentification GitHub absente sur cette machine (une fenêtre de connexion a pu s'ouvrir dans le navigateur ; sinon `gh auth login`, ou un gestionnaire d'identifiants git).
3. **Brancher un projet.** À faire depuis le dossier de travail du projet, celui où l'utilisateur ouvre ses sessions. Ce dossier reste où il est : seul le dossier de mémoire change.
   - **Nom.** L'argument, sinon `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et une question qui propose les projets du dépôt et le nom du dossier de travail courant s'il n'y figure pas. Ne continue qu'avec un nom confirmé.
   - **Chemin.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --project "<nom>"` affiche le nom tel que le dépôt l'écrit, si le projet est connu ou nouveau, et la ligne `reglage=` : la valeur à donner au réglage.
   - **Réglage.** Lis `.claude/settings.local.json` dans le dossier de travail (s'il n'existe pas, pars de `{}`), ajoute ou mets à jour la seule clé `autoMemoryDirectory` avec la valeur de `reglage=`, et garde tout le reste tel quel. Ce fichier est propre à l'appareil et n'est pas fait pour être commité : si le dossier de travail est un dépôt git et que `git status` montrerait ce fichier, dis-le à l'utilisateur plutôt que de toucher à son `.gitignore`. S'il préfère partager le réglage avec le dépôt du projet, la même clé va dans `.claude/settings.json`.
   - **Projet nouveau.** Si le script a dit `connu=non`, crée dans le clone `projets/<nom>/memory/MEMORY.md` avec une ligne de titre (`# Memory index`) : le dossier existe alors pour la première session.
   - **Ancienne mémoire locale.** Si le dossier de mémoire auto de ton prompt système n'est pas dans le clone et contient des fichiers, compare-le avant de l'abandonner : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --compare "<ancien dossier>" "<nom>"`. Le script liste ce qui n'existe que dans l'ancien dossier et ce qui diffère, sans rien modifier. Pour chaque fichier listé, montre la différence et propose de le copier dans le clone, ou de fusionner les deux contenus quand les deux ont du neuf ; l'utilisateur décide fichier par fichier. Rien n'est supprimé dans l'ancien dossier.
   - **Vérifier.** Le dossier de mémoire est lu au démarrage d'une session : demande à l'utilisateur d'ouvrir une nouvelle session dans ce dossier de travail, où le chemin du clone doit apparaître comme dossier de mémoire (la commande `/memory` l'affiche). À revérifier après une mise à jour de Claude Code : ce réglage a déjà été signalé comme ignoré dans certaines versions et certaines interfaces.
4. **Suite.** Propose en une question : mettre le clone à jour et lire la mémoire d'un projet (skill pull), consulter la mémoire générale (skill generale), ou rien pour l'instant. Si le setup a été déclenché par un autre skill qui a reçu le code 10, reprends ce skill là où il s'était arrêté.

## Sur claude.ai

Il n'y a ni configuration persistante ni réglage à poser : le dépôt est fixé pour la conversation par la variable d'environnement `CLAUDE_MEMOIRE_REPO`, que les autres skills passent aux scripts, et le clone vit dans le bac à sable (`~/claude-memory`) le temps de la conversation.

1. **Trouver le dépôt**, dans cet ordre : les instructions ou les connaissances du Projet (une ligne « dépôt mémoire : proprietaire/depot », dans les instructions ou dans un document du Projet), la mémoire claude.ai de l'utilisateur (ce que Claude retient de lui entre les conversations, s'il y a noté son dépôt mémoire), ce que l'utilisateur dit dans la conversation, sinon la liste des dépôts accessibles par l'app GitHub de Claude (outil de listage des dépôts) où tu cherches un candidat plausible.
2. **Confirmer quand c'est deviné.** Un dépôt écrit par l'utilisateur (instructions ou connaissances du Projet, mémoire claude.ai, conversation) s'utilise sans question : dis juste lequel tu utilises. Un dépôt pris dans la liste des dépôts accessibles est une supposition : pose une question, « Utiliser `proprietaire/depot` comme dépôt mémoire ? », même avec un seul candidat. Ne pousse jamais vers un dépôt deviné sans cette confirmation.
3. **Attacher le dépôt à la session** avec l'outil d'ajout de dépôt (« Ajouter un dépôt », `add_repo`) : le proxy git du bac à sable n'autorise que les dépôts attachés, et un clone sans cela échoue en code 2 avec `could not read Username`. Ne clone pas toi-même : les scripts le font.
4. **Vérifier l'accès** : `CLAUDE_MEMOIRE_REPO=<url> bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list`. Le script clone le dépôt dans le bac à sable et liste ce qu'il contient. Code 2 malgré l'attachement : l'app GitHub de Claude n'a pas accès à ce dépôt (page d'installation de l'app sur GitHub). Si le chemin du plugin n'est pas résolu, cherche `scripts/setup.sh` du plugin memoire dans le bac à sable.
5. **Suite.** Reprends le skill qui t'a amené ici avec `CLAUDE_MEMOIRE_REPO=<url>` sur chaque commande. Si le dépôt a été deviné puis confirmé, suggère à l'utilisateur, une fois, de l'enregistrer pour ne plus être interrogé : dans les instructions de son Projet (valable pour ce Projet), ou en demandant à Claude de retenir son dépôt mémoire (valable pour toutes ses conversations, via la mémoire claude.ai).
