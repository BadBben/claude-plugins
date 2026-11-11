---
name: pull
description: "Met à jour la mémoire partagée de cet appareil depuis le dépôt mémoire : récupère ce que les autres appareils ont poussé, le fusionne avec le travail local et aide à résoudre les conflits un par un, en expliquant ce que dit chaque version. À utiliser quand l'utilisateur demande de charger, récupérer, importer ou reprendre la mémoire d'un projet, ou de se synchroniser avec un autre appareil. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[nom-du-projet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh *), Read, Write, Edit
---

# Mettre à jour la mémoire depuis le dépôt partagé

Arguments reçus : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code : suis « Dans Claude Code ». Sinon, tu es sur claude.ai : suis « Sur claude.ai ».

Le dépôt mémoire est cloné une fois sur l'appareil (par défaut dans `~/claude-memory`) et ce clone est la mémoire : les projets branchés dessus y lisent et y écrivent directement. C'est git qui transporte et qui fusionne ; le script ajoute les contrôles et le résumé. Tu n'exécutes jamais git toi-même.

**Portée.** La fusion met à jour tout le clone, git ne sait pas faire autrement. Ce que la portée limite, c'est le travail local que le pull enregistre avant de fusionner : celui du projet de la session et de la partie transverse (la mémoire générale et les fichiers de la racine). Le travail en cours des autres projets n'est ni commité ni modifié. Les options de portée, à répéter à l'identique sur chaque appel de `pull.sh` (simulation, puis exécution) :
- `--memory-dir "<dossier>"` : le dossier de mémoire auto de cette session, chemin exact de la section « Memory » de ton prompt système, jamais deviné. C'est l'option par défaut.
- `--project "<nom>"` à la place, quand l'utilisateur nomme un projet.
- `--all` seulement si l'utilisateur demande explicitement tous les projets.

## Dans Claude Code

1. **Simulation.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --dry-run --memory-dir "<dossier de mémoire auto>"`
   Code 10 : aucun dépôt configuré. Enchaîne avec le skill setup (il demande l'URL et clone le dépôt), puis reviens ici.
   Code 11 : le clone appartient à un autre dépôt que celui qui est configuré, montre le message et arrête-toi.
   Code 8 : la fusion écraserait du travail non commité d'un autre projet. Va à l'étape 3.
   Code 6 : une fusion est déjà en cours, un pull précédent s'est arrêté sur des conflits. Passe directement à l'étape 6.
   Code 2 : git a échoué (réseau, authentification, dossier qui gêne), montre l'erreur et arrête-toi.
   Si le script écrit que le dossier de mémoire est hors du clone, ce dossier de travail n'est pas encore branché : dis-le et propose le skill setup (étape « Brancher un projet »), qui pose le réglage et regarde ce que l'ancienne mémoire locale a de plus. En attendant, la mémoire d'un projet se lit directement dans le clone, `MEMORY.md` d'abord, puis seulement les fiches utiles.
2. **Résumé.** Le script annonce la portée, puis range chaque fichier par partie du dépôt (un projet, `general`, ou `racine`) : `nouveau` et `depot` arrivent du dépôt, `supprime au depot` va disparaître, `les deux` a changé des deux côtés (git fusionne seul si les zones ne se chevauchent pas, sinon c'est un conflit), `local` n'a changé que sur cet appareil et attend un push, `reste en local` est le travail en cours d'un autre projet, que ce pull laisse tel quel. Explique en trois lignes ce qui arrive, ce qui sera fusionné et ce qui attend un push, en commençant par le projet de la session. Si le script dit « Rien a recuperer », dis-le, signale ce qui attend un push, et arrête-toi.
3. **Autre projet en travers (code 8).** Des fichiers d'un autre projet ont du travail local non commité et ont aussi changé au dépôt : la fusion les écraserait, et les commiter d'office ferait partir ce projet au prochain push. Rien n'a été commité ni fusionné. Explique-le en nommant le projet (ligne « Projets concernes ») et ses fichiers, puis pose une seule question avec AskUserQuestion : « Inclure <projet> dans la fusion » (son travail local sera commité en local, fusionné avec le dépôt, et partira au prochain push), « Annuler » (faire d'abord le pull depuis une session de ce projet). S'il inclut, reprends à l'étape 1 en ajoutant `--include "<projet>"` aux mêmes options, une fois par projet nommé.
4. **Confirmation.** Pose une seule question avec AskUserQuestion : « Récupérer et fusionner » (recommandé), « Annuler ». Si du travail local de la portée n'est pas encore commité (des lignes `local` ou `les deux`), précise dans la question qu'il sera d'abord enregistré dans un commit local, pour que rien ne se perde.
5. **Exécution.** La même commande sans `--dry-run`.
   Code 5 : un motif de secret dans le travail local. Rien n'a été commité ni fusionné. Montre les fichiers, corrige avec l'utilisateur, relance. N'ajoute `--force` que s'il te dit que c'est un faux positif.
6. **Conflits.** Si le script affiche `== CONFLITS a resoudre ==`, la fusion est en pause et attend que chaque fichier listé soit réglé. C'est là que tu es utile : ne choisis pas une version à la place de l'utilisateur, explique et propose. Dis-lui dès le premier conflit qu'il peut tout annuler (voir la fin de cette étape). Pour chaque fichier, dans l'ordre :
   - **Lire.** Ouvre le fichier dans le clone. Chaque conflit est un bloc en trois parties : de `<<<<<<< HEAD` à `|||||||`, la version de cet appareil ; de `|||||||` à `=======`, l'ancêtre commun, c'est-à-dire le texte d'avant les deux modifications ; de `=======` à `>>>>>>> origin/...`, la version du dépôt, poussée depuis un autre appareil.
   - **Expliquer.** Pour chaque bloc, dis en clair ce que chaque côté a changé par rapport à l'ancêtre, et ce que ça veut dire dans les faits : une information ajoutée, corrigée, retirée ou déplacée, et laquelle se perdrait si on gardait l'autre côté. Parle du contenu, pas des numéros de ligne.
   - **Proposer.** Si les deux côtés ajoutent ou précisent des choses différentes, propose un texte fusionné qui garde les deux informations, rédigé proprement, pas les deux versions mises bout à bout. Si les deux côtés se contredisent (deux valeurs pour un même fait, « fait » d'un côté et « à faire » de l'autre), ne mélange pas : présente le choix avec ta recommandation et sa raison (la plus récente d'après les dates écrites dans les fiches, la plus précise, celle qui concorde avec le reste de la mémoire), et dis ce que tu ne peux pas savoir. Dans un index `MEMORY.md`, la bonne fusion garde en général les lignes des deux côtés, une par fiche qui existe encore.
   - **Faire valider.** Une question AskUserQuestion par fichier, dont le texte résume ce que dit chaque version et donne le texte que tu proposes ; options : ta proposition en premier, « Garder la version de cet appareil », « Garder la version du dépôt ». Quand les blocs d'un même fichier appellent des choix différents, traite-les bloc par bloc. Ne tranche jamais seul une contradiction.
   - **Écrire.** Écris le fichier résolu sans aucun marqueur (`<<<<<<<`, `|||||||`, `=======`, `>>>>>>>`), puis relis-le en entier : en-tête YAML intact, aucune ligne en double.
   - **Conflit de suppression** (« supprime ici, modifie au depot » ou « modifie ici, supprime au depot ») : un côté a supprimé la fiche, l'autre l'a modifiée. Avant de proposer, regarde si son contenu a seulement été déplacé (une consolidation l'a fusionné dans une autre fiche ou versé au journal) : la suppression est alors voulue. Propose « garder » ou « supprimer » avec la raison. Garder : ne rien faire, le fichier présent dans le clone est conservé. Supprimer : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --drop "<chemin>"`.
   - **Conclure.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --conclude`. Il n'enregistre que les fichiers qui étaient en conflit, avec le reste de la fusion : le travail en cours des autres projets n'y entre pas. Code 6 : il reste des marqueurs, le script dit dans quels fichiers. Code 5 : un secret dans un fichier résolu, à corriger.

   Pour renoncer à tout moment : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --abort` remet le clone dans l'état d'avant la fusion. Le travail local est gardé et le dépôt n'a pas été touché.
7. **Conclusion.** Dis en une ou deux lignes ce qui a changé, et ce qui reste en local dans d'autres projets si le script le signale. Les fichiers sont à jour sur le disque, mais l'index `MEMORY.md` d'un projet n'est relu par Claude Code qu'au démarrage d'une session : propose de le lire tout de suite si l'utilisateur veut s'en servir dans cette conversation. Si le script dit que des commits locaux attendent un push (le travail local commité avant la fusion, ou la fusion elle-même), propose le skill push.

## Sur claude.ai

Pas de mémoire auto : le clone vit dans le bac à sable (`~/claude-memory`) le temps de la conversation, et la mémoire sert en contexte. La portée se donne par `--project "<nom>"`.

1. **Dépôt.** Si `CLAUDE_MEMOIRE_REPO` n'a pas encore été fixé dans cette conversation, passe par le skill setup (section claude.ai) : il trouve le dépôt, le fait confirmer et l'attache à la session.
2. **Pull.** `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh --project "<nom>"`
   Au premier appel de la conversation, le script clone le dépôt : pas de simulation nécessaire, tout est neuf. Ensuite il met le clone à jour ; si tu as écrit dans le clone entre-temps, les étapes 2 à 6 de « Dans Claude Code » s'appliquent telles quelles. Code 2 : accès refusé, voir le skill setup.
3. **Lire.** `MEMORY.md` dans `~/claude-memory/projets/<projet>/memory/` (les noms des projets : `setup.sh --list`), puis seulement les fiches utiles au sujet de la conversation. Garde-les en contexte et dis en une ligne ce que tu as chargé. Rien n'est écrit dans le dépôt.
