#!/bin/bash

# Configuration
DB_FILE="$HOME/.credentials_vault.kdbx"

# Ensure tools are installed
check_tools() {
    if ! command -v keepassxc-cli &> /dev/null; then
        echo "Error: 'keepassxc-cli' is not installed. Please install KeePassXC."
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is not installed. Run 'brew install jq'."
        exit 1
    fi
}

# Setup: Create KeePassXC DB if it doesn't exist
setup() {
    if [ ! -f "$DB_FILE" ]; then
        echo "Creating new KeePassXC database at $DB_FILE..."
        # -p forces the password prompt
        keepassxc-cli db-create -p "$DB_FILE"
    else
        echo "KeePassXC database already exists at $DB_FILE"
    fi
}

# Add or Update a company entry
add_company() {
    local company=$1
    local input_file=$2

    if [ -z "$company" ] || [ -z "$input_file" ]; then
        echo "Usage: $0 add <company_name> <input_file>"
        exit 1
    fi

    if [ ! -f "$input_file" ]; then
        echo "Error: File $input_file not found."
        exit 1
    fi

    # Read/Decrypt content
    local json_content
    if [[ "$input_file" == *.asc ]] || [[ "$input_file" == *.gpg ]]; then
        json_content=$(gpg --quiet --decrypt "$input_file" 2>/dev/null)
        if [ -z "$json_content" ]; then
            echo "Error: GPG decryption failed."
            exit 1
        fi
    else
        json_content=$(cat "$input_file")
    fi

    # Auto-wrap in {} if not already present
    # Trim leading/trailing whitespace
    json_content=$(echo "$json_content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ "$json_content" != \{* ]]; then
        echo "Fragment detected. Wrapping in {}..."
        json_content="{$json_content}"
    fi

    # Validate JSON
    if ! echo "$json_content" | jq . >/dev/null 2>&1; then
        echo "Error: The content of $input_file is not a valid JSON. Only JSON data can be stored."
        exit 1
    fi

    echo "Storing credentials for '$company' in KeePassXC (Password required)..."
    # Try to add. If it fails, try to edit (handling the "already exists" case)
    if ! keepassxc-cli add --username "developer" --url "local" --notes "$json_content" "$DB_FILE" "/$company" &>/dev/null; then
        echo "Entry exists. Updating..."
        keepassxc-cli edit --notes "$json_content" "$DB_FILE" "/$company" > /dev/null
    fi
    echo "Done."
}

# Apply configuration to a Serverless project
apply_config() {
    local sls_file=$1

    if [ -z "$sls_file" ]; then
        echo "Usage: $0 apply <path_to_serverless.yml>"
        exit 1
    fi

    if [ ! -f "$sls_file" ]; then
        echo "Error: File $sls_file not found."
        exit 1
    fi

    # Determine project directories
    local project_dir
    project_dir=$(dirname "$sls_file")
    local package_json="$project_dir/package.json"

    echo "Configuring project at $project_dir..."

    # 1. Copy get-secrets.js
    # We assume manage-secrets.sh is in the same directory as get-secrets.js originally,
    # or rely on the fact that this script is likely symlinked or run from its install location.
    # However, for robustness, we use the location of the currently running script.
    local script_dir
    script_dir=$(dirname "$0")
    # If script is run via symlink/PATH, $0 might be the path to the executable.
    # If we are strictly following the installer, the assets are together.

    # Fallback to SECRETS_MANAGER_PATH dir if $0 is not helpful (e.g. if sourced or aliased weirdly, though usually $0 works)
    if [ ! -f "$script_dir/get-secrets.js" ]; then
       # Try finding it based on the executed path in environment if available, or assume typical install structure
       if [ -n "$SECRETS_MANAGER_PATH" ]; then
            script_dir=$(dirname "$SECRETS_MANAGER_PATH")
       fi
    fi

    if [ -f "$script_dir/get-secrets.js" ]; then
        cp "$script_dir/get-secrets.js" "$project_dir/get-secrets.js"
        echo "✅ Copied get-secrets.js to $project_dir"
    else
        echo "❌ Error: get-secrets.js not found in $script_dir. Cannot copy."
        exit 1
    fi

    # 2. Modify serverless.yml
    # We look for 'custom:' and add the line if minimal intrusion is desired.
    # If 'custom:' doesn't exist, we append it.

    local config_line="  local: \${file(./get-secrets.js):getSecrets}"

    if grep -q "local: \${file(./get-secrets.js):getSecrets}" "$sls_file"; then
        echo "ℹ️  serverless.yml already contains the secret configuration."
    else
        if grep -q "^custom:" "$sls_file"; then
            # Add after custom:
            # We use sed to append after the line matching 'custom:'
            # For macOS/BSD sed, -i '' is required.
            sed -i '' "/^custom:/a\\
$config_line" "$sls_file"
            echo "✅ Added local config to custom section in serverless.yml"
        else
            # Append custom section
            echo "" >> "$sls_file"
            echo "custom:" >> "$sls_file"
            echo "$config_line" >> "$sls_file"
            echo "✅ Appended custom section to serverless.yml"
        fi
    fi

    # 3. Modify package.json scripts
    if [ -f "$package_json" ]; then
        # Check if scripts existing
        # We perform a logical update: Any script with 'sls' or 'serverless' gets '--stage local' appended
        # IF it doesn't already have it.
        # We'll use a temporary python one-liner or similar because complex JSON editing with sed is fragile.
        # Since jq is a dependency, let's use jq.

        tmp_json=$(mktemp)
        jq '
          .scripts |= with_entries(
            if (.value | test("sls|serverless")) and (.value | test("--stage local") | not) then
              .value += " --stage local"
            else
              .
            end
          )
        ' "$package_json" > "$tmp_json" && mv "$tmp_json" "$package_json"

        echo "✅ Updated package.json scripts to include --stage local"
    else
        echo "⚠️  package.json not found in $project_dir. Skipping script updates."
    fi

    echo "Done."
}

case "$1" in
    setup)
        check_tools
        setup
        ;;
    add)
        check_tools
        add_company "$2" "$3"
        ;;
    apply)
        check_tools
        # $2 is the path to serverless.yml
        apply_config "$2"
        ;;
    ls)
        check_tools
        keepassxc-cli ls "$DB_FILE" "/"
        ;;
    get-json)
        check_tools
        # Extract Notes and clean up
        raw=$(keepassxc-cli show -a Notes "$DB_FILE" "/$2" 2>/dev/null)
        clean=$(echo "$raw" | sed 's/^Notes: //')
        echo "$clean"
        ;;
    *)
        echo "Usage: $0 {setup|add|apply|ls|get-json}"
        echo "Example: $0 add company-abc credentials.json/.asc/.gpg"
        echo "Example: $0 apply /path/to/serverless.yml"
        echo "Example: $0 get-json company-name"
        exit 1
        ;;
esac
