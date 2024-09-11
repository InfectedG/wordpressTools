# Web3Factory

## Scripts de Sauvegarde et Restauration WordPress

Ce dépôt contient des scripts pour sauvegarder et restaurer Web3Factory, y compris les fichiers du site et la base de données. Les scripts prennent en charge deux environnements : production et préproduction.

### Contenu

- `wp_backup.sh` : Script de sauvegarde
- `wp_restore.sh` : Script de restauration
- `prod.env` : Configuration pour l'environnement de production
- `preprod.env` : Configuration pour l'environnement de préproduction

### Prérequis

- Accès shell au serveur hébergeant WordPress
- Permissions suffisantes pour lire/écrire dans les répertoires du site et exécuter des commandes MySQL
- `tar` et `mysqldump` installés sur le serveur

### Configuration

1. Copiez les fichiers de configuration et modifiez-les selon vos besoins :

```bash
cp prod.env.example prod.env
cp preprod.env.example preprod.env
```

2. Éditez `config_prod.env` et `config_preprod.env` pour y mettre vos paramètres spécifiques.

3. Assurez-vous que les scripts sont exécutables :

```bash
chmod +x wp_backup.sh wp_restore.sh
```

## Utilisation

### Sauvegarde

Pour sauvegarder le site :

```bash
./wp_backup.sh prod
```

Pour sauvegarder le site en préproduction :

```bash
./wp_backup.sh [prod|preprod]
```

Cela créera une archive du site et un dump de la base de données dans le répertoire de sauvegarde spécifié dans le fichier de configuration.

### Restauration

Pour restaurer le site :

```bash
./wp_restore.sh [prod|preprod] chemin/vers/sauvegarde_site.tar.gz chemin/vers/sauvegarde_db.sql
```

Cela restaurera les fichiers du site et la base de données à partir des fichiers de sauvegarde spécifiés.

## Sécurité

- Gardez les fichiers de configuration (`prod.env` et `preprod.env`) sécurisés car ils contiennent des informations sensibles.
- Limitez l'accès aux scripts de sauvegarde et de restauration aux utilisateurs autorisés uniquement.
- Stockez les sauvegardes dans un endroit sûr, idéalement hors du serveur web.

## Avertissement

Testez toujours ces scripts dans un environnement de développement avant de les utiliser en production. Assurez-vous d'avoir des sauvegardes fonctionnelles avant d'effectuer une restauration.