import datetime
import random
import time

CONTAS = [("personal", "default_claude_max_5x", 0), ("work", "default_claude_max_20x", 1)]
MODELOS = ["opus 4.1", "sonnet 4.5", "haiku 4.5"]
PROJETOS = ["api-gateway", "infra", "dotfiles", "blog"]


def janela(msgs):
    return {"msgs": msgs, "tools": msgs * 3, "entrada": msgs * 9000, "saida": msgs * 1800, "cache": msgs * 52000,
            "prompts": msgs // 4, "sessoes": max(1, msgs // 60)}


class Claude:
    def __init__(self):
        self.rnd = random.Random(7)

    def perfil(self, i, agora):
        hoje = datetime.date.today()
        base = 120 + 180 * i
        return {
            "hoje": janela(base), "semana": janela(base * 6), "total": janela(base * 40), "desde": int(agora) - 86400 * 60,
            "dias": [{"dia": (hoje - datetime.timedelta(days=d)).strftime("%d/%m"), "msgs": self.rnd.randint(40, base * 2),
                      "saida": self.rnd.randint(50000, 400000)} for d in range(13, -1, -1)],
            "horas": [self.rnd.randint(0, 60) if 8 <= h <= 23 else 0 for h in range(24)],
            "modelos": [{"nome": m, "msgs": base * (3 - k), "entrada": 10**6 // (k + 1), "saida": 2 * 10**5 // (k + 1),
                         "cache": 10**7 // (k + 1)} for k, m in enumerate(MODELOS)],
            "modelosHoje": [{"nome": m, "msgs": base // (k + 1), "entrada": 10**5, "saida": 2 * 10**4 // (k + 1), "cache": 10**6}
                            for k, m in enumerate(MODELOS)],
            "ritmo": {"msgsH": 30 + 20 * i, "saidaH": 40000 + 9000 * i}, "ultimaHora": int(agora) // 3600 * 3600,
            "projetos": [{"nome": p, "msgs": base // (k + 1)} for k, p in enumerate(PROJETOS)],
        }

    def amostra(self):
        agora = time.time()
        reseta = (datetime.datetime.now(datetime.UTC) + datetime.timedelta(days=2, hours=5)).isoformat()
        sessao = (datetime.datetime.now(datetime.UTC) + datetime.timedelta(hours=3)).isoformat()
        contas = [{"perfil": n, "cor": cor, "plano": plano, "estado": "ok",
                   "consultadoEm": int(agora) - 12,
                   "janelas": [{"rotulo": "Sessão 5h", "pct": 22.0 + 30 * i, "reseta": sessao},
                               {"rotulo": "Semanal", "pct": 48.0 + 41 * i, "reseta": reseta},
                               {"rotulo": "Semanal Opus", "pct": 12.0 + 20 * i, "reseta": reseta}]}
                  for i, (n, plano, cor) in enumerate(CONTAS)]
        sessoes = [{"pid": 4100 + k, "perfil": CONTAS[k % 2][0], "pasta": p, "usoMiB": 300 + 700 * (3 - k)}
                   for k, p in enumerate(PROJETOS[:3])]
        return {"geradoEm": int(agora), "claude": contas, "sessoes": sessoes,
                "estatisticas": {"geradoEm": int(agora), "arquivos": 42, "semConta": 0,
                                 "perfis": {n: self.perfil(i, agora) for i, (n, _, _) in enumerate(CONTAS)}}}
