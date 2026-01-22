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

case "$1" in
    setup)
        check_tools
        setup
        ;;
    add)
        check_tools
        add_company "$2" "$3"
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
        echo "Usage: $0 {setup|add|ls|get-json}"
        echo "Example: $0 add company-abc credentials.json/.asc/.gpg"
        echo "Example: $0 get-json company-name"
        exit 1
        ;;
esac
