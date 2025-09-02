#!/bin/bash

# Script de sauvegarde automatique des workflows N8N
# Sauvegarde quotidienne avec rotation sur 5 jours

# Configuration
BACKUP_DIR="/home/ubuntu/rag-n8n/backup"
N8N_URL="https://n8n.marcolopes.fr"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_DIR/backup.log"

# Chargement des variables d'environnement
if [ -f "/home/ubuntu/rag-n8n/.env" ]; then
    source /home/ubuntu/rag-n8n/.env
    N8N_EMAIL="$N8N_BACKUP_EMAIL"
    N8N_PASSWORD="$N8N_BACKUP_PASSWORD"
else
    log "ERREUR: Fichier .env introuvable"
    exit 1
fi

# Vérification des variables obligatoires
if [ -z "$N8N_EMAIL" ] || [ -z "$N8N_PASSWORD" ]; then
    log "ERREUR: Variables N8N_BACKUP_EMAIL ou N8N_BACKUP_PASSWORD manquantes dans .env"
    exit 1
fi

# Créer le répertoire de sauvegarde s'il n'existe pas
mkdir -p "$BACKUP_DIR"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction de nettoyage des anciennes sauvegardes (garde 5 jours)
cleanup_old_backups() {
    log "Nettoyage des anciennes sauvegardes..."
    find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz" -type f -mtime +4 -delete
    find "$BACKUP_DIR" -name "workflows_*.tar.gz" -type f -mtime +4 -delete
    find "$BACKUP_DIR" -name "backup_*" -type d -mtime +4 -exec rm -rf {} +
    find "$BACKUP_DIR" -name "workflows_*" -type d -mtime +4 -exec rm -rf {} +
    log "Nettoyage terminé"
}

# Fonction d'authentification et récupération du cookie
authenticate() {
    log "Authentification sur N8N..."
    
    # Récupération du cookie de session
    RESPONSE=$(curl -s -c /tmp/n8n_cookies -X POST \
        "$N8N_URL/rest/login" \
        -H "Content-Type: application/json" \
        -d "{\"emailOrLdapLoginId\":\"$N8N_EMAIL\",\"password\":\"$N8N_PASSWORD\"}")
    
    # Vérification de la réponse
    if echo "$RESPONSE" | jq -e '.data' > /dev/null 2>&1; then
        # Extraction du cookie depuis le fichier
        COOKIE=$(grep 'n8n-auth' /tmp/n8n_cookies | awk '{print $7}')
        if [ -n "$COOKIE" ]; then
            log "Authentification réussie"
            return 0
        fi
    fi
    
    log "ERREUR: Échec de l'authentification - $RESPONSE"
    return 1
}

# Fonction de sauvegarde des credentials
backup_credentials() {
    local backup_subdir="$1"
    
    log "Début de la sauvegarde des credentials..."
    
    # Récupération de la liste des credentials
    CREDENTIALS=$(curl -s -b /tmp/n8n_cookies -X GET \
        "$N8N_URL/rest/credentials" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ] || [ -z "$CREDENTIALS" ]; then
        log "ERREUR: Impossible de récupérer la liste des credentials"
        return 1
    fi
    
    # Création du sous-répertoire credentials
    mkdir -p "$backup_subdir/credentials"
    
    # Sauvegarde de la liste des credentials (métadonnées uniquement)
    echo "$CREDENTIALS" | jq '.' > "$backup_subdir/credentials/credentials_list.json"
    
    # Extraction et sauvegarde de chaque credential
    local credential_count=0
    echo "$CREDENTIALS" | jq -r '.data[]? | @base64' | while read -r credential_b64; do
        if [ -n "$credential_b64" ]; then
            credential=$(echo "$credential_b64" | base64 -d)
            credential_id=$(echo "$credential" | jq -r '.id')
            credential_name=$(echo "$credential" | jq -r '.name' | sed 's/[^a-zA-Z0-9_-]/_/g')
            credential_type=$(echo "$credential" | jq -r '.type')
            
            if [ "$credential_id" != "null" ] && [ "$credential_name" != "null" ]; then
                # Sauvegarde des métadonnées du credential (sans les données sensibles)
                echo "$credential" | jq '.' > "$backup_subdir/credentials/${credential_name}_${credential_id}.json"
                log "Credential sauvegardé: $credential_name (Type: $credential_type, ID: $credential_id)"
                credential_count=$((credential_count + 1))
            fi
        fi
    done
    
    log "Total credentials sauvegardés: $credential_count"
    return 0
}

# Fonction de sauvegarde des workflows
backup_workflows() {
    local backup_subdir="$BACKUP_DIR/backup_$DATE"
    mkdir -p "$backup_subdir"
    
    log "Début de la sauvegarde des workflows..."
    
    # Récupération de la liste des workflows
    WORKFLOWS=$(curl -s -b /tmp/n8n_cookies -X GET \
        "$N8N_URL/rest/workflows" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ] || [ -z "$WORKFLOWS" ]; then
        log "ERREUR: Impossible de récupérer la liste des workflows"
        return 1
    fi
    
    # Création du sous-répertoire workflows
    mkdir -p "$backup_subdir/workflows"
    
    # Extraction et sauvegarde de chaque workflow
    local workflow_count=0
    echo "$WORKFLOWS" | jq -r '.data[] | @base64' | while read -r workflow_b64; do
        workflow=$(echo "$workflow_b64" | base64 -d)
        workflow_id=$(echo "$workflow" | jq -r '.id')
        workflow_name=$(echo "$workflow" | jq -r '.name' | sed 's/[^a-zA-Z0-9_-]/_/g')
        
        if [ "$workflow_id" != "null" ] && [ "$workflow_name" != "null" ]; then
            # Récupération du workflow complet
            FULL_WORKFLOW=$(curl -s -b /tmp/n8n_cookies -X GET \
                "$N8N_URL/rest/workflows/$workflow_id" \
                -H "Content-Type: application/json")
            
            if [ $? -eq 0 ] && [ -n "$FULL_WORKFLOW" ]; then
                echo "$FULL_WORKFLOW" | jq '.' > "$backup_subdir/workflows/${workflow_name}_${workflow_id}.json"
                log "Workflow sauvegardé: $workflow_name (ID: $workflow_id)"
                workflow_count=$((workflow_count + 1))
            else
                log "ERREUR: Échec de la sauvegarde du workflow $workflow_name"
            fi
        fi
    done
    
    log "Total workflows sauvegardés: $workflow_count"
    
    # Sauvegarde des credentials
    backup_credentials "$backup_subdir"
    
    # Création d'une archive compressée
    cd "$BACKUP_DIR"
    tar -czf "n8n_backup_$DATE.tar.gz" "backup_$DATE/"
    
    if [ $? -eq 0 ]; then
        log "Archive complète créée: n8n_backup_$DATE.tar.gz"
        # Suppression du répertoire temporaire
        rm -rf "backup_$DATE/"
    else
        log "ERREUR: Échec de la création de l'archive"
        return 1
    fi
    
    return 0
}

# Fonction principale
main() {
    log "=== DÉBUT DE LA SAUVEGARDE ==="
    
    # Vérification des dépendances
    if ! command -v curl &> /dev/null; then
        log "ERREUR: curl n'est pas installé"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log "ERREUR: jq n'est pas installé"
        exit 1
    fi
    
    # Nettoyage des anciennes sauvegardes
    cleanup_old_backups
    
    # Authentification
    if ! authenticate; then
        log "ERREUR: Échec de l'authentification"
        exit 1
    fi
    
    # Sauvegarde des workflows
    if backup_workflows; then
        log "=== SAUVEGARDE TERMINÉE AVEC SUCCÈS ==="
    else
        log "=== SAUVEGARDE ÉCHOUÉE ==="
        exit 1
    fi
}

# Exécution du script principal
main "$@"
