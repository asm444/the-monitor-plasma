import bisect
import collections
import datetime
import json
import os
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from monitor.comum import gravar_privado, ler_json

HOME = Path.home()
ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
INTERVALO_USAGE = 30
INTERVALO_GLOBAL = 10
RECUO_MIN = 60
RECUO_MAX = 300
VALIDADE_USAGE = 600
RESPOSTA_MAX = 1 << 20
OMARCHY = HOME / ".cache/omarchy/agent-usage/claude-limits.json"
ROTULOS_OMARCHY = {"Session (5-hour)": "Sessão 5h", "Weekly (7-day)": "Semanal"}
INTERVALO_STATS = 60
DIAS_SERIE = 14
JANELAS = {
    "five_hour": "Sessão 5h",
    "seven_day": "Semanal",
    "seven_day_opus": "Semanal Opus",
    "seven_day_sonnet": "Semanal Sonnet",
    "seven_day_oauth_apps": "Semanal apps",
}
_ultima_consulta = 0.0


def consultar(token):
    req = urllib.request.Request(ENDPOINT, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            corpo = r.read(RESPOSTA_MAX + 1)
            if len(corpo) > RESPOSTA_MAX:
                return None, "resposta acima do teto", 0
            return json.loads(corpo.decode()), None, 0
    except urllib.error.HTTPError as e:
        espera = 0
        try:
            espera = int(e.headers.get("retry-after") or 0)
        except ValueError:
            pass
        return None, f"HTTP {e.code}", espera
    except Exception as e:
        return None, f"sem rede: {type(e).__name__}", 0


def janelas(payload):
    saida = []
    for chave, rotulo in JANELAS.items():
        b = payload.get(chave)
        if isinstance(b, dict) and b.get("utilization") is not None:
            saida.append({"rotulo": rotulo, "pct": float(b["utilization"]), "reseta": b.get("resets_at") or ""})
    for item in payload.get("limits") or []:
        if not isinstance(item, dict) or item.get("percent") is None or not item.get("scope"):
            continue
        modelo = (item["scope"].get("model") or {}).get("display_name") or "escopo"
        grupo = "Semanal" if item.get("group") == "weekly" else "Sessão 5h" if item.get("group") == "five_hour" else item.get("group") or ""
        saida.append({"rotulo": f"{grupo} {modelo}".strip(), "pct": float(item["percent"]),
                      "reseta": item.get("resets_at") or ""})
    extra = payload.get("extra_usage")
    if isinstance(extra, dict) and extra.get("is_enabled") and extra.get("utilization") is not None:
        saida.append({"rotulo": "Extra mensal", "pct": float(extra["utilization"]), "reseta": ""})
    return saida


def janelas_omarchy(limits):
    saida = []
    for item in limits:
        if not isinstance(item, dict) or item.get("percent") is None:
            continue
        rotulo = str(item.get("title") or item.get("label") or "")
        if rotulo.endswith(" Weekly"):
            rotulo = "Semanal " + rotulo.removesuffix(" Weekly")
        rotulo = ROTULOS_OMARCHY.get(rotulo, rotulo)
        saida.append({"rotulo": rotulo, "pct": round(100 * float(item["percent"]), 1), "reseta": item.get("resetsAt") or ""})
    return saida


def usage(conta):
    global _ultima_consulta
    agora = time.time()
    cred = ler_json(conta.dir / ".credentials.json").get("claudeAiOauth") or {}
    expira = (cred.get("expiresAt") or 0) / 1000
    base = {
        "perfil": conta.nome,
        "cor": conta.cor,
        "plano": cred.get("rateLimitTier") or cred.get("subscriptionType") or "",
    }
    token = cred.get("accessToken")
    if not token:
        return {**base, "estado": "sem login", "janelas": [], "consultadoEm": 0}

    cache_arq = conta.dir / "the-monitor-usage-cache.json"
    cache = ler_json(cache_arq)
    externo = ler_json(OMARCHY) if conta.dir.resolve() == (HOME / ".claude").resolve() else {}
    externo_em = (externo.get("fetchedAtMs") or 0) / 1000
    erro = cache.get("erro")
    pode = (agora - max(cache.get("attemptedAt", 0), externo_em) >= INTERVALO_USAGE
            and agora >= cache.get("esperaAte", 0)
            and agora - _ultima_consulta >= INTERVALO_GLOBAL)
    if pode and expira > agora:
        _ultima_consulta = agora
        cache["attemptedAt"] = agora
        payload, erro, espera = consultar(token)
        if payload is not None:
            cache["payload"], cache["fetchedAt"], erro = payload, agora, ""
            cache["recuo"] = 0
        elif erro == "HTTP 429":
            recuo = min(RECUO_MAX, espera or max(RECUO_MIN, 2 * cache.get("recuo", 0)))
            cache["recuo"] = recuo
            espera = recuo
        cache["erro"] = erro
        cache["esperaAte"] = agora + espera
        try:
            gravar_privado(cache_arq, cache)
        except OSError as e:
            erro = f"cache: {type(e).__name__}"

    proprio_em = cache.get("fetchedAt", 0)
    if externo_em > proprio_em:
        consultado_em, lista = externo_em, janelas_omarchy(externo.get("limits") or [])
    else:
        consultado_em, lista = proprio_em, janelas(cache.get("payload") or {})
    if expira <= agora:
        erro = "token expirado: abra " + conta.comando
    elif agora - consultado_em <= VALIDADE_USAGE:
        erro = ""
    else:
        erro = f"sem dado novo há {int((agora - consultado_em) // 60)}min" + (f" ({erro})" if erro else "")
    return {**base, "estado": erro or "ok", "janelas": lista, "consultadoEm": int(consultado_em)}


def ler_texto(caminho):
    try:
        return caminho.read_text()
    except OSError:
        return ""


def sessoes(contas):
    por_dir = {c.dir.resolve(): c.nome for c in contas}
    padrao = (HOME / ".claude").resolve()
    vistas, saida = set(), []
    for p in Path("/proc").iterdir():
        try:
            if (p / "comm").read_text().strip() != "claude":
                continue
            aba = (p / "cgroup").read_text().strip().split("::", 1)[-1]
            ambiente = (p / "environ").read_bytes().split(b"\0")
            pasta = os.path.basename(os.readlink(p / "cwd"))
        except OSError:
            continue
        if aba in vistas:
            continue
        vistas.add(aba)
        config = next((v.split(b"=", 1)[1].decode(errors="replace") for v in ambiente
                       if v.startswith(b"CLAUDE_CONFIG_DIR=")), "")
        dono = Path(os.path.expanduser(config)).resolve() if config else padrao
        base = Path("/sys/fs/cgroup" + aba)
        uso = sum(int(ler_texto(base / f) or 0) for f in ("memory.current", "memory.swap.current"))
        saida.append({"pid": int(p.name), "perfil": por_dir.get(dono, "?"), "pasta": pasta, "usoMiB": uso >> 20})
    return sorted(saida, key=lambda s: -s["usoMiB"])


def epoch(ts):
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def nome_modelo(m):
    partes = [p for p in m.split("-") if p != "claude" and not (p.isdigit() and len(p) == 8)]
    return (partes[0] + " " + ".".join(partes[1:])).strip() if partes else m


def somar(alvo, *valores):
    for k, v in enumerate(valores):
        alvo[k] += v


def lista_modelos(modelos):
    return [{"nome": m, "msgs": v[0], "entrada": v[1], "saida": v[2], "cache": v[3]}
            for m, v in sorted(modelos.items(), key=lambda x: -x[1][2])[:5] if v[0]]


def janela_vazia():
    return {"msgs": 0, "tools": 0, "entrada": 0, "saida": 0, "cache": 0, "prompts": 0, "sessoes": set()}


class Estatisticas(threading.Thread):
    def __init__(self, contas):
        super().__init__(daemon=True)
        self.contas = contas
        self.arquivos = {}
        self.saida = None

    def run(self):
        while True:
            try:
                self.saida = self.calcular()
            except OSError as e:
                self.saida = {"geradoEm": int(time.time()), "erro": f"{type(e).__name__}: {e}"[:200], "perfis": {}}
            time.sleep(INTERVALO_STATS)

    def raizes(self):
        vistas = {}
        for c in self.contas:
            raiz = (c.dir / "projects").resolve()
            if raiz.is_dir():
                vistas.setdefault(raiz, None)
        return list(vistas)

    @staticmethod
    def ler_arquivo(caminho, raiz):
        sid = caminho.stem if caminho.parent.parent == raiz else caminho.parent.parent.name
        horas, vistos, pasta = {}, set(), ""
        try:
            with open(caminho, "rb") as f:
                for linha in f:
                    if b'"assistant"' not in linha:
                        continue
                    try:
                        d = json.loads(linha)
                    except ValueError:
                        continue
                    m = d.get("message")
                    t = epoch(d.get("timestamp"))
                    if d.get("type") != "assistant" or not isinstance(m, dict) or t is None or m.get("model") == "<synthetic>":
                        continue
                    pasta = pasta or os.path.basename(d.get("cwd") or "")
                    b = horas.setdefault(int(t // 3600), [0, 0, 0, 0, 0, {}])
                    b[1] += sum(1 for c in m.get("content") or [] if isinstance(c, dict) and c.get("type") == "tool_use")
                    if m.get("id") in vistos:
                        continue
                    vistos.add(m.get("id"))
                    u = m.get("usage") or {}
                    valores = (1, 0, (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0),
                               u.get("output_tokens") or 0, u.get("cache_read_input_tokens") or 0)
                    for k in (0, 2, 3, 4):
                        b[k] += valores[k]
                    somar(b[5].setdefault(nome_modelo(m.get("model") or "?"), [0, 0, 0, 0]), valores[0], *valores[2:])
        except OSError:
            pass
        return sid, pasta, horas

    def historico(self):
        linhas, prompts = {}, {c.nome: [] for c in self.contas}
        for c in self.contas:
            try:
                texto = (c.dir / "history.jsonl").read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for linha in texto.splitlines():
                try:
                    h = json.loads(linha)
                    ts = h["timestamp"] / 1000
                except (ValueError, KeyError, TypeError):
                    continue
                prompts[c.nome].append(ts)
                if h.get("sessionId"):
                    linhas.setdefault(h["sessionId"], []).append((ts, c.nome))
        for lista in linhas.values():
            lista.sort()
        return linhas, prompts

    def calcular(self):
        vivos = {}
        for raiz in self.raizes():
            for caminho in raiz.glob("**/*.jsonl"):
                try:
                    st = caminho.stat()
                except OSError:
                    continue
                chave = (st.st_size, st.st_mtime_ns)
                antigo = self.arquivos.get(caminho)
                vivos[caminho] = antigo if antigo and antigo[0] == chave else (chave, *self.ler_arquivo(caminho, raiz))
        self.arquivos = vivos
        linhas, prompts = self.historico()

        agora = time.time()
        hoje = datetime.datetime.combine(datetime.date.today(), datetime.time()).timestamp()
        semana = agora - 7 * 86400
        dias = [datetime.date.today() - datetime.timedelta(days=i) for i in range(DIAS_SERIE - 1, -1, -1)]
        perfis = {c.nome: {"hoje": janela_vazia(), "semana": janela_vazia(), "total": janela_vazia(),
                           "dias": {d: [0, 0] for d in dias}, "horas": [0] * 24, "modelos": {}, "modelosHoje": {},
                           "projetos": collections.Counter(), "desde": 0, "ultima": 0, "ritmo": [0, 0]}
                  for c in self.contas}
        inicio_ritmo = (int(agora) // 3600 - 1) * 3600
        sem_conta = 0
        for _, sid, pasta, horas in vivos.values():
            dono_linha = linhas.get(sid)
            for h, (msgs, tools, entrada, saida, cache, modelos) in horas.items():
                t = h * 3600 + 1800
                if not dono_linha:
                    sem_conta += msgs
                    continue
                i = bisect.bisect_right(dono_linha, (t, "~")) - 1
                p = perfis[dono_linha[max(i, 0)][1]]
                quando = datetime.datetime.fromtimestamp(h * 3600)
                alvos = [p["total"]] + ([p["semana"]] if t >= semana else []) + ([p["hoje"]] if t >= hoje else [])
                for j in alvos:
                    j["msgs"] += msgs
                    j["tools"] += tools
                    j["entrada"] += entrada
                    j["saida"] += saida
                    j["cache"] += cache
                    j["sessoes"].add(sid)
                if quando.date() in p["dias"]:
                    p["dias"][quando.date()][0] += msgs
                    p["dias"][quando.date()][1] += saida
                if t >= semana:
                    p["horas"][quando.hour] += msgs
                    for m, v in modelos.items():
                        somar(p["modelos"].setdefault(m, [0, 0, 0, 0]), v[0], v[1], v[2], v[3])
                        if t >= hoje:
                            somar(p["modelosHoje"].setdefault(m, [0, 0, 0, 0]), v[0], v[1], v[2], v[3])
                    p["projetos"][pasta or "?"] += msgs
                if h * 3600 >= inicio_ritmo:
                    somar(p["ritmo"], msgs, saida)
                if msgs and (not p["desde"] or h * 3600 < p["desde"]):
                    p["desde"] = h * 3600
                if msgs:
                    p["ultima"] = max(p["ultima"], h * 3600)

        saida_perfis = {}
        for nome, p in perfis.items():
            for ts in prompts[nome]:
                for chave, inicio in (("total", 0), ("semana", semana), ("hoje", hoje)):
                    if ts >= inicio:
                        p[chave]["prompts"] += 1
            for chave in ("hoje", "semana", "total"):
                p[chave]["sessoes"] = len(p[chave]["sessoes"])
            saida_perfis[nome] = {
                "hoje": p["hoje"], "semana": p["semana"], "total": p["total"], "desde": p["desde"],
                "dias": [{"dia": d.strftime("%d/%m"), "msgs": v[0], "saida": v[1]} for d, v in p["dias"].items()],
                "horas": p["horas"],
                "modelos": lista_modelos(p["modelos"]),
                "modelosHoje": lista_modelos(p["modelosHoje"]),
                "ritmo": {"msgsH": round(p["ritmo"][0] * 3600 / (agora - inicio_ritmo)),
                          "saidaH": round(p["ritmo"][1] * 3600 / (agora - inicio_ritmo))},
                "ultimaHora": p["ultima"],
                "projetos": [{"nome": m, "msgs": v} for m, v in p["projetos"].most_common(4) if v],
            }
        return {"geradoEm": int(agora), "arquivos": len(vivos), "semConta": sem_conta, "perfis": saida_perfis}
