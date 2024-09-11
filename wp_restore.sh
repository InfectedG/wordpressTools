#!/bin/bash

# Fichier: wp_restore.sh

# Fonction pour charger la configuration
load_config() {
    if [ "$1" == "prod" ]; then
        source ./.prod.env
    elif [ "$1" == "preprod" ]; then
        source ./.preprod.env
    elif [ "$1" == "dev" ]; then
        source ./.dev.env
    else
        echo "Environnement non reconnu. Utilisez 'prod' ou 'preprod' ou 'dev'."
        exit 1
    fi
}

# Nouvelle fonction pour mettre à jour wp-config.php
update_wp_config() {
    local CONFIG_FILE="$SITE_DIR/wp-config.php"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Fichier wp-config.php non trouvé."
        return 1
    }
    
    sed -i "s/define( *'DB_NAME', *'[^']*' *);/define( 'DB_NAME', '$DB_NAME' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_USER', *'[^']*' *);/define( 'DB_USER', '$DB_USER' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_PASSWORD', *'[^']*' *);/define( 'DB_PASSWORD', '$DB_PASS' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_HOST', *'[^']*' *);/define( 'DB_HOST', '$DB_HOST' );/" "$CONFIG_FILE"
    
    echo "Fichier wp-config.php mis à jour avec les nouvelles informations de base de données."
}

# Fonction pour mettre à jour la base de données
update_db() {
    local OLD_URL="$1"
    local NEW_URL="$2"
    
    # Mise à jour des URLs dans la base de données
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
UPDATE wp_options SET option_value = replace(option_value, '$OLD_URL', '$NEW_URL') WHERE option_name = 'home' OR option_name = 'siteurl';
UPDATE wp_posts SET guid = replace(guid, '$OLD_URL', '$NEW_URL');
UPDATE wp_posts SET post_content = replace(post_content, '$OLD_URL', '$NEW_URL');
UPDATE wp_postmeta SET meta_value = replace(meta_value, '$OLD_URL', '$NEW_URL');
EOF

    echo "Base de données mise à jour avec la nouvelle URL."
}

# Fonction de restauration
restore() {
    local BACKUP_SITE="$1"
    local BACKUP_DB="$2"
    local FROM_ENV="$3"
    local TO_ENV="$4"
    
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
    
    # Si on déploie vers dev, mettre à jour wp-config.php
    if [ "$TO_ENV" == "dev" ]; then
        echo "Déploiement vers l'environnement de développement détecté. Mise à jour de wp-config.php..."
        update_wp_config
    fi
    
    # Si on déploie de prod vers preprod ou dev, mettre à jour la base de données
    if [ "$FROM_ENV" == "prod" ] && ([ "$TO_ENV" == "preprod" ] || [ "$TO_ENV" == "dev" ]); then
        echo "Déploiement de prod vers preprod/dev détecté. Mise à jour de la base de données..."
        update_db "$PROD_URL" "$PREPROD_URL"
    fi
    
    echo "Restauration terminée."
}

# Vérification des arguments
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <from_env> <to_env> <chemin_backup_site> <chemin_backup_db>"
    exit 1
fi

# Chargement de la configuration et exécution de la restauration
load_config "$2"  # Charger la config de l'environnement cible
restore "$3" "$4" "$1" "$2"

exit 0