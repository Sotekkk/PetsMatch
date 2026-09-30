#!/usr/bin/env bash
# Applique en PROD les migrations RLS / stockage du 30/09/2026, dans l'ordre,
# puis lance les vérifications (transactions annulées).
# Mode d'emploi complet : scripts/staging/MISE_EN_PROD_RLS.md
# Pré-requis : instantané de retour arrière généré juste avant
#   (scripts/staging/snapshot_policies.sql).
# Usage (depuis la racine du dépôt) : bash scripts/staging/appliquer_rls_prod.sh
set -u
cd "$(dirname "$0")/../.."

ENV_FILE="${USERPROFILE:-$HOME}/petsmatch-db.env"
PROD=$(grep '^PROD_DB_URL=' "$ENV_FILE" | cut -d= -f2-)
PSQL="/c/Program Files/PostgreSQL/17/bin/psql.exe"
[ -x "$PSQL" ] || PSQL=psql
export PGCLIENTENCODING=UTF8

MIGRATIONS="
migration_storage_policies_phase2a
migration_rls_messagerie
migration_rls_user_profiles
migration_rls_agenda_rdv_notifs_registre
migration_rls_documents_factures
migration_rls_partages_liens
migration_rls_donnees_privees
"

for m in $MIGRATIONS; do
  "$PSQL" "$PROD" -q -v ON_ERROR_STOP=1 -f "supabase/$m.sql" 2>&1 | grep -v NOTICE
  rc=${PIPESTATUS[0]}
  echo "$m : $([ "$rc" = 0 ] && echo OK || echo "ÉCHEC (exit $rc)")"
  if [ "$rc" != 0 ]; then
    echo "Arrêt : les migrations suivantes ne sont pas appliquées."
    exit 1
  fi
done

echo
echo "== Vérifications en prod (annulées, aucune trace)"
"$PSQL" "$PROD" -f scripts/staging/test_rls_prod.sql 2>&1 | grep -v '^$'
