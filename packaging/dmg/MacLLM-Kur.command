#!/bin/zsh
set -euo pipefail
DIR="${0:A:h}"
APP_SRC="$DIR/MacLLM.app"
if [[ ! -d "$APP_SRC" ]]; then
  /usr/bin/osascript -e 'display alert "MacLLM.app bulunamadı." as critical'
  exit 1
fi
ESCAPED_SRC="${APP_SRC//\'/\'\\\'\'}"
/usr/bin/osascript -e "do shell script \"rm -rf '/Applications/MacLLM.app' && cp -R '${ESCAPED_SRC}' /Applications/ && /usr/bin/xattr -dr com.apple.quarantine /Applications/MacLLM.app\" with administrator privileges"
/usr/bin/open -a MacLLM
