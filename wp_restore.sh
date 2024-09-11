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
    fi

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

    echo "Mise à jour de la base de données..."
    echo "Ancien URL : $OLD_URL"
    echo "Nouvel URL : $NEW_URL"

    # Mise à jour spécifique pour home et siteurl
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
UPDATE wp_options SET option_value = '$NEW_URL' WHERE option_name IN ('home', 'siteurl');
UPDATE wp_options SET option_value = replace(option_value, '$OLD_URL', '$NEW_URL') WHERE option_value LIKE '%$OLD_URL%';
UPDATE wp_posts SET guid = replace(guid, '$OLD_URL', '$NEW_URL');
UPDATE wp_posts SET post_content = replace(post_content, '$OLD_URL', '$NEW_URL');
UPDATE wp_postmeta SET meta_value = replace(meta_value, '$OLD_URL', '$NEW_URL') WHERE meta_value LIKE '%$OLD_URL%';
UPDATE wp_links SET link_url = replace(link_url, '$OLD_URL', '$NEW_URL');
UPDATE wp_links SET link_image = replace(link_image, '$OLD_URL', '$NEW_URL');
EOF

    if [ $? -eq 0 ]; then
        echo "Requêtes SQL exécutées avec succès."
    else
        echo "Erreur lors de l'exécution des requêtes SQL."
        return 1
    fi

    # Vérification des mises à jour
    local HOME_URL=$(/usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT option_value FROM wp_options WHERE option_name = 'home';")
    local SITE_URL=$(/usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT option_value FROM wp_options WHERE option_name = 'siteurl';")

    echo "URL 'home' actuel : $HOME_URL"
    echo "URL 'siteurl' actuel : $SITE_URL"

    if [ "$HOME_URL" = "$NEW_URL" ] && [ "$SITE_URL" = "$NEW_URL" ]; then
        echo "Les URLs principales ont été correctement mises à jour."
    else
        echo "Attention : Les URLs principales n'ont pas été mises à jour correctement."
        echo "Vérification supplémentaire des options 'home' et 'siteurl'..."
        /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('home', 'siteurl');"
    fi

    # Mise à jour des données sérialisées
    php -r "
function update_serialized_data(\$old_url, \$new_url, \$db_host, \$db_user, \$db_pass, \$db_name) {
    \$mysqli = new mysqli(\$db_host, \$db_user, \$db_pass, \$db_name);
    if (\$mysqli->connect_error) {
        die('Connect Error (' . \$mysqli->connect_errno . ') ' . \$mysqli->connect_error);
    }
    \$result = \$mysqli->query(\"SELECT option_id, option_name, option_value FROM wp_options WHERE option_value LIKE '%{\$old_url}%'\");
    while (\$row = \$result->fetch_assoc()) {
        \$value = \$row['option_value'];
        if (@unserialize(\$value) !== false) {
            \$unserialized = unserialize(\$value);
            \$updated = str_replace(\$old_url, \$new_url, serialize(\$unserialized));
            \$stmt = \$mysqli->prepare(\"UPDATE wp_options SET option_value = ? WHERE option_id = ?\");
            \$stmt->bind_param('si', \$updated, \$row['option_id']);
            \$stmt->execute();
            echo \"Updated serialized data in option: {\$row['option_name']}\\n\";
        }
    }
    \$mysqli->close();
}
update_serialized_data('$OLD_URL', '$NEW_URL', '$DB_HOST', '$DB_USER', '$DB_PASS', '$DB_NAME');
"

    echo "Mise à jour des données sérialisées terminée."

    # Vérification finale
    echo "Vérification finale des URLs dans la base de données..."
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%' LIMIT 5;"
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
    fi

    echo "Début de la restauration pour $TO_ENV..."

    # Nettoyage du répertoire cible
    rm -rf "$SITE_DIR"/*

    # Extraction de l'archive du site
    echo "Extraction de l'archive du site vers $SITE_DIR"
    tar -xzvf "$BACKUP_SITE" -C "$SITE_DIR" --strip-components=1
    #supprimer le premier niveau de répértoire  >
    # /srv/web3factory.net_preprod/web3factory.net/wp-content/...
    # /srv/web3factory.net_preprod/web3factory.net/wp-includes/...
    # /srv/web3factory.net_preprod/web3factory.net/index.php
    #...

    if [ $? -ne 0 ]; then
        echo "Erreur lors de l'extraction de l'archive"
        exit 1
    fi

    # Restauration de la base de données
    echo "Restauration de la base de données"
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <"$BACKUP_DB"

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
load_config "$2" # Charger la config de l'environnement cible
restore "$3" "$4" "$1" "$2"

exit 0
