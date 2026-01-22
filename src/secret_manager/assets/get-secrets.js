const { execSync } = require('child_process');
const fs = require('fs');

module.exports.getSecrets = async ({ resolveConfigurationProperty }) => {
  // Read the script path from the environment variable (defined in .zshrc)
  const scriptPath = process.env.SECRETS_MANAGER_PATH;

  if (!scriptPath) {
    throw new Error("SECRETS_MANAGER_PATH environment variable not found. Please check your .zshrc and run 'source ~/.zshrc'");
  }

  // Try to get a custom entry name from serverless.yml, otherwise fallback to 'app'
  const company = (await resolveConfigurationProperty(['custom', 'keepass_entry'])) || (await resolveConfigurationProperty(['app']));
  if (!company) {
    throw new Error("Property 'app' or 'custom.keepass_entry' not found in serverless.yml. Needed for KeePassXC lookup.");
  }

  // Get the prod configuration to use as a template for local
  const prodConfig = await resolveConfigurationProperty(['custom', 'prod']);
  if (!prodConfig) {
    throw new Error("Property 'custom.prod' not found in serverless.yml. Needed as a template for local.");
  }

  const cachePath = '/tmp/serverless-keepass-cache.json';
  const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

  let secrets = null;

  // Try to load from cache
  if (fs.existsSync(cachePath)) {
      try {
          const cacheData = JSON.parse(fs.readFileSync(cachePath, 'utf-8'));
          if (cacheData[company] && cacheData[company].timestamp && (Date.now() - cacheData[company].timestamp < CACHE_TTL_MS)) {
              secrets = cacheData[company].data;
              console.log(`⚡ Loaded secrets for '${company}' from cache.`);
          }
      } catch (e) {
          // ignore cache read errors
      }
  }

  if (!secrets) {
      console.log(`\n🔒 Fetching secrets for '${company}' from KeePassXC...`);

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
        if (fs.existsSync(cachePath)) {
            try {
                cacheData = JSON.parse(fs.readFileSync(cachePath, 'utf-8'));
            } catch (e) { /* ignore corrupt cache */ }
        }
        cacheData[company] = {
            timestamp: Date.now(),
            data: secrets
        };
        fs.writeFileSync(cachePath, JSON.stringify(cacheData, null, 2));

      } catch (error) {
        throw new Error(`Failed to fetch secrets from KeePassXC: ${error.message}`);
      }
  }

  // Create the local config by merging prod template with KeePassXC secrets
  // This ensures custom.local has all keys from custom.prod
  const localConfig = { ...prodConfig };

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

  return localConfig;
};
