# Secure Local Secrets Manager

This project provides a secure and local way to manage production credentials using **KeePassXC** and **GPG**, facilitating the secure injection of secrets into your Serverless projects.

## 🚀 Quick Start (Pip Install)

1.  **Install via Pip**:
    Run this command from within the package directory or install the wheel:
    ```bash
    pip install .
    ```

2.  **Initialize**:
    Run the initialization script to install system dependencies (KeePassXC, jq, GPG) and configure your shell:
    ```bash
    secret-manager-init
    ```
    *Note: This script may ask for your password to install system dependencies via brew/apt.*

3.  **Reload Shell**:
    ```bash
    source ~/.zshrc  # or ~/.bashrc
    ```

## 🛠 Quick Usage (ZSH Aliases)

I've configured aliases to make the workflow seamless:

### 1. Add Company Credentials (GPG Support)
If you receive a JSON file (encrypted or plain), import it into your personal vault:
```bash
# For GPG/ASC files (automatically decrypted)
secret-add company-name access.json.asc

# For plain JSON files
secret-add company-name access.json
```



### 2. List Stored Companies
```bash
secret-ls # Or ./manage-secrets.sh ls
```

## ⚡️ Serverless Direct Integration (Local Dev Only)

To avoid hardcoding secrets even in gitignored files, we use a JS helper that pulls secrets directly from KeePassXC into memory when running Serverless locally.

### How to set up a new Repository:

1. **Add the Helper**: Copy `get-secrets.js` to the root of your repository. This file is safe to commit as it contains no sensitive data.
2. **Update `serverless.yml`**: Configure the `custom` block to include a `local` environment.
    *   **template**: This defines which environment's configuration should be used as a base (e.g., `dev` or `prod`). The script will copy this config and override matching keys with secrets from the vault.
    *   **keepass_entry** (Optional): If your KeePassXC entry name differs from the `app` name in serverless.yml, specify it here.

```yaml
custom:
  # ... other env configs (dev, prod) ...
  local: ${file(./get-secrets.js):getSecrets}
```

### How it works:

1. **Dynamic Lookup**: When you run `sls offline --stage local`, Serverless calls `getSecrets`.
2. **Auto-Discovery**: The helper reads the `app` name from your `serverless.yml` and uses it to find the correct entry in KeePassXC.
3. **Smart Merge**: It takes your `custom.prod` configuration as a template and replaces only the keys found in your vault with real values.
4. **No Files**: Secrets are injected into memory. No flat JSON files are ever created on disk.

### 3. Update `package.json` (Recommended)
Add a script to easily run offline mode with the `local` stage. This ensures the secrets helper is triggered.

```json
"scripts": {
  "start": "sls offline start --stage local",
  "test:quotation": "sls invoke local -f GetQuotation -p events/event-quotation.json --stage local"
}
```

### 🧠 What is `get-secrets.js`?
It is a simple **middleware** that connects Serverless to your local KeePassXC vault.
*   **Safe**: It does not store secrets in files. It keeps them in memory only during the process execution.
*   **Smart**: It automatically matches keys from your vault to the keys in your `serverless.yml` configuration (case-insensitive).
*   **Cached**: It caches secrets in `/tmp/` for 1 hour to avoid asking for your password on every reload.

### Daily Usage:
```bash
npm start
# OR manually:
sls offline --stage local
```
*You will be prompted for your KeePassXC master password once in the terminal.*

## 🔒 Security Details

- **Local Vault**: Everything is stored in `~/.credentials_vault.kdbx`.
- **Environment Variable**: The script location is defined via `SECRETS_MANAGER_PATH` in your shell profile, allowing portability.
- **In-Memory**: Secrets are only kept in the process memory during execution.

---
*Keep it safe. Do not share your database password or the .kdbx file.*
