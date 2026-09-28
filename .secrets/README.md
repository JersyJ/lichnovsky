# .secrets/ (git-ignored)

Plaintext Secrets live here only long enough to be sealed:

```bash
scripts/secrets.sh init   # render templates, generate random values, prompt for tokens
scripts/secrets.sh seal   # write SealedSecrets into the app folders (these get committed)
```

Keep these values in your password manager, because this folder is the only readable copy of them.
The templates are in `scripts/secret-templates/`.
