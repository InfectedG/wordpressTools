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

# Fonction pour mettre à jour wp-config.php
update_wp_config() {
    local CONFIG_FILE="$SITE_DIR/wp-config.php"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Fichier wp-config.php non trouvé."
        return 1
    fi

    # Échapper les caractères spéciaux dans le mot de passe
    local ESCAPED_DB_PASS=$(printf '%s\n' "$DB_PASS" | sed -e 's/[\/&]/\\&/g')

    sed -i "s/define( *'DB_NAME', *'[^']*' *);/define( 'DB_NAME', '$DB_NAME' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_USER', *'[^']*' *);/define( 'DB_USER', '$DB_USER' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_PASSWORD', *'[^']*' *);/define( 'DB_PASSWORD', '$ESCAPED_DB_PASS' );/" "$CONFIG_FILE"
    sed -i "s/define( *'DB_HOST', *'[^']*' *);/define( 'DB_HOST', '$DB_HOST' );/" "$CONFIG_FILE"

    echo "Fichier wp-config.php mis à jour avec les nouvelles informations de base de données."

    # Vérification
    if grep -q "define( 'DB_PASSWORD', '$ESCAPED_DB_PASS' );" "$CONFIG_FILE"; then
        echo "Mot de passe correctement mis à jour dans wp-config.php"
    else
        echo "ERREUR : Le mot de passe n'a pas été correctement mis à jour dans wp-config.php"
        return 1
    fi
}

# Fonction pour mettre à jour la base de données
update_db() {
    local OLD_URL="$1"
    local NEW_URL="$2"

    echo "Mise à jour de la base de données..."
    echo "Ancien URL : $OLD_URL"
    echo "Nouvel URL : $NEW_URL"

    # Mise à jour des tables principales
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
    -- Mise à jour des options
    UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$NEW_URL');
    
    -- Mise à jour des posts
    UPDATE wp_posts SET post_content = REPLACE(post_content, '$OLD_URL', '$NEW_URL');
    UPDATE wp_posts SET guid = REPLACE(guid, '$OLD_URL', '$NEW_URL');
    UPDATE wp_posts SET post_excerpt = REPLACE(post_excerpt, '$OLD_URL', '$NEW_URL');
    
    -- Mise à jour des métadonnées
    UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');
    
    -- Mise à jour des commentaires
    UPDATE wp_comments SET comment_content = REPLACE(comment_content, '$OLD_URL', '$NEW_URL');
    UPDATE wp_comments SET comment_author_url = REPLACE(comment_author_url, '$OLD_URL', '$NEW_URL');
    
    -- Mise à jour des liens
    UPDATE wp_links SET link_url = REPLACE(link_url, '$OLD_URL', '$NEW_URL');
    UPDATE wp_links SET link_image = REPLACE(link_image, '$OLD_URL', '$NEW_URL');
    
    -- Mise à jour des termes
    UPDATE wp_termmeta SET meta_value = REPLACE(meta_value, '$OLD_URL', '$NEW_URL');
EOF

    if [ $? -ne 0 ]; then
        echo "Erreur lors de l'exécution des requêtes SQL."
        return 1
    fi

    # Mise à jour des données sérialisées
    php -r "
    function replace_urls(\$old_url, \$new_url, \$data) {
        if (is_string(\$data)) {
            return str_replace(\$old_url, \$new_url, \$data);
        }
        if (is_array(\$data) || is_object(\$data)) {
            foreach (\$data as \$key => \$value) {
                if (is_array(\$data)) {
                    \$data[\$key] = replace_urls(\$old_url, \$new_url, \$value);
                } elseif (is_object(\$data)) {
                    \$data->\$key = replace_urls(\$old_url, \$new_url, \$value);
                }
            }
        }
        return \$data;
    }

    \$mysqli = new mysqli('$DB_HOST', '$DB_USER', '$DB_PASS', '$DB_NAME');
    if (\$mysqli->connect_error) {
        die('Connect Error (' . \$mysqli->connect_errno . ') ' . \$mysqli->connect_error);
    }

    // Mise à jour des options sérialisées
    \$result = \$mysqli->query(\"SELECT option_id, option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%'\");
    while (\$row = \$result->fetch_assoc()) {
        \$value = \$row['option_value'];
        \$unserialized = @unserialize(\$value);
        if (\$unserialized !== false) {
            \$updated = serialize(replace_urls('$OLD_URL', '$NEW_URL', \$unserialized));
            \$stmt = \$mysqli->prepare(\"UPDATE wp_options SET option_value = ? WHERE option_id = ?\");
            \$stmt->bind_param('si', \$updated, \$row['option_id']);
            \$stmt->execute();
            echo \"Updated serialized data in option: {\$row['option_name']}\\n\";
        }
    }

    // Mise à jour des métadonnées sérialisées
    \$result = \$mysqli->query(\"SELECT meta_id, meta_key, meta_value FROM wp_postmeta WHERE meta_value LIKE '%$OLD_URL%'\");
    while (\$row = \$result->fetch_assoc()) {
        \$value = \$row['meta_value'];
        \$unserialized = @unserialize(\$value);
        if (\$unserialized !== false) {
            \$updated = serialize(replace_urls('$OLD_URL', '$NEW_URL', \$unserialized));
            \$stmt = \$mysqli->prepare(\"UPDATE wp_postmeta SET meta_value = ? WHERE meta_id = ?\");
            \$stmt->bind_param('si', \$updated, \$row['meta_id']);
            \$stmt->execute();
            echo \"Updated serialized data in postmeta: {\$row['meta_key']}\\n\";
        }
    }

    \$mysqli->close();
    "

    echo "Mise à jour de la base de données terminée."

    # Vérification finale
    echo "Vérification finale des URLs dans la base de données..."
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    SELECT option_name, option_value FROM wp_options WHERE option_value LIKE '%$OLD_URL%' LIMIT 5;
    SELECT ID, post_title, guid FROM wp_posts WHERE guid LIKE '%$OLD_URL%' OR post_content LIKE '%$OLD_URL%' LIMIT 5;
    SELECT post_id, meta_key, meta_value FROM wp_postmeta WHERE meta_value LIKE '%$OLD_URL%' LIMIT 5;
    SELECT comment_ID, comment_author_url FROM wp_comments WHERE comment_author_url LIKE '%$OLD_URL%' LIMIT 5;
    "
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

    echo "Début de la restauration de $FROM_ENV vers $TO_ENV..."

    # Nettoyage du répertoire cible
    rm -rf "$SITE_DIR"/*

    # Extraction de l'archive du site
    echo "Extraction de l'archive du site vers $SITE_DIR"
    tar -xzvf "$BACKUP_SITE" -C "$SITE_DIR" --strip-components=1

    if [ $? -ne 0 ]; then
        echo "Erreur lors de l'extraction de l'archive"
        exit 1
    fi

    # Restauration de la base de données
    echo "Restauration de la base de données"
    /usr/bin/mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_DB"

    # Mise à jour de wp-config.php pour tous les environnements
    echo "Mise à jour de wp-config.php..."
    update_wp_config

    # Mise à jour de la base de données si nécessaire
    if [ "$FROM_ENV" != "$TO_ENV" ]; then
        local FROM_URL="${FROM_ENV^^}_URL"
        local TO_URL="${TO_ENV^^}_URL"
        update_db "${!FROM_URL}" "${!TO_URL}"
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