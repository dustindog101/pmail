# pmail

Small CLI for listing and reading Proton Mail via [protonmail-api-client](https://github.com/opulentfox-29/protonmail-api-client).

## Credits

Built on **[opulentfox-29 / protonmail-api-client](https://github.com/opulentfox-29/protonmail-api-client)** (PyPI: `protonmail-api-client`). This project is only a thin wrapper; all Proton protocol and crypto work comes from that library. It is **not** an official Proton product.

Huge thanks to the upstream author for the client that makes this possible.

## Setup

Requires [uv](https://github.com/astral-sh/uv).

```bash
cd pmail
uv sync
./scripts/apply-version-patch.sh
```

`pmail.sh` also re-applies the version patch automatically when the installed constants look stale (for example after a fresh `uv sync`).

## Usage

```bash
./pmail.sh login -u you@proton.me   # password via getpass; 2FA prompted if required
./pmail.sh ls                       # newest 20
./pmail.sh ls -n 50
./pmail.sh read 0                   # index from last ls
./pmail.sh help
```

Session file (sensitive): `session.pickle` in this directory (override with `PMAIL_SESSION`). Never commit it.

## Version-header patch (Proton API error 5003)

Proton rejects requests whose `x-pm-appversion` header is outdated (**error 5003**, “App version bad”). The published `protonmail-api-client` package still ships older defaults such as:

- `PM_APP_VERSION_ACCOUNT = 'web-account@5.0.255.0'`
- `PM_APP_VERSION_MAIL = 'web-mail@5.0.66.5'`

`scripts/apply-version-patch.sh` rewrites the installed `protonmail/constants.py` to:

- `web-account@5.0.423.0`
- `web-mail@5.0.134.7`

**Important:** a fresh `uv sync` (or any reinstall that restores site-packages) **wipes** this patch. Re-run `./scripts/apply-version-patch.sh`, or rely on `pmail.sh`, which checks the versions before login/list/read and re-applies when stale. For a fully durable fix you would need to vendor the library or pin a fork that already bumps these headers.

## Layout

| Path | Purpose |
|------|---------|
| `pyproject.toml` | uv project; depends on `protonmail-api-client` |
| `pmail.sh` | CLI (`login`, `ls`, `read`, `help`) |
| `scripts/apply-version-patch.sh` | Patch `PM_APP_VERSION_*` in the venv |
| `session.pickle` | Saved login session (gitignored; never commit) |

No secrets, passwords, or personal email addresses belong in this repository.
