---
name: sync-rules
description: Перенос новых общих правил и улучшений инфраструктуры из текущего проекта в dev-kit — кодстайл, шаблон, личные правила
argument-hint: [что перенести; пусто — найти самому]
disable-model-invocation: true
---

# Синхронизация правил с dev-kit: $ARGUMENTS

dev-kit — `~/Work/dev-kit`:
- `standards/python-backend.md` — общий кодстайл;
- `template/` + `copier.yml` — шаблон проекта;
- `claude/CLAUDE.md` — личные правила;
- `claude/skills/` — скиллы.

## Шаг 1. Сравнение

Если в аргументах указано, что перенести, — сравнивать только это. Иначе:
- `backend/devtools/CLAUDE.md` и `CLAUDE.md` проекта ↔ `standards/python-backend.md`;
- инфраструктура проекта ↔ `template/`:
  - `docker/`;
  - `start.sh`, `run_tests.sh`, `lint.sh`;
  - `backend/pyproject.toml`, `backend/requirements-dev.txt`, `backend/.dockerignore`;
  - `.gitignore`, `backend/tests/conftest.py`;
- feedback-память проекта ↔ `claude/CLAUDE.md`.

## Шаг 2. Разделение

- **Общее** — подходит любому бэкенду: правила кода, раскладки, нейминга, тестов, улучшения скриптов и docker.
- **Только этого проекта** — его модули, домен, ТЗ, подписи и правила коммитов, секреты, пути. В dev-kit не переносить.

## Шаг 3. Согласование

Показать список по одной строке: что, откуда, куда. Дождаться «да» по списку.

## Шаг 4. Перенос

- Формулировки — короткие, в стиле файла, без ссылок на проект и ТЗ.
- В шаблоне правило, зависящее от Redis или воркера, — под условием Jinja `{% if use_redis %}` / `{% if use_worker %}`.
- Новый вопрос шаблона — в `copier.yml` с дефолтом, чтобы старые проекты обновлялись без ответа.

## Шаг 5. Проверка шаблона

В scratchpad сгенерировать три варианта — без Redis, с Redis, с Redis и воркером:
```bash
uvx copier copy --vcs-ref HEAD --defaults -d project_name="Check" -d use_redis=<…> -d use_worker=<…> ~/Work/dev-kit <scratchpad>/<вариант>
```
В каждом варианте:
- `bash -n` для скриптов;
- разбор YAML compose-файлов и TOML `pyproject.toml`;
- `python3 -m py_compile` для `conftest.py`.

Docker не запускать.

## Шаг 6. Коммит

Коммит в `~/Work/dev-kit` — подробное сообщение по личным правилам, автор — пользователь. Пуш — по команде.

## Шаг 7. Как обновить проекты

Проекты, созданные из шаблона (есть `.copier-answers.yml`), обновляются из своего корня при чистом дереве git:
```bash
uvx copier update --vcs-ref HEAD --defaults --conflict inline
```
Конфликты — маркерами в файлах. Показать пользователю diff до коммита.
