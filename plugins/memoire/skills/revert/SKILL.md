---
name: revert
description: "Remet le dossier d'un projet, ou la mémoire générale, dans l'état d'un commit précis du dépôt mémoire. Avec l'identifiant du commit, ou en le choisissant parmi les derniers commits du dossier. À utiliser quand l'utilisateur demande de revenir en arrière, restaurer, annuler une consolidation ou retrouver une version précédente de sa mémoire. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet | generale] [commit]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *)
---

# Revenir à une version précédente de la mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Sinon, tu es sur claude.ai : mêmes étapes, avec `CLAUDE_MEMOIRE_REPO=<url>` devant chaque commande (voir le skill setup, section claude.ai).

Ce que fait le revert : dans le clone du dépôt mémoire, le dossier choisi (`projets/<nom>/` ou `general/`) redevient ce qu'il était au commit choisi, fichiers ajoutés depuis retirés compris. Ce qui n'était pas encore commité dans ce dossier est d'abord enregistré dans un commit local, donc rien ne se perd. Le dépôt n'est pas modifié et aucun historique n'est réécrit : le prochain push enverra cet état d'avant comme un nouveau commit (l'avertissement de perte s'affichera, c'est attendu), et les versions plus récentes restent lisibles.

## Étapes

1. **Cible.** Premier argument : un nom de projet, ou `generale`. Sans argument, liste les projets avec `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et pose la question. Confirme le nom tel qu'il apparaît dans le dépôt.
2. **Commit.** Second argument s'il est donné. Sinon :
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh "<cible>"`
   Le script affiche les derniers commits du dossier, du plus récent au plus ancien, chacun avec sa date, son titre et la première ligne de son récap. S'il signale que le dépôt a des commits que ce clone n'a pas encore, propose le skill pull d'abord. Pose une seule question avec AskUserQuestion qui propose les quatre plus pertinents (hash, date, récap en une ligne), en précisant que l'utilisateur peut donner un autre identifiant. Ne choisis jamais à sa place.
3. **Simulation.**
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revert.sh "<cible>" <sha> --dry-run`
   Code 3 : projet ou commit inconnu, ou dossier absent à ce commit, montre le message et arrête-toi. Code 10 : skill setup, puis reviens ici.
4. **Confirmation.** Pose une seule question avec AskUserQuestion dont le texte contient le commit visé (hash, date, titre), le bilan du script (fichiers à restaurer, à retirer, identiques) et la liste des fichiers qui seraient retirés, suivi de « Restaurer cet état ? », options « Restaurer », « Annuler ». Rappelle dans la question que le dépôt n'est pas touché et que le travail en cours du dossier est d'abord commité en local.
5. **Exécution.** Même commande sans `--dry-run`.
   Code 6 : une fusion est en cours dans le clone, à conclure ou annuler d'abord (skill pull). Code 5 : un motif de secret dans le travail local à commiter, à corriger avant.
6. **Conclusion.** Deux lignes : l'état restauré (commit, nombre de fichiers) et le rappel que la mémoire sera chargée au prochain démarrage de session. Puis, selon ce que l'utilisateur a dit vouloir faire : relancer une consolidation (skill consolider) ou renvoyer cet état dans le dépôt (skill push, avec l'avertissement de perte à confirmer).
