import SwiftUI
import CoreBluetooth
import Combine

// ==== BLE UUIDs（ESP32側と一致させる） ====
let SERVICE_UUID = CBUUID(string: "e44b9ddb-630f-9052-9f2c-1b764b52ce72")
let CTRL_UUID    = CBUUID(string: "ebe9db63-5705-8280-37d5-808d4f5a35fb")

// =====================================================
// MARK: - ViewModel
// =====================================================
final class BLEVM: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // UI state
    @Published var isScanning = false
    @Published var peripherals: [CBPeripheral] = []
    @Published var statuses: [UUID: String] = [:]   // Discovered/Connecting/Connected/Ready/Disconnected/Failed
    @Published var chars: [UUID: CBCharacteristic] = [:]
    @Published var logText: String = ""

    // 固定RGB（送信に入れるが、SENDAI側では未使用でOK）
    let fixedR: UInt8 = 0
    let fixedG: UInt8 = 128
    let fixedB: UInt8 = 255

    private var cm: CBCentralManager!

    override init() {
        super.init()
        cm = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Logging
    private func ts() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
    func log(_ s: String) {
        let line = "[\(ts())] \(s)\n"
        print(line)
        logText.append(line)
    }

    // MARK: - Helpers
    func norm(_ name: String?) -> String {
        (name ?? "")
            .replacingOccurrences(of: "　", with: " ")
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
    }

    // 11Bペイロード（index=10 が route_id）
    func payloadChase(duration: UInt16, px: UInt16, offset: UInt16, routeId: UInt8) -> Data {
        var d = Data(count: 11)
        d[0]  = 0x03                       // cmd = Chase
        d[1]  = fixedR; d[2] = fixedG; d[3] = fixedB
        d[4]  = UInt8(duration & 0xFF)
        d[5]  = UInt8(duration >> 8)
        d[6]  = UInt8(px & 0xFF)
        d[7]  = UInt8(px >> 8)
        d[8]  = UInt8(offset & 0xFF)
        d[9]  = UInt8(offset >> 8)
        d[10] = routeId                    // ← ここがルート識別子
        return d
    }

    // MARK: - Central state
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            log("Bluetooth poweredOn")
        } else {
            isScanning = false
            log("Bluetooth state=\(central.state.rawValue)")
        }
    }

    // MARK: - Scan (auto-restart)
    func startScan() {
        guard cm.state == .poweredOn else { log("Cannot scan: Bluetooth not poweredOn"); return }
        peripherals = []; statuses = [:]; chars = [:]
        isScanning = true
        scanCycle()
    }
    func stopScan() {
        isScanning = false
        cm.stopScan()
        log("Scan stopped")
    }
    private func scanCycle() {
        guard isScanning else { return }
        cm.stopScan()
        cm.scanForPeripherals(withServices: [SERVICE_UUID],
                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("Scan start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.cm.stopScan()
            self.log("Scan pause")
            guard self.isScanning else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.scanCycle() }
        }
    }

    // MARK: - Discover / Connect
    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        if !peripherals.contains(where: { $0.identifier == p.identifier }) {
            peripherals.append(p)
            statuses[p.identifier] = "Discovered"
            log("Discovered \(p.name ?? "Unknown") rssi=\(RSSI)")
        }
    }

    func connect(_ p: CBPeripheral) {
        statuses[p.identifier] = "Connecting"
        p.delegate = self
        log("Connecting to \(p.name ?? "Unknown")")
        cm.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statuses[peripheral.identifier] = "Connected"
        log("Connected \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices([SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        statuses[peripheral.identifier] = "Failed"
        log("Failed to connect \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "nil")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        statuses[peripheral.identifier] = "Disconnected"
        chars[peripheral.identifier] = nil
        log("Disconnected \(peripheral.name ?? "Unknown")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { log("DiscoverServices error: \(e.localizedDescription)"); return }
        guard let svc = peripheral.services?.first(where: { $0.uuid == SERVICE_UUID }) else {
            log("Service not found on \(peripheral.name ?? "Unknown")"); return
        }
        peripheral.discoverCharacteristics([CTRL_UUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error { log("DiscoverCharacteristics error: \(e.localizedDescription)"); return }
        guard let c = service.characteristics?.first(where: { $0.uuid == CTRL_UUID }) else {
            log("CTRL characteristic not found on \(peripheral.name ?? "Unknown")"); return
        }
        chars[peripheral.identifier] = c
        statuses[peripheral.identifier] = "Ready"
        log("Characteristic ready on \(peripheral.name ?? "Unknown")")
    }

    // MARK: - Resolve peripherals by name
    func peripheral(named name: String) -> CBPeripheral? {
        peripherals.first(where: { norm($0.name) == norm(name) })
    }

    // MARK: - Ensure Ready (connect & wait)
    func ensureReady(_ p: CBPeripheral, timeoutSec: Double = 6.0, poll: Double = 0.25, done: @escaping (Bool)->Void) {
        if statuses[p.identifier] != "Ready" {
            connect(p)
        }
        let deadline = Date().addingTimeInterval(timeoutSec)
        func tick() {
            if statuses[p.identifier] == "Ready" { done(true); return }
            if Date() > deadline { done(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + poll, execute: tick)
        }
        tick()
    }

    // =====================================================
    // MARK: - Routes
    // =====================================================

    // SENDAI 1台で3ルート（route_id 切替）
    // TOKYO→MUMBAI→LONDON は 2台（セグメント名で送信）
    enum RouteKind {
        case sendai(routeId: UInt8)       // SENDAI という名前の1台へ送る
        case tokyoMumbaiLondon            // 2台へ前半/後半を累積オフセット
    }

    struct RouteParam { let duration: UInt16; let px: UInt16; let kind: RouteKind }

    // 送信先名（ESP32 の Local Name と一致）
    let NAME_SENDAI = "SENDAI"

    // 4ルート（必要に応じて数値は現場で微調整）
    let ROUTE_TABLE: [String: RouteParam] = [
        "SENDAI→LONDON":             .init(duration: 15000, px: 20, kind: .sendai(routeId: 0)),
        "SENDAI→SEOUL→LONDON":       .init(duration: 8000, px: 7, kind: .sendai(routeId: 1)),
        "SENDAI→FRANKFURT→LONDON":   .init(duration: 8000, px: 7, kind: .sendai(routeId: 2)),
        "TOKYO→MUMBAI→LONDON":       .init(duration: 5000, px: 5, kind: .tokyoMumbaiLondon)
    ]

    var ROUTE_NAMES: [String] { Array(ROUTE_TABLE.keys).sorted() }

    // 送信本体
    func sendUnifiedRoute(_ routeName: String) {
        guard let rp = ROUTE_TABLE[routeName] else { log("Route not defined: \(routeName)"); return }

        switch rp.kind {
        case .sendai(let rid):
            guard let p = peripheral(named: NAME_SENDAI) else { log("Peripheral not found: \(NAME_SENDAI)"); return }
            ensureReady(p) { ok in
                guard ok, let ch = self.chars[p.identifier] else { self.log("SENDAI not Ready"); return }
                let pl = self.payloadChase(duration: rp.duration, px: rp.px, offset: 0, routeId: rid)
                self.log("Send \(routeName) to SENDAI route_id=\(rid) dur=\(rp.duration) px=\(rp.px)")
                p.writeValue(pl, for: ch, type: .withoutResponse)
            }

        case .tokyoMumbaiLondon:
            // 前半：TOKYO→MUMBAI、後半：MUMBAI→LONDON（両方に送る）
            let segs: [(name: String, dur: UInt16, px: UInt16)] = [
                ("T→M",  rp.duration, rp.px),
                ("M→L", rp.duration, rp.px)
            ]
            var acc: UInt16 = 0
            func sendNext(_ idx: Int) {
                if idx >= segs.count { return }
                let seg = segs[idx]
                guard let p = self.peripheral(named: seg.name) else { self.log("Peripheral not found: \(seg.name)"); sendNext(idx+1); return }
                self.ensureReady(p) { ok in
                    guard ok, let ch = self.chars[p.identifier] else { self.log("Not Ready: \(seg.name)"); sendNext(idx+1); return }
                    let pl = self.payloadChase(duration: seg.dur, px: seg.px, offset: acc, routeId: 0)
                    self.log("Send \(seg.name): dur=\(seg.dur) px=\(seg.px) off=\(acc)")
                    p.writeValue(pl, for: ch, type: .withResponse)
                    acc += 1000
                    // 少し間を空けて次へ
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { sendNext(idx+1) }
                }
            }
            sendNext(0)
        }
    }
}

// =====================================================
// MARK: - View
// =====================================================
struct ContentView: View {
    @StateObject var vm = BLEVM()
    @State private var selectedRouteIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // ルート送信カード
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button(vm.isScanning ? "Scanning..." : "Scan") { vm.startScan() }
                            .disabled(vm.isScanning)
                            .font(.system(size: 18, weight: .bold))

                        Button("Stop Scan") { vm.stopScan() }
                            .font(.system(size: 16))

                        Spacer()

                        Button("Send Route (Chase)") {
                            let name = vm.ROUTE_NAMES[selectedRouteIndex]
                            vm.sendUnifiedRoute(name)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: 20, weight: .bold))
                    }

                    HStack(spacing: 16) {
                        Text("Route").font(.headline)
                        Picker("", selection: $selectedRouteIndex) {
                            ForEach(0..<vm.ROUTE_NAMES.count, id: \.self) { i in
                                Text(vm.ROUTE_NAMES[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text("SENDAI系の3ルートは route_id で切替（0/1/2）。TOKYO→MUMBAI→LONDON は2台へ累積オフセット送信。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal)

                // デバイス一覧（確認＆手動操作）
                List {
                    ForEach(vm.peripherals, id: \.identifier) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.name ?? "Unknown")
                                    .font(.system(size: 18, weight: .semibold))
                                Spacer()
                                Text(vm.statuses[p.identifier] ?? "")
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Button("Connect") { vm.connect(p) }
                                if let ch = vm.chars[p.identifier], (vm.statuses[p.identifier] == "Ready") {
                                    Text("Characteristic OK").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Characteristic …").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Text("Log").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $vm.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                    .padding(.horizontal)
            }
            .navigationTitle("ESP32 Route Controller")
        }
    }
}

