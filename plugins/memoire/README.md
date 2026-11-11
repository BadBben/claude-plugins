# memoire

Mémoire partagée entre appareils pour Claude Code, avec un dépôt git comme source unique. Le dépôt est cloné une fois sur chaque appareil, et ce clone est la mémoire : chaque projet y lit et y écrit sa mémoire auto directement. Le dépôt distant n'est lu ou écrit que sur demande, par six skills.

## Principe

- Un clone durable par appareil, dans `~/claude-memory` par défaut, le même chemin partout. C'est un clone git ordinaire : il s'ouvre dans un éditeur, un explorateur de fichiers ou un outil de notes, et `git log` y raconte l'histoire de la mémoire.
- Un projet se branche sur le clone par un réglage de Claude Code, `autoMemoryDirectory`, posé une fois dans son dossier de travail : sa mémoire auto vit alors dans `projets/<nom>/memory/` du clone. Le dossier de travail ne bouge pas, et rien n'est copié entre les deux.
- Git transporte et fusionne. Le plugin ajoute ce que git ne fait pas : un résumé en clair avant d'agir, des contrôles avant tout envoi (secret, marqueurs de conflit, perte), et l'aide de Claude pour résoudre un conflit en expliquant ce que dit chaque version.
- Un pull ou un push a une portée : le projet de la session et la partie transverse du dépôt, c'est-à-dire la mémoire générale et les fichiers de la racine. Le travail en cours des autres projets n'est jamais commité ni poussé par effet de bord.
- En dehors du clone, un seul fichier : `~/.claude/memoire/config.json`, qui ne contient que l'URL du dépôt.
- Pas de jeton : l'authentification git est celle de la machine (Git Credential Manager sur Windows, gestionnaire d'identifiants ou `gh auth login` ailleurs). Sur claude.ai, c'est le connecteur GitHub de l'utilisateur.

## Prérequis

- Claude Code connecté à un compte claude.ai (pour recevoir le plugin) ; Git 2.25 ou plus récent, 2.35 pour que les conflits montrent aussi l'ancêtre commun. Sur Windows, Git for Windows : les scripts tournent dans Git Bash.
- Une identité git : `git config --global user.name` et `user.email`.
- Un dépôt git privé pour la mémoire. Le plus simple : le créer depuis le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template) (bouton « Use this template », visibilité privée), qui contient la structure et le format attendus. Un dépôt vide fonctionne aussi : le premier push crée ce qu'il faut.
- Un emplacement de clone hors de tout dossier synchronisé par un service de fichiers (OneDrive, Dropbox, iCloud) : deux synchronisations qui écrivent dans le même dossier `.git` finissent par l'abîmer.

## Premier usage

1. Demander « configure ma mémoire partagée » (ou `/memoire:setup <url>`) et donner l'URL du dépôt mémoire (HTTPS, SSH ou `proprietaire/depot`). Le script clone le dépôt (le navigateur peut s'ouvrir pour la connexion GitHub, une fois), écrit la configuration, liste les projets présents et dit si une mémoire générale existe.
2. Dans le dossier de travail d'un projet, demander « branche ce projet sur ma mémoire » (ou `/memoire:setup <nom>`). Le skill écrit le réglage `autoMemoryDirectory` dans `.claude/settings.local.json` de ce dossier, crée la mémoire du projet si elle n'existe pas encore, et regarde ce que l'ancienne mémoire locale aurait de plus. Ouvrir ensuite une nouvelle session : la commande `/memory` doit montrer un dossier du clone.
3. Au quotidien : « récupère la mémoire » (`/memoire:pull`) en arrivant sur un appareil, « sauvegarde la mémoire » (`/memoire:push`) avant d'en changer.

Pour changer de dépôt : `/memoire:setup <nouvelle-url>`. Le skill montre l'ancienne URL et demande confirmation. Un clone n'est jamais supprimé ni remplacé par le plugin : il faut déplacer ou renommer le dossier soi-même, puis relancer.

## Les skills

| Commande | Ce qu'elle fait |
| --- | --- |
| `/memoire:setup [url ou projet]` | Configure le dépôt mémoire de l'appareil et le clone. Branche un projet sur sa mémoire dans le clone. Montre l'état du clone (`--status`) et ce qu'il contient (`--list`). |
| `/memoire:pull [projet]` | Met le clone à jour : simulation et résumé par projet, confirmation, puis fusion par git. Seul le travail local du projet de la session et de la partie transverse est commité avant la fusion. En cas de conflit, Claude explique ce que dit chaque version, propose un texte fusionné ou un choix argumenté, et conclut la fusion une fois les fichiers réglés. |
| `/memoire:push [projet]` | Envoie ce qui a changé dans le projet de la session et dans la partie transverse : contrôles, message de commit montré tel quel avec un récap, confirmation, commit et push. Ce qui reste en local dans les autres projets est listé à part. |
| `/memoire:generale [sujet]` | Lit l'index de `general/` puis le fichier utile. Peut y ajouter une entrée et la pousser sur demande. |
| `/memoire:consolider [projet ou generale]` | Réorganise une mémoire sans rien supprimer : pousse d'abord l'état de référence, fusionne les doublons, déplace le daté dans `journal.md`, allège l'index, rend compte de chaque déplacement, puis pousse après confirmation. |
| `/memoire:revert [projet ou generale] [commit]` | Remet le dossier d'un projet, ou la mémoire générale, dans l'état d'un commit, après simulation et confirmation. Sans commit, propose les derniers commits du dossier. Le dépôt n'est pas touché ; un push renverra cet état comme un nouveau commit. |

Les skills se déclenchent aussi sur une demande en clair (« récupère la mémoire », « sauvegarde la mémoire », « regarde dans ma mémoire générale »). Un rappel dans `~/.claude/CLAUDE.md` aide :

```
## Mémoire partagée (plugin memoire)
- Quand je demande de charger, récupérer ou reprendre la mémoire d'un projet : skill /memoire:pull.
- Quand je demande de sauvegarder, pousser ou partager la mémoire : skill /memoire:push.
- Pour une question sur moi, mes autres projets, mon environnement, ou un nom de projet inconnu : skill /memoire:generale.
- Sans demande de ma part, ne touche jamais au dépôt mémoire.
```

## Le dépôt mémoire

Structure attendue, fournie par le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template) :

```
<depot>/
  general/                 mémoire générale, hors projet
    MEMORY.md              index : une ligne par entrée
    profil/                qui est l'utilisateur, comment il travaille
    projets/               une fiche par projet
    references/            machines, comptes, outils, URLs (jamais de secret)
    apprentissages/        ce qui marche ou pas, décisions d'outillage
  projets/
    <nom>/
      memory/              mémoire auto du projet : fiches et index MEMORY.md
```

Le dossier d'un projet peut contenir autre chose à côté de `memory/` (un journal, des documents) : tout le dépôt est synchronisé, et `memory/` ne garde que les fiches que Claude Code traite comme de la mémoire.

Les fichiers ont le format de la mémoire auto de Claude Code : un sujet par fichier, nom en kebab-case, en-tête YAML.

```
---
name: slug-du-fichier
description: "une ligne, utilisée pour décider si le fichier est pertinent"
metadata:
  type: user | feedback | project | reference
---

Le contenu.
```

`MEMORY.md` est l'index d'un dossier : `- [Titre](dossier/fichier.md) : accroche`. Claude lit l'index d'abord, puis seulement le fichier utile.

## Fonctionnement

- **Clone.** `setup` clone le dépôt dans `~/claude-memory`. Si un dossier qui n'est pas un clone occupe l'emplacement, ou si le clone en place appartient à un autre dépôt, le script s'arrête sans rien supprimer. Les scripts ne changent pas la configuration du clone : leurs options git passent sur la ligne de commande.
- **Brancher un projet.** `setup --project <nom>` donne le chemin de la mémoire du projet dans le clone, sous la forme `~/claude-memory/projets/<nom>/memory`, identique sur tous les appareils. Le skill l'écrit dans la clé `autoMemoryDirectory` de `.claude/settings.local.json` du dossier de travail, sans toucher aux autres clés. Le nom du projet est résolu contre le dépôt sans tenir compte de la casse : les chemins git y sont sensibles, pas tous les systèmes de fichiers.
- **Portée.** `pull.sh` et `push.sh` couvrent toujours la partie transverse du dépôt (tout ce qui n'est pas dans `projets/<nom>/` : la mémoire générale et les fichiers de la racine), plus les projets qu'on leur donne. `--memory-dir <chemin>` reçoit le dossier de mémoire auto de la session : s'il est dans `projets/<nom>/` du clone, ce projet entre dans la portée (le chemin est accepté sous ses formes `C:\...`, `C:/...`, `/c/...` et `~/...`). `--project <nom>` nomme un projet, et se répète. Sans l'un ni l'autre, seule la partie transverse est couverte, et le script le dit. `--all` couvre tout le dépôt, sur demande explicite seulement. Le script annonce la portée sur sa première ligne.
- **Pull.** Le script rafraîchit ce que le clone sait du dépôt, puis résume ce qui changerait, par partie du dépôt (un projet, `general`, `racine`) : `nouveau`, `depot` (seul le dépôt a changé), `supprime au depot`, `les deux` (changé des deux côtés), `local` (changé seulement ici, en attente de push), `reste en local` (travail en cours d'un projet hors de la portée). Après confirmation, le travail local de la portée pas encore commité est enregistré dans un commit local, contrôle des secrets d'abord, puis `git merge` fusionne tout le dépôt. Le travail en cours des autres projets n'est ni commité ni modifié. S'il porte sur des fichiers que le dépôt a aussi changés, la fusion l'écraserait : le script s'arrête avant tout commit (code 8), nomme les projets, et `--include <projet>` les fait entrer dans la fusion. Un conflit n'est pas une erreur : le script liste les fichiers concernés et s'arrête là. Chaque conflit y apparaît en trois parties, la version de l'appareil, l'ancêtre commun et la version du dépôt, et c'est à partir d'elles que Claude explique et propose. `pull.sh --conclude` enregistre la fusion avec les seuls fichiers qui étaient en conflit, `--drop <chemin>` règle un conflit de suppression en retirant le fichier, `--abort` remet le clone dans l'état d'avant la fusion.
- **Push.** Ce qui part : les commits locaux déjà faits par un pull, plus le travail de la portée pas encore commité. Le commit est construit à partir de l'arbre qui a été montré et contrôlé, pas à partir de l'index : rien d'un autre projet ne peut y entrer, même indexé à la main. Ce qui reste en local dans les autres projets est listé à part. Les commits déjà faits partent entiers, et le script signale ceux qui emportent un autre projet. Les contrôles lisent le contenu qui part, dans l'ordre : fusion en cours ou marqueurs de conflit (code 6), dépôt en avance sur le clone (code 4, à lever par un pull), motif de secret dans un fichier ou dans un commit local pas encore poussé (code 5). Le commit a un titre fixe, `memoire(<parties touchées>): synchro depuis <machine> le <date>`, et un corps : le récap rédigé par la session, puis la liste des fichiers ajoutés, modifiés ou supprimés. Il n'existe pas de push forcé : `--force` ne sert qu'à laisser passer un faux positif de secret.
- **Perte possible.** Une mémoire grossit ou se réorganise, elle ne rétrécit pas sans raison. Un push qui supprime un fichier, ou retire beaucoup plus de lignes qu'il n'en ajoute (au moins 30, et plus du double), est signalé à la simulation et refusé au commit (code 7) tant que `--accept-loss` n'est pas passé, ce que le skill ne fait qu'après avoir montré l'avertissement à l'utilisateur. Un fichier déplacé n'est pas compté comme supprimé.
- **Retour en arrière.** Le skill `revert` remet le dossier d'un projet, ou `general/`, dans l'état d'un commit (`git restore` depuis ce commit, fichiers ajoutés depuis retirés compris). Le travail en cours du dossier est d'abord commité en local, le dépôt n'est pas touché et aucun historique n'est réécrit : le push suivant renvoie cet état d'avant comme un nouveau commit, avec l'avertissement de perte. La version annulée reste lisible.
- **Consolidation.** Le skill `consolider` fait converger une mémoire de projet vers une forme prévisible, par familles de fiches toujours dans le même ordre : `projet` (une fiche), `etat`, `regles`, `decisions`, `references`, `pieges`, `equipe` (optionnelle), `journal` (une fiche). Le nom d'une fiche dit sa famille puis son thème (`regles-git.md`, `references-donnees-client.md`), et l'index reprend les familles dans le même ordre : une session sait d'avance où chercher. Règles : rien n'est supprimé, le daté part dans `journal.md` (en ajout seul, par date de consolidation, avec la provenance) ; les fiches d'une même famille fusionnent, une fiche trop longue ou mélangée se découpe ; les conventions de dépôt (ce qui vaut pour toute session dans un dépôt de code) sont proposées pour le `CLAUDE.md` du dépôt, que l'utilisateur commite ; les dates relatives deviennent absolues ; ce qui contredit la doc ou explique une décision est gardé. Le dépôt reçoit l'état d'avant, puis l'état d'après, avec un compte rendu en cinq groupes : revenir en arrière est un `revert`.
- **Codes de sortie.** 1 usage, 2 git ou dossier qui gêne, 3 projet ou commit inconnu, 4 dépôt en avance sur le clone, 5 secret, 6 marqueurs de conflit ou fusion en cours, 7 perte refusée (sans `--accept-loss`), 8 la fusion écraserait le travail non commité d'un projet hors de la portée (`pull.sh --include`), 10 pas de dépôt configuré, 11 un autre dépôt est configuré ou cloné.

## Sur claude.ai

Le plugin installé sur le compte est aussi chargé dans le chat claude.ai, et le chat dispose d'un bac à sable avec un shell, git, et l'accès GitHub de l'app de Claude (lecture et écriture sur les dépôts auxquels l'app a accès). Les mêmes scripts y tournent, avec trois différences, que chaque SKILL.md décrit dans sa section « Sur claude.ai » :

- pas de configuration persistante dans le plugin : le dépôt est fixé pour la conversation par `CLAUDE_MEMOIRE_REPO`, pris dans les instructions du Projet (une ligne « dépôt mémoire : proprietaire/depot »), dans la mémoire claude.ai de l'utilisateur (lui demander de retenir son dépôt mémoire, une fois, vaut pour toutes ses conversations), dans la conversation, ou sinon parmi les dépôts accessibles, auquel cas il est confirmé par une question avant le premier usage ;
- pas de mémoire auto ni de réglage à poser : le clone vit dans le bac à sable (`~/claude-memory`) le temps de la conversation, et la portée se donne par `--project <nom>`. `pull` crée le clone ou le met à jour et Claude garde en contexte les fiches utiles ; `push` part de ce clone, où Claude écrit ce que la conversation a appris, puis commit et push avec les mêmes contrôles ;
- `CLAUDE_MEMOIRE_HOST=claude.ai` dans le titre des commits, et une identité git de repli si le bac à sable n'en a pas.

L'app GitHub de Claude doit avoir accès au dépôt mémoire (page d'installation de l'app sur GitHub), et le dépôt doit être attaché à la conversation (outil d'ajout de dépôt du chat) avant le premier clone : le proxy git du bac à sable n'autorise que les dépôts attachés. Le skill setup s'en charge. Un bouton « Add from GitHub » n'est pas nécessaire. La synchronisation GitHub des connaissances d'un Projet reste possible pour que Claude ait la mémoire sous les yeux sans la demander, en lecture seule et rafraîchie à la main.

## Venir d'une version 0.6.x

Les versions 0.6.x ne gardaient aucun clone : chaque skill clonait le dépôt dans un dossier temporaire et copiait les fichiers vers la mémoire auto locale. Depuis la 0.7.0, le clone est durable et il est la mémoire. Rien n'est supprimé par la mise à jour, et le dépôt ne change pas de forme.

1. Tant que la 0.6.x est encore installée, pousser les mémoires locales : le dépôt aura tout. Si la mise à jour est déjà arrivée, l'étape 3 rattrape ce qui manquerait.
2. `/memoire:setup` : le dépôt déjà configuré est cloné dans `~/claude-memory`.
3. Dans chaque dossier de travail : `/memoire:setup <nom>` pour brancher le projet. Le skill compare l'ancienne mémoire locale avec le clone et propose de reprendre ce qu'elle aurait de plus. Les anciens dossiers (`~/.claude/projects/<slug>/memory/`) restent en place.
4. L'ancienne copie locale de la mémoire générale (`~/.claude/memoire/general/`) n'est plus utilisée : `/memoire:generale` lit le clone, et propose la même comparaison.

Les fichiers `.memoire-sync` laissés par les anciennes versions ne servent plus.

## Développer le plugin

La marketplace ne reçoit que des versions publiées, chacune par une pull request : on ne développe pas directement dedans. Pour modifier le plugin, travailler sur une copie dans sa propre marketplace : éditer, `claude plugin validate plugins/memoire`, incrémenter `version` dans `.claude-plugin/plugin.json` (sans incrément, claude.ai ne voit pas de nouvelle version), commit, push. Les appareils reçoivent la nouvelle version par le compte claude.ai : relecture de la marketplace côté compte (bouton de synchronisation de la marketplace, dans l'app desktop uniquement, pour ne pas attendre), puis téléchargement au prochain démarrage d'un processus Claude Code (`claude -p ok --model haiku` suffit), puis `/reload-plugins` ou nouvelle session. Le détail observé est dans le README de la marketplace. Pour tester en local sans attendre : `claude plugin marketplace add <dossier de cette marketplace>` et `claude plugin install memoire@<nom de cette marketplace>`, en sachant qu'un plugin du même nom installé localement masque la copie synced.

Les scripts acceptent `CLAUDE_MEMOIRE_DIR` pour déplacer le clone, `CLAUDE_MEMOIRE_HOME` pour déplacer la configuration, `CLAUDE_MEMOIRE_REPO` pour imposer le dépôt sans configuration, et `CLAUDE_MEMOIRE_HOST` pour le nom écrit dans les titres de commit. Avec les deux premières, on rejoue tout sur des dépôts jetables sans toucher au vrai clone : c'est ce que fait la suite de tests de bout en bout rangée à côté du plugin dans son dépôt de développement.
