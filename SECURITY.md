# Security

## Reporting a vulnerability

Please do **not** open a public issue. Use GitHub's private reporting instead: *Security → Report a vulnerability* on this repository. Include the component, the input that triggers the problem, and what an attacker gains. You should get a first answer within a week.

## Threat model

A monitor runs with your user's privileges, reaches every machine you list, and reads your process table and AI-account credentials. It is a high-value target, so the design assumes the following attackers:

| # | Attacker | What they control |
|---|---|---|
| A1 | Any unprivileged user (or compromised service) on a monitored machine | Names and command lines of their own processes, their network interface names |
| A2 | A fully compromised monitored machine | Everything the agent prints, its stderr, timing |
| A3 | Another local user on the machine that shows the widget | Read access to files with default permissions |
| A4 | Someone on the network path | Traffic between machines |
| A5 | A mistaken or hostile config value | `config.toml` fields |

Out of scope: an attacker who already runs code as your user on the hub machine. They can read your credentials directly.

## Vectors and defences

Each row maps to a test in [`tests/test_seguranca.py`](tests/test_seguranca.py). During development, every defence was removed on purpose to confirm that its test fails.

| Vector | Attacker | Defence | Test |
|---|---|---|---|
| **Rich-text injection in the widget.** Qt renders strings that look like HTML as rich text. A process named `<img src=//evil>` would make your desktop fetch a URL, leaking your IP and that you are watching, or spoof the UI. | A1 | Every `PC3.Label` sets `textFormat: Text.PlainText`. | `Interface.test_todo_label_e_texto_puro` |
| **Secrets in command lines.** `mysql -pPASS`, `--token X`, `Authorization: Bearer …` and `https://user:pass@host` are visible in `/proc/*/cmdline` and would be shipped off the machine and stored. | A1, A3 | `agentes/linux.py` redacts at the source, before anything leaves the host: sensitive flags and `KEY=value` pairs, header values, URL credentials, `?token=` parameters, and known token prefixes (`sk-ant-`, `ghp_`, `github_pat_`, `xox?-`, `AKIA`, JWTs). Quoted `bash -c "…"` arguments are scanned too. | `Redacao.test_oculta_segredo` (14 shapes), `test_preserva_comando_comum` |
| **ReDoS / CPU burn through huge command lines.** A command line can be about 2 MB. | A1 | The raw cmdline is cut to 4 KiB before any regex runs; the regexes have no nested quantifiers. | `Redacao.test_cmdline_gigante_nao_trava` |
| **ssh option injection.** A `destino` such as `-oProxyCommand=…` turns into code execution. | A5 | `destino` must match `^(user@)?host$`, with the first character alphanumeric. `--` always precedes the host, for the hub and for collector pushes. | `Dispositivos.test_recusa_injecao_de_opcao_ssh`, `test_hub_poe_separador_antes_do_destino`, `test_coletor_recusa_destino_de_envio_malicioso` |
| **Path traversal through the device type.** `tipo = "../../x"` would pipe an arbitrary local file to a remote interpreter. | A5 | `tipo` must be the stem of an existing file in `agentes/`. | `Dispositivos.test_recusa_tipo_fora_do_registro` |
| **Hub denial of service.** An endless line, a stderr flood that blocks the pipe, thousands of interface names, or JSON nested 3000 levels deep. That last one parses fine, then crashes the state writer with `RecursionError` and takes down every tab. | A2 | Lines capped at 1 MiB (the agent is killed above it); stderr drained by a thread and only the last 800 bytes kept; at most 32 interfaces and 512 cores; samples deeper than 32 levels rejected (real data is 4–6 levels); any parse error skips the line without killing the thread. | `Hub.test_corta_linha_acima_do_teto`, `test_limita_interfaces`, `test_recusa_amostra_aninhada_que_derrubaria_a_escrita` |
| **Hostile config that crashes the hub.** | A5 | Deep TOML nesting becomes `ConfigInvalida`. Invalid entries show up as red "config: …" tabs, and the last good config stays active. | `ConfigHostil.test_aninhamento_fundo_vira_config_invalida`, `Dispositivos.*` |
| **Local information disclosure.** State files hold hostnames, process lists and account usage. | A3 | Files are created `0600` with `O_NOFOLLOW` inside `0700` directories. The units set `UMask=0077`, and collector pushes run `umask 077` on the remote side. | `Arquivos.test_estado_privado` |
| **Credential exposure.** | A3, A4 | The OAuth access token is read only to call `https://api.anthropic.com` over TLS (verified by default). It never goes into state, cache, logs or pushes. The account email is not collected. Responses are capped at 1 MiB. | review + `coletor.py --stdout` |
| **Man in the middle on ssh.** | A4 | `BatchMode=yes` and `StrictHostKeyChecking=yes`: unknown or changed host keys fail closed. | — |
| **Privilege escalation of the services.** | — | User units with `NoNewPrivileges=yes`; nothing runs as root and no port is opened. | — |

## What is still trusted

- The machines' `python3` and `ssh` binaries, and your `~/.ssh/config`.
- Redaction is best effort. It hides the common secret shapes but cannot recognise a password passed as a bare positional argument. If a machine runs tools like that, extend `SENSIVEL` / `EMBUTIDOS` in `agentes/linux.py` or write your own agent type.
- Folder names of Claude sessions and project names in the stats appear in the widget and in pushed state.
