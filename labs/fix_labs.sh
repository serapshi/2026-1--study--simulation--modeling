#!/usr/bin/env bash
# Добавляет исправление шрифта в lab02..lab08, не трогая остальные настройки преамбулы.
# Использование:
#   bash fix_labs.sh          # dry-run
#   bash fix_labs.sh apply    # применить
set -euo pipefail

MODE="${1:-dry}"
BASE="$HOME/work/study/2026-1/2026-1==study-simulation-modeling/2026-1--study--simulation--modeling/labs"
TS=$(date +%Y%m%d%H%M%S)

FONT_BLOCK='
%% Моноширинный шрифт с кириллицей (DejaVu Sans Mono)
\usepackage{fontspec}
\setmonofont{DejaVu Sans Mono}[Scale=MatchLowercase]'

for n in 02 03 04 05 06 07 08; do
  DST="$BASE/lab$n/report"
  echo "=== lab$n ==="

  if [ ! -d "$DST" ]; then
    echo "  пропуск: нет $DST"
    continue
  fi

  PRE="$DST/_resources/tex/preamble.tex"
  YML="$DST/_quarto.yml"

  # 1. preamble.tex: только добавляем блок шрифта, если его ещё нет
  if [ ! -f "$PRE" ]; then
    echo "  preamble.tex: НЕТ ФАЙЛА, пропускаю"
  elif grep -q 'setmonofont{DejaVu Sans Mono}' "$PRE"; then
    echo "  preamble.tex: блок DejaVu уже есть"
  else
    echo "  preamble.tex: добавлю блок DejaVu в конец"
    if [ "$MODE" = "apply" ]; then
      cp "$PRE" "$PRE.bak-$TS"
      printf '%s\n' "$FONT_BLOCK" >> "$PRE"
    fi
  fi

  # 2. _quarto.yml: добавляем monofont под format pdf:
  if [ ! -f "$YML" ]; then
    echo "  _quarto.yml: НЕТ ФАЙЛА, пропускаю"
    continue
  fi
  if grep -q "monofont" "$YML"; then
    echo "  _quarto.yml: monofont уже задан"
  elif grep -q "^  pdf:" "$YML"; then
    echo "  _quarto.yml: добавлю monofont под 'pdf:'"
    if [ "$MODE" = "apply" ]; then
      cp "$YML" "$YML.bak-$TS"
      sed -i '/^  pdf:/a\    monofont: "DejaVu Sans Mono"' "$YML"
    fi
  else
    echo "  _quarto.yml: блока 'pdf:' с отступом 2 нет, нужна ручная правка"
  fi
done

echo
if [ "$MODE" = "apply" ]; then
  echo "Готово. Далее в каждом labNN/report: make clean && make"
else
  echo "Dry-run. Для применения: bash fix_labs.sh apply"
fi