import os
import re
import socket
import tomllib
from dataclasses import dataclass
from pathlib import Path

HOME = Path.home()
ARQUIVO = Path(os.environ.get("THE_MONITOR_CONFIG") or HOME / ".config/the-monitor/config.toml")
AGENTES = Path(__file__).resolve().parent.parent / "agentes"
NOME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$")
DESTINO = re.compile(r"^(?:[A-Za-z0-9_][A-Za-z0-9._-]{0,31}@)?[A-Za-z0-9_][A-Za-z0-9._:-]{0,252}$")


class ConfigInvalida(ValueError):
    pass


@dataclass(frozen=True)
class Dispositivo:
    nome: str
    destino: str
    tipo: str

    @property
    def agente(self):
        return AGENTES / f"{self.tipo}.py"


@dataclass(frozen=True)
class Conta:
    nome: str
    dir: Path
    cor: int
    comando: str


def carregar():
    with open(ARQUIVO, "rb") as f:
        return tomllib.load(f)


def carregar_ou_vazio():
    try:
        return carregar()
    except FileNotFoundError:
        return {}
    except RecursionError:
        raise ConfigInvalida("config.toml aninhado demais")


def dispositivos(cfg):
    brutos = cfg.get("dispositivo")
    if brutos is None:
        brutos = [{"nome": socket.gethostname().split(".")[0], "destino": "local"}]
    if not isinstance(brutos, list):
        raise ConfigInvalida("[[dispositivo]] precisa ser lista de tabelas")
    tipos = {p.stem for p in AGENTES.glob("*.py") if NOME.match(p.stem)}
    validos, erros, nomes = [], [], set()
    for i, d in enumerate(brutos):
        if not isinstance(d, dict):
            erros.append((f"#{i + 1}", "entrada não é tabela"))
            continue
        nome, destino, tipo = (str(d.get(k, padrao)) for k, padrao in (("nome", ""), ("destino", ""), ("tipo", "linux")))
        if not NOME.match(nome):
            erros.append((f"#{i + 1}", "nome inválido: use letras, números, . _ - (até 32)"))
        elif nome in nomes:
            erros.append((nome, "nome repetido"))
        elif destino != "local" and not DESTINO.match(destino):
            erros.append((nome, "destino inválido: use local, alias do ssh ou usuario@host"))
        elif tipo not in tipos:
            erros.append((nome, f"tipo desconhecido; disponíveis: {', '.join(sorted(tipos))}"))
        else:
            nomes.add(nome)
            validos.append(Dispositivo(nome, destino, tipo))
    return validos, erros


def contas(cfg):
    sec = cfg.get("claude") or {}
    achadas = {}
    if sec.get("descobrir", True):
        for d in [HOME / ".claude", *sorted(HOME.glob(".claude-*"))]:
            if d.is_dir() and (d / ".credentials.json").is_file():
                nome = "claude" if d.name == ".claude" else d.name.removeprefix(".claude-")
                achadas[d.resolve()] = {"nome": nome, "dir": d}
    for c in sec.get("conta") or []:
        if not isinstance(c, dict) or not c.get("dir"):
            raise ConfigInvalida("[[claude.conta]] exige dir")
        d = Path(os.path.expanduser(str(c["dir"])))
        if not d.is_absolute():
            raise ConfigInvalida(f"[[claude.conta]] dir precisa ser absoluto: {c['dir']}")
        chave = d.resolve()
        if c.get("ignorar"):
            achadas.pop(chave, None)
            continue
        atual = achadas.setdefault(chave, {"nome": d.name.removeprefix(".claude-").lstrip("."), "dir": d})
        atual.update({k: c[k] for k in ("nome", "cor", "comando") if k in c})
    saida, nomes = [], set()
    for i, c in enumerate(sorted(achadas.values(), key=lambda c: str(c["nome"]))):
        nome = str(c["nome"])
        if not NOME.match(nome) or nome in nomes:
            raise ConfigInvalida(f"conta com nome inválido ou repetido: {nome!r}")
        nomes.add(nome)
        cor = c.get("cor", i)
        saida.append(Conta(nome, c["dir"], cor if isinstance(cor, int) and cor >= 0 else i,
                           str(c.get("comando") or f"claude-{nome}")))
    return saida
