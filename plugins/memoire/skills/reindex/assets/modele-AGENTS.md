# AGENTS.md : table de routage de la mémoire

Ce dépôt est la mémoire de {{utilisateur}}. {{Deux ou trois phrases, dans ses mots : à quoi sert cette mémoire et ce qu'elle contient.}} Tout y est en fiches Markdown, lisibles par n'importe quel assistant.

Ce fichier dit où trouver et où ranger. Le contenu est dans les fiches : rien n'est recopié ici.

## Comment t'en servir

1. Repère dans la table le dossier qui répond à la demande.
2. Lis d'abord l'index de ce dossier, `MEMORY.md` : une ligne par fiche.
3. Ouvre seulement les fiches utiles. Ne charge jamais un dossier entier.
4. Si rien ne correspond, dis-le plutôt que d'inventer.

Dans une session ouverte sur un projet, la mémoire de ce projet est déjà là, par son `MEMORY.md`. Cette table sert pour le reste : la mémoire générale et les autres projets.

## Table de routage

<!-- reindex:debut -->

| Dossier | Ce qu'il contient | Le lire quand | Y écrire |
|---|---|---|---|
| `general/profil/` | Qui est {{utilisateur}} : rôle, préférences, façon de travailler | Avant de proposer une façon de faire ou de régler le niveau d'explication | Une préférence durable, un retour sur la façon de travailler |
| `general/projets/` | Une fiche par projet : objectif, état en une ligne, où il vit | Un projet est nommé et ce n'est pas celui de la session | L'état résumé d'un projet quand il change de phase |
| `general/references/` | Machines, comptes, outils, adresses utiles | Besoin d'un fait d'environnement | Un fait d'environnement stable, jamais un secret |
| `general/apprentissages/` | Ce qui marche ou pas, valable d'un projet à l'autre | Avant de refaire un choix déjà rencontré | Une leçon réutilisable hors du projet où elle est née |
| `projets/<nom>/memory/` | La mémoire d'un projet : ses fiches et leur index | Toute demande sur ce projet, en commençant par son `MEMORY.md` | Tout ce qui est propre à ce projet |
| `projets/<nom>/` | À côté de `memory/`, ce qui n'est pas une fiche : journal, instantanés, documents | Sur demande, ou quand une fiche y renvoie | Rien sans demande : ce ne sont pas des fiches |

<!-- reindex:fin -->

`<nom>` vaut pour chaque projet. La liste des projets : les dossiers de `projets/`. Leur état : l'index de `general/`.

## Règles

<!-- Cette section appartient à {{utilisateur}}. Ni le skill reindex ni son script ne la réécrivent. -->
<!-- À retirer une fois les règles validées : celles qui suivent sont des propositions, à garder, reformuler ou retirer une par une. -->

- **Une seule mémoire.** Tout vit dans ce dépôt. Pas de copie ailleurs, pas de second dépôt.
- **Mémoire générale : ce qui vaut d'un projet à l'autre.** Une préférence, une leçon, un fait d'environnement. Un document entier reste où il est : la fiche garde ce qu'on en retient et le lien.
- **Mémoire d'un projet : ce qui aide à le reprendre.** Contexte, décisions et leur raison, état, pièges.
- **Jamais de secret.** Aucun mot de passe, jeton ou clé, nulle part.
- **La structure ne bouge pas.** Ne crée, ne renomme et ne déplace aucun dossier. Si un nouveau dossier paraît utile, propose-le.
- **L'index suit les fiches.** Toute fiche ajoutée, renommée ou retirée met à jour sa ligne dans le `MEMORY.md` de son dossier.
- **Seules les fiches vont dans `memory/`.** Un journal, un instantané ou un document se range à côté, dans `projets/<nom>/`. Le journal d'un projet est `projets/<nom>/journal.md` : il n'a pas de ligne dans `MEMORY.md`, et une fiche y renvoie par son chemin.
- **Dis-le quand ça contredit.** Si une demande ou un résultat contredit une décision ou un objectif écrit ici, dis-le clairement en citant la fiche, au lieu d'acquiescer. Si {{utilisateur}} maintient son choix, applique-le.
- **Écriture.** {{Langue, format des dates, habitudes de rédaction.}}

## Format d'une fiche

Un sujet par fiche, nom en kebab-case, en-tête YAML. Tout ce qui n'est pas `name` ou `description` va sous `metadata` :

```
---
name: nom-de-la-fiche
description: "une ligne, qui sert à décider si la fiche est utile"
metadata:
  type: user | feedback | project | reference
  status: actif | a-verifier | perime
  tags: [mot-cle, autre-mot-cle]
---
```

- `status` : `actif` par défaut. `a-verifier` pour un doute ou une information ancienne. `perime` pour ce qui est remplacé et attend d'être retiré ou versé au journal. Les trois valeurs s'écrivent ainsi, sans accent ni espace.
- `tags` : quelques mots-clés en kebab-case, sans accent, pour retrouver une fiche d'un dossier à l'autre. Reprends un tag existant avant d'en créer un.
- D'autres propriétés peuvent s'ajouter sous `metadata` quand elles servent (une priorité, une échéance, un interlocuteur).
- La date de mise à jour est `modified`, tenue par Claude Code : n'en ajoute pas d'autre. Garde les propriétés déjà présentes, y compris `node_type`, `originSessionId` et `modified`.
- Les liens entre fiches s'écrivent `[[nom-de-la-fiche]]` dans le texte.
- La ligne d'index d'une fiche : `- [Titre](fichier.md) : accroche`, dans le `MEMORY.md` de son dossier.

## Synchronisation

Ce dépôt est cloné sur chaque appareil. Rien ne se récupère ni ne se pousse sans demande explicite : dans Claude, par les skills `pull` et `push` du plugin `memoire`. Jamais en forçant : si le dépôt a avancé entre-temps, on fusionne d'abord.
