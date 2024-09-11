#!/bin/bash

# Fichier: wp_restore.sh

# Fonction pour charger la configuration
load_config() {
    if [ "$1" == "prod" ]; then
        source ./prod.env
    elif [ "$1" == "preprod" ]; then
        source ./preprod.env
    else
        echo "Environnement non reconnu. Utilisez 'prod' ou 'preprod'."
        exit 1
    fi
}

# Fonction de restauration
restore() {
    local BACKUP_SITE="$1"
    local BACKUP_DB="$2"
    
    if [ ! -f "$BACKUP_SITE" ] || [ ! -f "$BACKUP_DB" ]; then
        echo "Les fichiers de sauvegarde spécifiés n'existent pas."
        exit 1
    }
    
    echo "Début de la restauration pour $ENV..."
    
    # Restauration du site
    rm -rf "$SITE_DIR"/*
    tar -xzvf "$BACKUP_SITE" -C "$(dirname "$SITE_DIR")"
    
    # Restauration de la base de données
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_DB"
    
    echo "Restauration terminée."
}

# Vérification des arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <prod|preprod> <chemin_backup_site> <chemin_backup_db>"
    exit 1
fi

# Chargement de la configuration et exécution de la restauration
load_config "$1"
restore "$2" "$3"

exit 0