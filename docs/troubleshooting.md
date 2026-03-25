# Troubleshooting

## Git / SSH

### `git push` fails with "Permission denied (publickey)"

The GitHub SSH key may not be registered, or the agent doesn't have it loaded.

**1. Check which key is being used**
```bash
ssh -T git@github.com
# Should print: Hi fkadriver! You've successfully authenticated...
```

**2. If that fails, test keys directly to find the working one**
```bash
ssh -i ~/.ssh/id_ed25519_github -T git@github.com
ssh -i ~/.ssh/id_ed25519_legacy -T git@github.com
```

**3. Push with a specific key (temporary workaround)**
```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_github" git push
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_github" git pull
```

**4. If the agent has no connection**
```bash
# Check agent socket
echo $SSH_AUTH_SOCK

# No socket — start one manually (lasts current session only)
eval $(ssh-agent -s) && ssh-add ~/.ssh/id_ed25519_github

# Persistent fix: rebuild the host — gcr-ssh-agent (via gnome-keyring/vscode-server)
# sets SSH_AUTH_SOCK on login; AddKeysToAgent yes in user-scott.nix handles the rest
sudo nixos-rebuild switch --flake .#<hostname>
```

**5. Key not registered with GitHub**

The deployed key fingerprint can be found in Bitwarden item `4eb21873-7ca7-4114-9b0e-b3c90164bc7e` or by running:
```bash
ssh-keygen -lf ~/.ssh/id_ed25519_github.pub
```
Add the public key at **github.com → Settings → SSH and GPG keys → New SSH key**.

**6. After a nixos-rebuild, SSH config reverts and GitHub stops working**

The `github.com` host block in `modules/user-scott.nix` controls which key is used.
Check it points to `id_ed25519_github`:
```bash
grep -A3 "github.com" /etc/ssh/ssh_config
```
If wrong, fix in `user-scott.nix` and rebuild.

---

## Replacing the GitHub SSH key in Bitwarden

```bash
# Generate new key
ssh-keygen -t ed25519 -C "scott@latitude" -f /tmp/id_ed25519_github

# Register the public key at github.com → Settings → SSH keys
cat /tmp/id_ed25519_github.pub

# Update Bitwarden (item 4eb21873 — "github ssh", type: SSH Key)
export BW_SESSION=$(bw unlock --raw)
bw sync
NEW_PRIV=$(cat /tmp/id_ed25519_github)
NEW_PUB=$(cat /tmp/id_ed25519_github.pub)
FINGERPRINT=$(ssh-keygen -lf /tmp/id_ed25519_github.pub | awk '{print $2}')

bw get item 4eb21873-7ca7-4114-9b0e-b3c90164bc7e \
  | jq --arg priv "$NEW_PRIV" --arg pub "$NEW_PUB" --arg fp "$FINGERPRINT" \
      '.sshKey.privateKey = $priv | .sshKey.publicKey = $pub | .sshKey.keyFingerprint = $fp' \
  | bw encode \
  | bw edit item 4eb21873-7ca7-4114-9b0e-b3c90164bc7e

# Clean up and redeploy
rm /tmp/id_ed25519_github /tmp/id_ed25519_github.pub
sudo nixos-rebuild switch --flake .#<hostname>
```
