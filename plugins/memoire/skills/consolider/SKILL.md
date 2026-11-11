---
name: consolider
description: "Consolide une mémoire, celle d'un projet ou la mémoire générale : la fait converger vers une forme prévisible par familles de fiches, fusionne ou découpe, déplace les conventions de dépôt vers le CLAUDE.md, déplace le daté dans un journal sans rien supprimer, allège l'index, rend compte de chaque mouvement. À utiliser quand l'utilisateur demande de consolider, nettoyer, ranger, alléger ou réorganiser une mémoire. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet | generale]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Read, Write, Edit
---

# Consolider une mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Sinon, tu es sur claude.ai : mêmes étapes, avec `CLAUDE_MEMOIRE_REPO=<url>` devant chaque commande et `~/claude-memory/projets/<projet>/memory` comme dossier de mémoire, dans le clone du bac à sable (voir le skill setup, section claude.ai).

Principe : une consolidation réorganise, elle ne supprime pas. Elle fait converger la mémoire vers une forme prévisible, pour qu'une session sache d'avance où chercher. Ce qui est daté ou dépassé va dans un journal. Chaque mouvement est listé. Le dépôt garde l'état d'avant.

## Forme cible d'une mémoire de projet

Une mémoire de projet est faite de **familles** de fiches, toujours les mêmes, dans cet ordre. Le nom d'une fiche commence par le nom de sa famille : une fiche par famille quand c'est court, plusieurs `famille-theme.md` quand un thème mérite sa fiche.

| Famille | Contenu | `metadata.type` |
| --- | --- | --- |
| `projet` | une seule fiche, `projet.md` : quoi, pour qui, avec qui, dates clés, où vivent les choses (dépôts, docs, CLAUDE.md), et un court « où trouver quoi » dans cette mémoire | project |
| `etat` | où on en est et la suite immédiate ; courte, réécrite à chaque fois, le passé part au journal | project |
| `regles` | comment l'utilisateur veut travailler sur ce projet avec Claude : préférences, interdits, rituels ; pas les conventions du dépôt, qui vont dans `CLAUDE.md` | feedback |
| `decisions` | choix faits et leur pourquoi, datés, numérotés s'il y a une numérotation dans le projet ; une décision remplacée part au journal | project |
| `references` | environnements, données, comptes, URLs, commandes utiles ; jamais de secret | reference |
| `pieges` | ce qui a surpris ou coûté : pièges techniques, erreurs à ne pas refaire, leçons | feedback |
| `equipe` | optionnelle : les personnes, leur rôle, comment on leur parle, ce qui leur est dû | reference |
| `journal` | une seule fiche, `journal.md`, en ajout seul : ce que les consolidations ont retiré des fiches, par date | project |

Exemples de noms conformes : `regles.md`, `regles-front.md`, `decisions-metriques.md`, `references-donnees-client.md`, `pieges-backend.md`. Le nom dit la famille puis le thème, rien d'autre : pas de nom-phrase (« backend-only-never-touch-front »), le sens va dans `description` et dans l'accroche de l'index.

`MEMORY.md` reprend les familles dans le même ordre, une section par famille, une ligne par fiche : `- [Titre](fichier.md) : accroche`. Moins de 200 lignes. Pas de tiret long.

La mémoire générale a sa propre forme (`profil/`, `projets/`, `references/`, `apprentissages/`) : on la respecte telle quelle, les règles de fusion, de journal et de compte rendu s'appliquent de la même façon.

## Étapes

1. **Cible.** Premier argument : un nom de projet (sa mémoire dans le clone du dépôt, chemin affiché par `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --project "<nom>"`, ligne `memoire=`, jamais deviné) ou `generale` (dossier `general/` du clone, chemin affiché par `generale.sh path`). Sans argument, liste les projets du dépôt avec `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et pose la question. Dans tous les cas, confirme le nom tel qu'il apparaît dans le dépôt avant de continuer.
2. **Partir du frais.** Pull, avec la portée de la cible sur chaque commande : `--project "<projet>"` pour un projet, aucune option de portée pour `generale`. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --dry-run --project "<projet>"`, puis la même commande sans `--dry-run` s'il y a quelque chose à récupérer. Code 8 ou conflits : traite-les d'abord comme le dit le skill pull, et conclus la fusion.
3. **État de référence.** Push avant de toucher quoi que ce soit, pour que le dépôt ait la version d'avant : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh --dry-run --project "<projet>"` puis, s'il y a quelque chose, question « Pousser ? » avec le message, puis `--commit --message "<récap>"` avec la même portée. S'il n'y a rien à pousser, le dépôt est déjà la référence.
4. **Inventaire.** Liste le dossier, lis `MEMORY.md`, lis chaque fiche. Pour un projet de code, lis aussi le `CLAUDE.md` du dépôt (racine et sous-dossiers concernés) : c'est là que vivent les conventions. Note pour chaque fiche sa famille cible, les doublons, le périmé, les fiches chronologiques, les dates relatives, et ce qui est en fait une convention de dépôt.
5. **Conventions vers CLAUDE.md** (projets de code). Une règle qui vaut pour toute session dans ce dépôt, quel que soit le sujet (style de code et de commentaires, commandes à lancer ou à ne pas lancer, structure, interdits techniques) n'est pas une mémoire : sa place est dans le `CLAUDE.md` du dépôt, chargé à chaque session. Propose la liste de ce qui devrait y aller, avec l'emplacement (racine ou sous-dossier). Après accord de l'utilisateur, écris-le dans le `CLAUDE.md` (sans commit : c'est son dépôt de code, il commite), et la fiche d'origine ne garde qu'un pointeur d'une ligne ou disparaît si elle ne contenait que ça. Sans accord, rien ne bouge et la fiche reste.
6. **Consolidation**, dans le dossier de la cible, dans le clone :
   - Famille d'abord : chaque fiche rejoint sa famille. Fusionne quand plusieurs fiches disent la même chose ou relèvent du même thème (trois fiches de règles git deviennent `regles-git.md`), découpe quand une fiche mélange deux familles ou dépasse ce qu'une session lit d'un trait (environ 3 Ko), renomme pour entrer dans la forme. Une fiche n'est retirée que si tout son contenu utile est dans une autre fiche, dans `CLAUDE.md` ou dans le journal, et le compte rendu le dit.
   - Durable et daté : règles, décisions et leur pourquoi, références, pièges sont durables, à garder et affiner. Chronologie, étapes terminées, états intermédiaires, messages envoyés, tâches faites sont datés : ils partent dans `journal.md`, et `etat` ne garde que le présent.
   - Dates : toute date relative devient absolue.
   - Ne pas jeter ce qui serait pénible à retrouver : un fait qui contredit la doc officielle, une décision et sa raison, un piège rencontré. Jeter seulement ce qui est littéralement ailleurs et pointé (CLAUDE.md, README, historique git).
   - Liens `[[...]]` : dans les fiches vivantes, ils pointent vers des fiches qui existent encore (corrige-les ou remplace-les par le nom en clair). Dans le journal, le texte est recopié tel quel, liens compris : c'est une archive.
   - En-tête natif (`name`, `description` entre guillemets, `metadata.type` selon la famille). Claude Code ajoute lui-même `node_type`, `originSessionId` et `modified` : laisse-les, ne les recopie pas dans une fiche neuve.
   - Jamais de secret.
7. **Journal.** `journal.md` à la racine de la mémoire, en ajout seul, avec cet en-tête s'il n'existe pas :
   ```
   ---
   name: journal
   description: "Journal daté de cette mémoire : ce que les consolidations ont retiré des fiches, par date"
   metadata:
     type: project
   ---
   ```
   Puis une section `## <date de la consolidation>` et, dedans, chaque élément déplacé avec sa date d'origine et sa provenance (`de <fichier>`). Ajoute sa ligne dans `MEMORY.md` à la première création.
8. **Compte rendu.** Avant toute question, écris la liste de ce qui a changé, en cinq groupes : fusionné (quoi dans quoi), découpé ou renommé (ancien nom, nouveaux noms), déplacé vers `CLAUDE.md` (quoi, où), déplacé au journal, retiré (seulement ce qui est littéralement ailleurs, avec l'endroit). Si un groupe est vide, dis-le. Termine par ce que tu n'as pas pu trancher.
9. **Push.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh --dry-run --project "<projet>" --message "<récap>"` (sans `--project` pour `generale`). Le script peut signaler une perte possible (fichiers supprimés, ou beaucoup plus de lignes retirées qu'ajoutées) et demander `--accept-loss` : c'est attendu après une consolidation. Pose une seule question avec AskUserQuestion dont le texte contient le message de commit complet, l'avertissement de perte s'il y en a un, et « Pousser ? », options « Pousser », « Annuler ». S'il confirme : `--commit --message "<récap>"`, avec `--accept-loss` seulement si l'avertissement a été montré dans la question.
10. **Conclusion.** Une ligne : le hash du commit, le nombre de fichiers, et le commit de référence d'avant (ligne « Etat d'avant » affichée par le script au push) pour revenir en arrière si besoin. Si tu as écrit dans un `CLAUDE.md`, rappelle qu'il est à commiter dans le dépôt de code.
