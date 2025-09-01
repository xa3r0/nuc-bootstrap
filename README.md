# nuc-bootstrap

One repo, per‑OS bootstrap scripts. Run after a fresh install.

## Usage
```bash
git clone https://github.com/xa3r0/nuc-bootstrap
cd nuc-bootstrap/<os>
./bootstrap.sh
```

Each script is idempotent: safe to re-run. Common helpers live in `common/`.
