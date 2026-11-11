# memoire

Mémoire partagée entre appareils pour Claude Code, avec un dépôt git comme sauvegarde et point de synchronisation. La mémoire auto de Claude Code reste la mémoire de travail ; le dépôt n'est lu ou écrit que sur demande, par six skills.

## Principe

- Rien n'est cloné durablement sur l'appareil. Chaque skill clone le dépôt mémoire dans un dossier temporaire, travaille, et le supprime.
- En local : la mémoire auto de Claude Code (`~/.claude/projects/<slug>/memory/`), une copie de travail de la mémoire générale (`~/.claude/memoire/general/`) et un fichier de configuration (`~/.claude/memoire/config.json`) qui ne contient que l'URL du dépôt.
- Pas de jeton : l'authentification git est celle de la machine (Git Credential Manager sur Windows, gestionnaire d'identifiants ou `gh auth login` ailleurs). Sur claude.ai, c'est le connecteur GitHub de l'utilisateur.
- Un push refuse si le dépôt a avancé depuis la dernière synchro de l'appareil, si un fichier contient un motif de secret, ou s'il reste des marqueurs de conflit. Un pull fusionne à trois voies et pose des marqueurs de conflit quand les deux côtés ont changé au même endroit.

## Prérequis

- Claude Code connecté à un compte claude.ai (pour recevoir le plugin) ; Git ≥ 2.25 (clone partiel et sparse checkout ; à défaut, le script retombe sur un clone complet). Sur Windows, Git for Windows : les scripts tournent dans Git Bash.
- Une identité git : `git config --global user.name` et `user.email`.
- Un dépôt git privé pour la mémoire. Le plus simple : le créer depuis le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template) (bouton « Use this template », visibilité privée), qui contient la structure et le format attendus. Un dépôt vide fonctionne aussi : le premier push crée ce qu'il faut.

## Premier usage

1. Demander « charge la mémoire du projet X » (ou `/memoire:pull X`). Sans configuration, le skill enchaîne sur `setup`.
2. Coller l'URL du dépôt mémoire (HTTPS, SSH ou `proprietaire/depot`). Le script vérifie l'accès (le navigateur peut s'ouvrir pour la connexion GitHub, une fois), liste les projets présents et dit si une mémoire générale existe, puis écrit la configuration.
3. Choisir quoi charger : un projet, la générale, ou rien.

Pour changer de dépôt : `/memoire:setup <nouvelle-url>`. Le skill montre l'ancienne URL, prévient que les marqueurs de synchro locaux deviennent sans base et demande quoi faire de la copie locale de la générale.

## Les skills

| Commande | Ce qu'elle fait |
| --- | --- |
| `/memoire:setup [url]` | Configure le dépôt mémoire de l'appareil, ou en change. Liste ce que le dépôt contient (`--list` à tout moment). |
| `/memoire:pull <projet>` | Synchronise `projets/<projet>/memory/` vers la mémoire auto locale, fichier par fichier, après simulation et confirmation. Fusion à trois voies si les deux côtés ont changé. Visible à la session suivante. |
| `/memoire:push <projet>` | Copie la mémoire auto locale dans `projets/<projet>/memory/`, montre le diff et un récap, demande, puis commit et push. |
| `/memoire:generale [sujet]` | Met à jour la copie locale de `general/`, lit l'index puis le fichier utile. Peut y ajouter une entrée et la pousser sur demande. |
| `/memoire:consolider [projet ou generale]` | Réorganise une mémoire sans rien supprimer : pousse d'abord l'état de référence, fusionne les doublons, déplace le daté dans `journal.md`, allège l'index, rend compte de chaque déplacement, puis pousse après confirmation. |
| `/memoire:revert [projet ou generale] [commit]` | Remet la copie locale dans l'état d'un commit du dépôt, en miroir, après simulation et confirmation. Sans commit, propose les derniers commits du dossier. Le dépôt n'est pas touché ; un push renverra cet état comme un nouveau commit. |

Les skills se déclenchent aussi sur une demande en clair (« charge la mémoire du projet X », « sauvegarde la mémoire », « regarde dans ma mémoire générale »). Un rappel dans `~/.claude/CLAUDE.md` aide :

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
    <nom>/memory/          copie partagée de la mémoire auto d'un projet
```

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

- **Marqueur.** Chaque dossier synchronisé contient `.memoire-sync` (projet, dépôt, commit de la dernière synchro, date). Il sert de base à la fusion et au garde-fou du push. Il n'est jamais poussé. Le nom du projet est résolu contre le dépôt sans tenir compte de la casse, et un marqueur sans commit est refusé : un chemin git faux rendrait les garde-fous aveugles.
- **Pull.** Chaque fichier du dépôt est classé : `nouveau`, `identique`, `depot` (seul le dépôt a changé, copié), `local` (seule la copie locale a changé, gardée), `fusion` (les deux ont changé sans se chevaucher, `git merge-file`), `CONFLIT` (chevauchement : le fichier reçoit des blocs `<<<<<<< local` / `>>>>>>> depot`, que la session résout avec l'utilisateur). La comparaison se fait sur des copies LF, pour ignorer les fins de ligne Windows.
- **Push.** Garde-fous dans l'ordre : marqueurs de conflit (code 6), dépôt avancé depuis la dernière synchro (code 4, lever par un pull), motif de secret (code 5). Puis copie miroir, commit et push. Le commit a un titre fixe, `memoire(<projet>): synchro depuis <machine> le <date>`, et un corps : le récap rédigé par la session, puis la liste des fichiers ajoutés, modifiés ou supprimés.
- **Perte possible.** Une mémoire grossit ou se réorganise, elle ne rétrécit pas sans raison. Un push qui supprime un fichier, ou retire beaucoup plus de lignes qu'il n'en ajoute (au moins 30, et plus du double), est signalé à la simulation et refusé au commit (code 7) tant que `--accept-loss` n'est pas passé, ce que le skill ne fait qu'après avoir montré l'avertissement à l'utilisateur.
- **Retour en arrière.** Le skill `revert` remet la copie locale à l'état d'un commit du dossier (`git archive` de ce commit, miroir en local) sans toucher au dépôt, et pose le marqueur sur la tête actuelle : le push suivant renvoie cet état d'avant comme un nouveau commit, avec l'avertissement de perte. L'historique reste linéaire, la version annulée reste lisible.
- **Consolidation.** Le skill `consolider` fait converger une mémoire de projet vers une forme prévisible, par familles de fiches toujours dans le même ordre : `projet` (une fiche), `etat`, `regles`, `decisions`, `references`, `pieges`, `equipe` (optionnelle), `journal` (une fiche). Le nom d'une fiche dit sa famille puis son thème (`regles-git.md`, `references-donnees-client.md`), et l'index reprend les familles dans le même ordre : une session sait d'avance où chercher. Règles : rien n'est supprimé, le daté part dans `journal.md` (en ajout seul, par date de consolidation, avec la provenance) ; les fiches d'une même famille fusionnent, une fiche trop longue ou mélangée se découpe ; les conventions de dépôt (ce qui vaut pour toute session dans un dépôt de code) sont proposées pour le `CLAUDE.md` du dépôt, que l'utilisateur commite ; les dates relatives deviennent absolues ; ce qui contredit la doc ou explique une décision est gardé. Le dépôt reçoit l'état d'avant, puis l'état d'après, avec un compte rendu en cinq groupes : revenir en arrière est un `revert`.
- **Codes de sortie.** 1 usage, 2 git, 3 projet inconnu, 4 dépôt avancé, 5 secret, 6 marqueurs de conflit, 7 perte refusée (sans `--accept-loss`), 10 pas de dépôt configuré, 11 un autre dépôt est configuré (setup sans `--replace`).

## Sur claude.ai

Le plugin installé sur le compte est aussi chargé dans le chat claude.ai, et le chat dispose d'un bac à sable avec un shell, git, et l'accès GitHub de l'app de Claude (lecture et écriture sur les dépôts auxquels l'app a accès). Les mêmes scripts y tournent, avec trois différences, que chaque SKILL.md décrit dans sa section « Sur claude.ai » :

- pas de configuration persistante dans le plugin : le dépôt est fixé pour la conversation par `CLAUDE_MEMOIRE_REPO`, pris dans les instructions du Projet (une ligne « dépôt mémoire : proprietaire/depot »), dans la mémoire claude.ai de l'utilisateur (lui demander de retenir son dépôt mémoire, une fois, vaut pour toutes ses conversations), dans la conversation, ou sinon parmi les dépôts accessibles, auquel cas il est confirmé par une question avant le premier usage ;
- pas de mémoire auto : un dossier de travail `/home/claude/memoire/<projet>` en tient lieu. `pull` y synchronise la mémoire du projet et Claude la garde en contexte ; `push` part de ce dossier, où Claude écrit ce que la conversation a appris, puis commit et push avec les mêmes garde-fous ;
- `CLAUDE_MEMOIRE_HOST=claude.ai` dans le titre des commits, et une identité git de repli si le bac à sable n'en a pas.

L'app GitHub de Claude doit avoir accès au dépôt mémoire (page d'installation de l'app sur GitHub), et le dépôt doit être attaché à la conversation (outil d'ajout de dépôt du chat) avant le premier clone : le proxy git du bac à sable n'autorise que les dépôts attachés. Le skill setup s'en charge. Un bouton « Add from GitHub » n'est pas nécessaire. La synchronisation GitHub des connaissances d'un Projet reste possible pour que Claude ait la mémoire sous les yeux sans la demander, en lecture seule et rafraîchie à la main.

## Développer le plugin

La marketplace ne reçoit que des versions publiées, chacune par une pull request : on ne développe pas directement dedans. Pour modifier le plugin, travailler sur une copie dans sa propre marketplace : éditer, `claude plugin validate plugins/memoire`, incrémenter `version` dans `.claude-plugin/plugin.json` (sans incrément, claude.ai ne voit pas de nouvelle version), commit, push. Les appareils reçoivent la nouvelle version par le compte claude.ai : relecture de la marketplace côté compte (bouton de synchronisation de la marketplace, dans l'app desktop uniquement, pour ne pas attendre), puis téléchargement au prochain démarrage d'un processus Claude Code (`claude -p ok --model haiku` suffit), puis `/reload-plugins` ou nouvelle session. Le détail observé est dans le README de la marketplace. Pour tester en local sans attendre : `claude plugin marketplace add <dossier de cette marketplace>` et `claude plugin install memoire@<nom de cette marketplace>`, en sachant qu'un plugin du même nom installé localement masque la copie synced.

Les scripts acceptent `CLAUDE_MEMOIRE_HOME` pour déplacer la configuration et la copie locale de la générale (utile pour les tests), `CLAUDE_MEMOIRE_REPO` pour imposer le dépôt sans configuration, et `CLAUDE_MEMOIRE_HOST` pour le nom écrit dans les titres de commit.
