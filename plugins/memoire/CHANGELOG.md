# Changelog du plugin memoire

Une section par version, la plus récente en premier. La section de la version publiée sert de description à la pull request sur la marketplace publique.

## 0.11.2

Le skill `entretien`, après son premier passage réel. Aucun script ne change.

- Quand l'utilisateur demande son avis pendant l'échange, le skill le donne franchement, vérifie au besoin sans rien écrire, puis reprend avec une question.
- Quand un entretien décide une action qui n'est pas encore faite, la conclusion la nomme et propose de la faire, avant le push.

## 0.11.1

Documentation seule : la procédure de mise à jour suit le nouveau menu des plugins de l'app desktop. Aucun script ni skill ne change.

- Dans l'app, la mise à jour se fait depuis Paramètres > Plugins : recherche de mises à jour, puis « Mettre à jour », sans commande.
- L'app garde sa propre copie du plugin : `claude plugin list` peut afficher une version plus ancienne que la sienne. Le démarrage headless ne sert plus que pour Claude Code en ligne de commande.

## 0.11.0

Nouveau skill `entretien` : Claude interroge l'utilisateur pour enrichir sa mémoire. Aucun script ne change.

- Trois usages : trancher ce qui est flou, creuser un sujet, ouvrir un domaine qui manque. La mémoire générale par défaut, un projet s'il est nommé.
- Sans sujet, le skill propose quelques thèmes tirés des manques de la mémoire (fiches à vérifier, flou, contradictions, domaines absents), et reste ouvert à un sujet tout neuf. Il s'appuie sur `optimiser.sh --check`, qui n'écrit rien.
- Une question ouverte à la fois, avec des relances. Rien n'est écrit pendant l'échange, pas même dans la mémoire auto de la session.
- À la fin du thème, le skill montre ce qu'il retient, fiche par fiche. Seul ce qui est validé par une question à choix est écrit et indexé, rangé selon la table de routage d'`AGENTS.md`. Si rien ne convient, il suggère un endroit sans créer de dossier. Sans outil de questions à choix, la validation passe par des options a, b, c dans le message.
- Un thème, puis le skill demande s'il continue. Il ne commite ni ne pousse rien : le skill `push` envoie le résultat.
- Le bloc du `~/.claude/CLAUDE.md` gagne une ligne pour ce skill : `/memoire:setup` propose de le mettre à jour sur chaque appareil.

## 0.10.0

Le skill `setup` devient le parcours de mise en place, de bout en bout : une vue d'état de cinq étapes, et chaque étape faite depuis le même endroit.

- Sans argument, `setup` montre l'état des cinq étapes et la version du plugin, puis propose celles qui manquent, dans l'ordre : dépôt configuré et cloné, projet du dossier de travail branché, bloc du `~/.claude/CLAUDE.md`, `AGENTS.md` dans le dépôt, routine planifiée d'`optimiser`. Avec une URL ou un nom de projet, il fait ce qu'il faisait.
- Le bloc du `~/.claude/CLAUDE.md` est écrit par le plugin, après accord, entre deux marqueurs (`<!-- memoire:debut -->`, `<!-- memoire:fin -->`). Il se met à jour d'une version à l'autre sans toucher au reste du fichier, dont une copie est gardée avant chaque écriture. Un bloc posé à la main, sans marqueurs, est reconnu et proposé au remplacement, différence à l'appui. Le bloc gagne deux lignes : les skills `revert` et `setup`.
- La routine cloud d'`optimiser` se crée depuis le parcours : quatre questions (jour, heure, portée, modèle), la configuration montrée, puis la création avec l'outil de routines de la session, ou la consigne à coller quand il n'y en a pas. L'heure locale est convertie en cron UTC, avec l'avertissement du changement d'heure. La consigne est un modèle du plugin, `skills/optimiser/assets/consigne-routine.md`.
- Section « Routine cloud » du skill `optimiser`, réécrite d'après les premiers passages réels : la routine s'appuie sur le plugin du compte, chargé dans son environnement, sans cloner de second dépôt ; faute de configuration, chaque commande prend `CLAUDE_MEMOIRE_REPO` et le script clone le dépôt mémoire ; l'outil de questions à choix n'y existe pas, les questions se posent toutes dans un message, en options a, b, c, pour une réponse du type « 1a 2b 3a », sans plafond et sans option qui appliquerait tout ; une notification part quand la routine attend une décision ; le push sur la branche par défaut passe après la confirmation.
- `setup.sh` gagne quatre commandes, à la sortie stable : `--etapes` (l'état des étapes, hors ligne, sans rien écrire), `--bloc` et `--bloc --write` (montrer et écrire le bloc), `--cron <jour> <HH:MM>` (le cron UTC d'une heure locale), `--routine` (la consigne remplie). Nouveau code de sortie 12 : les marqueurs du bloc sont abîmés, rien n'est écrit. Nouvelle variable `CLAUDE_MEMOIRE_CLAUDE_MD`, pour essayer le bloc sur un fichier jetable.
- Le README est réorganisé autour d'une page « Mise en place », qui suit les cinq étapes.
- Suite de tests du dépôt de développement : `--groupe <nom>` ne rejoue qu'une partie des cas (`synchro`, `portee`, `reindex`, `optimiser`, `setup`), pour un passage rapide pendant une retouche. Un passage partiel s'annonce comme tel sur sa dernière ligne ; sans option, tout est rejoué comme avant.

## 0.9.1

Le skill `optimiser` présente ses propositions autrement. Aucun script ne change.

- Plus de long rapport suivi d'une question ouverte : un bilan en six lignes (score, corrections automatiques, nombre de propositions), puis des séries de questions à choix, quatre au plus par série, les plus graves d'abord, avec une recommandation en premier.
- Une question par proposition qui demande vraiment un avis. Les corrections sans alternative (forme, dates relatives, types d'en-tête) sont regroupées dans une seule question. Le détail d'une proposition ne se donne que sur demande.
- Nouvelle section « Routine cloud » : le passage peut être joué à heure fixe par une routine cloud de Claude Code, qui attend la décision de l'utilisateur et ne pousse rien avant. Le mode `--planifie`, local, reste disponible.

## 0.9.0

Nouveau skill `optimiser`, qui remplace `consolider` : il corrige seul ce qui est mécanique, mesure la santé de la mémoire et propose le reste.

- Liste fermée de ce qui se corrige sans accord : les index (ce que répare `reindex`), l'en-tête des fiches (`status: actif` ajouté quand il manque, un statut écrit autrement remis à sa valeur, une clé rangée sous `metadata`) et les liens `[[...]]` vers une fiche disparue, remplacés par son nom en clair. Le texte d'une fiche n'est jamais touché.
- Tout le reste est proposé dans un rapport numéroté, classé par gravité : doublons, contradictions, fiches périmées, trop longues, anciennes ou mal nommées, dates relatives, conventions de dépôt à sortir vers `CLAUDE.md`, rangement par familles. Seules les propositions choisies sont appliquées.
- Score de santé : la part des fiches sans aucun écart, en pourcentage, avec le nombre d'écarts par type. Il est calculé par le script, sans le modèle : le même état donne le même score à une date donnée.
- Nouveau script `optimiser.sh`, avec la sortie, la portée et le code 9 de `reindex.sh`, sur lequel il s'appuie : `--check` (par défaut) n'écrit rien, `--fix` corrige et commite, `--commit` enregistre les propositions appliquées. Chaque passage fait ses commits en local, à part du travail en cours, et ne pousse jamais. Le skill `revert` ramène au commit d'avant.
- Passage planifié : `optimiser.sh --planifie` tourne sans personne devant l'écran et écrit son rapport hors du dépôt, dans `~/.claude/memoire/optimiser/`. Le choix de l'outil de planification reste à l'utilisateur.
- Le journal n'est plus une fiche. Celui d'un projet est `projets/<nom>/journal.md`, à côté de `memory/`, sans ligne dans `MEMORY.md`, et les fiches y renvoient par son chemin. Un `journal.md` resté dans `memory/` est signalé, et un lien `[[journal]]` devient ce chemin. Pour la mémoire générale, rien n'est créé : le skill demande où le ranger.
- Valeurs de `status` : `actif`, `a-verifier`, `perime`, sans accent ni espace. Le modèle d'`AGENTS.md` et la documentation sont alignés ; les formes accentuées déjà écrites dans des fiches sont remises à ces valeurs par `optimiser`.
- Le skill `consolider` est retiré. Ce qu'il faisait de juste (fusion, journal, conventions vers `CLAUDE.md`, familles de fiches) devient des propositions d'`optimiser`. Dans le bloc du `~/.claude/CLAUDE.md`, une ligne de plus : celle du skill `optimiser`.
- `reindex.sh --fiches` ajoute à l'inventaire une ligne par fiche.
- Skill `reindex`, après son premier passage réel : la commande de l'étape 1 dit quoi faire sans dossier de mémoire auto ; les marqueurs du modèle s'écrivent comme dans le skill ; la création d'`AGENTS.md` passe par un brouillon hors du dépôt, montré puis copié après accord, et pose la question de la voix (première ou troisième personne) ; le commentaire du modèle sur les règles se retire une fois celles-ci validées ; le cas de la création est décrit pour `agents_hors_bloc`.
- Modèle d'`AGENTS.md` : la section « Synchronisation » dit que rien ne se récupère ni ne se pousse sans demande, et la liste des projets renvoie aux dossiers de `projets/`. `optimiser` signale un projet sans fiche dans `general/projets/`.

## 0.8.2

Documentation seule : le README décrit toute la mise en place sur un appareil. Aucun script ni skill ne change.

- Le bloc à poser dans `~/.claude/CLAUDE.md` devient une étape de « Premier usage ». Il importe `AGENTS.md` dans chaque session et dit à Claude quelle demande lance quel skill.
- Sa dernière ligne interdit pull, push et commit sans demande, au lieu d'interdire de toucher au dépôt : depuis le clone, les sessions y écrivent leur mémoire.
- Les étapes sont données dans l'ordre pour un appareil de plus, et la migration depuis une 0.6.x renvoie au même bloc.

## 0.8.1

Les skills fonctionnent dans une session Claude Code ouverte dans le clone du dépôt mémoire, où la mémoire auto est en général coupée. Aucun script ne change.

- Les sept skills reconnaissent Claude Code même quand le prompt système n'a pas de section « Memory ». Jusqu'ici, l'absence de cette section les faisait conclure à tort qu'ils étaient sur claude.ai.
- `pull`, `push` et `reindex` : sans dossier de mémoire auto, aucune option de portée, donc la partie transverse seule (la mémoire générale et la racine). Un projet nommé par l'utilisateur passe par `--project`, tout le dépôt par `--all` sur demande explicite.
- `setup` ne branche jamais le clone sur lui-même : depuis le clone, il le dit et renvoie vers le dossier de travail du projet.

## 0.8.0

Nouveau skill `reindex` : il vérifie et répare ce qui permet à une session de s'orienter dans le dépôt mémoire.

- `AGENTS.md`, à la racine du dépôt, devient la table de routage de la mémoire : pour chaque dossier, ce qu'il contient, quand le lire, quoi y écrire. Une ligne `@~/claude-memory/AGENTS.md` dans le `~/.claude/CLAUDE.md` de l'appareil la charge dans chaque session.
- Le fichier sépare ce qui est régénéré de ce qui est écrit à la main : la table vit entre deux marqueurs, `<!-- reindex:debut -->` et `<!-- reindex:fin -->`. Le skill n'écrit qu'entre eux, après confirmation. Le reste (présentation, règles, format des fiches) appartient à l'utilisateur et n'est jamais réécrit.
- `reindex.sh --check` (par défaut) contrôle sans rien écrire : `AGENTS.md` présent, sous 200 lignes et 16 Ko, chaque dossier couvert par une entrée, aucune entrée vers un chemin disparu ; dans chaque index `MEMORY.md`, une ligne par fiche, aucune ligne morte, aucune copie. Une entrée peut être générique : `projets/<nom>/memory/` couvre tous les projets.
- `reindex.sh --fix` répare les index : lignes manquantes reconstruites depuis l'en-tête des fiches (`name`, `description`), lignes mortes et copies retirées, index absent créé, lien remis à la casse du fichier. Il n'écrit jamais `AGENTS.md`, ne commite rien et ne pousse rien.
- Même portée que `pull` et `push` : `--fix` n'écrit que dans la partie transverse et dans le projet de la session (`--memory-dir`, `--project`), les autres projets sont signalés et laissés tels quels, sauf `--all`.
- Ce qui n'est pas une fiche (sous-dossier, fichier autre qu'un `.md`) est signalé quand il se trouve dans `memory/` : sa place est à côté, dans `projets/<nom>/`.
- Sortie stable, pensée pour être relue par un autre skill : un enregistrement par ligne, en colonnes séparées par des tabulations, et un bilan en `clé=valeur`. Nouveau code de sortie 9 : il reste des écarts dans la portée.
- Modèle d'`AGENTS.md` fourni avec le skill. Il décrit l'en-tête des fiches, étendu sous `metadata` : `status` (`actif`, `à vérifier`, `périmé`), `tags` et propriétés libres.

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
