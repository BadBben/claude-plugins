---
name: pull
description: "Charge la mémoire partagée d'un projet depuis le dépôt mémoire configuré dans la mémoire auto locale de cette session, avec fusion si les deux ont changé. À utiliser quand l'utilisateur demande de charger, récupérer, importer ou reprendre la mémoire d'un projet, ou de se synchroniser avec un autre appareil. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *)
---

# Charger la mémoire partagée d'un projet

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

Le dépôt mémoire n'est jamais gardé sur le disque : le script le clone dans un dossier temporaire, synchronise, puis nettoie.

## Dans Claude Code

1. **Nom du projet.** Prends le premier argument. S'il manque, liste les projets du dépôt avec `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et propose-les dans une question, avec le nom du dossier de travail courant s'il n'y figure pas ; ne continue qu'avec un nom confirmé. Le script résout la casse contre le dépôt, mais un nom confirmé évite les surprises.
2. **Dossier de mémoire auto locale.** Son chemin exact figure dans ton prompt système, section « Memory » (de la forme `.../.claude/projects/<slug>/memory/`). Utilise-le tel quel. Ne le devine jamais.
3. **Simulation.** Exécute :
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh "<projet>" "<dossier mémoire locale>" --dry-run`
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup (il demande l'URL), puis reviens ici.
   Code 3 : le projet n'existe pas dans le dépôt, montre la liste renvoyée et arrête-toi.
   Code 2 : git a échoué, montre l'erreur et arrête-toi.
4. **Résumé.** Le script classe chaque fichier : `nouveau`, `identique`, `depot` (copié), `local` (gardé), `fusion` (les deux ont changé, fusion automatique à trois voies) ou `CONFLIT` (les deux ont changé au même endroit). Explique en trois lignes ce qui serait copié, fusionné, en conflit, et quels fichiers n'existent qu'en local. Si tout est `identique` ou `local`, dis-le et arrête-toi.
5. **Confirmation.** Pose une seule question avec AskUserQuestion : « Fusionner » (recommandé, garde les fichiers locaux absents du dépôt), « Miroir » (supprime aussi ces fichiers), « Annuler ».
6. **Exécution.** Relance le script sans `--dry-run`, avec `--mirror` si l'utilisateur l'a choisi.
7. **Conflits.** Si le script liste des `CONFLIT`, ouvre chaque fichier concerné : il contient des blocs `<<<<<<< local` / `=======` / `>>>>>>> depot`. Pour chaque bloc, montre les deux versions, propose un texte fusionné qui garde les deux informations, et écris-le dans le fichier une fois validé, sans aucun marqueur restant. Tant qu'un marqueur subsiste, le push refusera (code 6). Termine en proposant le skill push pour partager la version fusionnée.
8. **Conclusion.** Rappelle que la mémoire synchronisée sera chargée au prochain démarrage de session, et propose de lire `MEMORY.md` tout de suite si l'utilisateur veut s'en servir dans cette conversation.

## Sur claude.ai

Pas de mémoire auto : la mémoire sert dans la conversation. Le bac à sable a un shell, git, et l'accès GitHub de l'app de Claude ; les scripts du plugin y tournent, avec un dossier de travail à la place de la mémoire auto.

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas encore été fixé dans cette conversation, passe par le skill setup (section claude.ai) : il trouve le dépôt et le fait confirmer.
2. **Nom du projet.** Premier argument, sinon demande-le ; le script liste les projets disponibles en cas de nom inconnu (code 3).
3. **Pull** dans le dossier de travail :
   `CLAUDE_MEMOIRE_REPO=<url> bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh "<projet>" /home/claude/memoire/<projet>`
   Pas de simulation nécessaire au premier pull de la conversation : le dossier est vide, tout est `nouveau`. Code 2 : accès refusé, voir le skill setup.
4. **Lire** `MEMORY.md` dans ce dossier, puis seulement les fichiers utiles au sujet de la conversation. Garde-les en contexte et dis en une ligne ce que tu as chargé. Rien n'est écrit dans le dépôt.
