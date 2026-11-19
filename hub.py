#!/usr/bin/python3
import collections
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monitor import config
from monitor.comum import gravar_privado, ler_json, raso

HOME = Path.home()
SAIDA = HOME / ".cache/the-monitor/estado.json"
CLAUDE = HOME / ".cache/the-monitor/claude.json"
HIST = 90
HIST_NUCLEO = 40
ONLINE_S = 5
LINHA_MAX = 1 << 20
ERRO_MAX = 200
IFACES_MAX = 32
NUCLEOS_MAX = 512
SSH = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ControlPath=none",
       "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=yes"]


def drenar(fluxo, fim):
    for linha in iter(lambda: fluxo.readline(ERRO_MAX * 4), b""):
        fim.append(linha)


class Maquina(threading.Thread):
    def __init__(self, dispositivo):
        super().__init__(daemon=True)
        self.disp = dispositivo
        self.ativo = True
        self.proc = None
        self.dado = None
        self.recebido = 0.0
        self.erro = "conectando"
        self.hist = {k: collections.deque(maxlen=HIST) for k in ("cpu", "ram", "swap", "ler", "gravar")}
        self.nucleos = []
        self.rede = {}

    def comando(self):
        if self.disp.destino == "local":
            return ["/usr/bin/python3", "-I", "-u", str(self.disp.agente), self.disp.nome], False
        return SSH + ["--", self.disp.destino, f"python3 -I -u - {self.disp.nome}"], True

    def ler_linhas(self):
        while True:
            linha = self.proc.stdout.readline(LINHA_MAX + 1)
            if not linha:
                return
            if len(linha) > LINHA_MAX:
                raise ValueError(f"agente mandou linha acima de {LINHA_MAX} bytes")
            yield linha

    def run(self):
        espera = 2
        while self.ativo:
            cmd, remoto = self.comando()
            fim_erro = collections.deque(maxlen=1)
            try:
                self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE if remoto else subprocess.DEVNULL,
                                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                threading.Thread(target=drenar, args=(self.proc.stderr, fim_erro), daemon=True).start()
                if remoto:
                    self.proc.stdin.write(self.disp.agente.read_bytes())
                    self.proc.stdin.close()
                for linha in self.ler_linhas():
                    try:
                        self.registrar(json.loads(linha))
                    except Exception:
                        continue
                    espera = 2
                self.proc.wait()
                ultima = fim_erro[0].decode(errors="replace").strip() if fim_erro else ""
                self.erro = (ultima or f"agente saiu com código {self.proc.returncode}")[:ERRO_MAX]
            except (OSError, ValueError) as e:
                self.erro = f"{type(e).__name__}: {e}"[:ERRO_MAX]
                if self.proc:
                    self.proc.kill()
            if self.ativo:
                time.sleep(espera)
                espera = min(60, espera * 2)

    def registrar(self, d):
        if not raso(d):
            raise ValueError
        m = d["mem"]
        self.hist["cpu"].append(float(d["cpu"]["pct"]))
        self.hist["ram"].append(round(100 * m["usada"] / m["total"], 1))
        self.hist["swap"].append(round(100 * m["swapUsada"] / m["swapTotal"], 1) if m["swapTotal"] else 0)
        self.hist["ler"].append(sum(x["lerBs"] for x in d["discos"]))
        self.hist["gravar"].append(sum(x["gravarBs"] for x in d["discos"]))
        nucleos = d["cpu"]["nucleos"][:NUCLEOS_MAX]
        if len(self.nucleos) != len(nucleos):
            self.nucleos = [collections.deque(maxlen=HIST_NUCLEO) for _ in nucleos]
        for fila, n in zip(self.nucleos, nucleos):
            fila.append(n["pct"])
        for i in d["rede"]["ifaces"]:
            nome = str(i["nome"])[:64]
            if nome not in self.rede and len(self.rede) >= IFACES_MAX:
                continue
            par = self.rede.setdefault(nome, (collections.deque(maxlen=HIST), collections.deque(maxlen=HIST)))
            par[0].append(i["rxBs"])
            par[1].append(i["txBs"])
        self.dado, self.recebido, self.erro = d, time.time(), ""

    def parar(self):
        self.ativo = False
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()

    def estado(self, agora):
        online = agora - self.recebido <= ONLINE_S
        return {"nome": self.disp.nome, "destino": self.disp.destino, "online": online,
                "recebidoEm": int(self.recebido), "erro": "" if online else self.erro or "sem dado novo",
                "dado": self.dado,
                "hist": {k: list(v) for k, v in self.hist.items()},
                "histNucleos": [list(f) for f in self.nucleos],
                "histRede": {k: {"rx": list(rx), "tx": list(tx)} for k, (rx, tx) in self.rede.items()}}


def ler_config():
    try:
        return config.dispositivos(config.carregar_ou_vazio())
    except (OSError, ValueError) as e:
        print(f"config ignorada: {e}", file=sys.stderr)
        return None


def main():
    maquinas, ordem, erros, marca = {}, [], [], None
    while True:
        try:
            atual = config.ARQUIVO.stat().st_mtime
        except FileNotFoundError:
            atual = 0
        if atual != marca:
            marca = atual
            lido = ler_config()
            if lido is not None:
                ordem, erros = lido
                for d in [d for d in maquinas if d not in ordem]:
                    maquinas.pop(d).parar()
                for d in ordem:
                    if d not in maquinas:
                        maquinas[d] = Maquina(d)
                        maquinas[d].start()
        agora = time.time()
        claude = ler_json(CLAUDE)
        estado = {"geradoEm": int(agora),
                  "hosts": [maquinas[d].estado(agora) for d in ordem]
                  + [{"nome": n, "destino": "", "online": False, "recebidoEm": 0, "erro": f"config: {e}", "dado": None,
                      "hist": {k: [] for k in ("cpu", "ram", "swap", "ler", "gravar")}, "histNucleos": [], "histRede": {}}
                     for n, e in erros],
                  "claude": claude or None}
        gravar_privado(SAIDA, estado)
        time.sleep(1)


if __name__ == "__main__":
    main()
