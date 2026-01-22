import os
import sys
import shutil
import subprocess
import platform

GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
RESET = '\033[0m'

def log(msg, color=RESET):
    print(f"{color}{msg}{RESET}")

def install_dependencies():
    system = platform.system()
    log(f"Detected OS: {system}", GREEN)

    if system == "Darwin": # macOS
        if shutil.which("brew"):
            log("Installing dependencies via Homebrew...", YELLOW)
            subprocess.run(["brew", "install", "--cask", "keepassxc"], check=False)
            subprocess.run(["brew", "install", "jq", "gnupg"], check=True)
        else:
            log("Homebrew not found. Please install keepassxc, jq, and gnupg manually.", RED)
    elif system == "Linux":
        # Check for apt-get (Debian/Ubuntu)
        if shutil.which("apt-get"):
            log("Installing dependencies via apt-get (sudo required)...", YELLOW)
            subprocess.run(["sudo", "apt-get", "update"], check=True)
            subprocess.run(["sudo", "apt-get", "install", "-y", "keepassxc", "jq", "gnupg"], check=True)
        else:
            log("apt-get not found. Please install keepassxc, jq, and gnupg manually.", RED)
    elif system == "Windows":
        log("Windows detected. Please ensure Chocolatey is installed.", YELLOW)
        if shutil.which("choco"):
             subprocess.run(["choco", "install", "keepassxc", "jq", "gnupg", "-y"], check=True)
        else:
             log("Chocolatey not found. Please install keepassxc, jq, and gpg4win manually.", RED)
    else:
        log(f"Unsupported OS: {system}. Please manually install keepassxc, jq, and gnupg.", RED)

def setup_files():
    home = os.path.expanduser("~")
    target_dir = os.path.join(home, ".secret-manager")

    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
        log(f"Created directory: {target_dir}", GREEN)

    # Locate assets relative to this script
    current_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(current_dir, "assets")

    files_to_copy = ["manage-secrets.sh", "get-secrets.js"]

    for filename in files_to_copy:
        src = os.path.join(assets_dir, filename)
        dst = os.path.join(target_dir, filename)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            os.chmod(dst, 0o755) # Make executable
            log(f"Copied {filename} to {target_dir}", GREEN)
        else:
            log(f"Warning: Asset {filename} not found in {assets_dir}", RED)

    return target_dir

def configure_shell(install_path):
    home = os.path.expanduser("~")
    shell = os.environ.get("SHELL", "")
    rc_file = None

    if "zsh" in shell:
        rc_file = os.path.join(home, ".zshrc")
    elif "bash" in shell:
        rc_file = os.path.join(home, ".bash_profile") if platform.system() == "Darwin" else os.path.join(home, ".bashrc")

    if not rc_file:
        log("Could not detect shell RC file. Please manually add configuration.", RED)
        return

    log(f"Configuring {rc_file}...", YELLOW)

    config_lines = [
        f'\n# Secret Manager Configuration',
        f'export SECRETS_MANAGER_PATH="{install_path}/manage-secrets.sh"',
        'alias secret-add=\'$SECRETS_MANAGER_PATH add\'',
        'alias secret-ls=\'$SECRETS_MANAGER_PATH ls\'',
        'alias secret-apply=\'$SECRETS_MANAGER_PATH apply\''
    ]

    # Check if already exists to avoid duplication
    try:
        if os.path.exists(rc_file):
            with open(rc_file, "r") as f:
                content = f.read()
                if "SECRETS_MANAGER_PATH" in content:
                    log("Configuration already exists in RC file. Skipping append.", YELLOW)
                    return

        with open(rc_file, "a") as f:
            f.write("\n".join(config_lines))
            f.write("\n")

        log(f"Successfully configured {rc_file}", GREEN)
        log("IMPORTANT: Please restart your terminal or run:", YELLOW)
        log(f"  source {rc_file}", YELLOW)

    except Exception as e:
        log(f"Failed to update {rc_file}: {e}", RED)

def main():
    log("=== Secret Manager Installer ===", GREEN)

    try:
        install_dependencies()
        target_dir = setup_files()
        configure_shell(target_dir)
        log("\nInstallation Complete! 🚀", GREEN)
    except Exception as e:
        log(f"\nInstallation failed: {e}", RED)
        sys.exit(1)

if __name__ == "__main__":
    main()
