#!/bin/bash
set -e

echo "📥 Mise à jour des images..."
docker compose pull

echo "🛑 Arrêt des conteneurs..."
docker compose down

echo "🚀 Redémarrage en arrière-plan..."
docker compose up -d

echo "✅ Mise à jour terminée !"
