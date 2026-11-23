---
name: entretien
description: "Interroge l'utilisateur pour enrichir sa mémoire, la mémoire générale par défaut ou un projet nommé : trancher ce qui est flou, creuser un sujet, ouvrir un domaine qui manque. Sans sujet, propose des thèmes tirés des manques de la mémoire, ou part d'un sujet tout neuf. Une question ouverte à la fois, avec des relances, et rien n'est écrit pendant l'échange : à la fin du thème, montre ce qui est retenu, fiche par fiche, et n'écrit que ce qui est validé par des questions à choix. Ne commite ni ne pousse rien. À utiliser quand l'utilisateur demande un entretien, demande à être interrogé ou veut développer un sujet dans sa mémoire. Pour nettoyer ou ranger une mémoire existante, c'est le skill optimiser. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[sujet] [projet nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --check*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Read, Write, Edit
---

# Entretien

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système te présente comme Claude Code, ou s'il a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Cette section manque quand la mémoire auto est coupée, par exemple dans une session ouverte dans le clone du dépôt mémoire : tu es quand même dans Claude Code. Sinon, tu es sur claude.ai, dans le bac à sable d'une conversation. Dans Claude Code, suis « Dans Claude Code » ; sur claude.ai, suis « Sur claude.ai ».

Tu interroges l'utilisateur pour que sa mémoire dise mieux ce qui compte : trancher ce qui est flou, creuser un sujet, ouvrir un domaine qui manque. Un entretien produit beaucoup de texte, dont peu mérite une fiche : c'est pour cela que l'écriture vient à la fin, et seulement après validation.

**Trois règles tiennent du début à la fin.**
- **Rien ne s'écrit pendant l'échange.** Ni fiche, ni index, ni brouillon dans le clone, ni mémoire auto de la session, même si ton prompt système t'invite à retenir ce que tu apprends. Tout reste dans la conversation jusqu'au bilan du thème.
- **Seul ce qui est validé est écrit**, fiche par fiche, à l'étape 5.
- **Ni commit ni push.** Tu n'exécutes jamais git toi-même, et ce skill laisse son travail dans le clone. C'est le skill push qui l'envoie, quand l'utilisateur le demande.

**Portée.** La mémoire générale par défaut, même dans la session d'un projet. Un projet seulement si l'utilisateur le nomme, en argument (`projet <nom>`) ou dans sa demande. Dans les commandes, `<portée>` vaut rien du tout pour la mémoire générale, et `--project "<nom>"` pour un projet.

**Les questions à choix.** Partout où ce skill en demande une, utilise l'outil de questions à choix de la session (AskUserQuestion dans Claude Code), ta recommandation en premier, marquée « (Recommandé) ». Si cet outil n'existe pas dans ta session, écris la question dans ton message avec des options a, b, c, une par ligne, ta recommandation en a, puis attends la réponse.

## Dans Claude Code

1. **État de la mémoire.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --check <portée>`
   Ce skill n'utilise ce script qu'avec `--check`, qui n'écrit rien. Codes 0 et 9 : le cas normal, les écarts servent à l'étape 2.
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup, puis reviens ici.
   Code 6 : une fusion est en cours dans le clone. Le skill pull la conclut ou l'annule ; ensuite seulement, reviens ici.
   Code 11 : le clone appartient à un autre dépôt, montre le message et arrête-toi. Code 2 : git a échoué, montre l'erreur et arrête-toi.
   Si le script écrit que le dépôt a des commits que ce clone n'a pas encore, propose le skill pull d'abord : une fiche écrite sur un état périmé prépare un conflit. S'il écrit que le projet est inconnu, donne les noms de `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --list` et arrête-toi : un nouveau projet se crée par le skill setup, pas ici.
   La ligne « Clone » donne le dossier où lire et écrire. Lis `AGENTS.md` à sa racine, sauf s'il est déjà chargé dans ta session, puis l'index de la portée : `general/MEMORY.md`, ou `projets/<nom>/memory/MEMORY.md`.

2. **Choisir le thème.**
   - Un sujet en argument ou dans la demande : c'est le thème, passe à l'étape 3.
   - Sans sujet, cherche ce qui manque à la mémoire. Lis les fiches signalées par le script, `general/profil/` pour la mémoire générale, et les autres seulement si leur ligne d'index touche un manque probable. Tu cherches :
     - les fiches à vérifier ou anciennes (écarts `fiche-a-verifier` et `fiche-ancienne` marqués `dans`) ;
     - le flou : une préférence sans sa raison, une règle qui hésite, une décision dont on ne sait plus si elle tient ;
     - les contradictions entre deux fiches, ou entre une fiche et une règle d'`AGENTS.md` ;
     - les domaines absents : un dossier vide, un projet sans fiche (`projet-sans-fiche`), une facette du travail ou des goûts de l'utilisateur que rien n'aborde.
   - Les écarts de forme (index, en-tête, liens, longueur) ne sont pas des thèmes : ils relèvent du skill optimiser.
   - Pose une question à choix : trois thèmes au plus, le plus utile en premier, chacun dit en une ligne ce qui manque et d'où vient ce constat, plus une option « Un sujet à moi » pour quelque chose que l'utilisateur a fait, aimé ou veut développer. Si la mémoire est presque vide, propose des domaines de départ : le métier, la façon de travailler, les outils, ce qui a marché ou non.

3. **L'entretien.** Lis d'abord les fiches qui touchent au thème, pour ne jamais redemander ce que la mémoire sait déjà. Ensuite :
   - **Une seule question par message**, ouverte, en texte libre. Pas d'outil de questions à choix ici : un choix fermerait la réponse, et le but est de faire parler.
   - **Court.** Pas de préambule, de compliment ni de résumé à chaque tour.
   - **Relance sur ce qui vient d'être dit** : un exemple concret, la raison, ce qui a changé, un contre-exemple, ce qui ferait changer d'avis. Une relance vaut mieux qu'un nouveau sujet.
   - **Ne souffle pas les réponses.** Pas de liste de possibilités, pas d'hypothèse présentée comme un fait.
   - **Sauf si l'utilisateur demande ton avis.** Donne-le franchement, en quelques phrases, en distinguant ce qui est sûr de ce qui ne l'est pas. Si la réponse demande une vérification (la doc, un fichier), fais-la sans rien écrire. Puis reprends avec une question.
   - **Si une réponse contredit une fiche ou une règle écrite**, cite-la et demande ce qui est vrai aujourd'hui. Tu ne tranches pas à la place de l'utilisateur.
   - **Un secret** (mot de passe, jeton, clé) ne se répète pas et n'ira dans aucune fiche : dis-le.
   - **Un autre sujet surgit** : garde-le pour l'étape 7 et reste sur le thème, sauf si l'utilisateur veut en changer.
   - **La fin du thème.** Quand l'utilisateur le dit, ou quand deux relances de suite n'apportent rien de neuf, pose une question à choix : « Passer au bilan », « Creuser encore ».

4. **Ce qui mérite une fiche.** Relis l'échange et filtre.
   - **À garder** : une préférence durable, une décision et sa raison, une leçon qui vaut ailleurs, un fait d'environnement stable. Pour un projet, tout ce qui aide à le reprendre : contexte, décisions, état, pièges.
   - **À laisser** : le récit, les exemples dont on n'a rien tiré, l'humeur du moment, ce qui est déjà écrit, et tout ce que tu as déduit sans que l'utilisateur l'ait dit.
   - **Zéro fiche est un résultat valable.** Dis-le simplement, et passe à l'étape 7.
   - **Compléter avant de créer.** Si une fiche couvre le sujet, propose de la compléter ou de la corriger. Un sujet par fiche.
   - **Dans les mots de l'utilisateur**, au plus près, en suivant les règles d'écriture d'`AGENTS.md`. Une date relative devient une date en clair, jamais devinée.
   - **Le rangement** suit la table de routage d'`AGENTS.md`. Sans table, il suit les dossiers de `general/` (`profil/`, `projets/`, `references/`, `apprentissages/`), et la conclusion propose le skill reindex. Un dossier nommé par la table mais pas encore présent est créé par sa première fiche. Si rien ne convient, suggère un endroit sans créer de dossier : la fiche va dans le dossier existant le plus proche ou n'est pas écrite, au choix de l'utilisateur.
   - Pour chaque fiche, prépare : l'action (créer, compléter, corriger), le chemin, le `type`, le texte exact, et pour une fiche existante l'ancien passage et le nouveau.

5. **Valider, fiche par fiche.** Une question à choix par fiche, par séries de quatre au plus.
   - Chaque question se comprend seule : l'action, le chemin et le texte retenu, mot pour mot (l'ancien et le nouveau pour une correction).
   - Options : « Écrire (Recommandé) », « Reformuler », « Ne pas écrire ». Aucune option ne valide tout d'un geste.
   - « Reformuler », ou une réponse libre : corrige le texte et repose la question pour cette fiche seule.
   - Sans outil de questions à choix : toutes les fiches du thème dans un seul message, numérotées, avec leurs options a, b, c, et une dernière ligne qui dit comment répondre, du type « 1a 2c 3a ». Une réponse incomplète ne vaut que pour les fiches citées : redemande les autres, sans rien supposer.
   - Rien n'est écrit avant la réponse.

6. **Écrire.** Seulement ce qui a été validé, tel qu'il a été validé, dans le clone.
   - **Fiche neuve** : nom en kebab-case, un `name` qu'aucune fiche du dossier ne porte, et l'en-tête du format d'`AGENTS.md` :
     ```
     ---
     name: nom-de-la-fiche
     description: "une ligne, qui sert à décider si la fiche est utile"
     metadata:
       type: user | feedback | project | reference
       status: actif
       tags: [mot-cle]
     ---
     ```
     Reprends un tag existant avant d'en créer un. N'ajoute ni `node_type`, ni `originSessionId`, ni `modified` : Claude Code les tient.
   - **Fiche existante** : modifie le seul passage validé et garde tout le reste, en-tête compris. Son `status` ne change que si la proposition validée le disait.
   - **Index** : ajoute ou mets à jour sa ligne dans le `MEMORY.md` du dossier, dans la bonne section : `- [Titre](dossier/fichier.md) : accroche` pour la mémoire générale, `- [Titre](fichier.md) : accroche` pour un projet.
   - **Contrôle** : relance la commande de l'étape 1. Aucun écart ne doit rester sur les fichiers que tu viens d'écrire : corrige-les toi-même. Les écarts d'avant ne sont pas le sujet de ce skill.

7. **Continuer ?** Une question à choix : le prochain thème (un sujet qui a surgi pendant l'échange d'abord, sinon le manque suivant), « Un sujet à moi », « S'arrêter là ». Un nouveau thème reprend à l'étape 2 ou 3, sans refaire l'étape 1.

8. **Conclusion.** Trois lignes au plus : les fiches écrites (leurs chemins), ce qui a été écarté ou reste sans emplacement, et le rappel que rien n'est commité ni poussé. Si l'entretien a décidé une action qui n'est pas encore faite (un fichier à créer, un réglage à changer), nomme-la et pose une question à choix : « La faire maintenant », « Plus tard ». Rien ne se lance sans ce oui, et une action faite passe avant le push, pour partir avec les fiches. Propose ensuite le skill push, sans le lancer. Si l'entretien a porté sur un projet qui n'est pas celui de la session, donne la commande avec son nom, `/memoire:push <nom>` : sans ce nom, ses fiches ne partiraient pas.

## Sur claude.ai

Le bac à sable a un shell, git et l'accès GitHub de l'app de Claude : les mêmes commandes fonctionnent, sur le clone du bac à sable (`~/claude-memory`), qui vit le temps de la conversation. Les étapes sont celles de « Dans Claude Code », avec trois différences :

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai). Préfixe ensuite chaque commande : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimiser.sh --check <portée>`. Le premier appel clone le dépôt.
2. **La question est tout ce que l'utilisateur voit.** Chaque question à choix contient ce qu'il faut pour décider, le texte de la fiche compris.
3. **Rien ne dure sans push.** Les fiches écrites restent dans le bac à sable. À la conclusion, pose une question à choix, « Pousser maintenant », « Ne pas pousser », en disant que sans push elles seront perdues à la fin de la conversation. Enchaîne avec le skill push seulement si la réponse est oui.
