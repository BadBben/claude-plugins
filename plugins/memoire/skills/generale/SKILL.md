---
name: generale
description: "Consulte ou enrichit la mémoire générale de l'utilisateur, hors projet (dossier general/ du dépôt mémoire) : son profil et ses préférences, l'index de ses projets, ses références (machines, comptes, outils, URLs) et ses apprentissages transverses. À utiliser pour une question sur l'utilisateur lui-même, sur un autre projet que le projet courant, sur son environnement, ou quand un nom de projet est inconnu. Lit l'index puis seulement le fichier utile. Ne jamais l'invoquer sans demande explicite."
argument-hint: "[sujet]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh *), Read, Write, Edit
---

# Mémoire générale

Sujet demandé : $ARGUMENTS

Où es-tu ? Si ton prompt système a une section « Memory » avec un dossier de mémoire auto, tu es dans Claude Code. Sinon, tu es sur claude.ai : mêmes étapes, avec `CLAUDE_MEMOIRE_REPO=<url>` devant chaque commande (voir « Sur claude.ai » en bas).

La mémoire générale a une copie de travail locale (`~/.claude/memoire/general/`, chemin exact affiché par le script) synchronisée avec `general/` du dépôt mémoire. Elle n'est jamais chargée en entier : l'index d'abord, puis le seul fichier pertinent.

## Consulter

1. Mets la copie locale à jour : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh pull`.
   Code 10 : aucun dépôt configuré, enchaîne avec le skill setup puis reviens ici. Si le script signale des `CONFLIT`, résous-les comme dans le skill pull avant de continuer.
2. Lis `MEMORY.md` dans la copie locale.
3. Choisis la ou les lignes qui répondent au sujet, et lis seulement ces fichiers. Si rien ne correspond, dis-le plutôt que d'inventer.
4. Réponds, en citant le fichier source.

## Enrichir

Seulement si l'utilisateur demande d'ajouter, noter ou mettre à jour quelque chose dans la mémoire générale.

1. Mets la copie locale à jour (étape 1 ci-dessus), pour partir de la version la plus récente.
2. Choisis le dossier : `profil/`, `projets/` (une fiche par projet, nommée comme le dossier dans `projets/` du dépôt), `references/` ou `apprentissages/`.
3. Crée ou modifie le fichier dans la copie locale, nom en kebab-case, avec l'en-tête natif de la mémoire auto (la description entre guillemets si elle contient `: `) :
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
5. Simulation : `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh push --dry-run`. Code 4 : le dépôt a avancé, refais un pull puis recommence. Code 5 : secret détecté, corrige. Code 6 : marqueurs de conflit à résoudre. « Rien a pousser » : une phrase, et arrête-toi. Avertissement « perte possible » : reporte-le dans la question, et n'ajoute `--accept-loss` au commit que si l'utilisateur a confirmé en l'ayant vu.
6. Le script affiche le bloc « Message de commit » (titre, ligne « (recap a rediger par la session) », liste des fichiers). Rédige le récap, deux ou trois phrases sur ce qui change dans le contenu, ton naturel, sans tiret long, sans guillemets doubles, sans `$` ni accent grave. Pose une seule question avec AskUserQuestion dont le texte contient le message de commit complet (titre, récap, liste des fichiers) suivi de « Pousser ce commit ? », options « Pousser », « Annuler » ; sur claude.ai, la question est la seule chose que l'utilisateur voit, donc rien d'autre avant. S'il confirme :
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh push --commit --message "<récap>"`
   Conclusion en une ligne : le hash du commit et le nombre de fichiers.

## Sur claude.ai

Le bac à sable a un shell, git et l'accès GitHub de l'app de Claude : les mêmes commandes fonctionnent, la copie locale vit dans le bac à sable le temps de la conversation. Si `CLAUDE_MEMOIRE_REPO` n'a pas été fixé dans cette conversation, passe par le skill setup (section claude.ai), puis préfixe chaque commande : `CLAUDE_MEMOIRE_REPO=<url> CLAUDE_MEMOIRE_HOST=claude.ai bash ${CLAUDE_PLUGIN_ROOT}/scripts/generale.sh ...`.
