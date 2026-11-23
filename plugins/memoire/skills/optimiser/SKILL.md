---
name: optimiser
description: "Entretient une mémoire, celle d'un projet ou la mémoire générale : corrige seul ce qui est mécanique (index, en-tête des fiches, liens vers une fiche disparue), donne un score de santé, puis fait trancher le reste par des questions à choix, les plus graves d'abord (doublons, contradictions, fiches périmées, trop longues ou mal rangées, dates relatives, journal, conventions à sortir vers CLAUDE.md), et n'applique que ce qui a été choisi. Chaque passage fait un commit local, annulable par le skill revert, sans rien pousser. À utiliser quand l'utilisateur demande d'optimiser, consolider, nettoyer, ranger, alléger ou réorganiser une mémoire, ou veut connaître son état de santé. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[verifier | nom-du-projet | generale | tout]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Read, Write, Edit
---

# Optimiser une mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système te présente comme Claude Code, ou s'il a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Cette section manque quand la mémoire auto est coupée, par exemple dans une session ouverte dans le clone du dépôt mémoire : tu es quand même dans Claude Code. Sinon, tu es sur claude.ai, dans le bac à sable d'une conversation. Dans Claude Code, suis « Dans Claude Code » ; sur claude.ai, suis « Sur claude.ai ».

Un passage fait trois choses, dans cet ordre. Le script corrige seul ce qui est mécanique. Il mesure la santé de la mémoire. Puis tu proposes le reste, et seul ce que l'utilisateur choisit est appliqué. Le dépôt mémoire est cloné sur l'appareil (par défaut dans `~/claude-memory`) : tout se passe dans ce clone. Les commits sont faits par le script, en local. Rien n'est jamais poussé ici, et tu n'exécutes jamais git toi-même.

**Ce qui se corrige seul.** La liste est fermée, et le script est le seul à l'appliquer :
- les index `MEMORY.md` : ce que répare le skill reindex (lignes manquantes reconstruites, lignes mortes et copies retirées, index absent créé) ;
- l'en-tête des fiches : `status: actif` ajouté sous `metadata` quand il manque, un statut écrit autrement (`à vérifier`, `Périmé`) remis à sa valeur, une clé autre que `name` et `description` rangée sous `metadata`. Jamais le texte ;
- un lien `[[...]]` vers une fiche disparue, remplacé par son nom en clair. Un lien `[[journal]]` devient le chemin du journal.

**Tout le reste se propose.** Rien d'autre ne s'écrit sans que l'utilisateur ait dit lesquelles des propositions appliquer.

**Portée.** Le script lit et contrôle tout le dépôt, mais il n'écrit et ne commite que dans la partie transverse (la mémoire générale et la racine) et dans les projets de la portée. Les autres projets sont signalés (`hors`) et laissés tels quels. Dans les commandes, `<portée>` est l'une de ces formes, à répéter à l'identique sur chaque appel :
- `--memory-dir "<dossier>"` : le dossier de mémoire auto de cette session, chemin exact de la section « Memory » de ton prompt système, jamais deviné. C'est la forme par défaut.
- `--project "<nom>"` à la place, quand l'utilisateur nomme un projet.
- rien du tout quand ton prompt système n'a pas de section « Memory » (mémoire auto coupée, comme dans une session ouverte dans le clone), ou quand l'argument est `generale` : seule la partie transverse est traitée.
- `--all` seulement si l'utilisateur demande explicitement tout le dépôt (argument `tout`).

## Dans Claude Code

1. **Contrôle.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --check <portée>`
   Code 0 : aucun écart dans la portée. Code 9 : des écarts, c'est le cas courant. Les deux se lisent de la même façon.
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup, puis reviens ici.
   Code 6 : une fusion est en cours dans le clone. Le skill pull la conclut ou l'annule ; ensuite seulement, reviens ici.
   Code 11 : le clone appartient à un autre dépôt, montre le message et arrête-toi. Code 2 : git a échoué, montre l'erreur et arrête-toi.
   Si le script écrit que le dépôt a des commits que ce clone n'a pas encore, propose le skill pull d'abord : corriger un état périmé prépare un conflit. S'il écrit que le dossier de mémoire est hors du clone, ce dossier de travail n'est pas branché : dis-le et propose le skill setup.
   S'il écrit une ligne « dernier passage avec rapport », un passage planifié a tourné sur cet appareil : lis le fichier qu'elle nomme et dis en une ligne ce qu'il a fait.
   Lis la sortie comme l'indique « Lire la sortie du script », plus bas. Résume en trois lignes : le score, ce qui se corrigerait seul (le nombre, par type), le nombre de propositions.
   Si l'argument est `verifier`, ou si l'utilisateur veut seulement son état de santé : arrête-toi là. Rien n'a été écrit.

2. **Corriger ce qui se corrige seul.** La même commande avec `--fix` à la place de `--check`. Pas de question avant : c'est la liste fermée, et l'utilisateur a demandé le passage. Annonce-le en une ligne avant de lancer.
   Le script commite d'abord, à part, le travail en cours de la portée (il le dit sur une ligne « travail local »), puis ses corrections dans un second commit. La ligne « Etat d'avant » donne le commit auquel le skill revert ramène. Note ce commit et `score_avant`.
   Code 5 : un motif de secret dans le travail en cours, que le script refuse de commiter. Montre le fichier nommé et arrête-toi. N'ajoute `--force` que si l'utilisateur te dit que c'est un faux positif.
   S'il reste 0 proposition et que tu n'en trouves aucune à l'étape 3, passe à la conclusion.

3. **Lire la mémoire.** Le script ne voit que la forme. Le fond, c'est toi : lis l'index, puis chaque fiche de la portée, dans le clone (son dossier est sur la ligne « Clone »). Pour un projet de code, lis aussi le `CLAUDE.md` du dépôt de code, où vivent ses conventions. Relève :
   - les doublons : deux fiches qui disent la même chose, ou une information répétée ;
   - les contradictions : entre deux fiches, ou entre une fiche et une règle ou une décision écrite (`AGENTS.md`, une fiche de décisions) ;
   - le périmé : un état dépassé, une décision remplacée, des tâches faites, une chronologie ;
   - ce qui est une convention de dépôt et pas une mémoire ;
   - une fiche qui mélange plusieurs sujets, ou dont le nom ne dit pas le contenu ;
   - ce qui s'éloigne de « La forme d'une mémoire de projet », plus bas.

4. **Le bilan, puis les questions.** L'utilisateur ne doit pas avoir à lire une longue liste ni à y répondre par écrit : tu lui dis en bref ce qui est fait, puis tu lui fais trancher le reste en cliquant.
   - **Prépare la liste.** Une seule liste : les lignes `proposition` du script et ce que tu as relevé à l'étape 3. Classe par gravité (haute, moyenne, faible), numérote de 1 à N. Pour chaque proposition : la ou les fiches, ce qui ne va pas en une phrase, et ce que tu ferais, précisément (quels fichiers changent, ce qui va où, ce qui est retiré et où son contenu reste lisible). Regroupe ce qui se décide d'un bloc : douze renommages pour suivre la même règle font une proposition, pas douze. La gravité des tiennes : haute quand une session serait trompée (contradiction, information fausse), moyenne quand la mémoire est douteuse ou mal rangée (doublon, périmé, fiche mélangée, convention de dépôt), faible pour la forme (nom, découpage, rédaction). Écris cette liste dans un brouillon hors du dépôt mémoire (le dossier temporaire de ta session) : elle te sert de référence, et tu donnes son chemin dans ta réponse.
   - **Le bilan**, dans ta réponse, en six lignes au plus : le score avant et après, le nombre de corrections automatiques par type, le commit du passage et l'état d'avant, le nombre de propositions par gravité, et le rappel que rien n'est poussé. Pas la liste détaillée.
   - **Les questions**, avec AskUserQuestion, par séries de quatre au plus, les plus graves d'abord :
     - une question par proposition qui demande vraiment son avis : gravité haute, plusieurs issues possibles, ou information que lui seul détient. Elle dit en une ou deux phrases la fiche, ce qui ne va pas et ce que tu ferais, et se comprend sans le reste de ta réponse ;
     - deux à quatre options courtes, ta recommandation en premier, marquée « (Recommandé) », et une dernière option pour préciser autrement ;
     - les propositions sans vraie alternative (forme, dates relatives, types d'en-tête, renvois) vont dans une seule question, « Appliquer aussi ces N corrections ? », avec leur liste, une ligne chacune ;
     - s'il y a plus de quatre questions, pose la série suivante quand il a répondu à la précédente.
   - Le détail d'une proposition ne se donne que s'il le demande. Rien n'est écrit dans la mémoire avant ses réponses.

5. **Appliquer.** Seulement les propositions choisies, dans le clone, en suivant « Règles pour appliquer ». Une proposition non choisie ne laisse aucune trace. Si l'une d'elles se révèle différente de ce que tu avais annoncé (plus de fichiers touchés, une perte que tu n'avais pas vue), arrête-toi sur celle-là et redemande.

6. **Commit des propositions.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --commit <portée> --message "<récap>"`
   Le récap : deux ou trois phrases sur ce qui a changé dans le contenu, ton naturel, sans tiret long, sans guillemets doubles, sans `$` ni accent grave. Le script commite ce qui a changé dans la portée, à part des corrections de l'étape 2, et ne pousse rien. S'il répond « Rien a commiter », aucune proposition n'a touché un fichier : passe à la suite. Code 5 : un motif de secret, à retirer avant.

7. **Dernier passage.** La commande de l'étape 2, avec `--fix`. Elle répare ce que tes modifications ont pu laisser de mécanique (la ligne d'index d'une fiche retirée, un lien vers elle) et donne le score final.

8. **Conclusion.** Cinq lignes au plus : le score avant et après, le nombre de corrections automatiques, les propositions appliquées et celles qui restent (par leur numéro), les commits faits (leur identifiant) et le commit d'« Etat d'avant » de l'étape 2, auquel le skill revert ramène, dossier par dossier. Rien n'est poussé : propose le skill push. Si tu as écrit dans un `CLAUDE.md`, rappelle qu'il est à commiter dans le dépôt de code, par l'utilisateur.

## Lire la sortie du script

Des sections `== ... ==`, et dedans un enregistrement par ligne, en colonnes séparées par des tabulations.

- « Corrections » (avec `--fix`) : `corrige`, le code, le fichier, le détail. Ce que le passage a écrit.
- « Ecarts » : `ecart`, le code, `dans` ou `hors` de la portée, `auto` (corrigé par `--fix`) ou `session` (une proposition), le fichier, le détail.
- « Propositions » : `proposition`, un numéro, la gravité, le code, le fichier, le détail. Les écarts `session` de la portée, les plus graves d'abord.
- « Sante » : `fiches`, `fiches_sans_ecart` et `score` pour la portée, les mêmes pour tout le dépôt (`score_depot`), `score_avant` après une correction, puis une ligne `type` par code avec son nombre d'écarts.
- « Bilan » : les totaux, et `commit`, l'identifiant du commit du passage.

Le score est la part des fiches de la portée sans aucun écart, en pourcentage arrondi vers le bas : 100 veut dire que toutes les fiches sont propres. Les écarts qui ne touchent aucune fiche (la table de routage, une ligne morte d'un index) sont comptés dans `ecarts_hors_fiches`, pas dans le score : cite-les à côté. Le script calcule ce score sans toi, et le même état donne le même score à une date donnée. Ne le recalcule pas, ne l'arrondis pas, et ne compte pas tes propres propositions dedans.

## Les codes d'écart

Ceux du skill reindex (`agents-...`, `index-...`, `fiche-sans-entete`, `fiche-entete-incomplet`, `memoire-hors-fiche`) arrivent tels quels : leur sens et leur traitement sont dans ce skill. Pour la table de routage `AGENTS.md`, propose de l'enchaîner plutôt que d'écrire la table ici. Les codes propres à ce skill :

| Code | Ce que ça veut dire | Gravité | Qui agit |
| --- | --- | --- | --- |
| `entete-sans-status` | Pas de `status` dans l'en-tête | | `--fix` : `status: actif` |
| `entete-format` | Statut écrit autrement, clé hors de `metadata` | moyenne s'il reste pour toi | `--fix` ; toi quand la clé existe aux deux endroits, que `metadata` est écrit sur une ligne ou que l'en-tête n'est pas fermé |
| `lien-mort` | Lien vers une fiche qui a existé et n'existe plus, ou `[[journal]]` | | `--fix` : le nom en clair, ou le chemin du journal |
| `lien-sans-cible` | Lien vers un nom qu'aucune fiche n'a jamais porté | faible | toi : faute de frappe à corriger, fiche à écrire, ou lien à laisser |
| `entete-status-inconnu` | Statut hors de `actif`, `a-verifier`, `perime` | moyenne | toi : demande ce qu'il voulait dire |
| `entete-type-inconnu` | `type` absent ou hors de `user`, `feedback`, `project`, `reference` | moyenne | toi : propose le type d'après le contenu |
| `fiche-nom-en-double` | Deux fiches du même dossier portent le même `name` | haute | toi : fusion si c'est un doublon, nouveau nom sinon |
| `fiche-a-verifier` | Fiche marquée `a-verifier` | moyenne | toi : vérifie avec l'utilisateur, corrige, puis `actif` ou `perime` |
| `fiche-perimee` | Fiche marquée `perime` | moyenne | toi : au journal, ou retirée si tout est ailleurs |
| `fiche-trop-longue` | Plus de 8 000 octets | moyenne | toi : découpe par sujet, ou verse le daté au journal |
| `fiche-ancienne` | Fiche active sans changement depuis plus de 90 jours (`project`) ou 180 jours (`reference`) | faible | toi : relis-la ; encore vraie, elle reste `actif` ; un doute, `a-verifier` |
| `date-relative` | « hier », « la semaine dernière » dans le texte | faible | toi : la date en clair, si elle se déduit ; sinon demande |
| `journal-dans-memory` | Un `journal.md` dans `memory/` | moyenne | toi : voir « Le journal » |
| `projet-sans-fiche` | Un projet n'a pas de fiche dans `general/projets/` | faible | toi : propose la fiche (objectif, état en une ligne, où il vit) |

Une fiche ancienne n'est pas une fiche fausse : le seuil sert à faire relire, pas à déclasser. Ne passe jamais une fiche en `a-verifier` ou en `perime` sans que l'utilisateur l'ait choisi.

## Règles pour appliquer

- **Réorganiser n'est pas supprimer.** Une fiche n'est retirée que si tout son contenu utile est dans une autre fiche, dans un `CLAUDE.md` ou dans le journal, et la proposition l'a dit. Ne jette pas ce qui serait pénible à retrouver : un fait qui contredit la doc officielle, une décision et sa raison, un piège rencontré.
- **Durable et daté.** Règles, décisions et leur raison, références, pièges sont durables : on les garde et on les affine. Chronologie, étapes terminées, états intermédiaires, messages envoyés, tâches faites sont datés : ils vont au journal, et la fiche d'état ne garde que le présent.
- **Fusion.** Le texte fusionné garde ce que chaque fiche avait de propre. Les liens vers la fiche retirée pointent vers celle qui reste, et sa ligne d'index disparaît : fais-le toi-même, le dernier passage ne ferait que remplacer ces liens par un nom en clair.
- **Renommage.** Corrige toi-même le lien de la ligne d'index, pour garder son accroche écrite à la main, et les liens `[[...]]` des autres fiches.
- **Contradiction.** Tu ne tranches pas : montre les deux textes, demande lequel est vrai, puis corrige l'autre ou marque-le `perime`.
- **Dates.** Une date relative devient une date en clair (2026-11-12), jamais devinée.
- **Conventions de dépôt** (projets de code). Une règle qui vaut pour toute session dans un dépôt, quel que soit le sujet (style de code et de commentaires, commandes à lancer ou à ne pas lancer, structure, interdits techniques), n'est pas une mémoire : sa place est dans le `CLAUDE.md` du dépôt de code, chargé à chaque session. Après accord, écris-la dans ce `CLAUDE.md`, à la racine ou dans le sous-dossier concerné, sans commit (c'est son dépôt, il commite). La fiche d'origine ne garde qu'un renvoi d'une ligne, ou disparaît si elle ne contenait que ça.
- **En-tête.** `name`, `description` entre guillemets, puis sous `metadata` : `type`, `status`, `tags`. Claude Code ajoute lui-même `node_type`, `originSessionId` et `modified` : laisse-les où ils sont, ne les recopie pas dans une fiche neuve.
- **Déplacer ou retirer un fichier** se fait par une commande de fichiers ordinaire dans le clone, jamais par git. La structure ne change pas : tu ne crées, ne renommes et ne déplaces aucun dossier. Si un nouveau dossier te paraît utile, tu le proposes.
- **Jamais de secret**, nulle part.

## Le journal

Le journal reçoit ce qui est daté ou dépassé, pour que les fiches ne gardent que le présent sans que rien ne se perde. Ce n'est pas une fiche.

- **Projet** : `projets/<nom>/journal.md`, à côté de `memory/`, jamais dedans. Il n'a pas de ligne dans `MEMORY.md` et pas d'en-tête de fiche : un titre, puis une section `## <date du passage>` par passage. S'il n'existe pas, tu le crées à cet endroit quand une proposition choisie y verse quelque chose.
- **En ajout seul.** Chaque élément versé garde sa date d'origine et sa provenance (`de <fichier>`). Le texte est recopié tel quel, liens compris : c'est une archive, on ne la réécrit pas.
- **Y renvoyer** : une fiche cite le journal par son chemin, `projets/<nom>/journal.md`, jamais par un lien `[[journal]]`.
- **`journal-dans-memory`** : un journal est resté dans `memory/`. Propose de le déplacer à côté, tel quel. Une fois déplacé, sa ligne d'index et les liens `[[journal]]` des fiches sont corrigés par le dernier passage.
- **Mémoire générale** : `general/` ne contient que des fiches, et rien ne dit d'avance où irait son journal. Regarde si `AGENTS.md` nomme un endroit. Sinon, ne crée rien : dis-le, suggère un fichier à la racine du dépôt, à côté de `general/` comme le journal d'un projet est à côté de `memory/`, et attends sa décision. En attendant, ce qui est dépassé dans la mémoire générale reste dans sa fiche, marqué `perime` s'il le choisit.

## La forme d'une mémoire de projet

Une mémoire prévisible se lit plus vite : une session sait d'avance où chercher. Cette forme sert de repère pour tes propositions de rangement, toutes de gravité faible. Elle ne s'impose pas : une mémoire tenue autrement, de façon régulière, se laisse comme elle est.

| Famille | Contenu | `metadata.type` |
| --- | --- | --- |
| `projet` | une fiche : quoi, pour qui, avec qui, dates clés, où vivent les choses (dépôts, docs, `CLAUDE.md`), et un court « où trouver quoi » | project |
| `etat` | où on en est et la suite immédiate ; courte, réécrite à chaque fois, le passé va au journal | project |
| `regles` | comment l'utilisateur veut travailler sur ce projet : préférences, interdits, rituels ; pas les conventions du dépôt | feedback |
| `decisions` | choix faits et leur raison, datés ; une décision remplacée va au journal | project |
| `references` | environnements, données, comptes, adresses, commandes utiles ; jamais de secret | reference |
| `pieges` | ce qui a surpris ou coûté : pièges techniques, erreurs à ne pas refaire | feedback |
| `equipe` | optionnelle : les personnes, leur rôle, ce qui leur est dû | reference |

Le nom d'une fiche dit sa famille puis son thème (`regles-git.md`, `decisions-metriques.md`), sans phrase : le sens va dans `description` et dans l'accroche de l'index. `MEMORY.md` reprend les familles dans le même ordre, une section par famille, une ligne par fiche, sous 200 lignes. La mémoire générale a sa propre forme, donnée par `AGENTS.md` : on la respecte telle quelle.

## Passage planifié

Le script a un mode fait pour tourner sans personne devant l'écran :

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --planifie <portée>`

Il fait ce que fait l'étape 2 : corrections de la liste fermée et commit local, jamais de push, jamais de proposition appliquée. git n'y pose aucune question. Le rapport est aussi écrit dans un fichier hors du dépôt, `~/.claude/memoire/optimiser/dernier-rapport.txt`, avec une ligne par passage dans `historique.tsv` à côté. Si quelque chose l'arrête (fusion en cours, secret dans le travail en cours), le rapport le dit.

- Ce skill ne planifie rien lui-même. Si l'utilisateur demande de mettre le passage en place, donne-lui la commande, avec le chemin réel du script, et laisse-le choisir son outil de planification. S'il préfère un passage qui l'attend dans le cloud, voir « Routine cloud », juste après : c'est le skill setup qui la crée.
- La portée s'écrit dans la commande planifiée, une fois pour toutes. Sans option, le passage ne corrige que la partie transverse et signale le reste. Avec `--all` ou des `--project`, dis-lui ce que cela entraîne : les commits d'un passage partent avec le prochain push, depuis n'importe quel projet, et le travail en cours de ces projets est commité en local avant le passage.
- Quand il demande ce qu'a donné le dernier passage, lis le rapport et résume-le. Pour traiter les propositions qu'il contient, reprends ce skill à l'étape 1 : l'état a pu changer depuis.

## Routine cloud

Autre façon de planifier : une routine de Claude Code dans le cloud, qui fait le passage à heure fixe puis attend la décision de l'utilisateur. Il la retrouve sur tous ses appareils, répond quand il veut, et rien ne tourne sur son poste. Le mode `--planifie` ne sert pas ici : c'est le déroulé ordinaire de ce skill, joué par la session de la routine.

Si c'est la consigne d'une routine qui t'a amené ici, tu es cette session : suis « Dans Claude Code » avec les différences ci-dessous, et les paramètres que donne la consigne (le dépôt, le préfixe des commandes, la portée).

- **La créer.** C'est le skill setup qui crée la routine, à l'étape 5 de son parcours : il demande le jour, l'heure, la portée et le modèle, puis la crée avec l'outil de routines de la session, ou donne la consigne à coller. La consigne vient d'un modèle du plugin, `assets/consigne-routine.md` dans le dossier de ce skill. Ce skill-ci ne crée, ne modifie et ne lance aucune routine.
- **Le plugin.** Le plugin installé sur le compte est chargé dans l'environnement d'une routine (sous `~/.claude/plugins/synced/`) et ses skills y sont listés : la routine s'appuie sur lui, sans cloner de second dépôt. Si le plugin manque, la consigne arrête la routine, qui le dit. Si `${CLAUDE_PLUGIN_ROOT}` n'est pas résolu dans une commande, cherche `scripts/optimiser.sh` du plugin memoire sous ce dossier.
- **Les commandes.** Il n'y a pas de configuration du plugin dans le cloud. Devant chaque commande de « Dans Claude Code » : `CLAUDE_MEMOIRE_REPO=<url du dépôt mémoire> CLAUDE_MEMOIRE_HOST=<un nom pour la routine>`. Le script clone alors lui-même le dépôt mémoire dans `~/claude-memory`, et c'est ce clone que la session lit et modifie, pas une autre copie du dépôt que l'environnement aurait préparée.
- **La portée** se fixe dans la consigne de la routine. Dans le cloud, le clone est neuf : il n'a aucun travail en cours, donc `--all` n'y fait partir par surprise le brouillon d'aucun projet.
- **Les questions.** L'outil de questions à choix n'existe pas dans une routine, même après une réponse de l'utilisateur : ne le cherche pas, ne l'attends pas. Les questions s'écrivent dans le message, avec des options a, b, c. C'est la norme dans une routine, pas un repli. L'étape 4 devient :
  - le bilan, en six lignes au plus, inchangé ;
  - puis toutes les questions du passage, dans le même message, numérotées, les plus graves d'abord. Aucun plafond par passage et aucune série à attendre : l'utilisateur tranche tout d'un coup ;
  - sous chaque question, ses options sur une ligne chacune, de a à d au plus : ta recommandation en a, marquée « (Recommandé) », et une dernière option pour préciser autrement ;
  - les corrections sans vraie alternative restent regroupées dans une seule question, avec leur liste ;
  - aucune option ni question qui appliquerait tout d'un geste : chaque point important se tranche pour lui-même ;
  - une dernière ligne dit comment répondre : le numéro et la lettre de chaque choix, du type « 1a 2b 3a ».
  Une réponse incomplète ne vaut que pour les questions citées : redemande les autres, sans rien supposer.
- **Prévenir.** Chaque fois que la session s'arrête sur une décision de l'utilisateur (les questions posées, la confirmation du push, un script qui a échoué), elle le prévient par l'outil de notification de la session, s'il existe : une ligne, avec le score et le nombre de questions. Une notification mobile existe dans les routines. Puis elle s'arrête.
- **Rien n'est poussé avant sa réponse.** La session fait les étapes 1 à 4, s'arrête sur ses questions et attend. Quand il a répondu, elle applique (étapes 5 à 7), puis enchaîne avec le skill push, avec le même préfixe et la même portée. La confirmation du push se pose de la même façon : une question, « a. Pousser », « b. Ne rien pousser », avec les commits, le nombre de fichiers et l'avertissement de perte s'il y en a un. S'il n'a retenu aucune proposition, demande-lui s'il veut pousser les corrections automatiques ou tout laisser. Après son oui, le push sur la branche par défaut du dépôt passe depuis une routine. Si l'environnement de la routine a expiré avant sa réponse, le passage est à relancer : le script redonne les mêmes corrections.
- **Ensuite**, l'utilisateur fait un pull sur ses appareils. La conclusion le lui rappelle.

## Sur claude.ai

Le bac à sable a un shell, git et l'accès GitHub de l'app de Claude : les mêmes commandes fonctionnent, sur le clone du bac à sable (`~/claude-memory`), qui vit le temps de la conversation. Quatre différences :

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai). Préfixe ensuite chaque commande : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh ...`. Le premier appel clone le dépôt.
2. **Portée.** Pas de mémoire auto : `--project "<nom>"` quand la conversation porte sur un projet, aucune option pour la partie transverse seule.
3. **La question est tout ce que l'utilisateur voit.** À l'étape 4, mets le bilan dans le texte de la première question, et dans chaque question tout ce qu'il faut pour décider.
4. **Rien ne dure sans push.** Les commits du passage restent dans le bac à sable : enchaîne avec le skill push avant la fin de la conversation, sinon le travail est perdu. Le passage planifié n'existe pas ici.
