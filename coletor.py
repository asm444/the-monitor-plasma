#!/usr/bin/python3
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monitor import claude, config, demo
from monitor.comum import gravar_privado

SAIDA = Path.home() / ".cache/the-monitor/claude.json"
DESTINO_ARQ = ".cache/the-monitor/claude.json"
INTERVALO = 5
SSH = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ControlPath=none",
       "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=yes"]


class Canal:
    REMOTO = ('umask 077; f=~/' + DESTINO_ARQ + '; mkdir -p "${f%/*}"; '
              'while IFS= read -r l; do printf "%s\\n" "$l" > "$f.tmp" && mv -f "$f.tmp" "$f"; done')

    def __init__(self, destino):
        self.destino = destino
        self.proc = None

    def enviar(self, dado):
        if self.proc is None or self.proc.poll() is not None:
            self.proc = subprocess.Popen(SSH + ["--", self.destino, self.REMOTO],
                                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
        try:
            self.proc.stdin.write(json.dumps(dado, separators=(",", ":")).encode() + b"\n")
            self.proc.stdin.flush()
            return True
        except OSError:
            self.proc.kill()
            self.proc = None
            return False


def ler_config():
    cfg = config.carregar_ou_vazio()
    destinos = [str(d) for d in (cfg.get("claude") or {}).get("enviar_para") or []]
    invalidos = [d for d in destinos if not config.DESTINO.match(d)]
    if invalidos:
        raise config.ConfigInvalida(f"claude.enviar_para inválido: {invalidos}")
    return config.contas(cfg), destinos


def main():
    uma_vez = "--uma-vez" in sys.argv
    if "--demo" in sys.argv:
        fonte = demo.Claude()
        contas, destinos = [], []
    else:
        fonte = None
        try:
            contas, destinos = ler_config()
        except (OSError, ValueError) as e:
            print(f"config ignorada: {e}", file=sys.stderr)
            contas, destinos = [], []
    est = claude.Estatisticas(contas)
    if fonte is None:
        est.start()
    canais = {}
    while True:
        if fonte is None:
            try:
                contas, destinos = ler_config()
                est.contas = contas
            except (OSError, ValueError) as e:
                print(f"config ignorada, mantendo a anterior: {e}", file=sys.stderr)
            dado = {"geradoEm": int(time.time()), "claude": [claude.usage(c) for c in contas],
                    "sessoes": claude.sessoes(contas), "estatisticas": est.saida}
        else:
            dado = fonte.amostra()
        gravar_privado(SAIDA, dado)
        if "--stdout" in sys.argv:
            print(json.dumps(dado, ensure_ascii=False, indent=1))
        for destino in destinos:
            if not canais.setdefault(destino, Canal(destino)).enviar(dado):
                print(f"envio para {destino} falhou", file=sys.stderr)
        if uma_vez:
            return
        time.sleep(INTERVALO)


if __name__ == "__main__":
    main()
