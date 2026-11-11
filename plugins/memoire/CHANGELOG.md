# Changelog du plugin memoire

Une section par version, la plus récente en premier. La section de la version publiée sert de description à la pull request sur la marketplace publique.

## 0.6.3

- La marketplace a un nouveau nom de dépôt, `BadBben/claude-plugins` ; le nom de marketplace `badbben` ne change pas.
- La marketplace ne reçoit plus que des versions publiées : son README et son `marketplace.json` arrivent avec chaque release.
- README du plugin : la section développement décrit le travail sur une copie, plus dans la marketplace.

## 0.6.2

- `consolider` fait converger une mémoire de projet vers une forme prévisible par familles de fiches (`projet`, `etat`, `regles`, `decisions`, `references`, `pieges`, `equipe`, `journal`), avec des noms `famille-theme.md` et un index dans le même ordre.
- Règles de fusion, de découpage et de renommage explicites ; les conventions de dépôt sont proposées pour le `CLAUDE.md` du dépôt de code, après accord, et la mémoire n'en garde qu'un pointeur.
- Compte rendu en cinq groupes (fusionné, découpé ou renommé, déplacé vers `CLAUDE.md`, déplacé au journal, retiré).

## 0.6.1

- Version publiable : auteur et descriptions sans mention personnelle, renvoi vers le modèle de dépôt `claude-memory-template`.

## 0.6.0

- Nouveau skill `revert` : remet la copie locale d'un projet, ou la générale, dans l'état d'un commit du dépôt, choisi parmi les derniers commits du dossier. Le dépôt n'est pas modifié ; le push suivant renvoie cet état comme un nouveau commit.

## 0.5.2

- Le nom de projet est résolu contre le dépôt sans tenir compte de la casse, et un marqueur de synchro sans commit est refusé.
- Le push affiche le commit d'avant dans tous les cas ; `setup --list` liste les projets et la générale du dépôt.
- `consolider` : renommage autorisé quand le sujet fusionné dépasse le nom, règles pour les liens et pour les champs d'en-tête ajoutés par Claude Code.

## 0.5.1

- Correction : un nom de projet écrit avec des majuscules alors que le dépôt le range en minuscules rendait les garde-fous aveugles sur un système de fichiers insensible à la casse.

## 0.5.0

- Nouveau skill `consolider` : réorganise une mémoire sans rien supprimer, le daté part dans `journal.md`, compte rendu, push de référence avant et push après.
- Garde-fou de perte au push : un fichier supprimé, ou beaucoup plus de lignes retirées qu'ajoutées, est signalé et refusé (code 7) sans `--accept-loss`.

## 0.4.7

- Sur claude.ai, le dépôt n'est confirmé que s'il est deviné ; il peut venir des instructions ou des connaissances du Projet, ou de la mémoire claude.ai du compte.

## 0.4.6

- Le message de commit est écrit dans le texte de la question de confirmation : sur claude.ai, la question est la seule chose visible.

## 0.4.5

- Sur claude.ai, le dépôt est attaché à la session avant le premier clone.

## 0.4.4

- Les scripts fonctionnent dans le bac à sable claude.ai : dépôt par `CLAUDE_MEMOIRE_REPO`, hôte par `CLAUDE_MEMOIRE_HOST`, identité git de repli, dossier de travail à la place de la mémoire auto. Les skills choisissent leur branche selon l'environnement.

## 0.4.3

- Documentation de la mise à jour : bouton de synchronisation côté app desktop, `claude -p ok --model haiku`.

## 0.4.2

- Documentation de la propagation des mises à jour.

## 0.4.1

- `argument-hint` entre guillemets ; le script imprime le message de commit tel quel et les skills `push` et `generale` ne montrent que ce message puis la question.

## 0.4.0

- Distribution par le compte claude.ai, zéro clone persistant (clone temporaire partiel), dépôt configuré une fois par `setup`, copie locale de la mémoire générale, skills neutres avec une section claude.ai.
