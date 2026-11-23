---
name: setup
description: "Met en place la mémoire partagée du plugin memoire sur un appareil, de bout en bout. Sans argument, affiche l'état des cinq étapes (dépôt configuré et cloné, projet du dossier de travail branché, bloc du CLAUDE.md, AGENTS.md, routine planifiée d'optimisation) avec la version du plugin, et propose celles qui manquent. Avec une URL, configure le dépôt mémoire et le clone ; avec un nom de projet, branche ce projet pour que sa mémoire auto vive dans le clone. À utiliser quand l'utilisateur demande de configurer, connecter, initialiser ou changer son dépôt mémoire, de brancher un projet sur sa mémoire partagée, de voir où en est la mise en place de sa mémoire, de poser ou mettre à jour le bloc du CLAUDE.md, de planifier l'optimisation de sa mémoire, ou quand un autre skill memoire répond qu'aucun dépôt n'est configuré (code 10)."
argument-hint: "[url-du-depot | nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *), Read, Write, Edit
---

# Mettre en place la mémoire partagée

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système te présente comme Claude Code, ou s'il a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Cette section manque quand la mémoire auto est coupée, par exemple dans une session ouverte dans le clone du dépôt mémoire : tu es quand même dans Claude Code. Sinon, tu es sur claude.ai, dans le bac à sable d'une conversation. Dans Claude Code, suis « Dans Claude Code » ; sur claude.ai, suis « Sur claude.ai ».

Le plugin ne connaît aucun dépôt par défaut et ne stocke jamais de jeton : l'authentification GitHub est celle de git sur la machine, ou celle de l'app GitHub de Claude sur claude.ai.

## Dans Claude Code

La mise en place d'un appareil tient en cinq étapes, toujours dans cet ordre :

1. le dépôt mémoire est configuré et cloné (par défaut dans `~/claude-memory`), une fois par appareil ;
2. le projet du dossier de travail est branché sur sa mémoire dans le clone, une fois par projet et par appareil ;
3. le bloc du plugin est dans `~/.claude/CLAUDE.md`, une fois par appareil, puis à chaque version qui le change ;
4. `AGENTS.md`, la table de routage, est dans le dépôt, une fois pour tous les appareils ;
5. une routine planifiée joue le skill optimiser, une fois pour le compte.

**Par où entrer.**
- Sans argument, ou quand l'utilisateur demande où en est sa mise en place : « Vue d'état », puis les étapes qui manquent.
- Avec une URL (HTTPS, SSH, ou `proprietaire/depot`) : étape 1.
- Avec un nom de projet, ou la demande de brancher un projet : étape 2.
- Quand un autre skill a reçu le code 10 : étape 1, puis reprends ce skill là où il s'était arrêté.
- Une demande qui nomme une étape (le bloc, la table de routage, la routine) : cette étape.

Dans tous les cas, termine par la vue d'état à jour quand quelque chose a changé.

### Vue d'état

C'est la vue de pilotage de l'utilisateur : elle doit se lire d'un coup d'œil.

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --etapes --workdir "<dossier de travail de la session>"`

Le script ne clone rien, ne contacte pas le dépôt et n'écrit rien. Il sort toujours en code 0. Sa sortie :
- `version=` : la version du plugin ;
- une ligne `etape` par étape, en colonnes séparées par des tabulations : le numéro, un code (`depot`, `projet`, `bloc`, `agents`, `routine`), l'état, le détail ;
- un bilan : `faites=`, `a_faire=`, `a_mettre_a_jour=`, `suivante=` (le numéro de la première étape à traiter, 0 s'il n'y en a pas) et, quand le clone est en place, `clone=` (avance, retard et travail non commité, tels que connus au dernier échange avec le dépôt).

Les états : `fait` ; `a-faire` ; `a-mettre-a-jour` (l'étape est faite, mais plus à jour) ; `sans-objet` (l'étape 2 dans une session ouverte dans le clone) ; `non-verifiable` (l'étape 5, que le script ne peut pas voir).

**L'étape 5 se vérifie avec toi.** Une routine vit sur le compte, pas sur l'appareil. Si la session a un outil de routines cloud (un skill `schedule`, un outil qui liste les routines du compte comme `RemoteTrigger`), liste les routines, sans rien créer, modifier ni lancer, et cherche celle dont la consigne nomme le skill optimiser du plugin memoire. Trouvée : `fait`, avec son nom, son horaire en heure locale et sa prochaine exécution ; si elle est désactivée, dis-le. Aucune : `à faire`. Pas d'outil de ce genre : « non vérifiable ici ». Un outil de tâches planifiées locales, qui tournent sur le poste, n'est pas un outil de routines cloud.

**Présentation.** Une ligne de titre avec la version, puis un tableau de cinq lignes, sans phrase autour :

| | Étape | État | Détail |
| --- | --- | --- | --- |
| 1 | Dépôt et clone | fait | l'adresse du dépôt, le dossier du clone |
| 2 | Projet branché | à faire | ce que dit le script |
| 3 | Bloc du `CLAUDE.md` | à mettre à jour | ... |
| 4 | `AGENTS.md` | fait | ... |
| 5 | Routine d'optimisation | non vérifiable ici | ... |

Garde le détail du script, raccourci s'il est long. Sous le tableau, une ligne pour l'état du clone si `clone=` annonce une avance, un retard ou du travail non commité (le skill pull récupère, le skill push envoie). Puis propose la suite en une question : l'étape `suivante` en premier, marquée « (Recommandé) », les autres étapes à faire ensuite, et « rien pour l'instant ». Si tout est fait, dis-le en une ligne et ne propose rien.

Les étapes s'enchaînent une par une : après chacune, reviens à la vue d'état et propose la suivante, jusqu'à ce que l'utilisateur s'arrête ou que tout soit fait.

### Étape 1 : le dépôt et son clone

1. **État.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --status`
   Code 10 : rien n'est configuré, continue. Sinon le script affiche le dépôt, le chemin du clone, l'avance et le retard, et si une fusion est en cours. Si le dépôt est déjà le bon, l'étape est faite.
2. **Dépôt et clone.** Prends l'URL en argument. Si elle manque, demande à l'utilisateur l'URL de son dépôt mémoire (HTTPS, SSH, ou `proprietaire/depot` pour GitHub). Ne la devine jamais. Puis `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh "<url>"` : il clone le dépôt s'il n'est pas encore sur l'appareil, écrit la configuration, et liste les projets et la mémoire générale.
   Code 11 : un autre dépôt est configuré, ou le clone en place appartient à un autre dépôt. Explique-le. `--replace` change le dépôt configuré, mais un clone n'est jamais supprimé ni remplacé par le script : c'est à l'utilisateur de déplacer ou renommer le dossier, puis on relance.
   Code 2 : le clone a échoué, ou un dossier qui n'est pas un clone git occupe l'emplacement. Montre le message. Causes habituelles du premier cas : URL fausse, ou authentification GitHub absente sur cette machine (une fenêtre de connexion a pu s'ouvrir dans le navigateur ; sinon `gh auth login`, ou un gestionnaire d'identifiants git).

### Étape 2 : brancher le projet du dossier de travail

À faire depuis le dossier de travail du projet, celui où l'utilisateur ouvre ses sessions. Ce dossier reste où il est : seul le dossier de mémoire change.

- **Jamais depuis le clone.** Si ton dossier de travail est le clone lui-même ou un de ses sous-dossiers (la vue d'état dit alors `sans-objet`), ne branche rien : le clone n'est le dossier de travail d'aucun projet, et un réglage écrit là pourrait partir dans le dépôt au push suivant. Dis-le, et propose de relancer ce skill depuis le dossier de travail du projet. Les autres étapes fonctionnent depuis le clone comme ailleurs.
- **Nom.** L'argument, sinon `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et une question qui propose les projets du dépôt et le nom du dossier de travail courant s'il n'y figure pas. Ne continue qu'avec un nom confirmé : le nom d'un projet mémoire désigne un sujet, pas forcément le dossier, et un nom mal choisi crée un second projet vide.
- **Chemin.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --project "<nom>"` affiche le nom tel que le dépôt l'écrit, si le projet est connu ou nouveau, et la ligne `reglage=` : la valeur à donner au réglage.
- **Réglage.** Lis `.claude/settings.local.json` dans le dossier de travail (s'il n'existe pas, pars de `{}`), ajoute ou mets à jour la seule clé `autoMemoryDirectory` avec la valeur de `reglage=`, et garde tout le reste tel quel. Ce fichier est propre à l'appareil et n'est pas fait pour être commité : si le dossier de travail est un dépôt git et que `git status` montrerait ce fichier, dis-le à l'utilisateur plutôt que de toucher à son `.gitignore`. S'il préfère partager le réglage avec le dépôt du projet, la même clé va dans `.claude/settings.json`.
- **Projet nouveau.** Si le script a dit `connu=non`, crée dans le clone `projets/<nom>/memory/MEMORY.md` avec une ligne de titre (`# Memory index`) : le dossier existe alors pour la première session.
- **Ancienne mémoire locale.** Si ton prompt système donne un dossier de mémoire auto, qu'il n'est pas dans le clone et qu'il contient des fichiers, compare-le avant de l'abandonner : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --compare "<ancien dossier>" "<nom>"`. Le script liste ce qui n'existe que dans l'ancien dossier et ce qui diffère, sans rien modifier. Pour chaque fichier listé, montre la différence et propose de le copier dans le clone, ou de fusionner les deux contenus quand les deux ont du neuf ; l'utilisateur décide fichier par fichier. Rien n'est supprimé dans l'ancien dossier.
- **Vérifier.** Le dossier de mémoire est lu au démarrage d'une session : demande à l'utilisateur d'ouvrir une nouvelle session dans ce dossier de travail, où le chemin du clone doit apparaître comme dossier de mémoire (la commande `/memory` l'affiche). À revérifier après une mise à jour de Claude Code : ce réglage a déjà été signalé comme ignoré dans certaines versions et certaines interfaces.

### Étape 3 : le bloc du `CLAUDE.md`

`~/.claude/CLAUDE.md` est le fichier d'instructions personnel de Claude Code, lu dans chaque session. Le plugin y tient un bloc, entre deux marqueurs (`<!-- memoire:debut -->` et `<!-- memoire:fin -->`) : la ligne qui importe `AGENTS.md` depuis le clone, les demandes qui lancent chaque skill, et la règle « ni pull, ni push, ni commit sans demande ». Le script est le seul à écrire entre les marqueurs. Tout ce qui est en dehors appartient à l'utilisateur et n'est jamais touché. Tu n'écris jamais ce bloc toi-même, ni avec Edit ni avec Write.

1. **Montrer.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --bloc` n'écrit rien. Il donne `fichier=`, `etat=`, puis le texte sous « Bloc a ecrire » et, quand un bloc est déjà là, « Bloc en place » et « Ce qui change » (une différence ligne à ligne). Selon `etat=` :
   - `absent` : le bloc sera ajouté à la fin du fichier, ou le fichier créé (`fichier_present=non`). Montre le bloc tel quel.
   - `a-jour` : rien à faire, dis-le.
   - `a-mettre-a-jour` : le bloc entre marqueurs n'est plus celui de cette version du plugin (une mise à jour, un clone déplacé, ou une retouche à la main). Montre ce qui change.
   - `sans-marqueurs` : un bloc posé à la main a été reconnu aux lignes de `lignes=`. Il sera remplacé par le bloc entre marqueurs. Montre « Ce qui change », et nomme une par une les lignes de l'ancien bloc qui ne se retrouvent pas dans le nouveau : une règle personnelle rangée là serait perdue. Propose de la remettre après l'écriture, hors des marqueurs.
   - `marqueurs-abimes` : un marqueur manque, est en double, ou ils sont dans le désordre. Le script n'écrira rien (code 12). Montre les lignes en cause et laisse l'utilisateur réparer, ou propose de le faire avec lui, puis relance.
2. **Demander.** Une question : écrire le bloc dans le fichier nommé, ou non. Rien n'est écrit sans son oui.
3. **Écrire.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --bloc --write`. Le reste du fichier est gardé tel quel, fins de ligne comprises, et le fichier d'avant est copié à l'endroit de la ligne `sauvegarde=`. Donne ce chemin.
4. **Lignes restées dehors.** Une ligne `hors_bloc=` nomme des lignes du plugin qui traînent hors du bloc (un import d'`AGENTS.md` ou un déclencheur de skill en double). Montre-les et propose de les retirer avec Edit : ce sont des lignes de l'utilisateur, il décide. Si une règle personnelle de l'ancien bloc est à remettre, écris-la hors des marqueurs, avec son accord.
5. **Vérifier.** Le fichier est lu au démarrage d'une session : dans une nouvelle session, ouverte dans n'importe quel dossier, Claude doit pouvoir citer une règle de la table de routage. Si l'étape 4 n'est pas faite, l'import ne trouve encore rien : c'est attendu.

### Étape 4 : `AGENTS.md`

La table de routage vit à la racine du dépôt mémoire et se partage par lui : une fois créée et poussée, les autres appareils la reçoivent par un pull.

- Si la vue d'état annonce un retard du clone, propose d'abord le skill pull : le fichier existe peut-être déjà dans le dépôt.
- Sinon, enchaîne avec le skill reindex : il crée `AGENTS.md` depuis son modèle, rédige les entrées et les fait valider. Ce skill-ci n'écrit pas la table.
- Le fichier n'est partagé qu'après un push : propose le skill push une fois la table validée.

### Étape 5 : la routine d'optimisation

Une routine cloud joue le skill optimiser à heure fixe, sans rien faire tourner sur le poste : elle fait le passage, pose ses questions, prévient l'utilisateur et attend sa réponse, sans rien pousser avant. Ce qu'une routine a de particulier est dans la section « Routine cloud » du skill optimiser. Ici, on la crée.

1. **Existe-t-elle ?** Si la vue d'état l'a trouvée, montre-la et arrête-toi : tu ne modifies ni ne remplaces une routine existante sans que l'utilisateur le demande.
2. **Quatre questions**, en une série, ta recommandation en premier :
   - le jour : un jour de la semaine, ou tous les jours ;
   - l'heure, en heure locale ;
   - la portée : tout le dépôt (recommandé : le clone d'une routine est neuf, sans travail en cours, donc aucun brouillon ne part par surprise), la partie transverse seule (mémoire générale et racine), ou un projet nommé ;
   - le modèle : propose ceux que l'outil de routines accepte, le plus capable en premier. Le passage lit toutes les fiches et rédige des propositions : la qualité compte plus que la vitesse.
3. **L'horaire.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --cron <jour> <HH:MM>`, avec le jour en toutes lettres (`dimanche`) ou `tous`. Le cron d'une routine se lit en UTC, avec un intervalle d'au moins une heure : le script convertit l'heure locale de l'appareil et rend `cron=`, la même heure en UTC, et `saison=`. Si `saison=oui`, le fuseau change d'heure deux fois par an et la routine passera une heure plus tôt ou plus tard à l'autre saison : dis-le avec l'heure que donne le script, c'est à l'utilisateur de corriger le cron à ce moment-là ou de s'en accommoder.
4. **La consigne.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --routine <portée>`, où `<portée>` est `--all`, `--project "<nom>"` (répétable) ou rien pour la partie transverse seule. `--host <nom>` change le nom écrit dans les titres de commit (`routine` par défaut). Le script remplit le modèle du plugin (`skills/optimiser/assets/consigne-routine.md`) avec l'adresse du dépôt, sans les identifiants qu'elle pourrait contenir. La consigne est tout ce qui suit la ligne « == Consigne == » : reprends-la telle quelle, sans la réécrire. Elle est courte exprès : le déroulé est dans le skill optimiser, et suit donc les mises à jour du plugin sans recréer la routine. S'il annonce une adresse qui n'est pas en HTTPS, demande l'adresse HTTPS du dépôt et remplace-la dans la consigne.
5. **Montrer la configuration**, avant de créer quoi que ce soit : le nom (par exemple « Optimiser la mémoire, dimanche 19 h »), l'horaire en heure locale et le cron en UTC, l'avertissement de saison, la portée, le modèle, le dépôt attaché, aucun connecteur, et la consigne. Puis une question : créer la routine, ou non.
6. **Créer**, quand la session a un outil de routines cloud, avec cet outil et selon sa propre documentation :
   - le nom, le cron en UTC, la consigne, le modèle ;
   - un seul dépôt attaché, le dépôt mémoire, par son adresse HTTPS : c'est ce qui donne à la routine le droit de le cloner et d'y pousser. Aucun dépôt du plugin : le plugin installé sur le compte est chargé dans l'environnement d'une routine ;
   - aucun connecteur. À la création, le serveur attache d'office tous les connecteurs du compte quand on n'en nomme aucun : demande explicitement une routine sans connecteur (avec `RemoteTrigger`, `clear_mcp_connections: true`) ;
   - si l'outil demande les outils autorisés : le shell, la lecture et l'écriture de fichiers, les skills et la notification ;
   - l'environnement cloud par défaut du compte, sauf demande contraire.
   Relaie ce que l'outil répond : l'heure de la prochaine exécution, à faire confirmer, et l'adresse de la routine. Ne la lance pas pour essayer sans que l'utilisateur le demande.
7. **Sans outil de routines**, ne crée rien. Donne la configuration du point 5 et la consigne dans un bloc à copier, et dis où la coller : sur claude.ai, page des routines de Claude Code (`claude.ai/code/routines`), ou dans Claude Code en ligne de commande avec `/schedule`. À régler à la main là-bas : le dépôt mémoire comme seul dépôt, l'horaire (un cron personnalisé se lit en UTC), le modèle, et les connecteurs à retirer, puisqu'ils sont tous cochés d'office.
8. **Ensuite.** La routine prévient quand elle attend une décision. Après chaque passage poussé, l'utilisateur lance le skill pull sur ses appareils.

## Sur claude.ai

Il n'y a ni configuration persistante ni réglage à poser : le dépôt est fixé pour la conversation par la variable d'environnement `CLAUDE_MEMOIRE_REPO`, que les autres skills passent aux scripts, et le clone vit dans le bac à sable (`~/claude-memory`) le temps de la conversation. Le parcours en cinq étapes ne s'applique pas ici : les étapes 2 et 3 règlent un appareil, et se font dans Claude Code.

1. **Trouver le dépôt**, dans cet ordre : les instructions ou les connaissances du Projet (une ligne « dépôt mémoire : proprietaire/depot », dans les instructions ou dans un document du Projet), la mémoire claude.ai de l'utilisateur (ce que Claude retient de lui entre les conversations, s'il y a noté son dépôt mémoire), ce que l'utilisateur dit dans la conversation, sinon la liste des dépôts accessibles par l'app GitHub de Claude (outil de listage des dépôts) où tu cherches un candidat plausible.
2. **Confirmer quand c'est deviné.** Un dépôt écrit par l'utilisateur (instructions ou connaissances du Projet, mémoire claude.ai, conversation) s'utilise sans question : dis juste lequel tu utilises. Un dépôt pris dans la liste des dépôts accessibles est une supposition : pose une question, « Utiliser `proprietaire/depot` comme dépôt mémoire ? », même avec un seul candidat. Ne pousse jamais vers un dépôt deviné sans cette confirmation.
3. **Attacher le dépôt à la session** avec l'outil d'ajout de dépôt (« Ajouter un dépôt », `add_repo`) : le proxy git du bac à sable n'autorise que les dépôts attachés, et un clone sans cela échoue en code 2 avec `could not read Username`. Ne clone pas toi-même : les scripts le font.
4. **Vérifier l'accès** : `CLAUDE_MEMOIRE_REPO=<url> bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list`. Le script clone le dépôt dans le bac à sable et liste ce qu'il contient. Code 2 malgré l'attachement : l'app GitHub de Claude n'a pas accès à ce dépôt (page d'installation de l'app sur GitHub). Si le chemin du plugin n'est pas résolu, cherche `scripts/setup.sh` du plugin memoire dans le bac à sable.
5. **Suite.** Reprends le skill qui t'a amené ici avec `CLAUDE_MEMOIRE_REPO=<url>` sur chaque commande. Si le dépôt a été deviné puis confirmé, suggère à l'utilisateur, une fois, de l'enregistrer pour ne plus être interrogé : dans les instructions de son Projet (valable pour ce Projet), ou en demandant à Claude de retenir son dépôt mémoire (valable pour toutes ses conversations, via la mémoire claude.ai).

**La routine, depuis claude.ai.** Si l'utilisateur demande de planifier l'optimisation de sa mémoire, suis l'étape 5 de « Dans Claude Code » avec `CLAUDE_MEMOIRE_REPO=<url>` devant les commandes. Le bac à sable est à l'heure UTC : demande son fuseau à l'utilisateur et passe-le au script, `TZ=<fuseau, par exemple Europe/Paris> bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --cron <jour> <HH:MM>`.
