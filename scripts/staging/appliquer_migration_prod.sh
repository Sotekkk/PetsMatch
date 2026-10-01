#!/usr/bin/env bash
# Applique UNE migration en PROD (à lancer soi-même, après l'avoir testée sur
# le staging), puis lance les vérifications RLS (transactions annulées).
# Usage (depuis la racine du dépôt, Git Bash) :
#   bash scripts/staging/appliquer_migration_prod.sh supabase/migration_xxx.sql
set -euo pipefail

FICHIER="${1:?Usage : bash scripts/staging/appliquer_migration_prod.sh supabase/migration_xxx.sql}"
[ -f "$FICHIER" ] || { echo "Fichier introuvable : $FICHIER"; exit 1; }

PSQL="/c/Program Files/PostgreSQL/17/bin/psql.exe"
PROD=$(grep '^PROD_DB_URL=' "$USERPROFILE/petsmatch-db.env" | cut -d= -f2-)
export PGCLIENTENCODING=UTF8

echo "── Application en PROD : $FICHIER"
"$PSQL" "$PROD" -q -v ON_ERROR_STOP=1 -f "$FICHIER" 2>&1 | grep -v NOTICE || true
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "ÉCHEC : rien n'a été modifié pour la partie en erreur (transaction annulée)."
  exit 1
fi
echo "── OK. Vérifications RLS :"
"$PSQL" "$PROD" -f scripts/staging/test_rls_prod.sql 2>&1 | grep -v '^$'
