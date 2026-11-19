#!/usr/bin/python3
import json
import math
import random
import sys
import time

NOME = sys.argv[1] if len(sys.argv) > 1 else "demo"
rnd = random.Random(NOME)
NUCLEOS = rnd.choice([4, 8, 12, 16])
RAM = rnd.choice([8, 16, 32, 64]) * 2**30
PROGRAMAS = ["postgres", "nginx", "python3", "node", "firefox", "plasmashell", "kwin_wayland", "sshd", "redis-server",
             "code", "java", "ollama"]
COMANDOS = {"postgres": "postgres -D /var/lib/pgsql/data", "python3": "python3 -m http.server 8080",
            "node": "node server.js --port 3000 --token ***", "java": "java -Xmx2g -jar app.jar",
            "redis-server": "redis-server *:6379", "ollama": "ollama serve"}


def onda(t, periodo, base, amplitude, fase=0.0):
    return max(0.0, min(100.0, base + amplitude * math.sin(2 * math.pi * t / periodo + fase) + rnd.uniform(-4, 4)))


def amostra(t, inicio):
    carga = onda(t, 90, 35, 25)
    usada = int(RAM * onda(t, 300, 55, 15) / 100)
    nucleos = [{"pct": round(onda(t, 60 + i * 7, carga, 20, i), 1), "mhz": rnd.randint(1800, 4800),
                "temp": round(45 + carga / 3 + rnd.uniform(-2, 2), 1)} for i in range(NUCLEOS)]
    procs = []
    for pid, nome in enumerate(PROGRAMAS, start=1000):
        procs.append({"pid": pid, "nome": nome, "estado": "S", "threads": rnd.randint(1, 40),
                      "mem": rnd.randint(20, 900) * 2**20, "usuario": "demo", "cpu": round(rnd.uniform(0, carga / 3), 1),
                      "cmd": COMANDOS.get(nome, "/usr/bin/" + nome)})
    return {
        "host": NOME, "kernel": "6.12.0-demo", "distro": "Demo Linux 1.0", "cpuModelo": "Demo CPU @ 3.6GHz",
        "nucleos": NUCLEOS, "geradoEm": int(t), "uptime": int(t - inicio) + 86400 * 3,
        "cpu": {"pct": round(carga, 1), "nucleos": nucleos, "mhzMedio": 3400, "temp": round(50 + carga / 3, 1),
                "tempCrit": 95, "carga": [round(carga / 25, 2)] * 3, "sensores": [{"nome": "nvme Composite", "c": 41.0}]},
        "mem": {"total": RAM, "usada": usada, "disponivel": RAM - usada, "cache": RAM // 5, "livre": RAM // 10,
                "swapTotal": 8 * 2**30, "swapUsada": int(8 * 2**30 * onda(t, 600, 10, 8) / 100)},
        "discos": [{"ponto": "/", "fs": "btrfs", "total": 512 * 10**9, "usado": 301 * 10**9,
                    "lerBs": int(onda(t, 40, 20, 20) * 2**20 / 10), "gravarBs": int(onda(t, 70, 15, 15) * 2**20 / 10)}],
        "rede": {"padrao": "eth0", "ifaces": [
            {"nome": "eth0", "virtual": False, "ip": "192.0.2.10", "rxBs": int(onda(t, 30, 30, 25) * 20000),
             "txBs": int(onda(t, 45, 20, 15) * 8000), "rxTotal": int(t) * 1000, "txTotal": int(t) * 400}]},
        "procs": {"total": 312, "threads": 1890, "rodando": 2, "lista": procs},
        "baterias": [], "gpus": [],
    }


def main():
    inicio = time.time()
    while True:
        time.sleep(1)
        sys.stdout.write(json.dumps(amostra(time.time(), inicio), separators=(",", ":")) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
