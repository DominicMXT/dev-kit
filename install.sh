#!/usr/bin/env bash
# Установка dev-kit в Claude Code: личные правила и скиллы — ссылками, подпись Claude в коммитах — отключается
# Запуск: ./install.sh

set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$CLAUDE_DIR/skills"

# Замена файла или папки ссылкой на dev-kit, прежний не-ссылочный объект сохраняется рядом
link() {
    local src="$1" dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dst" "$backup"
        echo "Прежний сохранён: $backup"
    fi
    ln -sfn "$src" "$dst"
    echo "Ссылка: $dst → $src"
}

# Личные правила
link "$KIT/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# Скиллы
for skill in "$KIT"/claude/skills/*/; do
    link "${skill%/}" "$CLAUDE_DIR/skills/$(basename "$skill")"
done

# Отключение подписи Claude в коммитах и PR
python3 - "$CLAUDE_DIR/settings.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
data["attribution"] = {"commit": "", "pr": "", "sessionUrl": False}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
echo "settings.json: подпись Claude в коммитах и PR отключена"

# Проверка uv: copier запускается через uvx
if ! command -v uvx >/dev/null 2>&1; then
    echo "Нужен uv (https://docs.astral.sh/uv/): шаблон разворачивается через uvx copier"
fi
