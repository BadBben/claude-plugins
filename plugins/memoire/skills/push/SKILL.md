---
name: push
description: "Sauvegarde la mémoire auto locale du projet courant dans le dépôt mémoire configuré, après confirmation (copie, commit, push). À utiliser quand l'utilisateur demande de sauvegarder, pousser, partager ou publier la mémoire, ou de la rendre disponible sur un autre appareil. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh *)
---

# Sauvegarder la mémoire locale dans le dépôt partagé

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

C'est la seule situation où un commit et un push git sont faits à la demande de l'utilisateur : le script s'en charge, dans un clone temporaire du dépôt mémoire. Tu n'exécutes jamais git toi-même.

## Dans Claude Code

1. **Nom du projet.** Prends le premier argument. S'il manque, liste les projets du dépôt avec `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et propose-les dans une question, avec le nom du dossier de travail courant s'il n'y figure pas (premier push) ; ne continue qu'avec un nom confirmé.
2. **Dossier de mémoire auto locale.** Son chemin exact figure dans ton prompt système, section « Memory ». Utilise-le tel quel. Ne le devine jamais.
3. **Simulation.** Exécute :
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh "<projet>" "<dossier mémoire locale>" --dry-run`
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup, puis reviens ici.
   Code 4 : le dépôt a avancé depuis la dernière synchro de cet appareil. Explique-le, propose le skill pull d'abord (il fusionne), et ne propose `--force` que si l'utilisateur dit vouloir écraser.
   Code 5 : un motif de secret a été détecté. Montre les fichiers, propose de les corriger, et ne force jamais de toi-même.
   Code 6 : un fichier contient encore des marqueurs de conflit laissés par un pull. Montre les fichiers, résous les marqueurs avec l'utilisateur (voir le skill pull), puis recommence.
   Code 2 : git a échoué, montre l'erreur et arrête-toi.
   Avertissement « perte possible » (fichiers supprimés, ou beaucoup plus de lignes retirées qu'ajoutées) : la simulation l'affiche et le commit exigera `--accept-loss`. Reporte l'avertissement dans la question de l'étape 5, et n'ajoute `--accept-loss` à l'étape 6 que si l'utilisateur a confirmé en l'ayant vu.
4. **Message de commit.** Si le script dit « Rien a pousser », réponds d'une phrase et arrête-toi. Sinon il affiche le bloc « Message de commit » : le titre, une ligne « (recap a rediger par la session) », puis la liste des fichiers. Rédige le récap : deux ou trois phrases sur ce qui a changé dans le contenu de la mémoire, ton naturel, sans tiret long, sans guillemets doubles, sans `$` ni accent grave. Le message complet, c'est le titre tel quel, ton récap, la liste des fichiers telle quelle.
5. **Confirmation.** Pose une seule question avec AskUserQuestion dont le texte contient le message de commit complet, suivi de « Pousser ce commit ? », options « Pousser », « Annuler ». Le message doit être lisible dans la question elle-même : sur claude.ai, la question est la seule chose que l'utilisateur voit. N'écris rien d'autre avant la question.
6. **Exécution.** Relance le script avec `--commit --message "<récap>"` (et `--force` seulement si l'utilisateur l'a demandé explicitement).
7. **Conclusion.** Une ligne : le hash du commit, le nombre de fichiers, et le commit d'avant (ligne « Etat d'avant » du script). Rien d'autre.

## Sur claude.ai

Pas de mémoire auto à copier : la mémoire à sauvegarder est ce que la conversation a appris. Le dossier de travail `/home/claude/memoire/<projet>` joue le rôle de la mémoire locale, et les scripts font le reste avec les mêmes garde-fous.

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai).
2. **Partir de l'état du dépôt.** Si le dossier de travail n'existe pas encore, fais d'abord le pull du skill pull (section claude.ai) : il crée le dossier et le marqueur de synchro, sans lequel le push refuserait (code 4). Lis `MEMORY.md` et les fichiers concernés par le sujet.
3. **Écrire** dans ce dossier ce que la conversation a établi et qui manque : un fait par fichier, nom en kebab-case, en-tête natif (`name`, `description` entre guillemets, `metadata.type` parmi user, feedback, project, reference), et une ligne par fichier dans `MEMORY.md`. Modifie un fichier existant plutôt que d'en créer un doublon. Jamais de secret.
4. **Simulation** :
   `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh "<projet>" /home/claude/memoire/<projet> --dry-run`
   Mêmes codes de sortie que dans Claude Code. Code 4 : un autre appareil a poussé depuis le pull, refais le pull (il fusionne) puis recommence.
5. **Message, confirmation, exécution, conclusion** : étapes 4 à 7 de « Dans Claude Code », avec `CLAUDE_MEMOIRE_REPO` et `CLAUDE_MEMOIRE_HOST=claude.ai` sur la commande `--commit`.
