# memoire

Mémoire partagée entre appareils pour Claude Code, avec un dépôt git comme source unique. Le dépôt est cloné une fois sur chaque appareil, et ce clone est la mémoire : chaque projet y lit et y écrit sa mémoire auto directement. Le dépôt distant n'est lu ou écrit que sur demande, par huit skills.

## Principe

- Un clone durable par appareil, dans `~/claude-memory` par défaut, le même chemin partout. C'est un clone git ordinaire : il s'ouvre dans un éditeur, un explorateur de fichiers ou un outil de notes, et `git log` y raconte l'histoire de la mémoire.
- Un projet se branche sur le clone par un réglage de Claude Code, `autoMemoryDirectory`, posé une fois dans son dossier de travail : sa mémoire auto vit alors dans `projets/<nom>/memory/` du clone. Le dossier de travail ne bouge pas, et rien n'est copié entre les deux.
- Git transporte et fusionne. Le plugin ajoute ce que git ne fait pas : un résumé en clair avant d'agir, des contrôles avant tout envoi (secret, marqueurs de conflit, perte), et l'aide de Claude pour résoudre un conflit en expliquant ce que dit chaque version.
- Un pull ou un push a une portée : le projet de la session et la partie transverse du dépôt, c'est-à-dire la mémoire générale et les fichiers de la racine. Le travail en cours des autres projets n'est jamais commité ni poussé par effet de bord.
- Deux niveaux d'index pour s'y retrouver sans tout lire : `AGENTS.md` à la racine, la table de routage (pour chaque dossier, ce qu'il contient, quand le lire, quoi y écrire), et un `MEMORY.md` par dossier de mémoire, une ligne par fiche. Le skill `reindex` les contrôle et les répare.
- Une mémoire s'entretient : le skill `optimiser` corrige seul ce qui est mécanique (index, en-tête des fiches, liens vers une fiche disparue), donne un score de santé, et propose le reste, que l'utilisateur choisit d'appliquer ou non.
- Une mémoire s'enrichit : le skill `entretien` interroge l'utilisateur, une question ouverte à la fois, et n'écrit à la fin du thème que les fiches validées une par une.
- En dehors du clone, un seul dossier : `~/.claude/memoire/`, avec `config.json`, qui ne contient que l'URL du dépôt, et les rapports du skill `optimiser`. Et un bloc dans `~/.claude/CLAUDE.md`, entre deux marqueurs, écrit après accord.
- Pas de jeton : l'authentification git est celle de la machine (Git Credential Manager sur Windows, gestionnaire d'identifiants ou `gh auth login` ailleurs). Sur claude.ai, c'est le connecteur GitHub de l'utilisateur.

## Prérequis

- Claude Code connecté à un compte claude.ai (pour recevoir le plugin) ; Git 2.25 ou plus récent, 2.35 pour que les conflits montrent aussi l'ancêtre commun. Sur Windows, Git for Windows : les scripts tournent dans Git Bash.
- Une identité git : `git config --global user.name` et `user.email`.
- Un dépôt git privé pour la mémoire. Le plus simple : le créer depuis le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template) (bouton « Use this template », visibilité privée), qui contient la structure et le format attendus. Un dépôt vide fonctionne aussi : le premier push crée ce qu'il faut.
- Un emplacement de clone hors de tout dossier synchronisé par un service de fichiers (OneDrive, Dropbox, iCloud) : deux synchronisations qui écrivent dans le même dossier `.git` finissent par l'abîmer.

## Mise en place

Tout se pilote depuis un seul skill : `/memoire:setup`, ou « où en est la mise en place de ma mémoire ? ». Sans argument, il montre l'état des cinq étapes et la version du plugin, puis propose celles qui manquent, dans l'ordre. Rien ne s'écrit sans accord.

| | Étape | Portée | Qui la fait |
| --- | --- | --- | --- |
| 1 | Dépôt configuré et cloné | une fois par appareil | `setup`, avec l'URL du dépôt |
| 2 | Projet du dossier de travail branché | une fois par projet et par appareil | `setup`, depuis ce dossier |
| 3 | Bloc dans `~/.claude/CLAUDE.md` | une fois par appareil, puis à chaque version qui le change | `setup`, après accord |
| 4 | `AGENTS.md` dans le dépôt | une fois pour tous les appareils | `reindex`, que `setup` enchaîne |
| 5 | Routine planifiée d'`optimiser` | une fois pour le compte | `setup`, après quatre questions |

### 1. Le dépôt et son clone

Donner l'URL du dépôt mémoire (HTTPS, SSH ou `proprietaire/depot`), ou la passer directement : `/memoire:setup <url>`. Le script clone le dépôt dans `~/claude-memory` (le navigateur peut s'ouvrir pour la connexion GitHub, une fois), écrit la configuration, liste les projets présents et dit si une mémoire générale existe.

Pour changer de dépôt : `/memoire:setup <nouvelle-url>`. Le skill montre l'ancienne URL et demande confirmation. Un clone n'est jamais supprimé ni remplacé par le plugin : il faut déplacer ou renommer le dossier soi-même, puis relancer.

### 2. Brancher un projet

Dans le dossier de travail d'un projet : `/memoire:setup <nom>`, ou « branche ce projet sur ma mémoire ». Le skill écrit le réglage `autoMemoryDirectory` dans `.claude/settings.local.json` de ce dossier, crée la mémoire du projet si elle n'existe pas encore, et regarde ce que l'ancienne mémoire locale aurait de plus. Le nom est celui du projet dans le dépôt mémoire, pas forcément celui du dossier : le skill le fait confirmer. Ouvrir ensuite une nouvelle session : la commande `/memory` doit montrer un dossier du clone. À refaire dans chaque dossier de travail qu'on ouvre sur cet appareil.

### 3. Le bloc du `CLAUDE.md`

`~/.claude/CLAUDE.md` est le fichier d'instructions personnel de Claude Code, lu dans chaque session. Le plugin y tient un bloc, que le skill montre puis écrit après accord :

```
<!-- memoire:debut -->
<!-- Bloc écrit par le skill setup du plugin memoire, qui le remplace en entier à chaque mise à jour : ce qui est personnel s'écrit en dehors des deux marqueurs. -->
## Mémoire partagée (plugin memoire)

@~/claude-memory/AGENTS.md

- Quand je demande de charger, récupérer ou reprendre la mémoire d'un projet : skill /memoire:pull.
- Quand je demande de sauvegarder, pousser ou partager la mémoire : skill /memoire:push.
- Pour une question sur moi, mes autres projets, mon environnement, ou un nom de projet inconnu : skill /memoire:generale.
- Quand je demande un entretien, ou d'être interrogé pour enrichir ma mémoire : skill /memoire:entretien.
- Quand je demande de vérifier ou réparer les index, ou de mettre à jour la table de routage : skill /memoire:reindex.
- Quand je demande d'optimiser, nettoyer ou ranger une mémoire, ou son état de santé : skill /memoire:optimiser.
- Quand je demande de revenir en arrière, ou d'annuler une optimisation : skill /memoire:revert.
- Quand je demande où en est la mise en place de ma mémoire, ou de brancher un projet : skill /memoire:setup.
- Sans demande de ma part, ne fais ni pull, ni push, ni commit dans le dépôt mémoire.
<!-- memoire:fin -->
```

- La ligne `@...` importe `AGENTS.md`, la table de routage du dépôt mémoire, dans chaque session, quel que soit le dossier de travail. Le chemin est celui du clone réel de l'appareil.
- Les lignes suivantes disent à Claude quelle demande lance quel skill. La dernière est la règle : rien ne part ni n'arrive sans demande.
- Entre les deux marqueurs, c'est le plugin qui écrit : quand une version change le bloc, la vue d'état le signale et le skill propose de le remplacer, en montrant ce qui change. Le reste du fichier n'est jamais touché, et une copie du fichier d'avant est gardée dans `~/.claude/memoire/`.
- Un bloc déjà posé à la main, sans marqueurs, est reconnu : le skill montre ligne à ligne ce que le remplacement change, puis le remplace après accord.

Pour vérifier, ouvrir une nouvelle session dans n'importe quel dossier et demander à Claude de citer une règle de la table.

### 4. `AGENTS.md`

La table de routage vit à la racine du dépôt mémoire : il suffit de la créer une fois, les autres appareils la reçoivent par un pull. Le skill `setup` enchaîne avec `reindex` (« crée la table de routage de ma mémoire »), qui la crée depuis un modèle et fait valider ses entrées, puis avec un push.

### 5. La routine d'optimisation

Une routine cloud de Claude Code joue le skill `optimiser` à heure fixe, sans rien faire tourner sur le poste. Elle fait le passage, pose ses questions, prévient par une notification et attend : rien n'est poussé avant la réponse. Ensuite, un pull sur chaque appareil.

Le skill pose quatre questions (le jour, l'heure, la portée, le modèle), montre la configuration, puis crée la routine quand la session a un outil de routines cloud. Sinon, il donne la consigne à coller sur `claude.ai/code/routines`, ou par `/schedule` dans Claude Code. À savoir :

- Le cron d'une routine se lit en UTC, avec un intervalle d'au moins une heure. Le skill convertit l'heure locale et prévient quand le fuseau change d'heure : la routine passe alors une heure plus tôt ou plus tard à l'autre saison.
- La routine n'a qu'un dépôt attaché, le dépôt mémoire, et aucun connecteur. Le plugin installé sur le compte y est chargé : elle s'appuie sur lui.
- La consigne est un modèle du plugin (`skills/optimiser/assets/consigne-routine.md`), court : le déroulé reste dans le skill `optimiser`, et suit donc les mises à jour du plugin sans recréer la routine.
- Une routine ne se voit pas depuis un script : la vue d'état la vérifie avec l'outil de routines de la session, ou affiche « non vérifiable ici ».

### Sur un appareil de plus

Installer le plugin, puis `/memoire:setup` : l'étape 1 avec la même URL, l'étape 2 pour chaque projet qu'on y ouvre, l'étape 3. Les étapes 4 et 5 sont déjà faites, elles valent pour tous les appareils. Terminer par un pull.

### Au quotidien

« Récupère la mémoire » (`/memoire:pull`) en arrivant sur un appareil, « sauvegarde la mémoire » (`/memoire:push`) avant d'en changer. `/memoire:setup` redonne l'état à tout moment, par exemple après une mise à jour du plugin.

## Les skills

| Commande | Ce qu'elle fait |
| --- | --- |
| `/memoire:setup [url ou projet]` | Sans argument, montre l'état des cinq étapes de la mise en place et la version du plugin, puis propose celles qui manquent. Avec une URL, configure le dépôt mémoire de l'appareil et le clone. Avec un nom, branche un projet sur sa mémoire dans le clone. Écrit le bloc du `~/.claude/CLAUDE.md` après accord, et crée la routine planifiée d'`optimiser`. |
| `/memoire:pull [projet]` | Met le clone à jour : simulation et résumé par projet, confirmation, puis fusion par git. Seul le travail local du projet de la session et de la partie transverse est commité avant la fusion. En cas de conflit, Claude explique ce que dit chaque version, propose un texte fusionné ou un choix argumenté, et conclut la fusion une fois les fichiers réglés. |
| `/memoire:push [projet]` | Envoie ce qui a changé dans le projet de la session et dans la partie transverse : contrôles, message de commit montré tel quel avec un récap, confirmation, commit et push. Ce qui reste en local dans les autres projets est listé à part. |
| `/memoire:generale [sujet]` | Lit l'index de `general/` puis le fichier utile. Peut y ajouter une entrée et la pousser sur demande. |
| `/memoire:entretien [sujet] [projet nom]` | Interroge l'utilisateur pour enrichir sa mémoire, la mémoire générale par défaut ou un projet nommé : trancher ce qui est flou, creuser un sujet, ouvrir un domaine qui manque. Sans sujet, propose des thèmes tirés des manques de la mémoire, ou part d'un sujet neuf. Rien n'est écrit pendant l'échange. À la fin du thème, chaque fiche proposée est validée par une question à choix, puis écrite et indexée selon `AGENTS.md`. Ne commite ni ne pousse rien. |
| `/memoire:reindex [verifier, projet ou tout]` | Contrôle la table de routage `AGENTS.md` et les index `MEMORY.md`, sans rien écrire avec `verifier`. Répare les index après confirmation (lignes manquantes reconstruites depuis l'en-tête des fiches, lignes mortes retirées), rédige les entrées de la table de routage et les fait valider avant de les écrire. Ne commite ni ne pousse rien. |
| `/memoire:optimiser [verifier, projet, generale ou tout]` | Entretient une mémoire. Corrige seul les index, l'en-tête des fiches et les liens vers une fiche disparue, dans un commit local. Donne un score de santé. Dit en bref ce qui est fait, puis fait trancher le reste par des questions à choix, les plus graves d'abord (doublons, contradictions, périmé, fiches trop longues, dates relatives, journal, conventions à sortir vers `CLAUDE.md`), et n'applique que ce qui a été choisi. Ne pousse rien. Avec `verifier`, n'écrit rien. |
| `/memoire:revert [projet ou generale] [commit]` | Remet le dossier d'un projet, ou la mémoire générale, dans l'état d'un commit, après simulation et confirmation. Sans commit, propose les derniers commits du dossier. Le dépôt n'est pas touché ; un push renverra cet état comme un nouveau commit. |

Les skills se déclenchent aussi sur une demande en clair (« récupère la mémoire », « sauvegarde la mémoire », « regarde dans ma mémoire générale »). C'est le bloc de l'étape 3 de « Mise en place », écrit dans `~/.claude/CLAUDE.md`, qui dit à Claude quelle demande lance quel skill.

## Le dépôt mémoire

Structure attendue, fournie par le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template) :

```
<depot>/
  AGENTS.md                table de routage : où trouver, où ranger
  general/                 mémoire générale, hors projet
    MEMORY.md              index : une ligne par entrée
    profil/                qui est l'utilisateur, comment il travaille
    projets/               une fiche par projet
    references/            machines, comptes, outils, URLs (jamais de secret)
    apprentissages/        ce qui marche ou pas, décisions d'outillage
  projets/
    <nom>/
      memory/              mémoire auto du projet : fiches et index MEMORY.md
      journal.md           le journal du projet : ce n'est pas une fiche
      ...                  à côté aussi : instantanés, documents
```

Le dossier d'un projet peut contenir autre chose à côté de `memory/` (un journal, des documents) : tout le dépôt est synchronisé, et `memory/` ne garde que les fiches que Claude Code traite comme de la mémoire. Le journal d'un projet est `projets/<nom>/journal.md` : il reçoit ce qui est daté ou dépassé, n'a pas de ligne dans `MEMORY.md`, et une fiche y renvoie par son chemin, pas par un lien `[[journal]]`. La mémoire générale n'a pas d'emplacement hors fiches par défaut : le skill `optimiser` le demande au lieu d'en créer un.

Les fichiers ont le format de la mémoire auto de Claude Code : un sujet par fichier, nom en kebab-case, en-tête YAML. Tout ce qui n'est pas `name` ou `description` va sous `metadata`, où Claude Code range lui-même ce qu'il ajoute.

```
---
name: slug-du-fichier
description: "une ligne, utilisée pour décider si le fichier est pertinent"
metadata:
  type: user | feedback | project | reference
  status: actif | a-verifier | perime
  tags: [mot-cle]
---

Le contenu.
```

`status` vaut `actif`, `a-verifier` ou `perime`, écrits ainsi, sans accent ni espace ; le skill `optimiser` ajoute `actif` là où il manque. `tags` est facultatif, et d'autres propriétés peuvent s'ajouter sous `metadata`. Le détail du format est dans le modèle d'`AGENTS.md`, que la table de routage met sous les yeux de chaque session.

`MEMORY.md` est l'index d'un dossier : `- [Titre](dossier/fichier.md) : accroche`. Claude lit l'index d'abord, puis seulement le fichier utile.

### La table de routage

`AGENTS.md`, à la racine du dépôt, dit pour chaque dossier ce qu'il contient, quand le lire et quoi y écrire. Le skill `reindex` le crée depuis un modèle (`skills/reindex/assets/modele-AGENTS.md`) et l'entretient. Pour qu'il soit chargé dans chaque session, quel que soit le dossier de travail, le bloc de « Mise en place » (étape 3) l'importe par cette ligne, dans le `~/.claude/CLAUDE.md` de chaque appareil :

```
@~/claude-memory/AGENTS.md
```

Le fichier tient en deux parties, séparées par deux marqueurs :

```
<!-- reindex:debut -->
| Dossier | Ce qu'il contient | Le lire quand | Y écrire |
|---|---|---|---|
| `general/profil/` | ... | ... | ... |
| `projets/<nom>/memory/` | ... | ... | ... |
<!-- reindex:fin -->
```

- Entre les marqueurs, la table : la seule partie que le skill écrit, après confirmation. Chaque ligne commence par un chemin entre accents graves. Un segment écrit `<nom>` vaut pour n'importe quel nom, et une entrée couvre tout ce qui est sous son chemin : `projets/<nom>/memory/` suffit pour tous les projets.
- Hors des marqueurs, la présentation, les règles et le format des fiches : cette partie appartient à l'utilisateur. Ni le skill ni le script ne la réécrivent.

Importé partout, le fichier doit rester court : le script signale tout dépassement de 200 lignes ou de 16 Ko.

## Fonctionnement

- **Clone.** `setup` clone le dépôt dans `~/claude-memory`. Si un dossier qui n'est pas un clone occupe l'emplacement, ou si le clone en place appartient à un autre dépôt, le script s'arrête sans rien supprimer. Les scripts ne changent pas la configuration du clone : leurs options git passent sur la ligne de commande.
- **Brancher un projet.** `setup --project <nom>` donne le chemin de la mémoire du projet dans le clone, sous la forme `~/claude-memory/projets/<nom>/memory`, identique sur tous les appareils. Le skill l'écrit dans la clé `autoMemoryDirectory` de `.claude/settings.local.json` du dossier de travail, sans toucher aux autres clés. Le nom du projet est résolu contre le dépôt sans tenir compte de la casse : les chemins git y sont sensibles, pas tous les systèmes de fichiers.
- **Mise en place guidée.** Quatre commandes de `setup.sh` portent le parcours du skill, toutes sans effet tant qu'on ne demande pas d'écrire.
  - `--etapes [--workdir <dossier>]` rend l'état des cinq étapes, hors ligne et sans rien écrire, toujours en code 0 : la version du plugin, une ligne `etape` par étape en colonnes séparées par des tabulations (numéro, code, état, détail), puis un bilan en `clé=valeur`, dont `suivante=`, la première étape à traiter. Les états : `fait`, `a-faire`, `a-mettre-a-jour`, `sans-objet` (l'étape 2 dans une session ouverte dans le clone), `non-verifiable` (la routine, qui vit sur le compte). L'étape 2 lit `autoMemoryDirectory` dans `.claude/settings.local.json` puis `.claude/settings.json` du dossier de travail, et vérifie qu'il pointe sur `projets/<nom>/memory` du clone.
  - `--bloc` montre le bloc du `~/.claude/CLAUDE.md` : son état (`absent`, `a-jour`, `a-mettre-a-jour`, `sans-marqueurs`, `marqueurs-abimes`), le texte à écrire, le texte en place et la différence. `--bloc --write` l'écrit entre ses deux marqueurs, `<!-- memoire:debut -->` et `<!-- memoire:fin -->`, que Claude Code retire du fichier avant de le charger. Le texte vient d'un modèle (`skills/setup/assets/bloc-claude-md.md`), où le chemin du clone est remplacé par le vrai. Hors du bloc, le fichier est recopié tel quel, fins de ligne comprises, et le fichier d'avant est gardé dans `~/.claude/memoire/CLAUDE.md.avant-bloc`. Un bloc posé à la main est reconnu à ses lignes (l'import d'`AGENTS.md` du clone, un déclencheur `/memoire:...`, la règle sur pull, push et commit) : c'est la section du titre qui les précède quand elle est faite surtout de ces lignes, sinon seulement les lignes elles-mêmes. Celles qui restent ailleurs sont signalées (`hors_bloc=`). Des marqueurs en double, isolés ou dans le désordre arrêtent l'écriture (code 12).
  - `--cron <jour> <HH:MM>` convertit un jour et une heure locale en cron UTC, celui qu'une routine attend, et dit ce que le changement d'heure fera à l'heure locale (`saison=`). Le fuseau est celui de l'appareil, ou celui de la variable `TZ`.
  - `--routine [--all | --project <nom>] [--host <nom>]` rend la consigne de la routine d'`optimiser`, depuis le modèle du plugin, avec l'adresse du dépôt configuré sans les identifiants qu'elle pourrait contenir. Rien n'est créé : c'est l'outil de routines de la session qui crée.
- **Portée.** `pull.sh` et `push.sh` couvrent toujours la partie transverse du dépôt (tout ce qui n'est pas dans `projets/<nom>/` : la mémoire générale et les fichiers de la racine), plus les projets qu'on leur donne. `--memory-dir <chemin>` reçoit le dossier de mémoire auto de la session : s'il est dans `projets/<nom>/` du clone, ce projet entre dans la portée (le chemin est accepté sous ses formes `C:\...`, `C:/...`, `/c/...` et `~/...`). `--project <nom>` nomme un projet, et se répète. Sans l'un ni l'autre, seule la partie transverse est couverte, et le script le dit. `--all` couvre tout le dépôt, sur demande explicite seulement. Le script annonce la portée sur sa première ligne.
- **Session ouverte dans le clone.** Le clone peut servir de dossier de travail pour une vue d'ensemble : mémoire générale, table de routage, tous les projets sous la main. Mieux vaut y couper la mémoire auto (`"autoMemoryEnabled": false` dans `.claude/settings.json` du dépôt mémoire), pour que Claude Code n'ouvre pas une mémoire de plus pour ce dossier. Une telle session n'a pas de dossier de mémoire auto : `pull`, `push` et `reindex` y travaillent sans option de portée, donc sur la partie transverse, sauf projet nommé. On n'y branche aucun projet : `setup` le refuse.
- **Pull.** Le script rafraîchit ce que le clone sait du dépôt, puis résume ce qui changerait, par partie du dépôt (un projet, `general`, `racine`) : `nouveau`, `depot` (seul le dépôt a changé), `supprime au depot`, `les deux` (changé des deux côtés), `local` (changé seulement ici, en attente de push), `reste en local` (travail en cours d'un projet hors de la portée). Après confirmation, le travail local de la portée pas encore commité est enregistré dans un commit local, contrôle des secrets d'abord, puis `git merge` fusionne tout le dépôt. Le travail en cours des autres projets n'est ni commité ni modifié. S'il porte sur des fichiers que le dépôt a aussi changés, la fusion l'écraserait : le script s'arrête avant tout commit (code 8), nomme les projets, et `--include <projet>` les fait entrer dans la fusion. Un conflit n'est pas une erreur : le script liste les fichiers concernés et s'arrête là. Chaque conflit y apparaît en trois parties, la version de l'appareil, l'ancêtre commun et la version du dépôt, et c'est à partir d'elles que Claude explique et propose. `pull.sh --conclude` enregistre la fusion avec les seuls fichiers qui étaient en conflit, `--drop <chemin>` règle un conflit de suppression en retirant le fichier, `--abort` remet le clone dans l'état d'avant la fusion.
- **Push.** Ce qui part : les commits locaux déjà faits par un pull, plus le travail de la portée pas encore commité. Le commit est construit à partir de l'arbre qui a été montré et contrôlé, pas à partir de l'index : rien d'un autre projet ne peut y entrer, même indexé à la main. Ce qui reste en local dans les autres projets est listé à part. Les commits déjà faits partent entiers, et le script signale ceux qui emportent un autre projet. Les contrôles lisent le contenu qui part, dans l'ordre : fusion en cours ou marqueurs de conflit (code 6), dépôt en avance sur le clone (code 4, à lever par un pull), motif de secret dans un fichier ou dans un commit local pas encore poussé (code 5). Le commit a un titre fixe, `memoire(<parties touchées>): synchro depuis <machine> le <date>`, et un corps : le récap rédigé par la session, puis la liste des fichiers ajoutés, modifiés ou supprimés. Il n'existe pas de push forcé : `--force` ne sert qu'à laisser passer un faux positif de secret.
- **Perte possible.** Une mémoire grossit ou se réorganise, elle ne rétrécit pas sans raison. Un push qui supprime un fichier, ou retire beaucoup plus de lignes qu'il n'en ajoute (au moins 30, et plus du double), est signalé à la simulation et refusé au commit (code 7) tant que `--accept-loss` n'est pas passé, ce que le skill ne fait qu'après avoir montré l'avertissement à l'utilisateur. Un fichier déplacé n'est pas compté comme supprimé.
- **Retour en arrière.** Le skill `revert` remet le dossier d'un projet, ou `general/`, dans l'état d'un commit (`git restore` depuis ce commit, fichiers ajoutés depuis retirés compris). Le travail en cours du dossier est d'abord commité en local, le dépôt n'est pas touché et aucun historique n'est réécrit : le push suivant renvoie cet état d'avant comme un nouveau commit, avec l'avertissement de perte. La version annulée reste lisible.
- **Réindexation.** `reindex.sh` lit tout le dépôt tel que git le commiterait (les fichiers ignorés et les fichiers cachés n'en font pas partie) et rend un inventaire, l'état d'`AGENTS.md`, puis les écarts. `--check`, par défaut, n'écrit rien. `--fix` répare les index de la portée : lignes manquantes reconstruites depuis l'en-tête des fiches (`- [name](chemin) : description`, ajoutées en fin d'index, sous le titre « Lignes reconstruites » quand l'index a des sections), lignes mortes et copies exactes retirées, index absent créé, lien remis à la casse du fichier. Les fins de ligne du fichier sont gardées. Il n'écrit jamais `AGENTS.md`, dont les entrées se rédigent, et ne commite rien : un push envoie le résultat. `general/` a un seul index pour tous ses sous-dossiers ; la mémoire d'un projet a le sien pour les fiches posées directement dans `memory/`, et ce qui s'y trouve d'autre (un sous-dossier, un fichier qui n'est pas un `.md`) est signalé comme à ranger à côté. La sortie est faite pour être relue par un autre skill : sous des titres `== ... ==`, un enregistrement par ligne, en colonnes séparées par des tabulations (`dossier`, `fichier`, `index`, `ecart`, `corrige`), et un bilan en `clé=valeur`. Un écart porte son code, `dans` ou `hors` de la portée, `auto` (réparé par `--fix`) ou `session` (une décision ou une rédaction), le fichier et le détail. Le script sort en 9 tant qu'il reste des écarts dans la portée ; ceux des autres projets sont listés sans compter. Avec `--fiches`, l'inventaire liste aussi chaque fiche, pour `optimiser.sh`.
- **Optimisation.** `optimiser.sh` lance `reindex.sh`, reprend ses écarts tels quels et sa liste de fiches, puis contrôle les fiches elles-mêmes : l'en-tête (un `status` sous `metadata`, parmi `actif`, `a-verifier` et `perime`, un `type` connu, aucune clé hors de `metadata`), les liens `[[...]]`, la taille (8 000 octets), l'ancienneté d'une fiche active (90 jours pour le type `project`, 180 pour `reference`, jamais pour `user` et `feedback`), les dates relatives dans le texte, un `name` porté par deux fiches, un journal resté dans `memory/`, un projet sans fiche dans `general/projets/`. La sortie a la forme de celle de `reindex.sh`, avec les mêmes options de portée et le même code 9.
  - `--check`, par défaut, n'écrit rien. `--fix` applique une liste fermée, dans la portée : les index (par `reindex.sh --fix`), `status: actif` ajouté quand il manque, un statut écrit autrement remis à sa valeur, une clé rangée sous `metadata`, un lien vers une fiche disparue remplacé par son nom en clair. Le texte d'une fiche n'est jamais touché, ses fins de ligne non plus. Une fiche a disparu quand l'historique du clone la connaît et qu'elle n'existe plus : un lien vers un nom jamais porté est seulement signalé, il peut annoncer une fiche à écrire. Un lien `[[journal]]` devient le chemin du journal quand le projet en a un à côté de `memory/`.
  - Tout le reste est une proposition : le script la signale (`session`) et la numérote par gravité, la session y ajoute ce qu'elle relève en lisant (doublons, contradictions, périmé, conventions de dépôt à sortir vers le `CLAUDE.md` du dépôt de code, rangement par familles de fiches), et seules les propositions choisies sont appliquées.
  - Le score de santé est la part des fiches de la portée sans aucun écart, en pourcentage arrondi vers le bas, avec le nombre d'écarts par type. Le script le calcule seul : le même état donne le même score à une date donnée, celle du jour ou celle de `--date`. Les écarts qui ne touchent aucune fiche sont comptés à part.
  - Un passage fait ses propres commits, en local, et ne pousse jamais. Avant de corriger, le travail en cours de la portée est commité à part, contrôle des secrets d'abord (code 5) : le commit du passage ne contient donc que ses corrections. `--commit` fait de même pour les propositions appliquées. Le script donne le commit d'avant, auquel le skill `revert` ramène.
  - `--planifie` est le mode d'un passage sans personne devant l'écran : `--fix`, git qui ne pose aucune question, le rapport écrit aussi dans `~/.claude/memoire/optimiser/dernier-rapport.txt`, une ligne par passage dans `historique.tsv` à côté, et un rapport même quand le passage est arrêté. Le plugin ne planifie rien : la commande se donne à l'outil de planification de son choix. Sans option de portée, un passage ne corrige que la partie transverse et signale le reste. Les commits d'un passage partent avec le push suivant, quel que soit le projet d'où il est lancé : c'est à peser avant de planifier avec `--all`.
  - Autre façon de planifier, sans rien faire tourner sur son poste : une routine cloud de Claude Code, créée par le skill `setup` (étape 5 de « Mise en place »). Elle s'appuie sur le plugin du compte, chargé dans son environnement, et les scripts y clonent eux-mêmes le dépôt mémoire (`CLAUDE_MEMOIRE_REPO` devant chaque commande, faute de configuration dans le cloud). Elle joue le skill à heure fixe, pose toutes ses questions dans un message, avec des options a, b, c auxquelles on répond « 1a 2b 3a » (l'outil de questions à choix n'existe pas dans une routine), prévient par une notification, puis attend. Rien n'est poussé avant la réponse, et l'utilisateur fait ensuite un pull sur ses postes. Le clone d'une routine est neuf, sans travail en cours : `--all` n'y fait partir le brouillon d'aucun projet. Le détail est dans la section « Routine cloud » du skill `optimiser`.
- **Entretien.** Le skill `entretien` n'a pas de script à lui. Il lit l'état de la mémoire avec `optimiser.sh --check`, qui n'écrit rien, pour repérer les fiches à vérifier ou anciennes, puis cherche lui-même le flou, les contradictions et les domaines absents. La portée est la mémoire générale, même dans la session d'un projet, sauf projet nommé. Une fiche validée est écrite dans le clone avec sa ligne d'index, sans commit : le skill `push` l'envoie, avec le nom du projet si ce n'est pas celui de la session. Sans outil de questions à choix, la validation se fait par des options a, b, c dans le message.
- **Codes de sortie.** 1 usage, 2 git ou dossier qui gêne, 3 projet ou commit inconnu, 4 dépôt en avance sur le clone, 5 secret, 6 marqueurs de conflit ou fusion en cours, 7 perte refusée (sans `--accept-loss`), 8 la fusion écraserait le travail non commité d'un projet hors de la portée (`pull.sh --include`), 9 il reste des écarts dans la portée (`reindex.sh`, `optimiser.sh`), 10 pas de dépôt configuré, 11 un autre dépôt est configuré ou cloné, 12 le bloc du `CLAUDE.md` ne peut pas être écrit sans risque (`setup.sh --bloc --write`, marqueurs abîmés).

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
5. Dans `~/.claude/CLAUDE.md`, retirer l'ancien rappel, puis laisser `/memoire:setup` écrire le bloc (étape 3 de « Mise en place »).

Les fichiers `.memoire-sync` laissés par les anciennes versions ne servent plus.

## Développer le plugin

La marketplace ne reçoit que des versions publiées, chacune par une pull request : on ne développe pas directement dedans. Pour modifier le plugin, travailler sur une copie dans sa propre marketplace : éditer, `claude plugin validate plugins/memoire`, incrémenter `version` dans `.claude-plugin/plugin.json` (sans incrément, claude.ai ne voit pas de nouvelle version), commit, push. Les appareils reçoivent la nouvelle version par le compte claude.ai. Dans l'app desktop : Paramètres > Plugins, recherche de mises à jour, « Mettre à jour », puis une nouvelle session. En ligne de commande, Claude Code garde une copie distincte de celle de l'app, mise à jour à son prochain démarrage. Le détail observé est dans le README de la marketplace. Pour tester en local sans attendre : `claude plugin marketplace add <dossier de cette marketplace>` et `claude plugin install memoire@<nom de cette marketplace>`, en sachant qu'un plugin du même nom installé localement masque la copie synced.

Les scripts acceptent `CLAUDE_MEMOIRE_DIR` pour déplacer le clone, `CLAUDE_MEMOIRE_HOME` pour déplacer la configuration, `CLAUDE_MEMOIRE_REPO` pour imposer le dépôt sans configuration, `CLAUDE_MEMOIRE_HOST` pour le nom écrit dans les titres de commit, et `CLAUDE_MEMOIRE_CLAUDE_MD` pour le fichier où `setup.sh` écrit son bloc. Avec la première, la deuxième et la dernière, on rejoue tout sur des dépôts et des fichiers jetables sans toucher au vrai clone ni au vrai `CLAUDE.md` : c'est ce que fait la suite de tests de bout en bout rangée à côté du plugin dans son dépôt de développement.

### Les tests

`tests/test_memoire.sh` rejoue tous les cas, sur des dépôts jetables, et rend une ligne `ok` ou `ECHEC` par cas. Compter un quart d'heure sous Windows, où git est lent. Pendant une retouche, on peut ne rejouer qu'une partie :

```
bash tests/test_memoire.sh                          # toute la suite
bash tests/test_memoire.sh --groupe setup           # un groupe
bash tests/test_memoire.sh --groupe portee,reindex  # plusieurs
bash tests/test_memoire.sh --liste                  # les groupes
```

| Groupe | Ce qu'il couvre |
| --- | --- |
| `synchro` | `setup`, `pull`, `push`, conflits, `revert`, mémoire générale |
| `portee` | la portée d'un pull ou d'un push (`--project`, `--memory-dir`, `--all`) |
| `reindex` | `reindex.sh` : index `MEMORY.md` et table de routage `AGENTS.md` |
| `optimiser` | `optimiser.sh` : corrections, score de santé, journal, passage planifié |
| `setup` | le parcours guidé de `setup.sh` : `--etapes`, `--bloc`, `--cron`, `--routine` |

Le filtre va par groupe, pas par numéro de cas : les cas s'enchaînent, chacun part de l'état que les précédents ont laissé sur leurs postes, et un cas rejoué seul échouerait sans que le plugin y soit pour rien. Un groupe, lui, a sa propre amorce et ses propres postes, et passe seul. Un nom de groupe inconnu arrête tout avec la liste des groupes, sans rien jouer. La dernière ligne d'un passage partiel le dit en toutes lettres (« PASSAGE PARTIEL »), avec le nombre de cas joués sur le total : ce n'est pas une suite verte, et la suite complète, sans `--groupe`, reste à passer avant de conclure.
