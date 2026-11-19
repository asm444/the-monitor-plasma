import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

from monitor import comum, config  # noqa: E402
import coletor  # noqa: E402
import hub  # noqa: E402

spec = importlib.util.spec_from_file_location("agente_linux", RAIZ / "agentes/linux.py")
agente = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agente)

SEGREDO = "Zq7xSegredoFalso9"


class Redacao(unittest.TestCase):
    def casos_ocultos(self):
        return [
            ["mysql", "-uroot", f"-p{SEGREDO}"],
            ["mysql", f"-pkey{SEGREDO}"],
            ["app", f"--password={SEGREDO}"],
            ["app", "--token", SEGREDO],
            ["app", "--api-key", SEGREDO],
            ["env", f"GITHUB_TOKEN={SEGREDO}"],
            ["curl", "-H", f"Authorization: Bearer {SEGREDO}", "https://x"],
            ["curl", "-H", f"X-Api-Key: {SEGREDO}", "https://x"],
            ["git", "clone", f"https://user:{SEGREDO}@host/repo"],
            ["curl", f"https://host/api?access_token={SEGREDO}&a=1"],
            ["bash", "-c", f"mysql -p{SEGREDO} banco"],
            ["sshd: x", "--secret", SEGREDO],
            ["tool", "ghp_" + "A1b2C3d4E5f6G7h8I9j0K1l2"],
            ["tool", "sk-ant-" + "api03-" + SEGREDO],
        ]

    def test_oculta_segredo(self):
        for argv in self.casos_ocultos():
            with self.subTest(argv=argv):
                saida = agente.redigir(argv)
                self.assertNotIn(SEGREDO, saida)
                self.assertNotIn("A1b2C3d4E5f6G7h8I9j0K1l2", saida)

    def test_preserva_comando_comum(self):
        argv = ["python3", "-m", "http.server", "--port", "8080", "--bind", "127.0.0.1"]
        self.assertEqual(agente.redigir(argv), " ".join(argv))

    def test_cmdline_gigante_nao_trava(self):
        enorme = "a:" * 1_000_000
        argv = [a for a in ("git\0" + enorme)[:agente.CMD_BRUTO_MAX].split("\0") if a]
        self.assertLessEqual(len(agente.redigir(argv)), agente.CMD_BRUTO_MAX)


class Dispositivos(unittest.TestCase):
    def validar(self, **campos):
        return config.dispositivos({"dispositivo": [{"nome": "x", "destino": "local", **campos}]})

    def test_aceita_destinos_validos(self):
        for destino in ("local", "server", "ops@192.0.2.10", "host.example.net"):
            with self.subTest(destino=destino):
                validos, erros = self.validar(destino=destino)
                self.assertEqual((len(validos), erros), (1, []))

    def test_recusa_injecao_de_opcao_ssh(self):
        for destino in ("-oProxyCommand=sh -c id", "--", "a b", "x;id", "$(id)", "user@-oX"):
            with self.subTest(destino=destino):
                validos, erros = self.validar(destino=destino)
                self.assertEqual(validos, [])
                self.assertEqual(len(erros), 1)

    def test_recusa_tipo_fora_do_registro(self):
        for tipo in ("../../etc/passwd", "inexistente", "linux.py"):
            with self.subTest(tipo=tipo):
                self.assertEqual(self.validar(tipo=tipo)[0], [])

    def test_recusa_nome_repetido_e_estranho(self):
        validos, erros = config.dispositivos({"dispositivo": [
            {"nome": "a", "destino": "local"}, {"nome": "a", "destino": "local"}, {"nome": "<b>", "destino": "local"}]})
        self.assertEqual([d.nome for d in validos], ["a"])
        self.assertEqual(len(erros), 2)

    def test_hub_poe_separador_antes_do_destino(self):
        m = hub.Maquina(config.Dispositivo("x", "server", "linux"))
        cmd, remoto = m.comando()
        self.assertTrue(remoto)
        self.assertEqual(cmd[cmd.index("server") - 1], "--")
        self.assertEqual(cmd[-1], "python3 -I -u - x")

    def test_coletor_recusa_destino_de_envio_malicioso(self):
        with tempfile.TemporaryDirectory() as tmp:
            arq = Path(tmp) / "config.toml"
            arq.write_text('[claude]\ndescobrir = false\nenviar_para = ["-oProxyCommand=id"]\n')
            antigo, config.ARQUIVO = config.ARQUIVO, arq
            try:
                with self.assertRaises(config.ConfigInvalida):
                    coletor.ler_config()
            finally:
                config.ARQUIVO = antigo


class ConfigHostil(unittest.TestCase):
    def test_aninhamento_fundo_vira_config_invalida(self):
        with tempfile.TemporaryDirectory() as tmp:
            arq = Path(tmp) / "config.toml"
            arq.write_text("x = " + "[" * 5000 + "]" * 5000)
            antigo, config.ARQUIVO = config.ARQUIVO, arq
            try:
                with self.assertRaises(ValueError):
                    config.carregar_ou_vazio()
            finally:
                config.ARQUIVO = antigo


class Contas(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.antigo = config.HOME
        config.HOME = self.home
        for d in (".claude", ".claude-trabalho", ".claude-sem-login"):
            (self.home / d).mkdir()
        for d in (".claude", ".claude-trabalho"):
            (self.home / d / ".credentials.json").write_text("{}")

    def tearDown(self):
        config.HOME = self.antigo
        self.tmp.cleanup()

    def test_descobre_contas_com_credencial(self):
        contas = config.contas({})
        self.assertEqual([c.nome for c in contas], ["claude", "trabalho"])
        self.assertEqual([c.cor for c in contas], [0, 1])

    def test_override_e_ignorar(self):
        cfg = {"claude": {"conta": [{"dir": str(self.home / ".claude"), "nome": "pessoal", "cor": 4},
                                    {"dir": str(self.home / ".claude-trabalho"), "ignorar": True}]}}
        contas = config.contas(cfg)
        self.assertEqual([(c.nome, c.cor, c.comando) for c in contas], [("pessoal", 4, "claude-pessoal")])

    def test_recusa_dir_relativo(self):
        with self.assertRaises(config.ConfigInvalida):
            config.contas({"claude": {"conta": [{"dir": "relativo"}]}})


class Hub(unittest.TestCase):
    def test_corta_linha_acima_do_teto(self):
        m = hub.Maquina(config.Dispositivo("x", "local", "linux"))
        m.proc = subprocess.Popen([sys.executable, "-c", f"print('x' * {hub.LINHA_MAX + 10})"], stdout=subprocess.PIPE)
        with self.assertRaises(ValueError):
            list(m.ler_linhas())
        m.proc.wait()
        m.proc.stdout.close()

    def test_recusa_amostra_aninhada_que_derrubaria_a_escrita(self):
        m = hub.Maquina(config.Dispositivo("x", "local", "linux"))
        fundo = []
        for _ in range(2900):
            fundo = [fundo]
        amostra = {"mem": {"usada": 1, "total": 2, "swapUsada": 0, "swapTotal": 0}, "cpu": {"pct": 1, "nucleos": []},
                   "discos": [], "rede": {"ifaces": []}, "x": fundo}
        with self.assertRaises(ValueError):
            m.registrar(amostra)
        self.assertIsNone(m.dado)
        with tempfile.TemporaryDirectory() as tmp:
            arq = Path(tmp) / "local.json"
            arq.write_text('{"claude":' + "[" * 2900 + "]" * 2900 + "}")
            self.assertEqual(comum.ler_json(arq), {})

    def test_limita_interfaces(self):
        m = hub.Maquina(config.Dispositivo("x", "local", "linux"))
        amostra = {"mem": {"usada": 1, "total": 2, "swapUsada": 0, "swapTotal": 0}, "cpu": {"pct": 1, "nucleos": []},
                   "discos": [], "rede": {"ifaces": [{"nome": f"if{i}", "rxBs": 0, "txBs": 0} for i in range(500)]}}
        m.registrar(amostra)
        self.assertEqual(len(m.rede), hub.IFACES_MAX)


class Demo(unittest.TestCase):
    def test_agente_demo_produz_amostra_que_o_hub_aceita(self):
        spec_demo = importlib.util.spec_from_file_location("agente_demo", RAIZ / "agentes/demo.py")
        demo = importlib.util.module_from_spec(spec_demo)
        spec_demo.loader.exec_module(demo)
        m = hub.Maquina(config.Dispositivo("homelab", "local", "demo"))
        m.registrar(json.loads(json.dumps(demo.amostra(1000.0, 900.0))))
        self.assertIsNotNone(m.dado)
        self.assertEqual(len(m.hist["cpu"]), 1)


class Arquivos(unittest.TestCase):
    def test_estado_privado(self):
        with tempfile.TemporaryDirectory() as tmp:
            alvo = Path(tmp) / "sub" / "estado.json"
            antigo = os.umask(0)
            try:
                comum.gravar_privado(alvo, {"a": 1})
            finally:
                os.umask(antigo)
            self.assertEqual(stat.S_IMODE(alvo.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(alvo.parent.stat().st_mode), 0o700)


class Interface(unittest.TestCase):
    def test_todo_label_e_texto_puro(self):
        qml = (RAIZ / "the-monitor/contents/ui/main.qml").read_text()
        blocos = re.findall(r"PC3\.Label \{([^\n]*\n[^\n]*)", qml)
        self.assertTrue(blocos)
        for b in blocos:
            self.assertIn("textFormat: Text.PlainText", b)


if __name__ == "__main__":
    unittest.main()
