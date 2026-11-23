# claude-plugins

Plugins Claude de BadBben, distribués comme une marketplace : un dossier par plugin sous `plugins/`, déclaré dans `.claude-plugin/marketplace.json`.

| Plugin | Rôle | Doc |
| --- | --- | --- |
| `memoire` | Mémoire partagée entre appareils via un dépôt git : mise en place guidée, pull, push, mémoire générale, entretien pour l'enrichir, table de routage et index, optimisation, retour en arrière | [plugins/memoire/README.md](plugins/memoire/README.md) |

## Installer

Sur claude.ai ou dans l'app Claude : Customize > Plugins > Add > Add marketplace, puis `BadBben/claude-plugins`. Ajouter ensuite le plugin voulu. Il est attaché au compte : il arrive dans Claude Code au démarrage de session suivant (plugin « synced ») et dans le chat.

Dans Claude Code seulement, sans passer par le compte : `claude plugin marketplace add BadBben/claude-plugins` puis `claude plugin install memoire@badbben`.

Pour le plugin `memoire`, il vous faut aussi un dépôt git privé pour vos données : créez-le depuis le modèle [claude-memory-template](https://github.com/BadBben/claude-memory-template), puis suivez le README du plugin.

## Versions

Ce dépôt ne reçoit que des versions publiées. Chaque version arrive par une pull request `release/<plugin>-v<version>`, avec les notes du `CHANGELOG.md` du plugin en description. Rien n'est développé directement ici.

## Comment une mise à jour se propage

Observé le 31 octobre 2026 avec la 0.4.1 du plugin memoire, et le 23 novembre 2026 avec la 0.11.0 pour le menu de l'app.

1. **Dans l'app desktop** (Paramètres > Plugins) : lancer la recherche de mises à jour, puis cliquer sur « Mettre à jour ». Aucune commande à lancer. Sans ce geste, « Synchroniser automatiquement » finit par relire la marketplace, avec un délai qui n'a pas été mesuré.
2. **L'app garde sa propre copie du plugin.** `claude plugin list` lit celle de la ligne de commande et peut donc afficher une version plus ancienne : pour savoir ce qu'a l'app, regarder son menu des plugins.
3. **Claude Code en ligne de commande** télécharge la nouvelle version au démarrage d'un processus, pas à `/reload-plugins`. Un démarrage headless suffit pour forcer, et la liste des plugins confirme la version arrivée. En Git Bash :
   ```
   claude -p n --model haiku && claude plugin list
   ```
   Dans PowerShell (pas de `&&`, et `claude.cmd` si l'installation est npm) :
   ```
   claude.cmd -p n --model haiku; claude.cmd plugin list
   ```
   La nouvelle copie arrive à côté de l'ancienne dans `~/.claude/plugins/synced/<compte>/` ; l'ancienne reste tant qu'une session l'utilise, puis est nettoyée.
4. **Une session déjà ouverte** garde sa version : `/reload-plugins` ou nouvelle session. Dans l'app desktop, ouvrir une nouvelle session suffit, sans redémarrer l'app.
5. **Une session cloud** (claude.ai/code) démarre toujours à neuf : elle a la dernière version.
