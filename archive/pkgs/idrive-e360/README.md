# iDrive e360 Package

This package provides the iDrive e360 endpoint backup client for NixOS.

## Using Your Own Account ID

The package is currently configured with a placeholder account ID (`BBAVCS39384`). To use your own account:

1. Log into your iDrive e360 console at https://www.idrive.com/endpoint-backup/
2. Click "Add Devices" → "Linux" tab
3. Right-click the download button and copy the link URL
4. Extract your account ID from the URL (format: `BBAVCS39384` or similar)
5. Update line 36 in `default.nix`:

```nix
url = "https://webapp.idrive360.com/api/v1/download/setup/deb/YOUR_ACCOUNT_ID?encryption=false";
```

6. Calculate the new SHA256 hash:

```bash
# Download your .deb file
wget -O idrive360.deb "https://webapp.idrive360.com/api/v1/download/setup/deb/YOUR_ACCOUNT_ID?encryption=false"

# Calculate hash
nix-hash --type sha256 --flat --base32 idrive360.deb
```

7. Update the sha256 on line 37 with the output

## Using a Local .deb File

Alternatively, you can use a locally downloaded .deb file:

```nix
services.idrive-e360 = {
  enable = true;
  debFile = /path/to/your/downloaded/idrive360.deb;
};
```

## Package Structure

After installation, files are organized as:

```
$out/
├── bin/
│   ├── idrive360          # Main CLI (account_setting.pl)
│   ├── idrive360-backup   # Backup script
│   └── idrive360-restore  # Restore script
└── share/idrive360/
    ├── *.pl              # All Perl scripts
    ├── *.pm              # Perl modules
    └── Idrivelib/        # Libraries and dependencies
```

## Available Commands

Once installed, you can use:

- `idrive360` - Main account and configuration interface
- `idrive360-backup` - Run backup operations
- `idrive360-restore` - Restore files from backup

All commands are Perl scripts that run with proper environment and working directory setup.
