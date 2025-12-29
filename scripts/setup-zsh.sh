#!/bin/bash
# ============================================================================
# Zsh Setup Script - Fish to Zsh Migration
# ============================================================================
# Installs zsh, oh-my-zsh, plugins, and migrates fish history
# ============================================================================

set -e

echo "=============================================="
echo "  Fish to Zsh Migration Script"
echo "=============================================="
echo ""

# Step 1: Install zsh
echo "[1/6] Installing zsh..."
if command -v zsh &> /dev/null; then
    echo "  Zsh already installed: $(zsh --version)"
else
    sudo pacman -S --noconfirm zsh
    echo "  Zsh installed: $(zsh --version)"
fi
echo ""

# Step 2: Install Oh My Zsh
echo "[2/6] Installing Oh My Zsh..."
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "  Oh My Zsh already installed"
else
    # Install without switching shell (we'll do that at the end)
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    echo "  Oh My Zsh installed"
fi
echo ""

# Step 3: Install Powerlevel10k
echo "[3/6] Installing Powerlevel10k theme..."
if [ -d "$HOME/powerlevel10k" ]; then
    echo "  Powerlevel10k already installed, updating..."
    git -C ~/powerlevel10k pull
else
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
    echo "  Powerlevel10k installed"
fi
echo ""

# Step 4: Install zsh plugins
echo "[4/6] Installing zsh plugins..."

# zsh-syntax-highlighting
if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "  zsh-syntax-highlighting already installed"
else
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
        ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    echo "  zsh-syntax-highlighting installed"
fi

# zsh-autosuggestions
if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "  zsh-autosuggestions already installed"
else
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    echo "  zsh-autosuggestions installed"
fi
echo ""

# Step 5: Migrate Fish history to Zsh
echo "[5/6] Migrating Fish history to Zsh..."
FISH_HISTORY="$HOME/.local/share/fish/fish_history"
ZSH_HISTORY="$HOME/.zsh_history"

if [ -f "$FISH_HISTORY" ]; then
    # Backup existing zsh history if it exists
    if [ -f "$ZSH_HISTORY" ]; then
        cp "$ZSH_HISTORY" "$ZSH_HISTORY.backup.$(date +%Y%m%d-%H%M%S)"
        echo "  Backed up existing zsh history"
    fi

    # Convert fish history format to zsh format
    # Fish format: - cmd: command\n  when: timestamp
    # Zsh format: : timestamp:0;command

    echo "  Converting fish history format..."
    python3 << 'PYTHON_SCRIPT'
import re
import os
from datetime import datetime

fish_history = os.path.expanduser("~/.local/share/fish/fish_history")
zsh_history = os.path.expanduser("~/.zsh_history")
zsh_history_new = os.path.expanduser("~/.zsh_history.fish_import")

# Read existing zsh history
existing_commands = set()
if os.path.exists(zsh_history):
    with open(zsh_history, 'r', errors='ignore') as f:
        for line in f:
            # Extract command from zsh history format
            match = re.match(r'^: \d+:\d+;(.*)$', line.strip())
            if match:
                existing_commands.add(match.group(1))

# Parse fish history
fish_commands = []
with open(fish_history, 'r', errors='ignore') as f:
    content = f.read()

# Fish history format: - cmd: <command>\n  when: <timestamp>
pattern = r'- cmd: (.*?)\n  when: (\d+)'
matches = re.findall(pattern, content, re.DOTALL)

for cmd, timestamp in matches:
    # Clean up the command (fish escapes newlines as \n)
    cmd = cmd.strip()
    if cmd and cmd not in existing_commands:
        fish_commands.append((int(timestamp), cmd))

# Sort by timestamp
fish_commands.sort(key=lambda x: x[0])

# Write merged history
with open(zsh_history_new, 'w') as f:
    # First copy existing zsh history
    if os.path.exists(zsh_history):
        with open(zsh_history, 'r', errors='ignore') as existing:
            f.write(existing.read())

    # Append fish commands
    for timestamp, cmd in fish_commands:
        # Zsh format: : timestamp:0;command
        # Handle multiline commands
        cmd_escaped = cmd.replace('\n', '\\\n')
        f.write(f": {timestamp}:0;{cmd_escaped}\n")

print(f"  Imported {len(fish_commands)} unique commands from fish history")
os.rename(zsh_history_new, zsh_history)
PYTHON_SCRIPT

    echo "  Fish history merged into zsh history"
else
    echo "  No fish history found at $FISH_HISTORY"
fi
echo ""

# Step 6: Set zsh as default shell
echo "[6/6] Setting zsh as default shell..."
if [ "$SHELL" = "/usr/bin/zsh" ] || [ "$SHELL" = "/bin/zsh" ]; then
    echo "  Zsh is already the default shell"
else
    echo "  Running: chsh -s /usr/bin/zsh"
    chsh -s /usr/bin/zsh
    echo "  Zsh set as default shell"
    echo "  NOTE: Log out and log back in for the change to take effect"
fi
echo ""

echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Log out and log back in (or restart terminal)"
echo "  2. Run 'p10k configure' to set up Powerlevel10k theme"
echo "  3. Your existing ~/.zshrc has been preserved"
echo ""
echo "If something goes wrong, switch back to fish:"
echo "  chsh -s /usr/bin/fish"
echo ""
