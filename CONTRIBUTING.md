# Contributing

Thanks for wanting to help! Any contribution counts: an idea in an issue, a bug report with the output of `journalctl --user -u the-monitor`, a new device type, or a translation.

## Good first contributions

- **A new device type.** Copy `agentes/demo.py`, make it print the same JSON shape from real data (macOS `sysctl`/`vm_stat`, a router API, `docker stats`…), and add a test that feeds one sample to `hub.Maquina.registrar`.
- **Widget translation.** The UI strings in `the-monitor/contents/ui/main.qml` are in Portuguese. Moving them to `i18n()` with an English catalogue would help most users.
- **More secret shapes for redaction.** Add the case to `Redacao.casos_ocultos` first, watch it fail, then extend `agentes/linux.py`.

## Ground rules

- **Standard library only.** Agents run on machines you do not control, piped over ssh, so they cannot import third-party packages. The hub and the collector follow the same rule.
- **Every security-relevant change brings a test that fails without it.** State the attacker and the vector in the PR, using the format of [SECURITY.md](SECURITY.md).
- **Anything that reaches the widget is untrusted text.** New labels must use `textFormat: Text.PlainText`; the test suite enforces it.
- Run `python3 -m unittest discover -s tests` and `ruff check .` before opening the PR. CI runs both.
- Demo data only in screenshots and fixtures. Never commit real hostnames, IPs, emails or tokens; use `example.net`, `192.0.2.0/24` and obviously fake secrets.

## Reporting security issues

Privately, as described in [SECURITY.md](SECURITY.md).
