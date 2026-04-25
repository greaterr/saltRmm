# saltRmm — Состояние проекта

## Архитектура

```
MacBook Pro (macOS, en0)
  ├── Docker Desktop
  │     ├── samba-dc      — Samba AD DC (домен rmm.lan)
  │     ├── salt-master   — Salt Master + Salt API
  │     ├── alcali-web    — Web UI для Salt
  │     ├── alcali-nginx  — Reverse proxy
  │     └── salt-db       — MariaDB (returner)
  └── launchd: update-dns.sh  — автообновление DNS при смене IP

Windows HUS (DESKTOP-E1R8HUS)
  ├── Домен: rmm.lan (OU=Computers)
  └── salt-minion  — подключён к macbook-pro-timur.rmm.lan

Windows NOTEBOOK_VN
  ├── Домен: rmm.lan (OU=Computers)
  └── salt-minion  — подключён к macbook-pro-timur.rmm.lan
```

> **Salt используется только для отладки.** Управление устройствами — через Samba AD (GPO, скрипты).

---

## Сеть

| Узел | DNS имя | Примечание |
|------|---------|------------|
| MacBook Pro (en0) | `macbook-pro-timur.rmm.lan` | IP динамический, меняется при смене Wi-Fi |
| Samba DC (Docker) | `dc1.rmm.lan` | Проброс портов с Mac, IP совпадает с Mac |
| Windows HUS | `DESKTOP-E1R8HUS.rmm.lan` | IP динамический |
| Windows NOTEBOOK_VN | `NOTEBOOK_VN.rmm.lan` | IP динамический |

> **IP нигде не хардкодится.** Все компоненты используют DNS имена.
> При смене сети `update-dns.sh` (launchd) автоматически обновляет A и PTR записи в Samba DNS.

### DNS на Mac
Файл `/etc/resolver/rmm.lan`:
```
nameserver 127.0.0.1
port 53
```
Mac резолвит `*.rmm.lan` через Samba DC (порт 53 проброшен на `127.0.0.1`).

### DNS на Windows устройствах
Адрес DNS сервера = IP DC (прописывается при domain join скриптом `join-domain.ps1`).
Windows резолвит `*.rmm.lan` через DC — hosts файл не используется.

### DNS зоны в Samba

| Зона | Назначение |
|------|-----------|
| `rmm.lan` | Forward zone — A записи всех хостов |
| `3.168.192.in-addr.arpa` | Reverse zone — PTR записи (обязательно для GPO!) |

> **Важно:** PTR зона обязательна. Без reverse DNS у Windows не работает Computer Policy в GPO.

### При смене Wi-Fi сети
`update-dns.sh` срабатывает автоматически через launchd и обновляет записи:
- A: `macbook-pro-timur.rmm.lan`, `dc1.rmm.lan`, `rmm.lan` (`@`)
- PTR: запись для Mac в reverse зоне

После этого все устройства переподключаются к Salt master и DC по именам без ручных правок.

---

## Домен Active Directory

| Параметр | Значение |
|----------|----------|
| Domain | `rmm.lan` |
| Realm | `RMM.LAN` |
| NetBIOS | `RMM` |
| DC hostname | `dc1.rmm.lan` |
| DC container | `samba-dc` |

### Структура OU

```
DC=rmm,DC=lan
├── OU=Computers          ← машинные аккаунты Windows устройств
│   ├── DESKTOP-E1R8HUS$
│   └── NOTEBOOK_VN$
├── OU=Users              ← доменные пользователи
│   ├── Administrator
│   ├── AD                ← пользователь для HUS
│   ├── ADUSER            ← пользователь для NOTEBOOK_VN
│   └── ADVN              ← дополнительный пользователь VN
├── OU=Groups             ← группы безопасности
│   └── VnUsers           ← группа: AD, ADUSER, ADVN
└── OU=Domain Controllers
    └── DC1$
```

### Учётные записи AD

| Учётная запись | OU | Пароль | Примечание |
|----------------|----|--------|------------|
| `Administrator` | (default) | `Admin1234!` | Доменный администратор |
| `AD` | `OU=Users` | `Admin1234!` | Пользователь HUS |
| `ADUSER` | `OU=Users` | `User1234!` | Пользователь NOTEBOOK_VN |
| `ADVN` | `OU=Users` | — | Дополнительный пользователь VN |
| `DESKTOP-E1R8HUS$` | `OU=Computers` | — | Machine account HUS |
| `NOTEBOOK_VN$` | `OU=Computers` | — | Machine account NOTEBOOK_VN |

### Группы

| Группа | OU | Члены |
|--------|----|-------|
| `VnUsers` | `OU=Groups` | AD, ADUSER, ADVN |

### GPO (Group Policy Objects)

Привязки GPO:

| GPO | Привязан к | Файлы в SYSVOL | Назначение |
|-----|-----------|----------------|------------|
| Default Domain Policy | `DC=rmm,DC=lan` | GPT.INI | Базовые настройки домена |
| RMM Base Policy | `DC=rmm,DC=lan` | GPT.INI | Базовая политика RMM |
| RMM Desktop Policy | `DC=rmm,DC=lan` | GPT.INI + User/Registry.pol | Настройки рабочего стола |
| RMM Security Policy | `DC=rmm,DC=lan` | GPT.INI | Политики безопасности |

> **Важно:** GPO без файлов `Machine/` или `User/` (пустые) показываются как `Filtered (Empty)` в `gpresult` — это нормально, пока настройки не добавлены.

---

## Samba DC — Конфигурация

### smb.conf (`/usr/local/samba/etc/smb.conf`)

```ini
[global]
    ldap server require strong auth = No
    dns forwarder = 8.8.8.8
    netbios name = DC1
    realm = RMM.LAN
    server role = active directory domain controller
    workgroup = RMM
    idmap_ldb:use rfc2307 = yes
    host msdfs = yes
    rpc server dynamic port range = 49152-49200

allow dns updates = nonsecure
server min protocol = SMB2_10
client max protocol = SMB3
server signing = mandatory
client signing = auto

[sysvol]
    path = /usr/local/samba/var/locks/sysvol
    read only = No

[netlogon]
    path = /usr/local/samba/var/locks/sysvol/rmm.lan/scripts
    read only = No
```

> **Критично:** `[sysvol] path` должен указывать на **корень** `/sysvol`, а не на `/sysvol/rmm.lan`.
> Windows обращается как `\\dc1\sysvol\rmm.lan\Policies\...` — путь должен разворачиваться в `sysvol/rmm.lan/Policies/`.

### SYSVOL структура на диске

```
/usr/local/samba/var/locks/sysvol/
└── rmm.lan/
    ├── Policies/
    │   ├── {31B2F340-...}   Default Domain Policy
    │   ├── {6AC1786C-...}   Default Domain Controllers Policy
    │   ├── {1FD8DC22-...}   RMM Base Policy
    │   ├── {47264CC9-...}   RMM Security Policy
    │   ├── {7156229C-...}   RMM Desktop Policy
    │   └── PolicyDefinitions/
    └── scripts/
```

### Проброс портов (docker/samba-dc.yml)

| Порт(ы) | Протокол | Назначение |
|---------|----------|------------|
| 53 | TCP/UDP | DNS |
| 88 | TCP/UDP | Kerberos |
| 135 | TCP | RPC Endpoint Mapper |
| 139 | TCP | NetBIOS |
| 389 | TCP/UDP | LDAP |
| 445 | TCP | SMB (SYSVOL, NETLOGON) |
| 464 | TCP/UDP | Kerberos password |
| 636 | TCP | LDAPS |
| 3268-3269 | TCP | Global Catalog |
| **49152-49200** | **TCP** | **RPC динамические порты (обязательно для GPO Computer Policy!)** |

> **Критично:** Без проброса RPC динамических портов `gpupdate /force` завершается с ошибкой
> `0x6BA RPC_S_SERVER_UNAVAILABLE` при обработке Computer Policy.

### Запуск Samba DC

```bash
docker compose -f docker/samba-dc.yml up -d
```

---

## Salt Stack

> Salt используется **только для отладки**. Управление через GPO/AD.

### Запуск

```bash
docker compose up -d
```

### Endpoints

| Сервис | URL | Логин / Пароль |
|--------|-----|----------------|
| Salt API | `https://localhost:8443` | `admin` / `password` |
| Alcali Web UI | `http://localhost:8081` | `admin` / `password` |
| Alcali (nginx TLS) | `https://localhost:8444` | `admin` / `password` |

### База данных (MariaDB)

| Параметр | Значение |
|----------|----------|
| Container | `salt-db` |
| Database | `salt` |
| User | `alcali` |
| Password | `alcali` |
| Root password | `rootpassword` |

### Минионы

| Minion ID | Хост | ОС | Master |
|-----------|------|----|--------|
| `HUS` | `DESKTOP-E1R8HUS` | Windows 11 Pro 26100 | `macbook-pro-timur.rmm.lan` |
| `NOTEBOOK_VN` | `NOTEBOOK_VN` | Windows 11 Pro 26200 | `macbook-pro-timur.rmm.lan` |

### Полезные команды Salt (только отладка)

```bash
# Проверить все минионы
docker exec salt-master salt '*' test.ping

# Список ключей
docker exec salt-master salt-key -L

# Выполнить команду на устройстве
docker exec salt-master salt 'HUS' cmd.run 'whoami'

# Проверить GPO
docker exec salt-master salt 'HUS' cmd.run 'cmd /c "gpresult /r /scope computer"'

# Запустить PowerShell скрипт
docker exec salt-master salt 'HUS' cmd.script salt://scripts/<script>.ps1 shell=powershell
```

---

## Диагностика GPO

### Проверка применения политик

```bash
# На устройстве (выполнить локально или через Salt)
gpupdate /force
gpresult /r

# Подробный HTML отчёт
gpresult /H C:\gpresult.html
```

### Чек-лист при проблемах с GPO

1. **DNS A запись** — `nslookup DESKTOP-E1R8HUS.rmm.lan` должна вернуть правильный IP
2. **PTR запись** — `nslookup <IP>` должна вернуть `DESKTOP-E1R8HUS.rmm.lan`
3. **SYSVOL доступен** — `dir \\rmm.lan\sysvol\rmm.lan\Policies\` должна показать все GPO папки
4. **RPC порты** — `Test-NetConnection dc1.rmm.lan -Port 135` и порты `49152-49200`
5. **Компьютер в правильном OU** — `samba-tool computer show <name>` → `OU=Computers`
6. **Event Log** — `Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-GroupPolicy/Operational"; Level=2,3} -MaxEvents 10`

### Управление DNS через samba-tool

```bash
# Просмотр A записей
docker exec samba-dc samba-tool dns query 127.0.0.1 rmm.lan @ ALL -U Administrator%Admin1234!

# Исправить A запись
docker exec samba-dc samba-tool dns delete 127.0.0.1 rmm.lan <hostname> A <old_ip> -U Administrator%Admin1234!
docker exec samba-dc samba-tool dns add    127.0.0.1 rmm.lan <hostname> A <new_ip> -U Administrator%Admin1234!

# Просмотр PTR записей (reverse zone)
docker exec samba-dc samba-tool dns query 127.0.0.1 3.168.192.in-addr.arpa @ ALL -U Administrator%Admin1234!

# Добавить PTR запись
docker exec samba-dc samba-tool dns add 127.0.0.1 3.168.192.in-addr.arpa <last_octet> PTR <fqdn>. -U Administrator%Admin1234!
```

### Управление пользователями AD

```bash
# Список пользователей
docker exec samba-dc samba-tool user list

# Список компьютеров
docker exec samba-dc samba-tool computer list

# Переместить объект в правильный OU
docker exec samba-dc samba-tool user move <username> "OU=Users,DC=rmm,DC=lan"

# Сменить пароль
docker exec samba-dc samba-tool user setpassword <username> --newpassword='NewPass!'

# Снять флаг "сменить пароль при входе"
docker exec samba-dc ldbmodify -H /usr/local/samba/private/sam.ldb <<EOF
dn: CN=<username>,OU=Users,DC=rmm,DC=lan
changetype: modify
replace: userAccountControl
userAccountControl: 512
EOF
```

### Управление GPO

```bash
# Список всех GPO
docker exec samba-dc samba-tool gpo listall

# GPO привязанные к OU
docker exec samba-dc samba-tool gpo getlink "DC=rmm,DC=lan"
docker exec samba-dc samba-tool gpo getlink "OU=Computers,DC=rmm,DC=lan"

# Привязать GPO к OU
docker exec samba-dc samba-tool gpo setlink "OU=Computers,DC=rmm,DC=lan" '{GUID}' -U Administrator%Admin1234!

# Отвязать GPO
docker exec samba-dc samba-tool gpo dellink "OU=Computers,DC=rmm,DC=lan" '{GUID}' -U Administrator%Admin1234!
```

---

## Domain Join — новое устройство

### Присоединить Windows к домену

```bash
# 1. Запустить скрипт на устройстве (через Salt или вручную)
docker exec salt-master salt '<MINION_ID>' cmd.script salt://scripts/join-domain.ps1 shell=powershell

# 2. После перезагрузки проверить
docker exec samba-dc samba-tool computer show <COMPUTERNAME>

# 3. Проверить DNS и PTR записи (добавить если нет)
docker exec samba-dc samba-tool dns query 127.0.0.1 rmm.lan <COMPUTERNAME> A -U Administrator%Admin1234!
docker exec samba-dc samba-tool dns query 127.0.0.1 3.168.192.in-addr.arpa <last_octet> PTR -U Administrator%Admin1234!
```

### Переприсоединить устройство

```bash
docker exec samba-dc samba-tool computer delete <COMPUTERNAME>
docker exec salt-master salt '<MINION_ID>' cmd.script salt://scripts/join-domain.ps1 shell=powershell
```

---

## Автообновление DNS при смене IP

При смене Wi-Fi launchd запускает `update-dns.sh`, который обновляет A и PTR записи для Mac/DC.

```bash
# Ручной запуск
bash update-dns.sh

# Статус launchd агента
launchctl list | grep saltrmm

# Лог
cat /tmp/saltrmm-updatedns.log
```

Файлы:
- `update-dns.sh` — скрипт обновления
- `com.saltrmm.updatedns.plist` — launchd агент (`~/Library/LaunchAgents/`)

---

## Структура проекта (ключевые файлы)

```
saltRmm/
├── docker-compose.yml          — Salt Master + Alcali + MariaDB
├── docker/samba-dc.yml         — Samba AD DC + проброс портов
├── update-dns.sh               — автообновление DNS
├── com.saltrmm.updatedns.plist — launchd агент
├── ssl/                        — TLS сертификаты
└── docker/
    ├── conf/master             — конфиг Salt Master
    └── srv/salt/
        └── scripts/            — PowerShell скрипты для Windows
```

### PowerShell скрипты (`docker/srv/salt/scripts/`)

> Все скрипты резолвят DC через `dc1.rmm.lan` — IP не хардкодится.

| Скрипт | Назначение |
|--------|------------|
| `join-domain.ps1` | Присоединение к домену |
| `install-salt-minion.ps1` | Установка Salt Minion (только для отладки) |
| `check-domain.ps1` | Проверка состояния домена на устройстве |
| `test-ad-policy.ps1` | Проверка DNS, служб, политик |
