#!/bin/bash

# Fichier: wp_backup.sh

# Fonction pour charger la configuration
load_config() {
    if [ "$1" == "prod" ]; then
        source ./.prod.env
    elif [ "$1" == "preprod" ]; then
        source ./.preprod.env
    else
        echo "Environnement non reconnu. Utilisez 'prod' ou 'preprod'."
        exit 1
    fi
}

# Fonction de sauvegarde
backup() {
    local DATE=$(date +"%Y%m%d_%H%M%S")
    local BACKUP_NAME="${SITE_NAME}_${ENV}_${DATE}"
    
    echo "Début de la sauvegarde pour $ENV..."
    
    # Sauvegarde du site en excluant node_modules
    tar --exclude='*/node_modules' -czvf "${BACKUP_DIR}/${BACKUP_NAME}_site.tar.gz" -C "$(dirname "$SITE_DIR")" "$(basename "$SITE_DIR")"
    
    # Sauvegarde de la base de données
    /usr/bin/mariadb-dump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "${BACKUP_DIR}/${BACKUP_NAME}_db.sql"
    
    echo "Sauvegarde terminée. Fichiers sauvegardés dans ${BACKUP_DIR}/${BACKUP_NAME}_site.tar.gz et ${BACKUP_DIR}/${BACKUP_NAME}_db.sql"
}

# Vérification des arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <prod|preprod>"
    exit 1
fi

# Chargement de la configuration et exécution de la sauvegarde
load_config "$1"
backup

exit 0