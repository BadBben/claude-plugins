# Changelog du plugin memoire

Une section par version, la plus récente en premier. La section de la version publiée sert de description à la pull request sur la marketplace publique.

## 0.7.0

Changement de fond : le dépôt mémoire est cloné une fois sur l'appareil, et ce clone devient la mémoire. Git transporte et fusionne ; le moteur de synchronisation maison disparaît.

- Clone durable dans `~/claude-memory` (variable `CLAUDE_MEMOIRE_DIR` pour le déplacer), créé par `setup`. Un clone n'est jamais supprimé ni remplacé par le plugin.
- Un projet se branche sur le clone par le réglage `autoMemoryDirectory` de Claude Code, écrit par le skill `setup` dans `.claude/settings.local.json` du dossier de travail : plus de copie entre la mémoire auto et le dépôt.
- `pull` et `push` ont une portée : le projet de la session et la partie transverse du dépôt (la mémoire générale et les fichiers de la racine). Le travail en cours des autres projets n'est ni commité ni poussé, et le push le liste à part. Options `--memory-dir <dossier de mémoire de la session>`, `--project <nom>`, et `--all` pour tout le dépôt sur demande explicite. Sans option, seule la partie transverse est couverte.
- Le pull fusionne tout le dépôt, mais ne commite avant la fusion que le travail local de la portée. Si la fusion devait écraser le travail non commité d'un autre projet, il s'arrête avant tout commit (nouveau code 8) et `--include <projet>` fait entrer ce projet dans la fusion. Le résumé du pull est rangé par projet.
- Conflits : git fusionne et montre l'ancêtre commun dans les fichiers ; Claude explique ce que dit chaque version et propose un texte fusionné ou un choix argumenté. Nouvelles options `pull.sh --conclude` (qui n'enregistre que les fichiers en conflit), `--drop <chemin>` et `--abort`.
- Contrôles gardés, limités aux fichiers qui partent : secret (code 5, y compris dans un commit local pas encore poussé), marqueurs de conflit (code 6), perte (code 7). Le push n'écrase plus jamais rien : un dépôt en avance demande toujours un pull (code 4), et `--force` ne sert qu'à laisser passer un faux positif de secret.
- La mémoire générale se lit dans `general/` du clone ; `generale.sh pull` et `generale.sh push` disparaissent.
- `revert` restaure le dossier d'un projet dans le clone, après avoir commité en local le travail en cours.
- Les marqueurs `.memoire-sync`, l'option `--mirror` du pull et la copie locale de la mémoire générale ne sont plus utilisés.

Migration depuis une 0.6.x : pousser les mémoires locales tant que la 0.6.x est installée, puis `/memoire:setup` pour cloner le dépôt et `/memoire:setup <nom>` dans chaque dossier de travail pour brancher le projet. `setup.sh --compare` et `generale.sh --compare-old` montrent ce que les anciennes copies locales ont de plus que le clone. Rien n'est supprimé : les anciens dossiers restent en place.

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
