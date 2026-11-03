  Решение проблем вручную на сервере

  Залогиниться в реестр или обновить токен:
docker login -u _login_ {{ swarm_registry_url }}

  Деплой:
docker stack deploy {{ env_name }} -c {{ env_project_root }}/docker-compose.yml --with-registry-auth

  Проверить ошибки деплоя:
docker stack ps --no-trunc {{ env_name }}

  Статус последнего деплоя:
docker stack ps --no-trunc {{ env_name }} | grep -v '\_ '

  Список контейнеров на ноде:
docker ps | grep -i {{ env_name }}

  Войти в контейнер на ноде:
docker exec -it $(docker ps -q -f name={{ env_name }}_app | head -1) bash

  Перезапустить контейнер на ноде (например, если потребляет много памяти):
docker stop $(docker ps -q -f name={{ env_name }}_app | head -1)

  Посмотреть порты сервисов и количество реплик:
docker service ls

  Перезапустить сервис (контейнер) на всех нодах:
docker service ls
docker service update --force _service_name_

  Удалить сервис:
docker service ls
docker service rm _service_name_
