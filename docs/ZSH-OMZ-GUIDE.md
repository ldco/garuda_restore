# Zsh + Oh My Zsh Guide

Complete reference for the configured Zsh shell with Oh My Zsh and plugins.

## Installed Plugins

| Plugin | Description |
|--------|-------------|
| git | Git aliases and completions |
| gitfast | Faster git completion |
| zsh-autosuggestions | Fish-like command suggestions |
| zsh-syntax-highlighting | Syntax highlighting for commands |
| zsh-history-substring-search | Search history with arrows |
| docker | Docker completions |
| npm | NPM completions |
| fzf-tab | Fuzzy tab completion |
| sudo | Quick sudo prefix |
| extract | Universal archive extractor |
| archlinux | Pacman/Paru aliases |
| python | Python/venv helpers |
| pip | Pip completions |
| copypath | Copy current path to clipboard |
| command-not-found | Suggests packages for unknown commands |

---

## Plugin Usage

### sudo
Press `ESC` twice to prepend `sudo` to the last command.

```bash
pacman -Syu        # oops, need sudo
# Press ESC ESC
sudo pacman -Syu   # automatically added
```

### extract
Extract any archive format with one command:

```bash
extract file.tar.gz
extract file.zip
extract file.7z
extract file.rar
extract file.tar.bz2
```

Supported: tar, gz, bz2, xz, zip, rar, 7z, deb, rpm, and more.

### copypath
Copy current directory path to clipboard:

```bash
copypath           # copies /current/path to clipboard
copypath file.txt  # copies /current/path/file.txt
```

### fzf-tab
Tab completion uses fuzzy finder. Just press `TAB` and type to filter:

```bash
cd /u/l/b<TAB>     # fuzzy matches /usr/local/bin
git checkout <TAB> # fuzzy search branches
kill <TAB>         # fuzzy search processes
```

### command-not-found
When you type an unknown command, suggests which package to install:

```bash
$ htop
htop may be found in the following packages:
  extra/htop 3.2.1-1
```

---

## Git Aliases (git plugin)

### Basic Commands

| Alias | Command |
|-------|---------|
| `g` | `git` |
| `gst` | `git status` |
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gc` | `git commit -v` |
| `gcmsg` | `git commit -m` |
| `gp` | `git push` |
| `gpl` | `git pull` |
| `gco` | `git checkout` |
| `gcb` | `git checkout -b` |
| `gb` | `git branch` |
| `gd` | `git diff` |
| `glog` | `git log --oneline --decorate --graph` |

### Advanced

| Alias | Command |
|-------|---------|
| `gsta` | `git stash push` |
| `gstp` | `git stash pop` |
| `grb` | `git rebase` |
| `grbc` | `git rebase --continue` |
| `grhh` | `git reset --hard HEAD` |
| `gcl` | `git clone` |
| `gf` | `git fetch` |
| `gm` | `git merge` |

---

## Archlinux Plugin Aliases

### Pacman

| Alias | Command | Description |
|-------|---------|-------------|
| `pacin` | `sudo pacman -S` | Install package |
| `pacins` | `sudo pacman -U` | Install local package |
| `pacrm` | `sudo pacman -Rns` | Remove package + deps |
| `pacss` | `pacman -Ss` | Search packages |
| `pacsi` | `pacman -Si` | Package info |
| `pacql` | `pacman -Ql` | List package files |
| `pacqo` | `pacman -Qo` | Find package owning file |
| `pacu` | `sudo pacman -Syu` | System update |
| `pacls` | `pacman -Qe` | List installed |

### Paru/Yay (AUR)

| Alias | Command |
|-------|---------|
| `yay` | `paru` |
| `yayin` | `paru -S` |
| `yayss` | `paru -Ss` |
| `yayu` | `paru -Syu` |

---

## Python Plugin

| Alias | Description |
|-------|-------------|
| `pyfind` | Find .py files |
| `pyclean` | Remove .pyc and __pycache__ |
| `mkv` | Create virtualenv |
| `vrun` | Run command in virtualenv |

---

## Docker Plugin

| Alias | Command |
|-------|---------|
| `dps` | `docker ps` |
| `dpsa` | `docker ps -a` |
| `di` | `docker images` |
| `dex` | `docker exec -it` |
| `dlog` | `docker logs` |
| `drm` | `docker rm` |
| `drmi` | `docker rmi` |
| `drun` | `docker run` |
| `dstop` | `docker stop` |
| `dstart` | `docker start` |

---

## History Substring Search

Use UP/DOWN arrows to search history by what you've typed:

```bash
git c<UP>     # cycles through: git commit, git checkout, git clone...
docker<UP>    # cycles through all docker commands
```

---

## Zsh Autosuggestions

As you type, suggestions appear in gray. Accept with:

| Key | Action |
|-----|--------|
| `Right Arrow` | Accept full suggestion |
| `Ctrl+E` | Accept full suggestion |
| `Ctrl+F` | Accept next word |
| `Alt+F` | Accept next word |

---

## FZF Integration

| Shortcut | Action |
|----------|--------|
| `Ctrl+R` | Fuzzy search command history |
| `Ctrl+T` | Fuzzy search files |
| `Alt+C` | Fuzzy cd into directory |

---

## Zoxide (Smart cd)

Jump to directories by frecency (frequency + recency):

```bash
z projects      # jumps to most visited dir matching "projects"
z gar res       # jumps to garuda-restore
zi              # interactive selection with fzf
```

---

## Custom Aliases (from .zshrc)

### Modern CLI Replacements

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `eza --icons --group-directories-first` | Better ls with icons |
| `ll` | `eza -la --icons --git` | Long list with git status |
| `la` | `eza -a --icons` | List all including hidden |
| `lt` | `eza --tree --level=2` | Tree view (2 levels) |
| `cat` | `bat --style=plain` | Syntax highlighted cat |
| `grep` | `grep --color=auto` | Colored grep |
| `wget` | `wget -c` | Resume downloads |

### Quick Navigation

| Alias | Goes to |
|-------|---------|
| `..` | Parent dir |
| `...` | 2 levels up |
| `....` | 3 levels up |
| `.....` | 4 levels up |

### Git (Custom)

| Alias | Command | Description |
|-------|---------|-------------|
| `g` | `git` | Short git |
| `gs` | `git status -sb` | Short status |
| `ga` | `git add .` | Add all |
| `gitc` | `git add . && git commit -am` | Add + commit with message |
| `gc` | `git commit` | Commit |
| `gp` | `git push` | Push |
| `gpl` | `git pull` | Pull |
| `gd` | `git diff` | Diff |
| `gb` | `git branch` | List branches |
| `gco` | `git checkout` | Checkout |
| `gcom` | `git checkout master` | Checkout master |
| `gcod` | `git checkout dev` | Checkout dev |
| `gpo` | `git push origin` | Push to origin |
| `gpom` | `git push -u origin master` | Push to origin/master |
| `gpomf` | `git push -f origin master` | Force push to master |
| `gpod` | `git push -u origin dev` | Push to origin/dev |
| `gpodf` | `git push -f origin dev` | Force push to dev |
| `gmd` | `git merge dev` | Merge dev branch |
| `grao` | `git remote add origin` | Add remote origin |
| `gundo` | `git reset HEAD~1 --mixed` | Undo last commit |
| `glog` | `git log --oneline --graph -20` | Pretty log |
| `gwip` | `git add -A && git commit -m "WIP"` | Quick WIP commit |
| `gpf` | `git push --force-with-lease` | Safe force push |
| `showremote` | `git remote get-url origin` | Show remote URL |
| `gcleanrepo` | prune + gc + reflog expire | Deep clean repo |
| `lg` | `lazygit` | Full git TUI |

### System & Arch

| Command | Points to | Description |
|---------|-----------|-------------|
| `update` | `scripts/system-update.sh` | Custom system update script |
| `check` | `scripts/system-health-check.sh` | System health check |
| `upd` | `/usr/bin/garuda-update` | Garuda system update |
| `fixpacman` | `sudo rm /var/lib/pacman/db.lck` | Remove pacman lock |
| `grubup` | `sudo update-grub` | Update GRUB config |
| `hw` | `hwinfo --short` | Hardware info |
| `big` | `expac -H M "%m\t%n" \| sort -h \| nl` | List packages by size |
| `gitpkg` | `pacman -Q \| grep -i "\-git" \| wc -l` | Count git packages |
| `rmpkg` | `sudo pacman -Rdd` | Force remove package |

### File Operations

| Alias | Command | Description |
|-------|---------|-------------|
| `tarnow` | `tar -acf` | Create archive (auto format) |
| `untar` | `tar -zxvf` | Extract tar.gz |

### Process Info

| Alias | Command | Description |
|-------|---------|-------------|
| `psmem` | `ps auxf \| sort -nr -k 4` | Processes by memory |
| `psmem10` | `ps auxf \| sort -nr -k 4 \| head -10` | Top 10 memory hogs |

---

## Configuration Files

| File | Purpose |
|------|---------|
| `~/.zshrc` | Main Zsh config |
| `~/.p10k.zsh` | Powerlevel10k theme config |
| `~/.oh-my-zsh/` | OMZ installation |
| `~/.oh-my-zsh/custom/plugins/` | Custom plugins |

---

## Useful Commands

```bash
# Reload zsh config
source ~/.zshrc

# Reconfigure Powerlevel10k theme
p10k configure

# Update Oh My Zsh
omz update

# List all aliases
alias

# List git aliases
alias | grep git
```
