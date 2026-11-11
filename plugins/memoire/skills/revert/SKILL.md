---
name: revert
description: "Remet la mémoire locale d'un projet, ou la mémoire générale, dans l'état d'un commit précis du dépôt mémoire, en miroir. Avec l'identifiant du commit, ou en le choisissant parmi les derniers commits du dossier. À utiliser quand l'utilisateur demande de revenir en arrière, restaurer, annuler une consolidation ou retrouver une version précédente de sa mémoire. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet | generale] [commit]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *)
---

# Revenir à une version précédente de la mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Sinon, tu es sur claude.ai : mêmes étapes, avec `CLAUDE_MEMOIRE_REPO=<url>` devant chaque commande et `/home/claude/memoire/<projet>` comme dossier (voir le skill setup, section claude.ai).

Ce que fait le revert : la copie locale devient, en miroir, le dossier tel qu'il était au commit choisi. Le dépôt n'est pas modifié, et le marqueur de synchro est posé sur la tête actuelle du dossier : le prochain push renverra cet état d'avant comme un nouveau commit (l'avertissement de perte s'affichera, c'est attendu), l'historique reste linéaire et les versions plus récentes restent lisibles.

## Étapes

1. **Cible.** Premier argument : un nom de projet (sa mémoire auto, chemin dans la section « Memory » de ton prompt système, jamais deviné) ou `generale` (copie locale, dossier `-`). Sans argument, liste les projets avec `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et pose la question. Confirme le nom tel qu'il apparaît dans le dépôt.
2. **Commit.** Second argument s'il est donné. Sinon :
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh "<projet>" "<dossier>" --list`
   Le script affiche les derniers commits du dossier, du plus récent au plus ancien, chacun avec sa date, son titre et la première ligne de son récap. Pose une seule question avec AskUserQuestion qui propose les quatre plus pertinents (hash, date, récap en une ligne), en précisant que l'utilisateur peut donner un autre identifiant. Ne choisis jamais à sa place.
3. **Simulation.**
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh "<projet>" "<dossier>" --commit <sha> --dry-run`
   Code 3 : commit inconnu, ou dossier absent à ce commit, montre le message et arrête-toi. Code 10 : skill setup, puis reviens ici.
4. **Confirmation.** Pose une seule question avec AskUserQuestion dont le texte contient le commit visé (hash, date, titre), le bilan du script (fichiers à restaurer, à retirer, identiques) et la liste des fichiers qui seraient retirés, suivi de « Restaurer cet état en miroir ? », options « Restaurer », « Annuler ». Rappelle dans la question que le dépôt n'est pas touché.
5. **Exécution.** Même commande sans `--dry-run`.
6. **Conclusion.** Deux lignes : l'état restauré (commit, nombre de fichiers) et le rappel que la mémoire sera chargée au prochain démarrage de session. Puis, selon ce que l'utilisateur a dit vouloir faire : relancer une consolidation (skill consolider) ou renvoyer cet état dans le dépôt (skill push, avec l'avertissement de perte à confirmer).
