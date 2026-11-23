#!/bin/zsh
# App in den StageView Spiegel auf GitHub (seit 23.11.2026, Ole: „Spiegel mit verschiedenen Backups wie bei der Web Version“).
# Schiebt main und alle Tags (testflight-<Build>) in das nackte Repo auf VPS 2 (~/.hermes/data/stageview-app.git, derselbe SSH
# Schlüssel wie für alles auf VPS 2), dann spiegelt `stageview-sichern` dort sofort nach GitHub (privates Repo oletrappmann/stageview:
# aktuell/app/, versionen/<Datum>/app.tar.gz, voller Verlauf als Zweig app). Kein eigener Job auf dem Mac: läuft am Ende von
# testflight.sh und iphone.sh, von Hand: scripts/sichern.sh. Nur Committetes kommt mit.
set -eu
cd "${0:A:h}/../.."
[ -z "$(git status --porcelain)" ] || echo "Hinweis: nicht committete Änderungen sind nicht im Spiegel."
git remote get-url vps >/dev/null 2>&1 || git remote add vps hermes@82.165.217.31:.hermes/data/stageview-app.git
git -c core.sshCommand="ssh -i $HOME/.ssh/id_ed25519" push -q vps main --tags
ssh -i ~/.ssh/id_ed25519 hermes@82.165.217.31 '~/.local/bin/stageview-sichern'
