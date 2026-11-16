#!/bin/sh
# StageView (videos.stagecraft.media), Quelle: Stagecraft OS, Skill stagecraft-stageview, eingespielt mit engine/installieren.sh
exec /home/hermes/.hermes/tools/python-3.14.7+20260901-linux-x64/bin/python3 -I -c "
import os, sys, runpy
os.environ.pop(\"PYTHONHOME\", None); os.environ.pop(\"PYTHONPATH\", None); os.environ.pop(\"VIRTUAL_ENV\", None)
sys.path.insert(0, \"/home/hermes/.hermes/hermes-agent\")
os.environ[\"HERMES_HOME\"] = os.environ.get(\"HERMES_HOME\") or \"/home/hermes/.hermes\"
import hermes_bootstrap
sys.argv = [\"stageview\"] + sys.argv[1:]
runpy.run_path(\"/home/hermes/.hermes/scripts/stageview/stageview.py\", run_name=\"__main__\")
" "$@"
