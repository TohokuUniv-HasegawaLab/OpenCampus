import SwiftUI
import CoreBluetooth
import Combine

// ==== 共通UUID（ESP32/PC用と合わせる）====
let SERVICE_UUID = CBUUID(string: "e44b9ddb-630f-9052-9f2c-1b764b52ce72")
let CHAR_UUID    = CBUUID(string: "ebe9db63-5705-8280-37d5-808d4f5a35fb")

// ==== トリガ用 Peripheral のローカル名（Windows側はこれを探す）====
let IPAD_TRIGGER_NAME = "SYNC"

// =====================================================
// MARK: - ViewModel
// =====================================================
final class BLEVM: NSObject, ObservableObject,
                   CBCentralManagerDelegate, CBPeripheralDelegate,
                   CBPeripheralManagerDelegate {

    // --- UI state ---
    @Published var isScanning = false
    @Published var peripherals: [CBPeripheral] = []
    @Published var statuses: [UUID: String] = [:]   // Discovered/Connecting/Connected/Ready/Disconnected/Failed
    @Published var chars: [UUID: CBCharacteristic] = [:]
    @Published var logText: String = ""

    // 固定RGB（SENDAI側では未使用でOK）
    let fixedR: UInt8 = 0
    let fixedG: UInt8 = 128
    let fixedB: UInt8 = 255

    // --- Central / Peripheral managers ---
    private var cm: CBCentralManager!
    private var pm: CBPeripheralManager?            // iPad を Peripheral 化
    private var triggerChar: CBMutableCharacteristic?

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
    
    func payloadBlinkAllFast(duration: UInt16, routeId: UInt8 = 0) -> Data {
        var d = Data(count: 11)
        d[0]  = 0x02                    // ★ blinkAll
        d[1]  = fixedR; d[2] = fixedG; d[3] = fixedB
        d[4]  = UInt8(duration & 0xFF)
        d[5]  = UInt8(duration >> 8)
        d[6]  = 1                       // ★ period_ms = 1 (最速)
        d[7]  = 0
        d[8]  = 0; d[9] = 0             // offset=0
        d[10] = routeId
        return d
    }


    // =====================================================
    // MARK: - Central (ESP32制御)
    // =====================================================
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            log("Bluetooth poweredOn (Central)")
        } else {
            isScanning = false
            log("Bluetooth state=\(central.state.rawValue)")
        }
    }

    // スキャン：広告サイズ問題回避のため withServices=nil で広めに拾う
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
    
    func sendAllFastBlink(duration: UInt16 = 5000, triggerPCFirst: Bool = false) {
        if triggerPCFirst { notifyPCTrigger() }
        for p in peripherals where statuses[p.identifier] == "Ready" {
            guard let ch = chars[p.identifier] else { continue }
            let pl = payloadBlinkAllFast(duration: duration, routeId: 0)
            log("Send FAST BLINK to \(p.name ?? "Unknown"): dur=\(duration) period=1ms")
            p.writeValue(pl, for: ch, type: .withoutResponse)
        }
    }


    private func scanCycle() {
        guard isScanning else { return }
        cm.stopScan()
        cm.scanForPeripherals(withServices: [SERVICE_UUID],
                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("Scan start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.cm.stopScan()
            self.log("Scan pause")
            guard self.isScanning else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.scanCycle() }
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        if !peripherals.contains(where: { $0.identifier == p.identifier }) {
            peripherals.append(p)
            statuses[p.identifier] = "Discovered"
            let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            log("Discovered \(p.name ?? "Unknown") rssi=\(RSSI) uuids=\(uuids)")
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
        peripheral.discoverCharacteristics([CHAR_UUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error { log("DiscoverCharacteristics error: \(e.localizedDescription)"); return }
        guard let c = service.characteristics?.first(where: { $0.uuid == CHAR_UUID }) else {
            log("CTRL characteristic not found on \(peripheral.name ?? "Unknown")"); return
        }
        chars[peripheral.identifier] = c
        statuses[peripheral.identifier] = "Ready"
        log("Characteristic ready on \(peripheral.name ?? "Unknown")")
    }

    // 名前一致（厳密）
    func peripheral(named name: String) -> CBPeripheral? {
        peripherals.first(where: { norm($0.name) == norm(name) })
    }
    // 必要なら部分一致に緩める：
    func peripheral(namedLike key: String) -> CBPeripheral? {
        let k = norm(key)
        return peripherals.first(where: { norm($0.name).contains(k) })
    }

    // Ready待ち（接続→Characteristic取得）
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
    // MARK: - iPad as Peripheral（PCへトリガ通知）
    // =====================================================
    func startTriggerPeripheral() {
        if pm == nil {
            pm = CBPeripheralManager(delegate: self, queue: .main)
            log("Trigger peripheral init…")
        } else {
            log("Trigger peripheral already init")
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            // サービス & キャラ（notify/read）を作る
            let props: CBCharacteristicProperties = [.notify, .read]
            let perms: CBAttributePermissions   = [.readable]
            let ch = CBMutableCharacteristic(type: CHAR_UUID,
                                             properties: props,
                                             value: nil,
                                             permissions: perms)
            let svc = CBMutableService(type: SERVICE_UUID, primary: true)
            svc.characteristics = [ch]
            peripheral.removeAllServices()
            peripheral.add(svc)
            triggerChar = ch
            log("Trigger service added")
        default:
            log("Peripheral(state)=\(peripheral.state.rawValue)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let e = error { log("didAdd error: \(e.localizedDescription)"); return }
        // 広告開始（名前 + サービスUUID）
        let ad: [String: Any] = [
            CBAdvertisementDataLocalNameKey: IPAD_TRIGGER_NAME,
            CBAdvertisementDataServiceUUIDsKey: [SERVICE_UUID]
        ]
        peripheral.startAdvertising(ad)
        log("Advertising \(IPAD_TRIGGER_NAME)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        log("PC subscribed")
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        log("PC unsubscribed")
    }

    /// PCへ合図（notifyで 0x01 を送る）
    func notifyPCTrigger() {
        guard let pm = pm, let ch = triggerChar else {
            log("Trigger peripheral not ready"); return
        }
        let ok = pm.updateValue(Data([0x01]), for: ch, onSubscribedCentrals: nil)
        log(ok ? "Sent notify(0x01) to PC" : "Notify buffer full; retry later")
        if !ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.notifyPCTrigger() }
        }
    }

    // =====================================================
    // MARK: - Routes（既存のルート制御）
    // =====================================================

    enum RouteKind {
        case sendai(routeId: UInt8)       // SENDAI 1台で切替
        case sendaiMumbaiLondon            // 2台へ前後半（累積オフセット）
        case three_NCC      //3台のNCCを経由
    }

    struct RouteParam { let duration: UInt16; let px: UInt16; let kind: RouteKind }

    // 送信先名（ESP32 の Local Name と一致）
    let NAME_SENDAI = "SENDAI"

    // 4ルート（現場値は必要に応じて調整）
    let ROUTE_TABLE: [String: RouteParam] = [
        "SENDAI→LONDON":             .init(duration: 10000, px: 7, kind: .sendai(routeId: 0)),
        "SENDAI→SEOUL→LONDON":       .init(duration: 7000, px:  5, kind: .sendai(routeId: 1)),
        "SENDAI→FRANKFURT→LONDON":   .init(duration: 7000, px:  5, kind: .sendai(routeId: 2)),
        "SENDAI→MUMBAI→LONDON":       .init(duration:  4000, px:  3, kind: .sendaiMumbaiLondon),
        "SENDAI→SEOUL→MUNBAI→FRANKFURT→LONDON": .init(duration:  1000, px:  1, kind: .three_NCC)
    ]

    var ROUTE_NAMES: [String] { Array(ROUTE_TABLE.keys).sorted() }

    // 送信本体
    func sendUnifiedRoute(_ routeName: String) {
        guard let rp = ROUTE_TABLE[routeName] else { log("Route not defined: \(routeName)"); return }

        switch rp.kind {
        case .sendai(let rid):
            guard let p = peripheral(named: NAME_SENDAI) ?? peripheral(namedLike: NAME_SENDAI)
            else { log("Peripheral not found: \(NAME_SENDAI)"); return }
            ensureReady(p) { ok in
                guard ok, let ch = self.chars[p.identifier] else { self.log("SENDAI not Ready"); return }
                let pl = self.payloadChase(duration: rp.duration, px: rp.px, offset: 0, routeId: rid)
                self.log("Send \(routeName) to SENDAI route_id=\(rid) dur=\(rp.duration) px=\(rp.px)")
                p.writeValue(pl, for: ch, type: .withoutResponse)
            }

        case .sendaiMumbaiLondon:
            let segs: [(name: String, dur: UInt16, px: UInt16, routeID: UInt8)] = [
                ("SD→MB",  rp.duration, rp.px, 0),
                ("MB→LO",  rp.duration, rp.px, 0)
            ]
            var acc: UInt16 = 0
            func sendNext(_ idx: Int) {
                if idx >= segs.count { return }
                let seg = segs[idx]
                guard let p = self.peripheral(named: seg.name) ?? self.peripheral(namedLike: seg.name)
                else { self.log("Peripheral not found: \(seg.name)"); sendNext(idx+1); return }
                self.ensureReady(p) { ok in
                    guard ok, let ch = self.chars[p.identifier] else { self.log("Not Ready: \(seg.name)"); sendNext(idx+1); return }
                    let pl = self.payloadChase(duration: seg.dur, px: seg.px, offset: acc, routeId: seg.routeID)
                    self.log("Send \(seg.name): dur=\(seg.dur) px=\(seg.px) off=\(acc)")
                    p.writeValue(pl, for: ch, type: .withoutResponse)
                    acc &+= (seg.dur/2)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sendNext(idx+1) }
                }
            }
            sendNext(0)

        case .three_NCC:
            // 4セグメント：①SENDAI前半 ②S→M ③M→F ④SENDAI後半
            // dur/px は例。必要に応じてROUTE_TABLEからrp.duration/rp.px等で調整
            struct Hop { let name: String; let dur: UInt16; let px: UInt16; let routeId: UInt8 }
            let hops: [Hop] = [
                .init(name: "SENDAI", dur: (rp.duration-1000), px: rp.px, routeId: 10), // 前半(0..14) 青
                .init(name: "SL→MB",    dur: rp.duration, px: rp.px, routeId:  0), // 中央1
                .init(name: "MB→FR",    dur: rp.duration, px: rp.px, routeId:  0), // 中央2
                .init(name: "SENDAI", dur: (rp.duration-1000), px: rp.px, routeId: 11)  // 後半(15..end) 緑
            ]

            var acc: UInt16 = 0
            func sendNext(_ idx: Int) {
                if idx >= hops.count { return }
                let h = hops[idx]
                guard let p = self.peripheral(named: h.name) ?? self.peripheral(namedLike: h.name)
                else { self.log("Peripheral not found: \(h.name)"); sendNext(idx+1); return }

                self.ensureReady(p) { ok in
                    guard ok, let ch = self.chars[p.identifier] else { self.log("Not Ready: \(h.name)"); sendNext(idx+1); return }
                    let pl = self.payloadChase(duration: h.dur, px: h.px, offset: acc, routeId: h.routeId)
                    self.log("Send \(h.name): dur=\(h.dur) px=\(h.px) off=\(acc) routeId=\(h.routeId)")
                    p.writeValue(pl, for: ch, type: .withoutResponse)
                    acc &+= 200  // 累積オフセットで順に遅らせる
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { sendNext(idx+1) }
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
                // トップ操作
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button(vm.isScanning ? "Scanning..." : "Scan") { vm.startScan() }
                            .disabled(vm.isScanning)
                            .font(.system(size: 18, weight: .bold))

                        Button("Stop Scan") { vm.stopScan() }
                            .font(.system(size: 16))

                        Spacer()

                        Button("Send Route (Chase)") {
                            // ① PCへ合図（iPad→PC：notify 0x01）
                            vm.notifyPCTrigger()
                            // ② 少し待ってからLED側へ送信
                            let name = vm.ROUTE_NAMES[selectedRouteIndex]
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0) {
                                vm.sendUnifiedRoute(name)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: 20, weight: .bold))
                        
                        Button("Fast Blink (All)") {
                            vm.sendAllFastBlink(duration: 10000, triggerPCFirst: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.system(size: 16, weight: .semibold))
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

                    Text("PCへトリガ通知 → 0.3秒後にESP制御。SENDAI系はroute_id=0/1/2で切替。MUMBAI系は2台へ累積オフセット送信。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal)

                // デバイス一覧
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
                                if let _ = vm.chars[p.identifier],
                                   (vm.statuses[p.identifier] == "Ready") {
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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(2)))
                    .padding(.horizontal)
            }
            .navigationTitle("ESP32 Route Controller")
            .onAppear {
                // iPad を Peripheral 化（PCが購読してくる）
                vm.startTriggerPeripheral()
            }
        }
    }
}

