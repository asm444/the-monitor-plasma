import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var estado: null
    property int agora
    property string erroLeitura
    property int aba: 0
    property string ordem: "cpu"
    property var ifaceSel: ({})
    property string cmdFoco
    readonly property var hosts: estado ? estado.hosts : []
    readonly property var claude: estado && estado.claude && estado.claude.claude ? estado.claude : null
    readonly property bool abaClaude: !!claude && aba >= hosts.length
    readonly property var host: abaClaude || hosts.length === 0 ? null : hosts[Math.min(aba, hosts.length - 1)]
    readonly property var d: host ? host.dado : null
    readonly property bool atrasado: !estado || agora - estado.geradoEm > 5

    readonly property var ifacesVivas: {
        if (!d) return []
        var l = []
        for (var i = 0; i < d.rede.ifaces.length; i++) {
            var f = d.rede.ifaces[i]
            if (f.rxTotal + f.txTotal > 0 && (!f.virtual || f.nome.indexOf("tailscale") === 0)) l.push(f)
        }
        return l
    }
    readonly property var iface: {
        if (!d) return null
        var alvo = ifaceSel[host.nome] || d.rede.padrao
        for (var i = 0; i < ifacesVivas.length; i++) if (ifacesVivas[i].nome === alvo) return ifacesVivas[i]
        return ifacesVivas.length ? ifacesVivas[0] : null
    }
    readonly property var histIface: host && iface && host.histRede[iface.nome] ? host.histRede[iface.nome] : { rx: [], tx: [] }
    readonly property var procs: {
        if (!d) return []
        var l = d.procs.lista.slice()
        var o = ordem
        l.sort(function(a, b) {
            if (o === "mem") return b.mem - a.mem
            if (o === "pid") return a.pid - b.pid
            if (o === "nome") return a.nome.localeCompare(b.nome)
            return b.cpu - a.cpu || b.mem - a.mem
        })
        return l
    }

    readonly property int idadeClaude: claude ? agora - claude.geradoEm : 0
    readonly property var stats: claude && claude.estatisticas ? claude.estatisticas : null
    readonly property real picoGeral: {
        var m = 0
        if (claude) for (var i = 0; i < claude.claude.length; i++) m = Math.max(m, principal(claude.claude[i]))
        return m
    }
    readonly property bool algumOffline: {
        if (!claude) return false
        for (var i = 0; i < claude.claude.length; i++) if (claude.claude[i].estado !== "ok") return true
        return false
    }
    readonly property string humor: !claude || idadeClaude > 10 ? "rain"
        : algumOffline ? "skull"
        : picoGeral >= 80 ? "fire"
        : picoGeral <= 25 ? "halo"
        : "smart"

    readonly property color gVerde: "#4ADE80"
    readonly property color gAmarelo: "#FACC15"
    readonly property color gVermelho: "#EF4444"
    readonly property color cCpu: "#4ADE80"
    readonly property color cMem: "#FACC15"
    readonly property color cDisco: "#F59E0B"
    readonly property color cRede: "#A78BFA"
    readonly property color cProc: "#F87171"
    readonly property color cAba: "#38BDF8"
    readonly property color terracota: "#D97757"
    readonly property color ambar: "#D97706"
    readonly property color ambarClaro: "#F59E0B"
    readonly property color creme: "#F5E6D3"
    readonly property color violeta: "#8B5CF6"
    readonly property color rosa: "#EC4899"
    readonly property color verde: "#10B981"
    readonly property color lima: "#84CC16"
    readonly property color azul: "#3B82F6"
    readonly property color ciano: "#06B6D4"
    readonly property color vermelho: "#EF4444"
    readonly property color dourado: "#FFD700"
    readonly property color bordaSutil: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
    readonly property real fonte: Kirigami.Theme.defaultFont.pixelSize
    property real alturaPainel: 0
    readonly property real fonteMini: Math.round(Math.max(11, Math.min(fonte * 1.05, alturaPainel / 2.5)))
    readonly property string mono: "monospace"

    function alfa(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mistura(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    function grad(p) {
        p = Math.max(0, Math.min(100, p || 0))
        return p < 50 ? mistura(gVerde, gAmarelo, p / 50) : mistura(gAmarelo, gVermelho, (p - 50) / 50)
    }
    function gradTemp(t, crit) { return grad(100 * (t - 35) / Math.max(10, (crit || 95) - 35)) }
    function bytes(b) {
        if (b === null || b === undefined) return "-"
        var u = ["B", "K", "M", "G", "T"], i = 0, v = b
        while (v >= 1024 && i < 4) { v /= 1024; i++ }
        return v.toFixed(v >= 100 || i === 0 ? 0 : 1) + u[i]
    }
    function taxa(b) { return bytes(b) + "/s" }
    function pct(u, t) { return t > 0 ? 100 * u / t : 0 }
    function esq(s, n) { s = String(s); while (s.length < n) s = " " + s; return s }
    function duracao(s) {
        if (s === null || s === undefined) return ""
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m"
    }
    function idadeTxt(s) {
        if (s < 0) return "nunca"
        if (s < 120) return s + "s"
        if (s < 7200) return Math.floor(s / 60) + "min"
        return Math.floor(s / 3600) + "h"
    }
    function maximo(l) { var m = 0; for (var i = 0; i < (l || []).length; i++) m = Math.max(m, l[i]); return m }
    function ultimo(l) { return l && l.length ? l[l.length - 1] : 0 }
    function escolheIface(nome) {
        var novo = Object.assign({}, ifaceSel)
        novo[host.nome] = nome
        ifaceSel = novo
    }

    readonly property var paletas: [[terracota, ambarClaro], [violeta, rosa], [verde, lima], [azul, ciano], [dourado, creme]]
    function paleta(nome) {
        var l = claude ? claude.claude : []
        for (var i = 0; i < l.length; i++) if (l[i].perfil === nome) return paletas[(l[i].cor || 0) % paletas.length]
        return paletas[0]
    }
    function corPct(p, base) { return p >= 90 ? vermelho : p >= 75 ? ambarClaro : base }
    function principal(c) {
        var m = 0
        for (var i = 0; i < c.janelas.length; i++) m = Math.max(m, c.janelas[i].pct)
        return m
    }
    function falta(iso) {
        if (!iso) return ""
        var s = Math.floor(Date.parse(iso) / 1000) - agora
        if (s <= 0) return "resetou"
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m " + (s % 60) + "s"
    }
    function rotuloCurto(r) {
        var t = r.replace("Semanal ", "").replace("Sessão ", "").toLowerCase()
        return t === "semanal" ? "sem" : t === "extra mensal" ? "extra" : t
    }
    function resetSemanal(c) {
        for (var i = 0; i < c.janelas.length; i++) if (c.janelas[i].rotulo === "Semanal") return c.janelas[i].reseta
        return c.janelas.length ? c.janelas[0].reseta : ""
    }
    function humorTexto() { return { rain: "Sem sinal", skull: "Usage offline", fire: "Pegando fogo", halo: "Tranquilo", smart: "Focado" }[humor] }
    function num(n) {
        n = n || 0
        return n >= 1e9 ? (n / 1e9).toFixed(1) + "B" : n >= 1e6 ? (n / 1e6).toFixed(1) + "M"
            : n >= 1e4 ? Math.round(n / 1e3) + "k" : n >= 1e3 ? (n / 1e3).toFixed(1) + "k" : String(n)
    }
    function projecao(j) {
        if (!j.reseta) return null
        var dur = j.rotulo.indexOf("Sessão") === 0 ? 5 * 3600 : 7 * 86400
        var resta = Math.floor(Date.parse(j.reseta) / 1000) - agora
        var passou = dur - resta
        if (resta <= 0 || j.pct <= 0 || passou < dur * 0.03) return null
        if (j.pct >= 100) return { estoura: true, texto: "esgotado · libera em " + duracao(resta) }
        var taxa = j.pct / passou
        var fim = j.pct + taxa * resta
        if (fim < 100) return { estoura: false, texto: "no ritmo atual fecha em " + Math.round(fim) + "% no reset" }
        return { estoura: true, texto: "no ritmo atual esgota em " + duracao((100 - j.pct) / taxa) + ", " + duracao(resta - (100 - j.pct) / taxa) + " antes do reset" }
    }
    function statsDe(nome) { return stats && stats.perfis ? stats.perfis[nome] || null : null }
    function dataCurta(s) { var d = new Date(s * 1000); return ("0" + d.getDate()).slice(-2) + "/" + ("0" + (d.getMonth() + 1)).slice(-2) }
    function humorCor() { return { rain: azul, skull: vermelho, fire: "#F97316", halo: dourado, smart: verde }[humor] }

    P5Support.DataSource {
        engine: "executable"
        connectedSources: ["date +%s; cat \"$HOME/.cache/the-monitor/estado.json\" 2>&1"]
        interval: 1000
        onNewData: function(source, data) {
            var out = data["stdout"] || ""
            var nl = out.indexOf("\n")
            root.agora = parseInt(out.substring(0, nl))
            try {
                root.estado = JSON.parse(out.substring(nl + 1))
                root.erroLeitura = ""
            } catch (e) {
                root.erroLeitura = out.substring(nl + 1, nl + 200) || "estado.json vazio: o hub the-monitor está rodando?"
            }
        }
    }

    toolTipMainText: "The Monitor"
    toolTipSubText: {
        var l = []
        for (var i = 0; i < hosts.length; i++) {
            var h = hosts[i]
            l.push(h.nome + ": " + (h.online && h.dado
                ? "cpu " + Math.round(h.dado.cpu.pct) + "% · ram " + Math.round(pct(h.dado.mem.usada, h.dado.mem.total)) + "%"
                : "offline"))
        }
        if (claude) l.push("claude: pico " + Math.round(picoGeral) + "%")
        return l.join("\n")
    }

    component Grafico: Canvas {
        id: g
        property var pts: []
        property real teto: 100
        property bool auto: false
        property bool invertido: false
        property bool grade: true
        property int capacidade: 90
        property color c1: root.gVerde
        property color c2: root.gAmarelo
        property color c3: root.gVermelho
        readonly property real escala: auto ? Math.max(10240, root.maximo(pts) * 1.15) : teto
        onPtsChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (grade) {
                ctx.strokeStyle = root.bordaSutil.toString()
                ctx.lineWidth = 1
                for (var k = 1; k < 4; k++) {
                    var y = Math.round(height * k / 4) + 0.5
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                }
            }
            var l = pts || []
            if (!l.length) return
            var gr = invertido ? ctx.createLinearGradient(0, 0, 0, height) : ctx.createLinearGradient(0, height, 0, 0)
            gr.addColorStop(0, c1.toString())
            gr.addColorStop(0.5, c2.toString())
            gr.addColorStop(1, c3.toString())
            ctx.fillStyle = gr
            var w = width / capacidade
            var larg = Math.max(1, w > 3 ? w - 1 : w)
            var x0 = width - l.length * w
            for (var i = 0; i < l.length; i++) {
                var h = Math.max(1, height * Math.min(1, l[i] / escala))
                ctx.fillRect(x0 + i * w, invertido ? 0 : height - h, larg, h)
            }
        }
    }

    component Barras: Item {
        id: barras
        property var valores: []
        property color c1
        property color c2
        property int destaque: -1
        readonly property real teto: Math.max(1, root.maximo(valores))
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2.2
        Row {
            anchors.fill: parent
            spacing: 2
            Repeater {
                model: barras.valores.length
                Item {
                    required property int index
                    width: (barras.width - (barras.valores.length - 1) * 2) / barras.valores.length
                    height: barras.height
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: barras.valores[parent.index] > 0 ? Math.max(2, parent.height * barras.valores[parent.index] / barras.teto) : 1
                        radius: 2
                        opacity: parent.index === barras.destaque ? 1 : barras.valores[parent.index] > 0 ? 0.7 : 0.25
                        gradient: Gradient {
                            GradientStop { position: 0; color: barras.c2 }
                            GradientStop { position: 1; color: barras.c1 }
                        }
                        Behavior on height { NumberAnimation { duration: 400 } }
                    }
                }
            }
        }
    }

    component Rodape: RowLayout {
        property alias esquerda: rEsq.text
        property alias meio: rMeio.text
        property alias direita: rDir.text
        Layout.fillWidth: true
        PC3.Label { textFormat: Text.PlainText; id: rEsq; font.pixelSize: root.fonte * 0.68; opacity: 0.5 }
        Item { Layout.fillWidth: true }
        PC3.Label { textFormat: Text.PlainText; id: rMeio; font.pixelSize: root.fonte * 0.72; font.weight: Font.DemiBold; opacity: 0.75 }
        Item { Layout.fillWidth: true }
        PC3.Label { textFormat: Text.PlainText; id: rDir; font.pixelSize: root.fonte * 0.68; opacity: 0.5 }
    }

    component Medidor: Item {
        id: med
        property real valor
        property bool porGrad: true
        property color cor: root.gVerde
        Layout.fillWidth: true
        implicitHeight: Math.round(root.fonte * 0.6)
        readonly property int n: Math.max(4, Math.floor(width / 6))
        Row {
            anchors.fill: parent
            spacing: 1
            Repeater {
                model: med.n
                Rectangle {
                    required property int index
                    readonly property real p: 100 * (index + 0.5) / med.n
                    width: (med.width - (med.n - 1)) / med.n
                    height: med.height
                    radius: 1
                    color: p <= med.valor ? (med.porGrad ? root.grad(p) : med.cor) : root.bordaSutil
                }
            }
        }
    }

    component Caixa: Item {
        id: caixa
        default property alias conteudo: miolo.data
        property string titulo
        property string info
        property color cor
        Layout.fillWidth: true
        implicitHeight: miolo.implicitHeight + selo.height + Kirigami.Units.largeSpacing
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: selo.height / 2
            radius: 8
            color: root.alfa(caixa.cor, 0.04)
            border.width: 1
            border.color: root.alfa(caixa.cor, 0.7)
        }
        Rectangle {
            id: selo
            x: 10
            width: linhaSelo.implicitWidth + 14
            height: linhaSelo.implicitHeight + 4
            radius: height / 2
            color: Qt.tint(Kirigami.Theme.backgroundColor, root.alfa(caixa.cor, 0.25))
            border.width: 1
            border.color: root.alfa(caixa.cor, 0.7)
            RowLayout {
                id: linhaSelo
                anchors.centerIn: parent
                spacing: 6
                PC3.Label { textFormat: Text.PlainText; text: caixa.titulo; font.family: root.mono; font.weight: Font.Bold; color: caixa.cor; font.pixelSize: root.fonte * 0.9 }
                PC3.Label {
                    textFormat: Text.PlainText
                    visible: caixa.info !== ""
                    text: caixa.info
                    font.family: root.mono
                    font.pixelSize: root.fonte * 0.8
                    opacity: 0.75
                }
            }
        }
        ColumnLayout {
            id: miolo
            anchors.fill: parent
            anchors.topMargin: selo.height + 4
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottomMargin: 8
            spacing: 4
        }
    }

    component Mono: PC3.Label {
        textFormat: Text.PlainText
        font.family: root.mono
        font.pixelSize: root.fonte * 0.85
    }

    component Mini: PC3.Label {
        textFormat: Text.PlainText
        font.family: root.mono
        font.pixelSize: root.fonteMini
        lineHeight: 0.92
    }

    component BarraGradiente: Rectangle {
        id: barra
        property real pct
        property color c1
        property color c2
        Layout.preferredWidth: 40
        implicitHeight: 6
        radius: height / 2
        color: root.bordaSutil
        Rectangle {
            width: Math.max(parent.height, parent.width * Math.min(1, barra.pct / 100))
            visible: barra.pct > 0
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: barra.pct >= 90 ? root.vermelho : barra.c1 }
                GradientStop { position: 1; color: barra.pct >= 90 ? "#F97316" : barra.c2 }
            }
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }
    }

    component Anel: Item {
        id: anel
        property real pct
        property color c1
        property color c2
        property string rotulo
        property real espessura: 8
        implicitWidth: Kirigami.Units.gridUnit * 5
        implicitHeight: implicitWidth
        Behavior on pct { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        onPctChanged: tela.requestPaint()
        Canvas {
            id: tela
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - anel.espessura
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                ctx.strokeStyle = root.bordaSutil.toString()
                ctx.lineWidth = anel.espessura
                ctx.stroke()
                var fim = -Math.PI / 2 + 2 * Math.PI * Math.min(1, Math.max(0.005, anel.pct / 100))
                var quente = anel.pct >= 90
                var g = ctx.createConicalGradient(cx, cy, -Math.PI / 2)
                g.addColorStop(0, (quente ? root.vermelho : anel.c1).toString())
                g.addColorStop(1, (quente ? "#F97316" : anel.c2).toString())
                ctx.beginPath()
                ctx.arc(cx, cy, r, -Math.PI / 2, fim)
                ctx.strokeStyle = root.alfa(quente ? root.vermelho : anel.c2, 0.22).toString()
                ctx.lineWidth = anel.espessura + 7
                ctx.lineCap = "round"
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(cx, cy, r, -Math.PI / 2, fim)
                ctx.strokeStyle = g
                ctx.lineWidth = anel.espessura
                ctx.lineCap = "round"
                ctx.stroke()
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: -2
            PC3.Label {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: Math.round(anel.pct) + "%"
                font.pixelSize: root.fonte * 1.55
                font.weight: Font.Black
                color: anel.pct >= 90 ? root.vermelho : anel.c2
            }
            PC3.Label {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: anel.rotulo
                font.pixelSize: root.fonte * 0.7
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                opacity: 0.55
            }
        }
    }

    component Cartao: Rectangle {
        id: cartao
        default property alias conteudo: mioloCartao.data
        property color c1
        property color c2
        property bool alerta
        Layout.fillWidth: true
        implicitHeight: mioloCartao.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: 14
        border.width: alerta ? 2 : 1
        border.color: alerta ? root.alfa(root.vermelho, 0.7) : root.alfa(c1, 0.45)
        gradient: Gradient {
            GradientStop { position: 0; color: root.alfa(cartao.c1, 0.16) }
            GradientStop { position: 1; color: root.alfa(cartao.c2, 0.04) }
        }
        ColumnLayout {
            id: mioloCartao
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: 6
        }
    }

    component Pilula: Rectangle {
        property alias texto: rotuloPilula.text
        property color cor
        radius: height / 2
        color: root.alfa(cor, 0.18)
        border.width: 1
        border.color: root.alfa(cor, 0.4)
        implicitWidth: rotuloPilula.implicitWidth + 14
        implicitHeight: rotuloPilula.implicitHeight + 4
        PC3.Label {
            textFormat: Text.PlainText
            id: rotuloPilula
            anchors.centerIn: parent
            font.pixelSize: root.fonte * 0.8
            font.weight: Font.Bold
            color: parent.cor
        }
    }

    component Aba: Rectangle {
        id: botao
        property bool selecionada
        default property alias conteudo: linhaAba.data
        signal acionada()
        implicitWidth: linhaAba.implicitWidth + 20
        implicitHeight: linhaAba.implicitHeight + 10
        radius: 6
        color: selecionada ? root.alfa(root.cAba, 0.25) : mouseAba.containsMouse ? root.alfa(root.cAba, 0.1) : "transparent"
        border.width: 1
        border.color: selecionada ? root.cAba : root.bordaSutil
        RowLayout {
            id: linhaAba
            anchors.centerIn: parent
            spacing: 6
        }
        MouseArea {
            id: mouseAba
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: botao.acionada()
        }
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: linhaCompacta.implicitWidth + Kirigami.Units.smallSpacing * 2
        onHeightChanged: root.alturaPainel = height
        Component.onCompleted: root.alturaPainel = height
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        RowLayout {
            id: linhaCompacta
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing
            Image {
                visible: !!root.claude
                source: Qt.resolvedUrl("../icons/conta.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                sourceSize: Qt.size(Kirigami.Units.iconSizes.small, Kirigami.Units.iconSizes.small)
            }
            Repeater {
                model: root.claude ? root.claude.claude.length : 0
                ColumnLayout {
                    id: miniPerfil
                    required property int index
                    readonly property var c: root.claude.claude[index]
                    readonly property var cores: root.paleta(c.perfil)
                    spacing: 0
                    RowLayout {
                        spacing: 4
                        Mini { text: miniPerfil.c.perfil; font.weight: Font.Black; color: miniPerfil.cores[0] }
                        Mini {
                            text: miniPerfil.c.estado === "ok" ? "↻ " + root.falta(root.resetSemanal(miniPerfil.c)) : miniPerfil.c.estado
                            color: miniPerfil.c.estado === "ok" ? Kirigami.Theme.textColor : root.vermelho
                            opacity: miniPerfil.c.estado === "ok" ? 0.7 : 1
                            Layout.maximumWidth: root.fonte * 9
                            elide: Text.ElideRight
                        }
                    }
                    RowLayout {
                        spacing: 4
                        Repeater {
                            model: miniPerfil.c.janelas.length
                            RowLayout {
                                id: miniJanela
                                required property int index
                                readonly property var j: miniPerfil.c.janelas[index]
                                spacing: 2
                                Mini { text: root.rotuloCurto(miniJanela.j.rotulo); opacity: 0.7 }
                                BarraGradiente {
                                    Layout.preferredWidth: root.fonteMini * 2.4
                                    implicitHeight: Math.round(root.fonteMini * 0.45)
                                    pct: miniJanela.j.pct
                                    c1: miniPerfil.cores[0]
                                    c2: miniPerfil.cores[1]
                                }
                                Mini {
                                    text: Math.round(miniJanela.j.pct) + "%"
                                    font.weight: Font.Bold
                                    color: root.corPct(miniJanela.j.pct, Kirigami.Theme.textColor)
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { visible: !!root.claude; width: 1; Layout.preferredHeight: root.fonteMini * 2; color: root.bordaSutil }
            Repeater {
                model: root.hosts.length
                ColumnLayout {
                    id: miniHost
                    required property int index
                    readonly property var h: root.hosts[index]
                    readonly property var dh: h.dado
                    readonly property real cpu: dh ? dh.cpu.pct : 0
                    readonly property real ram: dh ? root.pct(dh.mem.usada, dh.mem.total) : 0
                    spacing: 0
                    RowLayout {
                        spacing: 4
                        Rectangle { width: Math.round(root.fonteMini * 0.55); height: width; radius: width / 2; color: miniHost.h.online ? root.verde : root.vermelho }
                        Mini { text: miniHost.h.nome; font.weight: Font.Black; color: miniHost.h.online ? root.cAba : root.vermelho }
                        Mini {
                            visible: !!miniHost.dh && miniHost.dh.cpu.temp !== null
                            text: miniHost.dh && miniHost.dh.cpu.temp !== null ? Math.round(miniHost.dh.cpu.temp) + "°" : ""
                            color: miniHost.dh ? root.gradTemp(miniHost.dh.cpu.temp, miniHost.dh.cpu.tempCrit) : root.verde
                        }
                    }
                    RowLayout {
                        spacing: 2
                        Mini { text: "cpu"; opacity: 0.7 }
                        Medidor { Layout.fillWidth: false; Layout.preferredWidth: root.fonteMini * 2.4; implicitHeight: Math.round(root.fonteMini * 0.45); valor: miniHost.cpu }
                        Mini { text: root.esq(Math.round(miniHost.cpu), 2) + "%"; font.weight: Font.Bold; color: root.grad(miniHost.cpu) }
                        Mini { text: "ram"; opacity: 0.7; Layout.leftMargin: 2 }
                        Medidor { Layout.fillWidth: false; Layout.preferredWidth: root.fonteMini * 2.4; implicitHeight: Math.round(root.fonteMini * 0.45); valor: miniHost.ram }
                        Mini { text: root.esq(Math.round(miniHost.ram), 2) + "%"; font.weight: Font.Bold; color: root.grad(miniHost.ram) }
                    }
                }
            }
            Rectangle {
                visible: root.atrasado
                width: 8; height: 8; radius: 4
                color: root.vermelho
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 52
        Layout.minimumWidth: Kirigami.Units.gridUnit * 40
        Layout.preferredHeight: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Kirigami.Icon { source: "utilities-system-monitor"; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
            PC3.Label { textFormat: Text.PlainText; text: "The Monitor"; font.pixelSize: root.fonte * 1.3; font.weight: Font.Black; color: root.cAba }
            Item { Layout.preferredWidth: 6 }
            Repeater {
                model: root.hosts.length
                Aba {
                    id: abaHost
                    required property int index
                    readonly property var h: root.hosts[index]
                    selecionada: !root.abaClaude && root.host === h
                    onAcionada: root.aba = index
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: abaHost.h.online ? root.verde : root.vermelho
                    }
                    Mono {
                        text: abaHost.h.nome
                        font.weight: abaHost.selecionada ? Font.Bold : Font.Normal
                    }
                    Mono {
                        visible: !!abaHost.h.dado
                        text: abaHost.h.dado ? Math.round(abaHost.h.dado.cpu.pct) + "%" : ""
                        color: root.grad(abaHost.h.dado ? abaHost.h.dado.cpu.pct : 0)
                        font.pixelSize: root.fonte * 0.75
                    }
                }
            }
            Aba {
                visible: !!root.claude
                selecionada: root.abaClaude
                onAcionada: root.aba = root.hosts.length
                Image {
                    source: Qt.resolvedUrl("../icons/conta.svg")
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    sourceSize: Qt.size(14, 14)
                }
                Mono { text: "claude"; font.weight: root.abaClaude ? Font.Bold : Font.Normal }
                Mono {
                    text: Math.round(root.picoGeral) + "%"
                    color: root.corPct(root.picoGeral, root.terracota)
                    font.pixelSize: root.fonte * 0.75
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 7; height: 7; radius: 4
                color: root.atrasado ? root.vermelho : root.verde
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            Mono {
                text: root.erroLeitura !== "" ? "erro" : root.atrasado ? "hub parado" : "live"
                color: root.atrasado || root.erroLeitura !== "" ? root.vermelho : root.verde
            }
        }

        PC3.Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.erroLeitura !== ""
            wrapMode: Text.Wrap
            text: root.erroLeitura
            color: root.vermelho
            font.pixelSize: root.fonte * 0.8
        }

        StackLayout {
            Layout.fillWidth: true
            visible: root.abaClaude || !!root.host
            currentIndex: root.abaClaude ? 1 : 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.fillWidth: true
                    visible: !!root.host && !root.host.online
                    implicitHeight: textoOffline.implicitHeight + 10
                    radius: 6
                    color: root.alfa(root.vermelho, 0.15)
                    border.width: 1
                    border.color: root.alfa(root.vermelho, 0.5)
                    PC3.Label {
                        textFormat: Text.PlainText
                        id: textoOffline
                        anchors.fill: parent
                        anchors.margins: 5
                        wrapMode: Text.Wrap
                        font.pixelSize: root.fonte * 0.85
                        color: root.vermelho
                        text: !root.host ? "" : root.host.nome + " (" + root.host.destino + ") offline: " + root.host.erro
                            + (root.host.recebidoEm > 0 ? " · último dado há " + root.idadeTxt(root.agora - root.host.recebidoEm) : "")
                    }
                }

                PC3.Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: !!root.host && !root.d
                    text: "aguardando o primeiro dado de " + (root.host ? root.host.destino : "")
                    opacity: 0.6
                }

                Caixa {
                    visible: !!root.d
                    titulo: "cpu"
                    info: root.d ? root.d.cpuModelo + " · " + root.d.distro + " · " + root.d.kernel : ""
                    cor: root.cCpu

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Mono {
                            text: root.d ? "total " + root.esq(Math.round(root.d.cpu.pct), 3) + "%" : ""
                            font.weight: Font.Bold
                            font.pixelSize: root.fonte
                            color: root.grad(root.d ? root.d.cpu.pct : 0)
                        }
                        Mono {
                            visible: !!root.d && root.d.cpu.temp !== null
                            text: root.d && root.d.cpu.temp !== null ? Math.round(root.d.cpu.temp) + "°C" : ""
                            font.weight: Font.Bold
                            color: root.d ? root.gradTemp(root.d.cpu.temp, root.d.cpu.tempCrit) : root.verde
                        }
                        Mono {
                            visible: !!root.d && !!root.d.cpu.mhzMedio
                            text: root.d && root.d.cpu.mhzMedio ? (root.d.cpu.mhzMedio / 1000).toFixed(2) + " GHz" : ""
                            opacity: 0.8
                        }
                        Mono { text: root.d ? "load " + root.d.cpu.carga.join(" ") : ""; opacity: 0.8 }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: root.d ? root.d.baterias.length : 0
                            Mono {
                                required property int index
                                readonly property var b: root.d.baterias[index]
                                text: "bat " + b.pct + "% " + (b.status === "Charging" ? "▲" : b.status === "Discharging" ? "▼" : "")
                                    + (b.watts ? " " + b.watts + "W" : "") + (b.restanteS ? " " + root.duracao(b.restanteS) : "")
                                color: b.pct <= 15 && b.status === "Discharging" ? root.vermelho : root.grad(100 - b.pct)
                            }
                        }
                        Mono { text: root.d ? "up " + root.duracao(root.d.uptime) : ""; opacity: 0.6 }
                    }

                    Grafico {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                        pts: root.host ? root.host.hist.cpu : []
                    }

                    GridLayout {
                        id: gradeNucleos
                        readonly property int n: root.d ? root.d.cpu.nucleos.length : 0
                        readonly property int colunas: n <= 4 ? 1 : n <= 8 ? 2 : n <= 16 ? 4 : 6
                        Layout.fillWidth: true
                        flow: GridLayout.TopToBottom
                        rows: Math.max(1, Math.ceil(n / colunas))
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: 1
                        Repeater {
                            model: gradeNucleos.n
                            RowLayout {
                                id: nucleo
                                required property int index
                                readonly property var info: root.d ? root.d.cpu.nucleos[index] : null
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 4
                                Mono { text: "C" + nucleo.index; opacity: 0.7; Layout.preferredWidth: root.fonte * 1.9 }
                                Grafico {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.fonte * 0.95
                                    grade: false
                                    capacidade: 40
                                    pts: root.host && root.host.histNucleos[nucleo.index] ? root.host.histNucleos[nucleo.index] : []
                                }
                                Mono {
                                    text: nucleo.info ? root.esq(Math.round(nucleo.info.pct), 3) + "%" : ""
                                    color: root.grad(nucleo.info ? nucleo.info.pct : 0)
                                    font.weight: Font.Bold
                                }
                                Mono {
                                    visible: !!nucleo.info && nucleo.info.temp !== null
                                    text: nucleo.info && nucleo.info.temp !== null ? Math.round(nucleo.info.temp) + "°" : ""
                                    color: root.d && nucleo.info ? root.gradTemp(nucleo.info.temp, root.d.cpu.tempCrit) : root.verde
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Repeater {
                            model: root.d ? root.d.gpus.length : 0
                            Mono {
                                required property int index
                                readonly property var gp: root.d.gpus[index]
                                text: "GPU " + gp.nome
                                    + (gp.uso !== null ? " " + gp.uso + "%" : "")
                                    + (gp.mhz ? " " + gp.mhz + "/" + gp.mhzMax + " MHz" : "")
                                    + (gp.vramTotal ? " · VRAM " + root.bytes(gp.vramUsada) + "/" + root.bytes(gp.vramTotal) : "")
                                    + (gp.temp ? " · " + Math.round(gp.temp) + "°" : "")
                                color: root.grad(gp.uso || 0)
                                font.pixelSize: root.fonte * 0.78
                            }
                        }
                        Repeater {
                            model: root.d ? root.d.cpu.sensores.length : 0
                            Mono {
                                required property int index
                                readonly property var s: root.d.cpu.sensores[index]
                                text: s.nome + " " + Math.round(s.c) + "°"
                                color: root.gradTemp(s.c, 95)
                                font.pixelSize: root.fonte * 0.78
                                opacity: 0.85
                            }
                        }
                    }
                }

                RowLayout {
                    visible: !!root.d
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.alignment: Qt.AlignTop
                        spacing: Kirigami.Units.largeSpacing

                        Caixa {
                            id: caixaMem
                            titulo: "mem"
                            info: root.d ? "total " + root.bytes(root.d.mem.total) : ""
                            cor: root.cMem
                            readonly property var linhas: root.d ? [
                                ["usada", root.d.mem.usada, root.d.mem.total],
                                ["disponível", root.d.mem.disponivel, root.d.mem.total],
                                ["cache", root.d.mem.cache, root.d.mem.total],
                                ["livre", root.d.mem.livre, root.d.mem.total],
                                ["swap", root.d.mem.swapUsada, root.d.mem.swapTotal]
                            ] : []
                            Repeater {
                                model: 5
                                ColumnLayout {
                                    id: linhaMem
                                    required property int index
                                    readonly property var l: caixaMem.linhas[index] || ["", 0, 0]
                                    readonly property real p: root.pct(l[1], l[2])
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Mono { text: linhaMem.l[0]; opacity: 0.85 }
                                        Item { Layout.fillWidth: true }
                                        Mono { text: root.bytes(linhaMem.l[1]); font.weight: Font.Bold }
                                        Mono { text: root.esq(Math.round(linhaMem.p), 3) + "%"; color: root.grad(linhaMem.index === 1 ? 100 - linhaMem.p : linhaMem.p) }
                                    }
                                    Medidor {
                                        valor: linhaMem.p
                                        porGrad: linhaMem.index === 0 || linhaMem.index === 4
                                        cor: [root.gVerde, root.gVerde, root.ciano, root.azul, root.violeta][linhaMem.index]
                                    }
                                }
                            }
                            Grafico {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                                pts: root.host ? root.host.hist.ram : []
                            }
                        }

                        Caixa {
                            titulo: "discos"
                            info: root.host ? "r " + root.taxa(root.ultimo(root.host.hist.ler)) + "  w " + root.taxa(root.ultimo(root.host.hist.gravar)) : ""
                            cor: root.cDisco
                            Grafico {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                                auto: true
                                grade: false
                                pts: root.host ? root.host.hist.ler : []
                                c1: root.ciano; c2: root.azul; c3: root.violeta
                            }
                            Grafico {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                                auto: true
                                grade: false
                                invertido: true
                                pts: root.host ? root.host.hist.gravar : []
                                c1: root.ambarClaro; c2: "#F97316"; c3: root.vermelho
                            }
                            Repeater {
                                model: root.d ? root.d.discos.length : 0
                                ColumnLayout {
                                    id: disco
                                    required property int index
                                    readonly property var dsk: root.d.discos[index]
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Mono { text: disco.dsk.ponto; font.weight: Font.Bold }
                                        Mono { text: disco.dsk.fs; opacity: 0.5; font.pixelSize: root.fonte * 0.72 }
                                        Item { Layout.fillWidth: true }
                                        Mono {
                                            visible: disco.dsk.lerBs + disco.dsk.gravarBs > 0
                                            text: "r " + root.taxa(disco.dsk.lerBs) + " w " + root.taxa(disco.dsk.gravarBs)
                                            font.pixelSize: root.fonte * 0.72
                                            opacity: 0.75
                                        }
                                        Mono { text: root.bytes(disco.dsk.usado) + "/" + root.bytes(disco.dsk.total) }
                                    }
                                    Medidor { valor: root.pct(disco.dsk.usado, disco.dsk.total) }
                                }
                            }
                        }

                        Caixa {
                            titulo: "rede"
                            info: root.iface ? root.iface.nome + (root.iface.ip ? " " + root.iface.ip : "") : ""
                            cor: root.cRede
                            Flow {
                                Layout.fillWidth: true
                                visible: root.ifacesVivas.length > 1
                                spacing: 4
                                Repeater {
                                    model: root.ifacesVivas.length
                                    Aba {
                                        id: abaIface
                                        required property int index
                                        readonly property var f: root.ifacesVivas[index]
                                        selecionada: !!root.iface && root.iface.nome === f.nome
                                        onAcionada: root.escolheIface(f.nome)
                                        Mono { text: abaIface.f ? abaIface.f.nome : ""; font.pixelSize: root.fonte * 0.72 }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Mono { text: "▼"; color: root.cRede; font.weight: Font.Black }
                                Mono { text: root.iface ? root.taxa(root.iface.rxBs) : ""; font.weight: Font.Bold; font.pixelSize: root.fonte }
                                Item { Layout.fillWidth: true }
                                Mono { text: "pico " + root.taxa(root.maximo(root.histIface.rx)); opacity: 0.6; font.pixelSize: root.fonte * 0.75 }
                                Mono { text: root.iface ? "total " + root.bytes(root.iface.rxTotal) : ""; opacity: 0.6; font.pixelSize: root.fonte * 0.75 }
                            }
                            Grafico {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                                auto: true
                                pts: root.histIface.rx
                                c1: root.violeta; c2: root.cRede; c3: root.rosa
                            }
                            Grafico {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                                auto: true
                                invertido: true
                                pts: root.histIface.tx
                                c1: root.ciano; c2: root.azul; c3: root.violeta
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Mono { text: "▲"; color: root.ciano; font.weight: Font.Black }
                                Mono { text: root.iface ? root.taxa(root.iface.txBs) : ""; font.weight: Font.Bold; font.pixelSize: root.fonte }
                                Item { Layout.fillWidth: true }
                                Mono { text: "pico " + root.taxa(root.maximo(root.histIface.tx)); opacity: 0.6; font.pixelSize: root.fonte * 0.75 }
                                Mono { text: root.iface ? "total " + root.bytes(root.iface.txTotal) : ""; opacity: 0.6; font.pixelSize: root.fonte * 0.75 }
                            }
                        }
                    }

                    Caixa {
                        id: caixaProcs
                        Layout.preferredWidth: 3
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        titulo: "procs"
                        info: root.d ? root.d.procs.total + " procs · " + root.d.procs.threads + " thr · " + root.d.procs.rodando + " run" : ""
                        cor: root.cProc
                        readonly property int linhas: 26
                        readonly property var colunas: [
                            { t: "pid", o: "pid", w: 4.2, dir: true },
                            { t: "programa", o: "nome", w: 0, dir: false },
                            { t: "usuário", o: "", w: 5.5, dir: false },
                            { t: "thr", o: "", w: 2.6, dir: true },
                            { t: "mem", o: "mem", w: 3.6, dir: true },
                            { t: "cpu%", o: "cpu", w: 6.5, dir: true }
                        ]

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: caixaProcs.colunas.length
                                Mono {
                                    id: cabCol
                                    required property int index
                                    readonly property var c: caixaProcs.colunas[index]
                                    Layout.fillWidth: c.w === 0
                                    Layout.preferredWidth: c.w ? root.fonte * c.w : -1
                                    horizontalAlignment: c.dir ? Text.AlignRight : Text.AlignLeft
                                    text: c.t + (root.ordem === c.o ? (c.o === "pid" || c.o === "nome" ? "▲" : "▼") : "")
                                    font.weight: Font.Bold
                                    color: root.ordem === c.o ? root.cProc : Kirigami.Theme.textColor
                                    opacity: c.o ? 1 : 0.7
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: cabCol.c.o !== ""
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.ordem = cabCol.c.o
                                    }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.alfa(root.cProc, 0.4) }

                        Repeater {
                            model: caixaProcs.linhas
                            Item {
                                id: linhaProc
                                required property int index
                                readonly property var p: root.procs[index] || null
                                visible: !!p
                                Layout.fillWidth: true
                                implicitHeight: conteudoProc.implicitHeight + 2
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: mouseProc.containsMouse ? root.alfa(root.cProc, 0.15) : linhaProc.index % 2 ? root.alfa(Kirigami.Theme.textColor, 0.03) : "transparent"
                                }
                                MouseArea {
                                    id: mouseProc
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onContainsMouseChanged: if (containsMouse && linhaProc.p) root.cmdFoco = linhaProc.p.cmd
                                }
                                RowLayout {
                                    id: conteudoProc
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    Mono { Layout.preferredWidth: root.fonte * 4.2; horizontalAlignment: Text.AlignRight; text: linhaProc.p ? linhaProc.p.pid : ""; opacity: 0.6 }
                                    Mono {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: linhaProc.p ? linhaProc.p.nome : ""
                                        font.weight: linhaProc.p && linhaProc.p.estado === "R" ? Font.Bold : Font.Normal
                                        color: linhaProc.p && linhaProc.p.estado === "R" ? root.gVerde : Kirigami.Theme.textColor
                                    }
                                    Mono { Layout.preferredWidth: root.fonte * 5.5; elide: Text.ElideRight; text: linhaProc.p ? linhaProc.p.usuario : ""; opacity: 0.6 }
                                    Mono { Layout.preferredWidth: root.fonte * 2.6; horizontalAlignment: Text.AlignRight; text: linhaProc.p ? linhaProc.p.threads : ""; opacity: 0.7 }
                                    Mono {
                                        Layout.preferredWidth: root.fonte * 3.6
                                        horizontalAlignment: Text.AlignRight
                                        text: linhaProc.p ? root.bytes(linhaProc.p.mem) : ""
                                        color: root.d && linhaProc.p ? root.grad(4 * root.pct(linhaProc.p.mem, root.d.mem.total)) : Kirigami.Theme.textColor
                                    }
                                    RowLayout {
                                        Layout.preferredWidth: root.fonte * 6.5
                                        spacing: 3
                                        Medidor {
                                            implicitHeight: root.fonte * 0.5
                                            valor: linhaProc.p ? Math.min(100, linhaProc.p.cpu * 4) : 0
                                        }
                                        Mono {
                                            Layout.preferredWidth: root.fonte * 2.6
                                            horizontalAlignment: Text.AlignRight
                                            text: linhaProc.p ? linhaProc.p.cpu.toFixed(1) : ""
                                            color: root.grad(linhaProc.p ? linhaProc.p.cpu * 4 : 0)
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Mono {
                            Layout.fillWidth: true
                            visible: root.cmdFoco !== ""
                            text: "> " + root.cmdFoco
                            elide: Text.ElideMiddle
                            font.pixelSize: root.fonte * 0.75
                            opacity: 0.7
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: cabecalho.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: 16
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.alfa(root.terracota, 0.35) }
                        GradientStop { position: 0.6; color: root.alfa(root.ambar, 0.15) }
                        GradientStop { position: 1; color: root.alfa(root.violeta, 0.2) }
                    }
                    border.width: 1
                    border.color: root.alfa(root.terracota, 0.5)
                    RowLayout {
                        id: cabecalho
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing
                        Item {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                            Image {
                                visible: root.humor !== "skull"
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 6
                                width: parent.width * 0.7
                                height: parent.height * 0.7
                                source: Qt.resolvedUrl("../icons/conta.svg")
                                sourceSize: Qt.size(parent.width, parent.height)
                                fillMode: Image.PreserveAspectFit
                                SequentialAnimation on scale {
                                    running: root.abaClaude && root.expanded
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.06; duration: root.humor === "fire" ? 250 : 1200; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: root.humor === "fire" ? 250 : 1200; easing.type: Easing.InOutSine }
                                }
                            }
                            Image {
                                id: sprite
                                anchors.fill: parent
                                property int quadro
                                source: Qt.resolvedUrl("../icons/" + root.humor + "-" + quadro + ".png")
                                sourceSize: Qt.size(parent.width, parent.height)
                                fillMode: Image.PreserveAspectFit
                                smooth: false
                                Timer {
                                    running: root.abaClaude && root.expanded
                                    repeat: true
                                    interval: ({ fire: 120, halo: 250, rain: 100, skull: 200, smart: 300 })[root.humor]
                                    onTriggered: sprite.quadro = (sprite.quadro + 1) % 6
                                }
                            }
                        }
                        ColumnLayout {
                            spacing: 2
                            RowLayout {
                                spacing: 8
                                PC3.Label { textFormat: Text.PlainText; text: "Claude"; font.pixelSize: root.fonte * 1.6; font.weight: Font.Black; color: root.creme }
                                Pilula { texto: root.humorTexto(); cor: root.humorCor() }
                            }
                            PC3.Label {
                                textFormat: Text.PlainText
                                text: root.idadeClaude > 10 ? "sem dado do coletor há " + root.idadeTxt(root.idadeClaude) : "usage ao vivo"
                                font.pixelSize: root.fonte * 0.85
                                color: root.idadeClaude > 10 ? root.vermelho : root.ambarClaro
                            }
                        }
                        Item { Layout.fillWidth: true }
                        PC3.Label {
                            textFormat: Text.PlainText
                            visible: !!root.stats
                            Layout.alignment: Qt.AlignBottom
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.Wrap
                            text: !root.stats ? "" : root.stats.erro ? "estatísticas: " + root.stats.erro
                                : "estatísticas de " + root.stats.arquivos + " transcripts · há " + root.idadeTxt(root.agora - root.stats.geradoEm)
                                  + (root.stats.semConta ? "\n" + root.num(root.stats.semConta) + " respostas sem conta no history" : "")
                            font.pixelSize: root.fonte * 0.7
                            color: root.stats && (root.stats.erro || root.agora - root.stats.geradoEm > 180) ? root.vermelho : Kirigami.Theme.textColor
                            opacity: 0.55
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: root.claude ? root.claude.claude.length : 0
                        Cartao {
                            id: cartaoPerfil
                            required property int index
                            readonly property var perfil: root.claude.claude[index]
                            readonly property var cores: root.paleta(perfil.perfil)
                            readonly property real pico: root.principal(perfil)
                            readonly property var st: root.statsDe(perfil.perfil)
                            readonly property var linhasStats: [["respostas", "msgs"], ["prompts", "prompts"], ["sessões", "sessoes"],
                                ["ferramentas", "tools"], ["tokens saída", "saida"], ["tokens entrada", "entrada"], ["cache lido", "cache"]]
                            readonly property var porDia: {
                                var l = []
                                if (st) for (var i = 0; i < st.dias.length; i++) l.push(st.dias[i].saida)
                                return l
                            }
                            readonly property var kpis: {
                                if (!st) return []
                                var s = st.semana, mediaDia = s.saida / 7, abertas = 0
                                var ses = root.claude.sessoes || []
                                for (var i = 0; i < ses.length; i++) if (ses[i].perfil === perfil.perfil) abertas++
                                var lidos = s.cache + s.entrada
                                var parado = root.agora - st.ultimaHora
                                return [
                                    ["ritmo agora", root.num(st.ritmo.saidaH) + "/h", st.ritmo.msgsH + " resp/h · saída"],
                                    ["hoje × média", mediaDia > 0 ? Math.round(100 * st.hoje.saida / mediaDia) + "%" : "-", "média " + root.num(Math.round(mediaDia)) + "/dia"],
                                    ["cache hit", lidos > 0 ? Math.round(100 * s.cache / lidos) + "%" : "-", "do contexto · 7 dias"],
                                    ["saída/resposta", root.num(s.msgs ? Math.round(s.saida / s.msgs) : 0), (s.msgs ? (s.tools / s.msgs).toFixed(1) : "0") + " tools/resp"],
                                    ["sessões abertas", String(abertas), st.hoje.sessoes + " com atividade hoje"],
                                    ["última atividade", !st.ultimaHora ? "-" : parado < 3600 ? "nesta hora" : "há " + Math.floor(parado / 3600) + "h", st.projetos.length ? "top: " + st.projetos[0].nome : ""]
                                ]
                            }
                            function hojeDe(nome) {
                                if (!st) return 0
                                for (var i = 0; i < st.modelosHoje.length; i++) if (st.modelosHoje[i].nome === nome) return st.modelosHoje[i].saida
                                return 0
                            }
                            readonly property real somaModelos: {
                                var t = 0
                                if (st) for (var i = 0; i < st.modelos.length; i++) t += st.modelos[i].saida
                                return Math.max(1, t)
                            }
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 1
                            c1: cores[0]
                            c2: cores[1]
                            alerta: perfil.estado !== "ok" || pico >= 90

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Image {
                                    source: Qt.resolvedUrl("../icons/conta.svg")
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    sourceSize: Qt.size(16, 16)
                                }
                                PC3.Label { textFormat: Text.PlainText; text: "claude-" + cartaoPerfil.perfil.perfil; font.pixelSize: root.fonte * 1.1; font.weight: Font.Bold; color: cartaoPerfil.c2 }
                                Pilula {
                                    texto: cartaoPerfil.perfil.plano.replace("default_claude_", "").replace("_", " ").toUpperCase()
                                    cor: cartaoPerfil.c1
                                }
                                Item { Layout.fillWidth: true }
                                PC3.Label {
                                    textFormat: Text.PlainText
                                    text: cartaoPerfil.perfil.estado === "ok" ? "há " + root.idadeTxt(root.agora - cartaoPerfil.perfil.consultadoEm) : cartaoPerfil.perfil.estado
                                    font.pixelSize: root.fonte * 0.75
                                    color: cartaoPerfil.perfil.estado === "ok" ? Kirigami.Theme.textColor : root.vermelho
                                    opacity: cartaoPerfil.perfil.estado === "ok" ? 0.5 : 1
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                Anel {
                                    implicitWidth: Kirigami.Units.gridUnit * 4.6
                                    pct: cartaoPerfil.pico
                                    c1: cartaoPerfil.c1
                                    c2: cartaoPerfil.c2
                                    rotulo: "pico"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: cartaoPerfil.perfil.janelas.length
                                        ColumnLayout {
                                            id: janela
                                            required property int index
                                            readonly property var j: cartaoPerfil.perfil.janelas[index]
                                            Layout.fillWidth: true
                                            spacing: 3
                                            RowLayout {
                                                Layout.fillWidth: true
                                                PC3.Label { textFormat: Text.PlainText; text: janela.j.rotulo; font.pixelSize: root.fonte * 0.88; font.weight: Font.DemiBold }
                                                Item { Layout.fillWidth: true }
                                                PC3.Label { textFormat: Text.PlainText; text: root.falta(janela.j.reseta); font.pixelSize: root.fonte * 0.78; opacity: 0.55 }
                                                PC3.Label {
                                                    textFormat: Text.PlainText
                                                    text: Math.round(janela.j.pct) + "%"
                                                    font.pixelSize: root.fonte * 0.95
                                                    font.weight: Font.Black
                                                    color: root.corPct(janela.j.pct, cartaoPerfil.c2)
                                                }
                                            }
                                            BarraGradiente {
                                                Layout.fillWidth: true
                                                implicitHeight: 8
                                                pct: janela.j.pct
                                                c1: cartaoPerfil.c1
                                                c2: cartaoPerfil.c2
                                            }
                                            PC3.Label {
                                                textFormat: Text.PlainText
                                                readonly property var proj: root.projecao(janela.j)
                                                visible: !!proj
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: proj ? proj.texto : ""
                                                font.pixelSize: root.fonte * 0.7
                                                font.weight: proj && proj.estoura ? Font.Bold : Font.Normal
                                                color: proj && proj.estoura ? root.vermelho : Kirigami.Theme.textColor
                                                opacity: proj && proj.estoura ? 1 : 0.6
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle { visible: !!cartaoPerfil.st; Layout.fillWidth: true; implicitHeight: 1; color: root.bordaSutil }
                            GridLayout {
                                visible: !!cartaoPerfil.st
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 6
                                rowSpacing: 6
                                Repeater {
                                    model: cartaoPerfil.kpis.length
                                    Rectangle {
                                        id: kpi
                                        required property int index
                                        readonly property var k: cartaoPerfil.kpis[index]
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: colKpi.implicitHeight + 8
                                        radius: 8
                                        color: root.alfa(cartaoPerfil.c1, 0.1)
                                        border.width: 1
                                        border.color: root.alfa(cartaoPerfil.c1, 0.3)
                                        ColumnLayout {
                                            id: colKpi
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            anchors.leftMargin: 7
                                            spacing: 0
                                            PC3.Label { textFormat: Text.PlainText; text: kpi.k[0]; font.pixelSize: root.fonte * 0.64; font.weight: Font.Bold; font.capitalization: Font.AllUppercase; opacity: 0.55 }
                                            PC3.Label { textFormat: Text.PlainText; text: kpi.k[1]; font.pixelSize: root.fonte * 1.05; font.weight: Font.Black; color: cartaoPerfil.c2 }
                                            PC3.Label { textFormat: Text.PlainText; Layout.fillWidth: true; text: kpi.k[2]; elide: Text.ElideRight; font.pixelSize: root.fonte * 0.64; opacity: 0.6 }
                                        }
                                    }
                                }
                            }
                            GridLayout {
                                visible: !!cartaoPerfil.st
                                Layout.fillWidth: true
                                columns: 4
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: 1
                                Repeater {
                                    model: cartaoPerfil.st ? (cartaoPerfil.linhasStats.length + 1) * 4 : 0
                                    PC3.Label {
                                        textFormat: Text.PlainText
                                        required property int index
                                        readonly property int lin: Math.floor(index / 4)
                                        readonly property int col: index % 4
                                        Layout.fillWidth: col === 0
                                        horizontalAlignment: col === 0 ? Text.AlignLeft : Text.AlignRight
                                        text: lin === 0 ? ["", "hoje", "7 dias", "total"][col]
                                            : col === 0 ? cartaoPerfil.linhasStats[lin - 1][0]
                                            : root.num(cartaoPerfil.st[["", "hoje", "semana", "total"][col]][cartaoPerfil.linhasStats[lin - 1][1]])
                                        font.family: col === 0 ? Kirigami.Theme.defaultFont.family : root.mono
                                        font.pixelSize: root.fonte * (lin === 0 ? 0.72 : 0.82)
                                        font.weight: lin === 0 || col === 1 ? Font.Bold : Font.Normal
                                        font.capitalization: lin === 0 ? Font.AllUppercase : Font.MixedCase
                                        opacity: lin === 0 ? 0.55 : col === 0 ? 0.75 : 1
                                        color: lin > 0 && col === 1 ? cartaoPerfil.c2 : Kirigami.Theme.textColor
                                    }
                                }
                            }
                            Barras {
                                visible: !!cartaoPerfil.st
                                valores: cartaoPerfil.porDia
                                c1: cartaoPerfil.c1
                                c2: cartaoPerfil.c2
                                destaque: valores.length - 1
                            }
                            Rodape {
                                visible: !!cartaoPerfil.st
                                esquerda: cartaoPerfil.st ? cartaoPerfil.st.dias[0].dia : ""
                                meio: "tokens de saída por dia"
                                direita: "hoje"
                            }
                            Barras {
                                visible: !!cartaoPerfil.st
                                implicitHeight: Kirigami.Units.gridUnit * 1.6
                                valores: cartaoPerfil.st ? cartaoPerfil.st.horas : []
                                c1: cartaoPerfil.c2
                                c2: cartaoPerfil.c1
                                destaque: new Date(root.agora * 1000).getHours()
                            }
                            Rodape {
                                visible: !!cartaoPerfil.st
                                esquerda: "0h"
                                meio: "respostas por hora · 7 dias"
                                direita: "23h"
                            }
                            PC3.Label { textFormat: Text.PlainText; visible: !!cartaoPerfil.st; text: "MODELOS MAIS USADOS · POR TOKENS DE SAÍDA"; font.pixelSize: root.fonte * 0.68; font.weight: Font.Bold; opacity: 0.55 }
                            Row {
                                visible: !!cartaoPerfil.st
                                Layout.fillWidth: true
                                height: 6
                                spacing: 1
                                Repeater {
                                    model: cartaoPerfil.st ? cartaoPerfil.st.modelos.length : 0
                                    Rectangle {
                                        required property int index
                                        width: Math.max(2, (parent.width - 4) * cartaoPerfil.st.modelos[index].saida / cartaoPerfil.somaModelos)
                                        height: 6
                                        radius: 3
                                        color: root.mistura(cartaoPerfil.c2, cartaoPerfil.c1, index / Math.max(1, cartaoPerfil.st.modelos.length - 1))
                                        opacity: 1 - index * 0.15
                                    }
                                }
                            }
                            GridLayout {
                                visible: !!cartaoPerfil.st
                                Layout.fillWidth: true
                                columns: 6
                                columnSpacing: 8
                                rowSpacing: 1
                                Repeater {
                                    model: cartaoPerfil.st ? (cartaoPerfil.st.modelos.length + 1) * 6 : 0
                                    PC3.Label {
                                        textFormat: Text.PlainText
                                        required property int index
                                        readonly property int lin: Math.floor(index / 6)
                                        readonly property int col: index % 6
                                        readonly property var m: lin > 0 ? cartaoPerfil.st.modelos[lin - 1] : null
                                        Layout.fillWidth: col === 0
                                        horizontalAlignment: col === 0 ? Text.AlignLeft : Text.AlignRight
                                        elide: Text.ElideRight
                                        text: lin === 0 ? ["modelo", "%", "resp 7d", "saída 7d", "saída hoje", "cache 7d"][col]
                                            : col === 0 ? m.nome
                                            : col === 1 ? Math.round(100 * m.saida / cartaoPerfil.somaModelos) + "%"
                                            : col === 2 ? root.num(m.msgs)
                                            : col === 3 ? root.num(m.saida)
                                            : col === 4 ? root.num(cartaoPerfil.hojeDe(m.nome))
                                            : root.num(m.cache)
                                        font.family: col === 0 ? Kirigami.Theme.defaultFont.family : root.mono
                                        font.pixelSize: root.fonte * (lin === 0 ? 0.64 : 0.78)
                                        font.weight: lin === 0 || col === 1 ? Font.Bold : lin === 1 ? Font.DemiBold : Font.Normal
                                        font.capitalization: lin === 0 ? Font.AllUppercase : Font.MixedCase
                                        opacity: lin === 0 ? 0.55 : 1
                                        color: lin > 0 && (col === 1 || col === 4) ? cartaoPerfil.c2 : Kirigami.Theme.textColor
                                    }
                                }
                            }
                            PC3.Label {
                                textFormat: Text.PlainText
                                visible: !!cartaoPerfil.st && cartaoPerfil.st.projetos.length > 0
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: {
                                    var l = []
                                    if (cartaoPerfil.st) for (var i = 0; i < cartaoPerfil.st.projetos.length; i++)
                                        l.push(cartaoPerfil.st.projetos[i].nome + " " + root.num(cartaoPerfil.st.projetos[i].msgs))
                                    return "projetos 7d: " + l.join(" · ")
                                }
                                font.pixelSize: root.fonte * 0.72
                                opacity: 0.75
                            }
                            PC3.Label {
                                textFormat: Text.PlainText
                                visible: !!cartaoPerfil.st && cartaoPerfil.st.desde > 0
                                text: cartaoPerfil.st ? "total desde " + root.dataCurta(cartaoPerfil.st.desde) + " · transcripts locais" : ""
                                font.pixelSize: root.fonte * 0.68
                                opacity: 0.45
                            }
                        }
                    }
                }

                Cartao {
                    id: cartaoSessoes
                    readonly property var lista: root.claude && root.claude.sessoes ? root.claude.sessoes : []
                    readonly property int maior: {
                        var m = 1
                        for (var i = 0; i < lista.length; i++) m = Math.max(m, lista[i].usoMiB)
                        return m
                    }
                    visible: lista.length > 0
                    c1: root.terracota
                    c2: root.violeta

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        PC3.Label { textFormat: Text.PlainText; text: "Sessões Claude"; font.pixelSize: root.fonte * 1.1; font.weight: Font.Bold; color: root.ambarClaro }
                        Item { Layout.fillWidth: true }
                        PC3.Label { textFormat: Text.PlainText; text: cartaoSessoes.lista.length + " abertas"; font.pixelSize: root.fonte * 0.75; opacity: 0.5 }
                    }
                    Repeater {
                        model: cartaoSessoes.lista.length
                        Item {
                            id: itemSessao
                            required property int index
                            readonly property var s: cartaoSessoes.lista[index]
                            readonly property var cores: root.paleta(s.perfil)
                            Layout.fillWidth: true
                            implicitHeight: linhaSessao.implicitHeight + 4
                            Rectangle {
                                anchors.left: parent.left
                                height: parent.height
                                radius: 5
                                width: parent.width * Math.min(1, itemSessao.s.usoMiB / cartaoSessoes.maior)
                                opacity: 0.25
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: itemSessao.cores[0] }
                                    GradientStop { position: 1; color: itemSessao.cores[1] }
                                }
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                            RowLayout {
                                id: linhaSessao
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Rectangle { width: 8; height: 8; radius: 4; color: itemSessao.cores[0] }
                                PC3.Label { textFormat: Text.PlainText; text: itemSessao.s.perfil.charAt(0).toUpperCase(); font.weight: Font.Black; font.pixelSize: root.fonte * 0.8; color: itemSessao.cores[0] }
                                PC3.Label { textFormat: Text.PlainText; Layout.fillWidth: true; text: itemSessao.s.pasta; elide: Text.ElideRight; font.pixelSize: root.fonte * 0.82 }
                                Mono {
                                    text: itemSessao.s.usoMiB >= 1024 ? (itemSessao.s.usoMiB / 1024).toFixed(1) + "G" : itemSessao.s.usoMiB + "M"
                                    font.weight: Font.Bold
                                    color: itemSessao.cores[1]
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
