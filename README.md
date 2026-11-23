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

1. **Dans l'app desktop** (Paramètres > Plugins) : lancer la recherche de mises à jour, puis cliquer sur « Mettre à jour ». Aucune commande à lancer.
2. **Ouvrir une nouvelle session.** Une session déjà ouverte garde sa version, sauf après `/reload-plugins`. Il n'y a pas besoin de redémarrer l'app.
3. **Claude Code en ligne de commande** garde sa propre copie du plugin, mise à jour à son prochain démarrage.
4. **Une session cloud** (claude.ai/code) démarre toujours à neuf : elle a la dernière version.
