HOST ?= login
BUILD ?= up --build --remove-orphans -d
DC ?= $(shell docker compose version 2>&1 >/dev/null && echo "docker compose" || echo "docker-compose")
IMAGES := $(shell $(DC) config | awk '{if ($$1 == "image:") print $$2;}' | sort | uniq)
SUBNET ?= 10.11
SUBNET6 ?= 2001:db8:1:1::

.EXPORT_ALL_VARIABLES:

default: ./docker-compose.yml run

./docker-compose.yml: buildout.sh
	bash buildout.sh > ./docker-compose.yml

build: ./docker-compose.yml
	env COMPOSE_HTTP_TIMEOUT=3000 $(DC) --ansi=never --progress=plain $(BUILD)

stop:
	$(DC) down

set_nocache:
	$(eval BUILD := build --no-cache)

nocache: set_nocache build

clean-nodelist:
	truncate -s0 scaleout/nodelist

clean:
	test -f ./docker-compose.yml && ($(DC) kill -s SIGKILL; $(DC) down --remove-orphans -t1 -v; unlink ./docker-compose.yml) || true
	[ -f cloud_socket ] && unlink cloud_socket || true

uninstall:
	$(DC) down --rmi all --remove-orphans -t1 -v
	$(DC) rm -v

run: ./docker-compose.yml
	$(DC) up --remove-orphans -d

cloud:
	test -f cloud_socket && unlink cloud_socket || true
	touch cloud_socket
	test -f ./docker-compose.yml && unlink ./docker-compose.yml || true
	env CLOUD=1 bash buildout.sh > ./docker-compose.yml
	python3 ./cloud_monitor.py3 "$(DC)"
	test -f ./docker-compose.yml && unlink ./docker-compose.yml || true
	test -f cloud_socket && unlink cloud_socket || true

bash:
	$(DC) exec $(HOST) /bin/bash

save: build
	docker save -o scaleout.tar $(IMAGES)

load:
	docker load -i scaleout.tar

benchmark-%: clean-nodelist clean
	$(eval SLURM_BENCHMARK := $(subst benchmark-,,$@))
	env SLURM_BENCHMARK=$(SLURM_BENCHMARK) bash buildout.sh > ./docker-compose.yml
	env COMPOSE_HTTP_TIMEOUT=3000 $(DC) --ansi=never --progress=plain $(BUILD)
	$(DC) up --remove-orphans -d
	$(DC) exec $(HOST) bash -c '(find /root/benchmark/run.d/ -type f -name $(SLURM_BENCHMARK)\*.sh | xargs -i echo bash "{} &"; echo wait) | bash -x'
	$(DC) down &>/dev/null
	truncate -s0 scaleout/nodelist

test-build: clean-nodelist clean build
	$(DC) exec $(HOST) bash /usr/local/bin/test-build.sh
	test -f ./docker-compose.yml && ($(DC) kill -s SIGKILL; $(DC) down --remove-orphans -t1 -v; unlink ./docker-compose.yml) || true
	[ -f cloud_socket ] && unlink cloud_socket || true
