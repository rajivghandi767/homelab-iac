#!/bin/bash
set -e

create_catalog() {
    local user=$1
    local pass=$2
    local db=$3

    echo "  Creating User: $user and Database: $db"
    
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE USER "$user" WITH PASSWORD '$pass';
        CREATE DATABASE "$db";
        GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$user";
        -- Grant Schema ownership (Critical for Django migrations)
        ALTER DATABASE "$db" OWNER TO "$user";
EOSQL
}

# --- PRODUCTION DATABASES ---

# 1. Create Portfolio PROD Catalog
if [ -n "$PORTFOLIO_PROD_DB_USER" ]; then
    create_catalog "$PORTFOLIO_PROD_DB_USER" "$PORTFOLIO_PROD_DB_PASSWORD" "$PORTFOLIO_PROD_DB_NAME"
fi

# 2. Create Trivia PROD Catalog
if [ -n "$TRIVIA_PROD_DB_USER" ]; then
    create_catalog "$TRIVIA_PROD_DB_USER" "$TRIVIA_PROD_DB_PASSWORD" "$TRIVIA_PROD_DB_NAME"
fi

# 3. Create Prop & Ferry PROD Catalog
if [ -n "$PROP_FERRY_PROD_DB_USER" ]; then
    create_catalog "$PROP_FERRY_PROD_DB_USER" "$PROP_FERRY_PROD_DB_PASSWORD" "$PROP_FERRY_PROD_DB_NAME"
fi

# 4. Create Silicon Valley PROD Catalog
if [ -n "$SVT_PROD_DB_USER" ]; then
    create_catalog "$SVT_PROD_DB_USER" "$SVT_PROD_DB_PASSWORD" "$SVT_PROD_DB_NAME"
fi