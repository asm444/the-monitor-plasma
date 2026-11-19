import json
import os

PROFUNDIDADE_MAX = 32


def raso(valor):
    pilha = [(valor, 1)]
    while pilha:
        v, nivel = pilha.pop()
        if nivel > PROFUNDIDADE_MAX:
            return False
        if isinstance(v, dict):
            pilha.extend((x, nivel + 1) for x in v.values())
        elif isinstance(v, list):
            pilha.extend((x, nivel + 1) for x in v)
    return True


def ler_json(caminho):
    try:
        dado = json.loads(caminho.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return dado if raso(dado) else {}


def gravar_privado(caminho, dado):
    caminho.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = caminho.with_name(f"{caminho.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(dado, f, separators=(",", ":"))
    os.chmod(tmp, 0o600)
    os.replace(tmp, caminho)
