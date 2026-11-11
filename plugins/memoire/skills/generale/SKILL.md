---
name: generale
description: "Consulte ou enrichit la mémoire générale de l'utilisateur, hors projet (dossier general/ du dépôt mémoire) : son profil et ses préférences, l'index de ses projets, ses références (machines, comptes, outils, URLs) et ses apprentissages transverses. À utiliser pour une question sur l'utilisateur lui-même, sur un autre projet que le projet courant, sur son environnement, ou quand un nom de projet est inconnu. Lit l'index puis seulement le fichier utile. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[sujet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh *), Read, Write, Edit
---

# Mémoire générale

Sujet demandé : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Sinon, tu es sur claude.ai : mêmes étapes, avec `CLAUDE_MEMOIRE_REPO=<url>` devant chaque commande (voir « Sur claude.ai » en bas).

La mémoire générale est le dossier `general/` du clone du dépôt mémoire (par défaut `~/claude-memory/general/`, chemin exact affiché par le script). Elle se lit sur place, même hors ligne, et suit le reste du dépôt : ce sont les skills pull et push qui la synchronisent. Elle n'est jamais chargée en entier : l'index d'abord, puis le seul fichier pertinent.

## Consulter

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh` affiche le dossier et l'index `MEMORY.md`.
   Code 10 : aucun dépôt configuré, enchaîne avec le skill setup puis reviens ici. Si le script signale que le dépôt a des commits que ce clone n'a pas encore, dis-le : la réponse vaut pour l'état du dernier pull, et le skill pull met tout à jour si la fraîcheur compte.
2. Choisis dans l'index la ou les lignes qui répondent au sujet, et lis seulement ces fichiers. Si rien ne correspond, dis-le plutôt que d'inventer.
3. Réponds, en citant le fichier source.

## Enrichir

Seulement si l'utilisateur demande d'ajouter, noter ou mettre à jour quelque chose dans la mémoire générale.

1. Pars de la version la plus récente : si l'étape 1 de « Consulter » a signalé un retard, fais d'abord le pull en suivant le skill pull.
2. Choisis le dossier : `profil/`, `projets/` (une fiche par projet, nommée comme le dossier dans `projets/` du dépôt), `references/` ou `apprentissages/`.
3. Crée ou modifie le fichier dans `general/` du clone, nom en kebab-case, avec l'en-tête natif de la mémoire auto (la description entre guillemets si elle contient `: `) :
   ```
   ---
   name: slug-du-fichier
   description: "une ligne"
   metadata:
     type: user | feedback | project | reference
   ---
   ```
   Jamais de secret : pas de mot de passe, de jeton, de clé.
4. Ajoute ou mets à jour la ligne correspondante dans `MEMORY.md`, dans la bonne section : `- [Titre](dossier/fichier.md) : accroche`.
5. Pousse en suivant le skill push à partir de sa simulation, sans option de portée : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/push.sh --dry-run`, le message de commit montré tel quel dans une seule question (« Pousser ? », options « Pousser », « Annuler »), puis `--commit --message "<récap>"`. Sans option de portée, seule la partie transverse part : la mémoire générale et les fichiers de la racine du dépôt. Le travail en cours des projets reste en local, le script le liste à part ; dis-le dans la question s'il y en a.

## Ancienne copie locale

Les versions 0.6.x gardaient une copie de la mémoire générale à part (`~/.claude/memoire/general/`). Elle n'est plus utilisée et n'est jamais supprimée par le plugin. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh --compare-old` liste ce qu'elle a de plus que le clone ou de différent, sans rien modifier. Pour chaque fichier listé, montre la différence et propose de le reprendre dans le clone ; l'utilisateur décide, puis un push.

## Sur claude.ai

Le bac à sable a un shell, git et l'accès GitHub de l'app de Claude : les mêmes commandes fonctionnent, le clone vit dans le bac à sable le temps de la conversation. Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai), puis préfixe chaque commande : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh`.
