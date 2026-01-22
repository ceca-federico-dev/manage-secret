const { execSync } = require('child_process');
const fs = require('fs');

module.exports.getSecrets = async ({ resolveConfigurationProperty }) => {
  // Read the script path from the environment variable (defined in .zshrc)
  const scriptPath = process.env.SECRETS_MANAGER_PATH;

  if (!scriptPath) {
    throw new Error("SECRETS_MANAGER_PATH environment variable not found. Please check your .zshrc and run 'source ~/.zshrc'");
  }

  // Read serverless.yml content manually to avoid circular dependencies during variable resolution
  // We use js-yaml (standard dependency of Serverless) for robust parsing
  const slsContent = fs.readFileSync('serverless.yml', 'utf8');
  let slsConfig;

  try {
      // Try to load js-yaml from the project's node_modules (Serverless depends on it)
      // Since this script runs in the serverless process, require('js-yaml') should work if hoisted or if we are lucky.
      // If not, we might need to rely on the user having it or being in the path.
      // Common path: node_modules/js-yaml or node_modules/serverless/node_modules/js-yaml
      try {
          slsConfig = require('js-yaml').load(slsContent);
      } catch (e) {
         // If generic require fails, try to find it relative to current working dir
         // This is a bit of a hail mary but cleaner than manual parsing if it works
         slsConfig = require(process.cwd() + '/node_modules/js-yaml').load(slsContent);
      }
  } catch (e) {
      // Fallback: If js-yaml is completely missing, we have to fail or revert to manual.
      // Given the user request, we must error out if we can't use the library.
      throw new Error("Could not load 'js-yaml' to parse serverless.yml. Please ensure it is installed in your project or available to Serverless: " + e.message);
  }

  // Extract 'app' name
  const company = slsConfig.app || slsConfig.custom?.keepass_entry;

  if (!company) {
    throw new Error("Property 'app' or 'custom.keepass_entry' not found in serverless.yml. Needed for KeePassXC lookup.");
  }

  // Extract 'custom.dev' block
  // Note: We access the raw object. Variables ${...} will NOT be resolved here, which is what we want!
  // We want the static template values.
  const devConfig = slsConfig.custom?.dev;

  if (!devConfig) {
    throw new Error("Property 'custom.dev' not found in serverless.yml. Needed as a template for local.");
  }

  const cachePath = '/tmp/serverless-keepass-cache.json.gpg';
  const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

  let secrets = null;

  // Helper to get GPG Recipient
  const getGpgRecipient = () => {
    try {
      const output = execSync('gpg --list-secret-keys --with-colons', { encoding: 'utf-8' });
      const fprLine = output.split('\n').find(line => line.startsWith('fpr:'));
      return fprLine ? fprLine.split(':')[9] : null;
    } catch (e) {
      return null;
    }
  };

  const gpgRecipient = getGpgRecipient();
  if (!gpgRecipient) {
      throw new Error("❌ GPG recipient not found. An encrypted cache is required for security. Please ensure you have a GPG secret key configured.");
  }

  // Try to load from cache
  if (fs.existsSync(cachePath)) {
      try {
          // Check file age (hard expiration)
          const stats = fs.statSync(cachePath);
          if (Date.now() - stats.mtimeMs > CACHE_TTL_MS) {
              fs.unlinkSync(cachePath);
              console.log("⏰ Cache expired and deleted.");
          } else if (gpgRecipient) {
              const decrypted = execSync(`gpg --quiet --decrypt "${cachePath}"`, {
                  stdio: ['inherit', 'pipe', 'inherit'],
                  encoding: 'utf-8'
              });
              const cacheData = JSON.parse(decrypted);
              if (cacheData[company] && cacheData[company].timestamp && (Date.now() - cacheData[company].timestamp < CACHE_TTL_MS)) {
                  secrets = cacheData[company].data;
                  console.log(`⚡ Loaded secrets for '${company}' from encrypted cache.`);
              }
          }
      } catch (e) {
          // ignore cache read errors
      }
  }

  if (!secrets) {
      console.log(`\n🔒 Fetching secrets for '${company}' from KeePassXC (Password required)...`);

      try {
        // This will trigger the KeePassXC password prompt in the terminal
        const output = execSync(`${scriptPath} get-json ${company}`, {
          stdio: ['inherit', 'pipe', 'inherit'],
          encoding: 'utf-8'
        });

        if (!output || output.trim() === "" || output.includes("Could not find")) {
            throw new Error(`Entry for company '${company}' not found or empty in KeePassXC.`);
        }

        secrets = JSON.parse(output);

        // Update cache
        let cacheData = {};
        if (fs.existsSync(cachePath) && gpgRecipient) {
            try {
                const decrypted = execSync(`gpg --quiet --decrypt "${cachePath}"`, {
                    stdio: ['inherit', 'pipe', 'inherit'],
                    encoding: 'utf-8'
                });
                cacheData = JSON.parse(decrypted);
            } catch (e) { /* ignore corrupt cache */ }
        }

        cacheData[company] = {
            timestamp: Date.now(),
            data: secrets
        };

        if (gpgRecipient) {
            execSync(`gpg --quiet --encrypt --recipient "${gpgRecipient}" --output "${cachePath}" --yes`, {
                input: JSON.stringify(cacheData),
                encoding: 'utf-8'
            });
        }

      } catch (error) {
        throw new Error(`Failed to fetch secrets from KeePassXC: ${error.message}`);
      }
  }

  // Create the local config by merging dev template with KeePassXC secrets
  // This ensures custom.local has all keys from custom.dev
  const localConfig = { ...devConfig };

  // Replace placeholders with real secrets (case-insensitive key matching)
  for (const secretKey in secrets) {
    const lowerSecretKey = secretKey.toLowerCase();
    for (const configKey in localConfig) {
      if (configKey.toLowerCase() === lowerSecretKey) {
        localConfig[configKey] = secrets[secretKey];
        break;
      }
    }
  }

  // --- Safety Guard ---
  // Force safe values for local stage to prevent accidental production emissions
  const safetyOverrides = {
    'production': false,
    'is_production': false,
    'emission_enabled': false,
    'is_test': true,
    'stage': 'local'
  };

  const appliedOverrides = [];
  for (const configKey in localConfig) {
    const lowerKey = configKey.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(safetyOverrides, lowerKey)) {
        if (localConfig[configKey] !== safetyOverrides[lowerKey]) {
            localConfig[configKey] = safetyOverrides[lowerKey];
            appliedOverrides.push(configKey);
        }
    }
  }

  if (appliedOverrides.length > 0) {
      console.log(`🛡️  Safety Guard: Forced safe values for [${appliedOverrides.join(', ')}]`);
  }

  return localConfig;
};
