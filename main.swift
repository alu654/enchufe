// Enchufe: muestra en la barra de menú los W de carga, el tiempo para llenar y la temperatura.
import Cocoa
import IOKit
import ServiceManagement

// MARK: - Sensores de temperatura (IOHID, sin root)
typealias IOHIDEventSystemClientRef = OpaquePointer
typealias IOHIDServiceClientRef = OpaquePointer
typealias IOHIDEventRef = OpaquePointer
@_silgen_name("IOHIDEventSystemClientCreate") func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> IOHIDEventSystemClientRef?
@_silgen_name("IOHIDEventSystemClientSetMatching") func IOHIDEventSystemClientSetMatching(_ c: IOHIDEventSystemClientRef, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func IOHIDEventSystemClientCopyServices(_ c: IOHIDEventSystemClientRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyProperty") func IOHIDServiceClientCopyProperty(_ s: IOHIDServiceClientRef, _ k: CFString) -> CFTypeRef?
@_silgen_name("IOHIDServiceClientCopyEvent") func IOHIDServiceClientCopyEvent(_ s: IOHIDServiceClientRef, _ t: Int64, _ a: Int32, _ b: Int64) -> IOHIDEventRef?
@_silgen_name("IOHIDEventGetFloatValue") func IOHIDEventGetFloatValue(_ e: IOHIDEventRef, _ f: Int32) -> Double

final class Termometro {
    private let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    init() {
        if let c = client {
            _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
    }
    /// (cpu máx, batería) en °C
    func leer() -> (cpu: Double?, bateria: Double?) {
        guard let c = client, let servicios = IOHIDEventSystemClientCopyServices(c) as? [AnyObject] else { return (nil, nil) }
        var cpu: [Double] = [], bat: [Double] = []
        for obj in servicios {
            let s = unsafeBitCast(obj, to: IOHIDServiceClientRef.self)
            let nombre = (IOHIDServiceClientCopyProperty(s, "Product" as CFString) as? String ?? "").lowercased()
            guard let ev = IOHIDServiceClientCopyEvent(s, 15, 0, 0) else { continue }
            let t = IOHIDEventGetFloatValue(ev, 15 << 16)
            guard t > 5, t < 130 else { continue }
            if nombre.contains("tdie") { cpu.append(t) }
            if nombre.contains("battery") || nombre.contains("gas gauge") { bat.append(t) }
        }
        return (cpu.max(), bat.isEmpty ? nil : bat.reduce(0, +) / Double(bat.count))
    }
}

// MARK: - Batería
struct Estado {
    var enchufado = false, cargando = false, lleno = false
    var porcentaje = 0
    var wCargador: Double = 0      // potencia nominal del cargador
    var wEntrada: Double = 0       // lo que entra de la pared
    var wBateria: Double = 0       // lo que entra a la batería (+) o sale (-)
    var minutosParaLlenar: Int?
}

func leerBateria() -> Estado {
    var e = Estado()
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return e }
    defer { IOObjectRelease(svc) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = props?.takeRetainedValue() as? [String: Any] else { return e }

    func int(_ v: Any?) -> Int { (v as? NSNumber)?.int64Value.toInt ?? 0 }
    e.enchufado = d["ExternalConnected"] as? Bool ?? false
    e.cargando = d["IsCharging"] as? Bool ?? false
    e.lleno = d["FullyCharged"] as? Bool ?? false
    e.porcentaje = int(d["CurrentCapacity"])
    let mV = Double(int(d["Voltage"]))
    let mA = Double(int(d["InstantAmperage"] ?? d["Amperage"]))
    e.wBateria = mV * mA / 1_000_000
    if let ad = d["AdapterDetails"] as? [String: Any] { e.wCargador = Double(int(ad["Watts"])) }
    if let pt = d["PowerTelemetryData"] as? [String: Any] {
        e.wEntrada = Double(int(pt["SystemPowerIn"])) / 1000
    }
    let ttf = int(d["AvgTimeToFull"])
    if ttf > 0 && ttf < 65535 { e.minutosParaLlenar = ttf }
    else if e.cargando, mA > 0 {
        let cur = Double(int(d["AppleRawCurrentCapacity"])), max = Double(int(d["AppleRawMaxCapacity"]))
        if max > cur { e.minutosParaLlenar = Int((max - cur) / mA * 60) }
    }
    return e
}
extension Int64 { var toInt: Int { Int(truncatingIfNeeded: self) } }

// MARK: - App
final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let termo = Termometro()
    let menu = NSMenu()
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.menu = menu
        actualizar()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.actualizar() }
    }

    func termico() -> (texto: String, caliente: Bool) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return ("normal", false)
        case .fair: return ("tibia", false)
        case .serious: return ("caliente", true)
        case .critical: return ("muy caliente", true)
        @unknown default: return ("?", false)
        }
    }

    func dur(_ m: Int) -> String { m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m)m" }

    func actualizar() {
        let b = leerBateria()
        let t = termo.leer()
        let th = termico()
        let tempRef = t.cpu ?? t.bateria
        let caliente = th.caliente || (tempRef ?? 0) >= 85 || (t.bateria ?? 0) >= 40

        // Siempre visible; desenchufada muestra sólo la temperatura.
        item.isVisible = true

        var partes: [String] = []
        let w = b.wEntrada > 0.5 ? b.wEntrada : max(b.wBateria, 0)
        if b.enchufado {
            if b.cargando {
                partes.append("⚡\(Int(w.rounded()))W")
                if let m = b.minutosParaLlenar { partes.append(dur(m)) }
            } else {
                partes.append(b.lleno || b.porcentaje >= 100 ? "🔌 llena" : "🔌 en pausa")
            }
        }
        if let tc = tempRef { partes.append("\(Int(tc.rounded()))°") }

        let attr = NSMutableAttributedString(string: partes.joined(separator: " · "),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        if caliente {
            attr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: attr.length))
        }
        item.button?.attributedTitle = attr

        // Menú con detalle
        menu.removeAllItems()
        func linea(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        linea("Batería: \(b.porcentaje)%  \(b.cargando ? "cargando" : b.enchufado ? "enchufada, sin cargar" : "a batería")")
        if b.enchufado {
            if b.wCargador > 0 { linea("Cargador: \(Int(b.wCargador)) W") }
            if b.wEntrada > 0 { linea("Entrando de la pared: \(String(format: "%.1f", b.wEntrada)) W") }
        }
        linea(String(format: "A la batería: %+.1f W", b.wBateria))
        if b.cargando {
            let vel = b.wBateria >= 30 ? "rápida" : b.wBateria >= 12 ? "normal" : "lenta"
            linea("Velocidad: \(vel)\(b.minutosParaLlenar.map { " · llena en \(dur($0))" } ?? "")")
        }
        menu.addItem(.separator())
        if let c = t.cpu { linea(String(format: "Chip: %.0f °C", c)) }
        if let bt = t.bateria { linea(String(format: "Batería: %.0f °C", bt)) }
        linea("Estado térmico: \(th.texto)\(caliente ? " 🔥" : "")")
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { if s.status == .enabled { try s.unregister() } else { try s.register() } } catch { NSSound.beep() }
        actualizar()
    }
}

if CommandLine.arguments.contains("--dump") {
    let b = leerBateria(); let t = Termometro().leer()
    print(b, t, ProcessInfo.processInfo.thermalState.rawValue); exit(0)
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
