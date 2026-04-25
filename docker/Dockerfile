FROM python:3.11-slim-bookworm

ARG SALT_ROLE=master

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libffi-dev \
    libssl-dev \
    libzmq3-dev \
    pkg-config \
    git \
    procps \
    curl \
    default-libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /salt-src

COPY requirements/base.txt requirements/base.txt
COPY requirements/crypto.txt requirements/crypto.txt
COPY requirements/zeromq.txt requirements/zeromq.txt
COPY requirements/constraints.txt requirements/constraints.txt

RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements/zeromq.txt

COPY . .

RUN pip install --no-cache-dir -e . --no-deps \
    && pip install --no-cache-dir mysqlclient

RUN mkdir -p /etc/salt /var/cache/salt /var/log/salt /var/run/salt /srv/salt /srv/pillar

EXPOSE 4505 4506

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV SALT_ROLE=${SALT_ROLE}

ENTRYPOINT ["/entrypoint.sh"]
