#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd "$SCRIPT_DIR" || { echo "Failed to change to script directory. Aborting."; exit 1; }

echo "Starting deployment..."
echo "Current working directory: $(pwd)"

# --- Article Generation Logic ---
echo "Generating new article..."
if ! bash ./generate_article.sh; then
    echo "Article generation failed. Aborting deployment."
    exit 1

else
    echo "Article generated successfully."
    # --- Deployment Logic ---
    echo "Building Hugo site and deploying with Nginx..."
    docker compose up --build -d

    echo "Deployment complete!"
fi


