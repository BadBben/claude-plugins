---
name: push
description: "Envoie dans le dépôt mémoire ce qui a changé dans la mémoire du projet de la session et dans la mémoire générale, après contrôles et confirmation (commit, puis push). Les autres projets ne partent pas. À utiliser quand l'utilisateur demande de sauvegarder, pousser, partager ou publier la mémoire, ou de la rendre disponible sur un autre appareil. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *)
---

# Envoyer la mémoire locale dans le dépôt partagé

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

Le dépôt mémoire est cloné une fois sur l'appareil (par défaut dans `~/claude-memory`) et les projets branchés dessus y écrivent directement. C'est la seule situation où un commit et un push sont faits à la demande de l'utilisateur, et c'est le script qui s'en charge. Tu n'exécutes jamais git toi-même.

**Portée.** Un push envoie le travail du projet de la session et de la partie transverse (la mémoire générale et les fichiers de la racine). Le travail en cours des autres projets n'est ni commité ni poussé : le script le liste à part, et il reste tel quel sur l'appareil. Les options de portée, à répéter à l'identique sur chaque appel de `push.sh` (simulation, puis commit) :
- `--memory-dir "<dossier>"` : le dossier de mémoire auto de cette session, chemin exact de la section « Memory » de ton prompt système, jamais deviné. C'est l'option par défaut.
- `--project "<nom>"` à la place, quand l'utilisateur nomme un projet.
- `--all` seulement si l'utilisateur demande explicitement de pousser tous les projets.

## Dans Claude Code

1. **Simulation.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh --dry-run --memory-dir "<dossier de mémoire auto>"`
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup, puis reviens ici.
   Code 4 : le dépôt a avancé, un autre appareil a poussé. Explique-le et propose le skill pull, qui fusionne ; il n'existe aucun moyen de forcer.
   Code 5 : un motif de secret, dans un fichier ou dans un commit local pas encore poussé. Montre ce que le script nomme et propose de corriger. N'ajoute `--force` que si l'utilisateur te dit que c'est un faux positif.
   Code 6 : des marqueurs de conflit restent dans un fichier, ou une fusion est en cours. Reprends le skill pull à son étape des conflits, puis recommence.
   Code 11 : le clone appartient à un autre dépôt, montre le message et arrête-toi. Code 2 : git a échoué, montre l'erreur et arrête-toi.
   Si le script écrit que le dossier de mémoire est hors du clone, ce que cette session a mémorisé n'est pas dans le clone et ne partirait pas : dis-le et propose le skill setup (étape « Brancher un projet »), puis reviens ici.
   Avertissement « perte possible » (fichiers supprimés, ou beaucoup plus de lignes retirées qu'ajoutées) : la simulation l'affiche et le commit exigera `--accept-loss`. Reporte l'avertissement dans la question de l'étape 3, et n'ajoute `--accept-loss` à l'étape 4 que si l'utilisateur a confirmé en l'ayant vu.
2. **Message de commit.** Le script annonce la portée sur sa première ligne. S'il dit « Rien a pousser », réponds d'une phrase, signale ce qui reste en local dans d'autres projets s'il le liste, et arrête-toi. Sinon, deux cas :
   - Il affiche le bloc « Message de commit » : le titre, une ligne « (recap a rediger par la session) », puis la liste des fichiers. Rédige le récap : deux ou trois phrases sur ce qui a changé dans le contenu de la mémoire, ton naturel, sans tiret long, sans guillemets doubles, sans `$` ni accent grave. Le message complet, c'est le titre tel quel, ton récap, la liste des fichiers telle quelle.
   - Il affiche « Rien de nouveau a commiter » suivi de commits locaux : ce sont des commits déjà faits par un pull (le travail local d'avant la fusion, la fusion elle-même). Ils partent tels quels, sans récap ; la question montre leur liste et celle des fichiers.
3. **Confirmation.** Pose une seule question avec AskUserQuestion dont le texte contient le message de commit complet (ou la liste des commits locaux), suivi de « Pousser ? », options « Pousser », « Annuler ». Ajoute dans la question, quand le script les affiche :
   - le bloc « Restent en local » : les fichiers d'autres projets qui ne partent pas, en une ligne par projet ;
   - la ligne « Attention : ces commits deja faits touchent aussi d'autres projets » : des commits antérieurs emportent un autre projet avec eux, il faut que l'utilisateur le sache avant de dire oui.

   Tout doit être lisible dans la question elle-même : sur claude.ai, elle est la seule chose que l'utilisateur voit. N'écris rien d'autre avant la question.
4. **Exécution.** La même commande avec `--commit --message "<récap>"` à la place de `--dry-run`, avec `--accept-loss` seulement si la perte a été montrée et confirmée, et `--force` seulement pour un faux positif de secret déclaré par l'utilisateur.
   Code 4 à ce stade : un autre appareil a poussé entre la simulation et le push. Le commit est gardé dans le clone, rien n'est perdu : skill pull, puis relance.
5. **Conclusion.** Une ligne : le hash du commit, le nombre de fichiers, et le commit d'avant (ligne « Etat d'avant » du script). Une ligne de plus s'il reste du travail en local dans d'autres projets. Rien d'autre.

## Sur claude.ai

Pas de mémoire auto : ce qu'il y a à sauvegarder, c'est ce que la conversation a appris. Le clone du bac à sable (`~/claude-memory`) reçoit tes fiches, et les scripts font le reste avec les mêmes contrôles. La portée se donne par `--project "<nom>"`.

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai).
2. **Partir de l'état du dépôt.** `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --project "<nom>"` : il clone au premier appel, met à jour ensuite. Lis `MEMORY.md` du projet (`~/claude-memory/projets/<projet>/memory/`) et les fiches concernées par le sujet.
3. **Écrire** dans ce dossier ce que la conversation a établi et qui manque : un sujet par fiche, nom en kebab-case, en-tête natif (`name`, `description` entre guillemets, `metadata.type` parmi user, feedback, project, reference), et une ligne par fiche dans `MEMORY.md`. Modifie une fiche existante plutôt que d'en créer un doublon. Jamais de secret.
4. **Simulation** : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh --dry-run --project "<nom>"`. Mêmes codes de sortie que dans Claude Code. Code 4 : un appareil a poussé depuis ton pull, refais le pull (il fusionne) puis recommence.
5. **Message, confirmation, exécution, conclusion** : étapes 2 à 5 de « Dans Claude Code », avec `CLAUDE_MEMOIRE_REPO` et `CLAUDE_MEMOIRE_HOST=claude.ai` sur la commande `--commit`.
