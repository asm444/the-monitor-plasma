#!/usr/bin/python3
import fcntl
import json
import os
import pwd
import re
import socket
import struct
import sys
import time
from pathlib import Path

TICK = 1.0
FS_REAIS = {"ext2", "ext3", "ext4", "xfs", "btrfs", "vfat", "f2fs", "exfat", "ntfs", "ntfs3", "zfs", "bcachefs"}
VIRTUAIS = ("lo", "docker", "br-", "veth", "virbr", "vboxnet", "vnet", "tun", "tap", "wg", "tailscale", "zt")
CPU_PRINCIPAL = [("k10temp", "Tctl"), ("k10temp", "Tdie"), ("zenpower", "Tdie"), ("coretemp", "Package id 0"),
                 ("cpu_thermal", "temp1"), ("acpitz", "temp1")]
FABRICANTES = {"0x1002": "AMD", "0x8086": "Intel", "0x10de": "NVIDIA"}
TOP_PROCS = 25
CMD_BRUTO_MAX = 4096
OCULTO = "***"
SENSIVEL = re.compile(r"(?i)pass|pwd|secret|token|key|auth|credential|cookie|signature|bearer")
FLAG_COM_VALOR = re.compile(r"^(-{1,2}[^=\s]+)=(.*)$", re.S)
ATRIBUICAO = re.compile(r"^([A-Za-z_][\w.-]*)=(.*)$", re.S)
EMBUTIDOS = [
    (re.compile(r"(?i)\b(bearer|basic|token)(\s+|:)[A-Za-z0-9._~+/=-]{8,}"), r"\1\2" + OCULTO),
    (re.compile(r"(://[^/\s:@]+:)[^@\s/]+@"), r"\1" + OCULTO + "@"),
    (re.compile(r"(?i)\b(?:sk-ant-[\w-]+|gh[opsur]_[A-Za-z0-9]{20,}|github_pat_\w+|xox[abposr]-[\w-]+|AKIA[0-9A-Z]{16}"
                r"|AIza[\w-]{30,}|eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]+)"), OCULTO),
    (re.compile(r"(?i)([?&][^=&\s]*(?:pass|pwd|secret|token|key|auth|sig)[^=&\s]*=)[^&\s]+"), r"\1" + OCULTO),
]
SENHA_COLADA = {"mysql", "mariadb", "mysqldump", "mariadb-dump", "mysqladmin", "mariadb-admin"}


def ler(caminho, padrao=""):
    try:
        with open(caminho) as f:
            return f.read()
    except OSError:
        return padrao


def ler_int(caminho):
    try:
        return int(ler(caminho).strip())
    except ValueError:
        return None


def estatico():
    distro = ""
    for linha in ler("/etc/os-release").splitlines():
        if linha.startswith("PRETTY_NAME="):
            distro = linha.split("=", 1)[1].strip('"')
    modelo = ""
    for linha in ler("/proc/cpuinfo").splitlines():
        if linha.startswith("model name"):
            modelo = linha.split(":", 1)[1].strip()
            break
    return {"host": socket.gethostname(), "kernel": os.uname().release, "distro": distro,
            "cpuModelo": modelo, "nucleos": os.cpu_count()}


def mapa_sensores():
    lista = []
    for h in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        nome = ler(h / "name").strip()
        for entrada in sorted(h.glob("temp*_input")):
            base = entrada.name[:-len("_input")]
            rotulo = ler(h / (base + "_label")).strip() or base
            lista.append((nome, rotulo, str(entrada), ler_int(h / (base + "_crit"))))
    return lista


def nucleo_fisico(i):
    return ler_int(f"/sys/devices/system/cpu/cpu{i}/topology/core_id")


def embutidos(texto):
    for padrao, troca in EMBUTIDOS:
        texto = padrao.sub(troca, texto)
    return texto


def redigir(argv):
    saida, ocultar_proximo = [], False
    programa = os.path.basename(argv[0]) if argv else ""
    for arg in argv:
        ocultar, ocultar_proximo = ocultar_proximo, False
        if ocultar and not arg.startswith("-"):
            saida.append(OCULTO)
            continue
        if " " in arg.strip():
            saida.append(embutidos(redigir(arg.split())))
            continue
        if arg.endswith(":") and SENSIVEL.search(arg):
            saida += [arg, OCULTO]
            break
        m = FLAG_COM_VALOR.match(arg) or ATRIBUICAO.match(arg)
        if programa in SENHA_COLADA and arg.startswith("-p") and len(arg) > 2:
            arg = "-p" + OCULTO
        elif m and SENSIVEL.search(m.group(1)):
            arg = f"{m.group(1)}={OCULTO}"
        elif arg.startswith("-") and SENSIVEL.search(arg):
            ocultar_proximo = True
        saida.append(embutidos(arg))
    return " ".join(saida)


class Agente:
    def __init__(self):
        self.info = estatico()
        self.sensores = mapa_sensores()
        self.ncpu = self.info["nucleos"]
        self.fisico = [nucleo_fisico(i) for i in range(self.ncpu)]
        self.clk = os.sysconf("SC_CLK_TCK")
        self.pagina = os.sysconf("SC_PAGE_SIZE")
        self.usuarios = {}
        self.t_ant = time.monotonic()
        self.cpu_ant = self._cpu()
        self.proc_ant = self._procs()
        self.disco_ant = self._diskstats()
        self.rede_ant = self._rede()

    @staticmethod
    def _cpu():
        saida = {}
        for linha in ler("/proc/stat").splitlines():
            if not linha.startswith("cpu"):
                break
            partes = linha.split()
            campos = [int(x) for x in partes[1:]]
            saida[partes[0]] = (sum(campos[:8]), campos[3] + campos[4])
        return saida

    @staticmethod
    def _procs():
        tabela = {}
        for nome in os.listdir("/proc"):
            if not nome.isdigit():
                continue
            try:
                with open(f"/proc/{nome}/stat") as f:
                    bruto = f.read()
                uid = os.stat(f"/proc/{nome}").st_uid
            except OSError:
                continue
            fim = bruto.rfind(")")
            r = bruto[fim + 2:].split()
            tabela[int(nome)] = (bruto[bruto.find("(") + 1:fim], r[0], int(r[11]) + int(r[12]),
                                 int(r[17]), int(r[21]), uid, r[19])
        return tabela

    @staticmethod
    def _diskstats():
        saida = {}
        for linha in ler("/proc/diskstats").splitlines():
            c = linha.split()
            if len(c) >= 10:
                saida[c[2]] = (int(c[5]) * 512, int(c[9]) * 512)
        return saida

    @staticmethod
    def _rede():
        saida = {}
        for linha in ler("/proc/net/dev").splitlines()[2:]:
            nome, resto = linha.split(":", 1)
            c = resto.split()
            saida[nome.strip()] = (int(c[0]), int(c[8]))
        return saida

    def _usuario(self, uid):
        if uid not in self.usuarios:
            try:
                self.usuarios[uid] = pwd.getpwuid(uid).pw_name
            except KeyError:
                self.usuarios[uid] = str(uid)
        return self.usuarios[uid]

    def cpu(self, dt):
        atual = self._cpu()
        pct = {}
        for chave, (total, ocioso) in atual.items():
            ant = self.cpu_ant.get(chave)
            dtot = total - ant[0] if ant else 0
            pct[chave] = round(100.0 * (1 - (ocioso - ant[1]) / dtot), 1) if dtot > 0 else 0.0
        self.cpu_ant = atual
        temps = {}
        for nome, rotulo, entrada, _ in self.sensores:
            v = ler_int(entrada)
            if v is not None:
                temps[(nome, rotulo)] = v / 1000
        principal, critico = None, None
        for chave in CPU_PRINCIPAL:
            if chave in temps:
                principal = temps[chave]
                critico = next((c for n, r, _, c in self.sensores if (n, r) == chave), None)
                break
        por_nucleo = {int(r.split()[1]): v for (n, r), v in temps.items() if n == "coretemp" and r.startswith("Core ")}
        nucleos = []
        for i in range(self.ncpu):
            freq = ler_int(f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq")
            nucleos.append({"pct": pct.get(f"cpu{i}", 0.0),
                            "mhz": freq // 1000 if freq else None,
                            "temp": por_nucleo.get(self.fisico[i])})
        freqs = [n["mhz"] for n in nucleos if n["mhz"]]
        outros = [{"nome": f"{n} {r}", "c": round(v, 1)} for (n, r), v in temps.items()
                  if (n, r) not in CPU_PRINCIPAL and not (n == "coretemp" and r.startswith("Core "))]
        return {"pct": pct.get("cpu", 0.0), "nucleos": nucleos,
                "mhzMedio": round(sum(freqs) / len(freqs)) if freqs else None,
                "temp": round(principal, 1) if principal is not None else None,
                "tempCrit": critico / 1000 if critico else 95,
                "carga": [round(x, 2) for x in os.getloadavg()], "sensores": outros}

    def memoria(self):
        m = {}
        for linha in ler("/proc/meminfo").splitlines():
            k, v = linha.split(":")
            m[k] = int(v.split()[0]) * 1024
        return {"total": m["MemTotal"], "usada": m["MemTotal"] - m["MemAvailable"], "disponivel": m["MemAvailable"],
                "cache": m.get("Cached", 0) + m.get("SReclaimable", 0) - m.get("Shmem", 0),
                "livre": m["MemFree"], "swapTotal": m["SwapTotal"], "swapUsada": m["SwapTotal"] - m["SwapFree"]}

    def discos(self, dt):
        atual = self._diskstats()
        vistos, saida = set(), []
        for linha in ler("/proc/mounts").splitlines():
            dev, ponto, fs = linha.split()[:3]
            ponto = ponto.replace("\\040", " ")
            if fs not in FS_REAIS and not (fs == "tmpfs" and ponto == "/tmp"):
                continue
            chave = dev if fs != "tmpfs" else ponto
            if chave in vistos:
                continue
            vistos.add(chave)
            try:
                st = os.statvfs(ponto)
            except OSError:
                continue
            nome_dev = os.path.basename(os.path.realpath(dev)) if dev.startswith("/dev/") else ""
            ler_bs = gravar_bs = 0
            if nome_dev in atual and nome_dev in self.disco_ant:
                ler_bs = max(0, atual[nome_dev][0] - self.disco_ant[nome_dev][0]) / dt
                gravar_bs = max(0, atual[nome_dev][1] - self.disco_ant[nome_dev][1]) / dt
            saida.append({"ponto": ponto, "fs": fs,
                          "total": st.f_blocks * st.f_frsize, "usado": (st.f_blocks - st.f_bfree) * st.f_frsize,
                          "lerBs": round(ler_bs), "gravarBs": round(gravar_bs)})
        self.disco_ant = atual
        return saida

    @staticmethod
    def _ip(iface):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                return socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, struct.pack("256s", iface[:15].encode()))[20:24])
        except OSError:
            return ""

    def rede(self, dt):
        atual = self._rede()
        padrao = ""
        for linha in ler("/proc/net/route").splitlines()[1:]:
            c = linha.split()
            if len(c) > 1 and c[1] == "00000000":
                padrao = c[0]
                break
        ifaces = []
        for nome, (rx, tx) in atual.items():
            if nome == "lo":
                continue
            ant = self.rede_ant.get(nome, (rx, tx))
            ifaces.append({"nome": nome, "virtual": nome.startswith(VIRTUAIS), "ip": self._ip(nome),
                           "rxBs": round(max(0, rx - ant[0]) / dt), "txBs": round(max(0, tx - ant[1]) / dt),
                           "rxTotal": rx, "txTotal": tx})
        self.rede_ant = atual
        return {"padrao": padrao, "ifaces": ifaces}

    def processos(self, dt):
        atual = self._procs()
        lista, threads, rodando = [], 0, 0
        for pid, (comm, est, ticks, thr, rss, uid, inicio) in atual.items():
            threads += thr
            rodando += est == "R"
            ant = self.proc_ant.get(pid)
            cpu = 100.0 * (ticks - ant[2]) / self.clk / dt / self.ncpu if ant and ant[6] == inicio else 0.0
            lista.append((pid, comm, est, thr, rss * self.pagina, uid, max(0.0, cpu)))
        self.proc_ant = atual
        escolhidos = {p[0]: p for p in sorted(lista, key=lambda p: -p[6])[:TOP_PROCS]}
        escolhidos.update({p[0]: p for p in sorted(lista, key=lambda p: -p[4])[:TOP_PROCS]})
        top = []
        for pid, comm, est, thr, mem, uid, cpu in escolhidos.values():
            cmd = redigir([a for a in ler(f"/proc/{pid}/cmdline")[:CMD_BRUTO_MAX].split("\0") if a])
            top.append({"pid": pid, "nome": comm, "estado": est, "threads": thr, "mem": mem,
                        "usuario": self._usuario(uid), "cpu": round(cpu, 1), "cmd": cmd[:240] or f"[{comm}]"})
        return {"total": len(lista), "threads": threads, "rodando": rodando, "lista": top}

    @staticmethod
    def baterias():
        saida = []
        for b in sorted(Path("/sys/class/power_supply").glob("BAT*")):
            pot = ler_int(b / "power_now")
            volt = ler_int(b / "voltage_now")
            if pot is None and volt:
                corrente = ler_int(b / "current_now")
                pot = corrente * volt // 10**6 if corrente is not None else None
            agora = ler_int(b / "energy_now")
            cheio = ler_int(b / "energy_full")
            if agora is None and volt:
                carga, carga_cheia = ler_int(b / "charge_now"), ler_int(b / "charge_full")
                agora = carga * volt // 10**6 if carga is not None else None
                cheio = carga_cheia * volt // 10**6 if carga_cheia is not None else None
            status = ler(b / "status").strip()
            restante = None
            if pot and agora is not None:
                if status == "Discharging":
                    restante = round(3600 * agora / pot)
                elif status == "Charging" and cheio:
                    restante = round(3600 * max(0, cheio - agora) / pot)
            saida.append({"nome": b.name, "pct": ler_int(b / "capacity"), "status": status,
                          "watts": round(pot / 10**6, 1) if pot else None, "restanteS": restante})
        return saida

    @staticmethod
    def gpus():
        saida = []
        for card in sorted(Path("/sys/class/drm").glob("card[0-9]")):
            dev = card / "device"
            fab = ler(dev / "vendor").strip()
            if not fab:
                continue
            temp = None
            for t in dev.glob("hwmon/hwmon*/temp1_input"):
                temp = (ler_int(t) or 0) / 1000
            saida.append({"nome": FABRICANTES.get(fab, fab) + " " + card.name, "uso": ler_int(dev / "gpu_busy_percent"),
                          "vramUsada": ler_int(dev / "mem_info_vram_used"), "vramTotal": ler_int(dev / "mem_info_vram_total"),
                          "mhz": ler_int(card / "gt_cur_freq_mhz"), "mhzMax": ler_int(card / "gt_max_freq_mhz"),
                          "temp": temp})
        return saida

    def amostra(self):
        t = time.monotonic()
        dt = max(t - self.t_ant, 1e-3)
        self.t_ant = t
        return {**self.info, "geradoEm": int(time.time()),
                "uptime": int(float(ler("/proc/uptime").split()[0])),
                "cpu": self.cpu(dt), "mem": self.memoria(), "discos": self.discos(dt), "rede": self.rede(dt),
                "procs": self.processos(dt), "baterias": self.baterias(), "gpus": self.gpus()}


def main():
    agente = Agente()
    while True:
        time.sleep(TICK)
        sys.stdout.write(json.dumps(agente.amostra(), separators=(",", ":")) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
