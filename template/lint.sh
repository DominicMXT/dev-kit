#!/usr/bin/env bash
# Линтинг и форматирование кода бэкенда через ruff
# Запуск: ./lint.sh

cd "$(dirname "$0")/backend"

RUFF_IMAGE="ghcr.io/astral-sh/ruff:0.15.11"

# Выбор ruff: локальный бинарь или Docker-образ, без установки пакетов в систему
if command -v ruff &>/dev/null; then
    RUFF=(ruff)
else
    RUFF=(docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/io" -w /io "$RUFF_IMAGE")
fi

"${RUFF[@]}" check . --select I --fix
"${RUFF[@]}" check .
LINT_EXIT=$?
"${RUFF[@]}" format .

find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -delete 2>/dev/null
rm -rf .ruff_cache 2>/dev/null

exit $LINT_EXIT
