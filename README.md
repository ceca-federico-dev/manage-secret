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

### 3. Apply Configuration to Project
```bash
secret-apply ./serverless.yml
```

## ⚡️ Serverless Direct Integration (Local Dev Only)

To avoid hardcoding secrets even in gitignored files, we use a JS helper that pulls secrets directly from KeePassXC into memory when running Serverless locally.

### Automated Setup with `secret-apply`:

Instead of manually copying files and editing configs, simply run:

```bash
secret-apply ./serverless.yml
```

This command will automatically:
1.  **Copy** the `get-secrets.js` helper to your project root.
2.  **Configure** `serverless.yml` injecting the `local: ${file(./get-secrets.js):getSecrets}` line.
3.  **Update** `package.json` scripts to append `--stage local` to any serverless command.

### Manual Setup (If preferred):

1. **Add the Helper**: Copy `get-secrets.js` to the root of your repository.
2. **Update `serverless.yml`**: Configure the `custom` block:
```yaml
custom:
  local: ${file(./get-secrets.js):getSecrets}
```
3. **Update `package.json`**: Add `--stage local` to your start scripts.

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
