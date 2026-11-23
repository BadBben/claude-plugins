---
name: reindex
description: "Vérifie et répare ce qui permet de s'orienter dans la mémoire partagée : AGENTS.md, la table de routage à la racine du dépôt mémoire (pour chaque dossier, ce qu'il contient, quand le lire, quoi y écrire), et les index MEMORY.md (une ligne par fiche, aucune ligne morte, lignes manquantes reconstruites depuis l'en-tête des fiches). À utiliser quand l'utilisateur demande de créer, mettre à jour ou vérifier AGENTS.md ou la table de routage, de réindexer sa mémoire, de vérifier ou réparer ses index, ou après un changement de structure du dépôt mémoire. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[verifier | nom-du-projet | tout]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/reindex.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Read, Write, Edit
---

# Réindexer la mémoire

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système te présente comme Claude Code, ou s'il a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Cette section manque quand la mémoire auto est coupée, par exemple dans une session ouverte dans le clone du dépôt mémoire : tu es quand même dans Claude Code. Sinon, tu es sur claude.ai, dans le bac à sable d'une conversation. Dans Claude Code, suis « Dans Claude Code » ; sur claude.ai, suis « Sur claude.ai ».

Deux choses permettent à une session de s'orienter dans le dépôt mémoire, cloné sur l'appareil (par défaut dans `~/claude-memory`) :

- `AGENTS.md`, à la racine : la table de routage. Pour chaque dossier, ce qu'il contient, quand le lire, quoi y écrire. Elle est importée dans chaque session, d'où ses limites : 200 lignes et 16 Ko.
- `MEMORY.md`, l'index de chaque dossier de mémoire : une ligne par fiche.

Le script fait ce qui est mécanique : l'inventaire, les contrôles, et la réparation des index. Toi, tu fais ce qui demande du jugement : rédiger les entrées de la table de routage, ranger les lignes reconstruites, proposer une suite pour ce que le script ne peut que signaler. Tu n'exécutes jamais git toi-même, et ce skill ne commite ni ne pousse rien : c'est le rôle du skill push.

**Portée.** Le script lit et contrôle tout le dépôt, mais `--fix` n'écrit que dans la partie transverse (la mémoire générale et la racine) et dans les projets de la portée. Les index des autres projets sont signalés (`hors`) et laissés tels quels. Dans les commandes, `<portée>` est l'une de ces formes, à répéter à l'identique sur chaque appel :
- `--memory-dir "<dossier>"` : le dossier de mémoire auto de cette session, chemin exact de la section « Memory » de ton prompt système, jamais deviné. C'est la forme par défaut.
- `--project "<nom>"` à la place, quand l'utilisateur nomme un projet.
- rien du tout quand ton prompt système n'a pas de section « Memory » (mémoire auto coupée, comme dans une session ouverte dans le clone) : seule la partie transverse est réparée, les index des projets sont signalés.
- `--all` seulement si l'utilisateur demande explicitement tout le dépôt (argument `tout`).

## Dans Claude Code

1. **Contrôle.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/reindex.sh --check <portée>`, avec la forme de `<portée>` qui correspond à ta session : `--memory-dir "<dossier de mémoire auto>"` si ton prompt système a une section « Memory », rien du tout sinon.
   Code 0 : rien à faire dans la portée. Dis-le en une ligne, signale ce que le script liste hors de la portée, et arrête-toi.
   Code 9 : des écarts, à lire à l'étape 2.
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup, puis reviens ici.
   Code 6 : une fusion est en cours dans le clone. Le skill pull la conclut ou l'annule ; ensuite seulement, reviens ici.
   Code 11 : le clone appartient à un autre dépôt, montre le message et arrête-toi. Code 2 : git a échoué, montre l'erreur et arrête-toi.
   Si le script écrit que le dépôt a des commits que ce clone n'a pas encore, propose le skill pull d'abord : réparer un état périmé prépare un conflit. S'il écrit que le dossier de mémoire est hors du clone, ce dossier de travail n'est pas branché : dis-le et propose le skill setup.

2. **Lire le résultat.** La ligne « Clone » donne le dossier où lire et écrire. « Inventaire » liste les dossiers à router (`routage=oui`, `non`, ou `-` quand la table est illisible) et les index. « AGENTS.md » donne l'état de la table. « Ecarts » a une ligne par écart, en colonnes séparées par des tabulations : le code, `dans` ou `hors` de la portée, `auto` (réparé par `--fix`) ou `session` (pour toi, avec l'utilisateur), le fichier, le détail. Les codes sont expliqués plus bas.
   Résume en quelques lignes, en commençant par le projet de la session : ce que `--fix` réparerait, ce qui demande une décision, ce qui concerne d'autres projets.
   Si l'argument est `verifier`, ou si l'utilisateur veut seulement savoir où il en est : arrête-toi là. Rien n'a été écrit.

3. **Réparer les index** (écarts `auto` dans la portée).
   - Rapproche d'abord les lignes mortes et les lignes manquantes d'un même index. Une fiche renommée apparaît deux fois : une ligne morte vers l'ancien nom, une ligne manquante pour le nouveau. Sa ligne mérite d'être gardée : son accroche a été écrite à la main, alors que `--fix` la supprimerait pour en reconstruire une depuis l'en-tête.
   - Pose une seule question avec AskUserQuestion, dont le texte liste ce qui va changer, index par index : lignes ajoutées, lignes retirées (cite-les), liens corrigés pour une fiche renommée, copies supprimées, index créés. Options : « Réparer les index », « Annuler ». Rien n'est écrit avant.
   - S'il confirme : corrige d'abord toi-même le lien des fiches renommées, puis lance la même commande avec `--fix` à la place de `--check`. Le bloc « Corrections » liste ce que le script a écrit.
   - Range ensuite chaque ligne reconstruite. Le script les ajoute en fin d'index, sous le titre « Lignes reconstruites » quand l'index a des sections, avec le `name` de la fiche comme titre et sa `description` comme accroche. Déplace chaque ligne dans la section qui lui convient, donne-lui un titre lisible, raccourcis l'accroche si elle dépasse une ligne d'écran sans en changer le sens, et retire le titre « Lignes reconstruites » une fois vide.

4. **Ce que le script ne répare pas dans les fiches** (écarts `session` hors d'`AGENTS.md`). Pour chacun, explique et propose, sans rien faire d'office :
   - `fiche-sans-entete`, `fiche-entete-incomplet` : la fiche n'a pas l'en-tête dont sa ligne d'index se construit. Si c'est bien une fiche, propose l'en-tête (`name`, `description`, `metadata`) et écris-le après accord. Si c'est un document, sa place est à côté de `memory/`.
   - `memoire-hors-fiche` : un sous-dossier ou un fichier qui n'est pas une fiche se trouve dans `memory/`. Sa place est à côté, dans `projets/<nom>/`. Tu ne déplaces rien : dis ce qui est à déplacer et où, l'utilisateur décide et le fait. Un journal resté dans `memory/` sous le nom `journal.md` passe ce contrôle, parce que c'est un `.md` : le skill optimiser le signale, et sa place est `projets/<nom>/journal.md`, sans ligne dans `MEMORY.md`.
   - `index-ligne-morte` ou `index-ligne-en-double` en `session` : la ligne porte d'autres liens vivants, ou deux lignes différentes pointent vers la même fiche. Propose le texte à garder.
   - `index-trop-long` : au-delà de 200 lignes ou de 25 Ko, Claude Code ne charge pas la fin de l'index. Propose le skill optimiser.

5. **La table de routage** (écarts `agents-...`). Lis d'abord « Ce qui fait une bonne entrée » et « Le format d'AGENTS.md », plus bas.
   - **Pas d'`AGENTS.md`** (`agents-absent`). Pars du modèle `${CLAUDE_PLUGIN_ROOT}/skills/reindex/assets/modele-AGENTS.md`, dans cet ordre :
     - La voix. Le fichier est à l'utilisateur et sera lu dans chaque session : demande-lui s'il le veut à la première personne (« ma mémoire », « si je maintiens mon choix ») ou à la troisième (« la mémoire de », suivi de son prénom). Le modèle est écrit à la troisième, avec `{{utilisateur}}` : à la première personne, réécris les phrases qui le portent, sans rien changer d'autre.
     - La présentation, avec ce qu'il dit de sa mémoire (demande-lui s'il n'a rien dit : deux ou trois phrases suffisent).
     - Les entrées, à partir de l'inventaire : lis l'index de chaque dossier, pas les fiches.
     - Les règles. Celles du modèle sont des propositions : passe-les une par une avec lui, qui garde, reformule ou retire chacune, et écris-les dans ses mots. Une fois qu'il les a validées, retire le second commentaire de la section « Règles », celui qui commence par « À retirer » : il ne dit plus vrai. Le premier reste.
     - La ligne sous la table et la section « Synchronisation » se gardent telles quelles, sauf s'il les reformule. La première renvoie à l'index de `general/` pour l'état des projets : si `general/projets/` n'a pas une fiche par projet, dis-le (le skill optimiser le signale).
     - Aucun `{{...}}` ne doit rester.
   - **`AGENTS.md` existe.** Tu n'écris qu'entre les deux marqueurs. Une entrée par `agents-chemin-sans-entree`, sauf si une entrée générique suffit. Pour un `agents-entree-sans-chemin`, demande si le dossier a été renommé (tu corriges le chemin et gardes le texte) ou supprimé (tu retires la ligne). Les entrées qui ne sont pas en cause restent telles quelles.
   - **`agents-bloc-invalide`** : le fichier n'a pas ses deux marqueurs, ou les a en désordre. Propose de les poser autour de la table existante, sans toucher au reste.
   - **`agents-hors-limites`** : dis ce qui pourrait sortir du fichier et vers quelle fiche. Si ce sont des règles, l'utilisateur seul décide.
   - **`agents-entree-illisible`** : une ligne de la table n'a pas de chemin en première colonne. Montre-la et propose sa correction.
   - **Montrer avant d'écrire.** Écris dans ta réponse les entrées ajoutées, retirées ou modifiées (l'ancien texte et le nouveau), puis pose une seule question avec AskUserQuestion : « Écrire ces entrées », « Annuler ». Rien n'est écrit dans `AGENTS.md` avant cette confirmation.
   - **Pour une création**, le fichier entier ne tient pas dans une question. Écris-le d'abord en brouillon hors du dépôt mémoire (le dossier temporaire de ta session), montre ce brouillon en entier dans ta réponse, puis pose la question : « Créer AGENTS.md », « Annuler ». Après accord, copie le brouillon à l'identique à la racine du clone. S'il demande un changement, corrige le brouillon et montre-le de nouveau.
   - **Vérifier que tu n'as touché qu'au bloc.** Note la valeur de `agents_hors_bloc` à l'étape 1. Elle doit être la même après ton écriture. Si elle est passée d'`inchange` à `modifie`, ta modification a débordé sur la partie écrite à la main : remets ce texte comme il était avant de continuer. Pour une création, ce contrôle ne s'applique pas : la ligne n'existe pas à l'étape 1 (`agents_etat=absent`) et vaut `nouveau` ensuite, tant que le fichier n'a pas été commité par un push. Ce qui tient lieu de preuve, c'est que le fichier écrit est le brouillon validé.

6. **Recontrôle.** La commande de l'étape 1. Code 0 : tout est en ordre dans la portée. Code 9 : dis ce qui reste et pourquoi (une décision en attente, un fichier à déplacer par l'utilisateur).

7. **Conclusion.** Trois lignes au plus : ce qui a été réparé, ce qui reste, ce qui concerne d'autres projets. Rien n'est commité ni poussé : propose le skill push, qui envoie le projet de la session et la partie transverse, donc `AGENTS.md`. Après une création d'`AGENTS.md`, donne à l'utilisateur la ligne d'import à ajouter lui-même dans le `~/.claude/CLAUDE.md` de chaque appareil, avec le chemin du clone (par défaut `@~/claude-memory/AGENTS.md`) : c'est elle qui charge la table dans chaque session. Tu ne modifies pas ce fichier.

## Ce qui fait une bonne entrée

Chaque ligne de la table entre dans le contexte de chaque session. Ces règles décident de ce que tu écris, et leur raison compte autant qu'elles.

- **Elle route, elle ne résume pas.** Une entrée dit où trouver et où ranger, jamais le contenu. Une information recopiée dans la table vit en double et se périme : la table pointe vers l'index, l'index vers la fiche.
- **Seulement ce qu'une session ne peut pas deviner.** Ne répète pas ce que le nom du dossier dit déjà. Écris ce qui évite une erreur : quand le lire, quoi y écrire, quoi ne pas y mettre.
- **Courte.** Une ligne de tableau, trois cellules de quelques mots. Un fichier long est moins bien suivi, et le script refuse au-delà de 200 lignes ou de 16 Ko.
- **Générique quand c'est possible.** `<nom>` vaut pour n'importe quel nom : une seule entrée `projets/<nom>/memory/` couvre tous les projets, et la table ne grossit pas à chaque projet. Une entrée couvre aussi tout ce qui est sous son chemin. N'écris une entrée propre à un projet que si l'utilisateur veut router vers lui par son sujet.
- **Fidèle à l'arborescence.** Tout dossier de l'inventaire est couvert, toute entrée désigne un chemin qui existe. Une table fausse est pire que pas de table : la session range au mauvais endroit en toute confiance.
- **Quand tu ne sais pas, demande.** Ce qu'un dossier contient se lit dans son index. Quand le lire et quoi y écrire, c'est l'utilisateur qui le sait.
- **La structure est stable.** Tu ne crées, ne renommes et ne déplaces aucun dossier. Si un nouveau dossier te paraît utile, tu le proposes.

## Le format d'AGENTS.md

Le fichier sépare ce qui est régénéré de ce qui est écrit à la main, par deux lignes de marqueur (des commentaires HTML, chacun seul sur sa ligne) :

```
<!-- reindex:debut -->

| Dossier | Ce qu'il contient | Le lire quand | Y écrire |
|---|---|---|---|
| `general/profil/` | ... | ... | ... |
| `projets/<nom>/memory/` | ... | ... | ... |

<!-- reindex:fin -->
```

- **Les deux marqueurs** s'écrivent exactement comme ci-dessus, sans rien ajouter dans le commentaire. Le modèle les porte sous cette forme.
- **Entre les marqueurs** : la table de routage. C'est la seule partie que ce skill écrit. Chaque ligne commence par le chemin qu'elle décrit, entre accents graves, depuis la racine du dépôt. Plusieurs tableaux et du texte entre eux sont permis ; le script ne lit que les lignes de tableau.
- **Hors des marqueurs** : la présentation, le mode d'emploi, les règles, le format des fiches. Cette partie appartient à l'utilisateur, dans ses mots. Tu ne la réécris jamais, pas même pour corriger une faute. Si une règle te semble contredire l'arborescence ou une autre règle, dis-le et laisse-le trancher ; s'il te dicte un changement, tu l'écris tel qu'il le dit.
- Le script ne modifie jamais `AGENTS.md`, même avec `--fix`.

## Les codes d'écart

| Code | Ce que ça veut dire | Qui répare |
| --- | --- | --- |
| `agents-absent` | Pas d'`AGENTS.md` à la racine | toi, étape 5 |
| `agents-hors-limites` | Plus de 200 lignes ou de 16 Ko | toi, avec l'utilisateur |
| `agents-bloc-invalide` | Marqueurs absents, en double ou en désordre | toi, après accord |
| `agents-entree-illisible` | Ligne de la table sans chemin en première colonne | toi |
| `agents-entree-sans-chemin` | Une entrée désigne un chemin qui n'existe pas | toi, étape 5 |
| `agents-chemin-sans-entree` | Un dossier, ou un fichier à côté de `memory/`, n'est couvert par aucune entrée | toi, étape 5 |
| `index-absent` | Un dossier a des fiches et pas de `MEMORY.md` | `--fix` |
| `index-ligne-manquante` | Une fiche n'a pas de ligne dans son index | `--fix` |
| `index-ligne-morte` | Une ligne pointe vers une fiche qui n'existe plus | `--fix`, ou toi si la ligne a d'autres liens |
| `index-ligne-en-double` | Plusieurs lignes pour une même fiche | `--fix` si elles sont identiques, sinon toi |
| `index-lien-casse` | Le lien n'a pas les mêmes majuscules que le fichier : il casse sur un système sensible à la casse | `--fix` |
| `index-trop-long` | Plus de 200 lignes ou de 25 Ko | skill optimiser |
| `fiche-sans-entete`, `fiche-entete-incomplet` | Pas d'en-tête, ou sans `name` ou sans `description` | toi, étape 4 |
| `memoire-hors-fiche` | Un sous-dossier ou un fichier qui n'est pas une fiche, dans `memory/` | l'utilisateur, sur ta proposition |

## Sur claude.ai

Le bac à sable a un shell, git et l'accès GitHub de l'app de Claude : les mêmes commandes fonctionnent, sur le clone du bac à sable (`~/claude-memory`), qui vit le temps de la conversation. Trois différences :

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai). Préfixe ensuite chaque commande : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/reindex.sh ...`. Le premier appel clone le dépôt.
2. **Portée.** Pas de mémoire auto : `--project "<nom>"` quand la conversation porte sur un projet, aucune option pour la partie transverse seule.
3. **Rien ne dure sans push.** Ce que tu répares ou écris reste dans le bac à sable : enchaîne avec le skill push avant la fin de la conversation, sinon le travail est perdu. Chaque question de confirmation est la seule chose que l'utilisateur voit à ce moment-là : elle doit contenir tout ce qu'il faut pour décider.

Les étapes sont celles de « Dans Claude Code ». La ligne d'import de l'étape 7 ne concerne que Claude Code : sur claude.ai, la table se lit à la demande, depuis le clone.
