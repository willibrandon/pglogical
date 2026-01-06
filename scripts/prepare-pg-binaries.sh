#!/bin/bash
# Script to download and repackage PostgreSQL binaries for CI
# Run this locally, then upload the resulting ZIPs to GitHub release "pg-binaries"

set -e

declare -A versions=(
    ["13"]="13.20-1"
    ["14"]="14.17-1"
    ["15"]="15.12-1"
    ["16"]="16.8-1"
    ["17"]="17.4-1"
    ["18"]="18.0-1"
)

OUTPUT_DIR="./pg-binaries"
TEMP_DIR="${TMPDIR:-/tmp}"

mkdir -p "$OUTPUT_DIR"

for pg_major in "${!versions[@]}"; do
    pg_version="${versions[$pg_major]}"
    edb_url="https://get.enterprisedb.com/postgresql/postgresql-${pg_version}-windows-x64-binaries.zip"
    download_path="${TEMP_DIR}/postgresql-${pg_major}-edb.zip"
    extract_path="${TEMP_DIR}/pg-extract-${pg_major}"
    output_zip="${OUTPUT_DIR}/postgresql-${pg_major}-windows-x64.zip"

    echo -e "\033[36mProcessing PostgreSQL ${pg_major}...\033[0m"

    # Download from EDB
    if [[ ! -f "$download_path" ]]; then
        echo "  Downloading from EDB..."
        curl -L -o "$download_path" "$edb_url"
    else
        echo "  Using cached download"
    fi

    # Extract
    echo "  Extracting..."
    rm -rf "$extract_path"
    unzip -q "$download_path" -d "$extract_path"

    # EDB ZIP extracts to pgsql/ folder - perfect, just rezip
    echo "  Creating $output_zip..."
    rm -f "$output_zip"
    (cd "$extract_path" && zip -rq "../$(basename "$output_zip")" pgsql)
    mv "${extract_path}/../$(basename "$output_zip")" "$output_zip"

    # Cleanup
    rm -rf "$extract_path"

    size=$(du -m "$output_zip" | cut -f1)
    echo -e "  \033[32mDone: $output_zip (${size} MB)\033[0m"
done

echo ""
echo -e "\033[32mAll binaries ready in $OUTPUT_DIR\033[0m"
echo ""
echo -e "\033[33mNext steps:\033[0m"
echo "1. Create GitHub release 'pg-binaries' at:"
echo "   https://github.com/willibrandon/pglogical/releases/new?tag=pg-binaries"
echo ""
echo "2. Upload all ZIP files from $OUTPUT_DIR"
echo ""
echo "3. Publish the release"
