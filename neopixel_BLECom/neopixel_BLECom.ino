#include <NimBLEDevice.h>
#include <Adafruit_NeoPixel.h>

// ==== ハード設定 ====
#define LED_PIN     5
#define NUM_LEDS    90
#define RX_LED_PIN  2   // 受信インジケータ用。基板に合わせて変更可（無ければ外す）

// ==== BLE設定 ====
static const char* DEVICE_NAME  = "SENDAI";
static const char* SERVICE_UUID = "e44b9ddb-630f-9052-9f2c-1b764b52ce72";
static const char* CHAR_UUID    = "ebe9db63-5705-8280-37d5-808d4f5a35fb";

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

// 受信コマンドバッファ（11Bプロトコル）
volatile bool hasCmd = false;
uint8_t  cmdBuf[11];

// RX LED制御
volatile bool rxBlinkReq = false;
unsigned long rxLedOffAt = 0;         // millis() で消灯時刻
const uint16_t rxBlinkMs = 60;        // 受信LEDを点ける時間

// 接続ハンドル保持（必要なら切断に使用）
volatile uint16_t lastConnId = 0;


// ==== BLE Callbacks ====
class ServerCB : public NimBLEServerCallbacks {
  // 新しい NimBLE で呼ばれる版
  void onConnect(NimBLEServer* s, NimBLEConnInfo& connInfo) {
    lastConnId = connInfo.getConnHandle();
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& connInfo, int reason) {
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->start(); // 再アドバタイズ
  }
  // 旧い NimBLE で呼ばれる版（引数なし）
  void onConnect(NimBLEServer* s) {
    lastConnId = 0; // 不明でもOK
  }
  void onDisconnect(NimBLEServer* s) {
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->start();
  }
};

class RxCB : public NimBLECharacteristicCallbacks {
  // 新しい NimBLE で呼ばれる版
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) {
    handleWrite(c);
  }
  // 旧い NimBLE で呼ばれる版
  void onWrite(NimBLECharacteristic* c) {
    handleWrite(c);
  }
  // 共通処理
  void handleWrite(NimBLECharacteristic* c) {
    std::string v = c->getValue();
    if (v.size() == 11) {
      for (int i = 0; i < 11; i++) cmdBuf[i] = (uint8_t)v[i];
      hasCmd = true;
      rxBlinkReq = true; // 受信インジケータ要求
    }
  }
};



// ====== エフェクト関数 ======
void ledsOff() {
  for (int i = 0; i < NUM_LEDS; i++) strip.setPixelColor(i, 0);
  strip.show();
}

void solidColor(uint8_t r, uint8_t g, uint8_t b, uint16_t duration_ms) {
  for (int i = 0; i < NUM_LEDS; i++) strip.setPixelColor(i, strip.Color(r, g, b));
  strip.show();
  delay(duration_ms);
  ledsOff();
}

void blinkAll(uint8_t r, uint8_t g, uint8_t b, uint16_t duration_ms, uint16_t period_ms) {
  unsigned long t0 = millis();
  if (period_ms == 0) period_ms = 50;
  bool on = false;
  while ((millis() - t0) < duration_ms) {
    on = !on;
    for (int i = 0; i < NUM_LEDS; i++) strip.setPixelColor(i, on ? strip.Color(r, g, b) : 0);
    strip.show();
    delay(period_ms);
  }
  ledsOff();
}

void chase(uint8_t r, uint8_t g, uint8_t b, uint16_t duration_ms, uint16_t step_delay_ms, uint8_t routeid) {
  unsigned long t0 = millis();
  int pos = 0;
  if (routeid==1){
  while ((millis() - t0) < duration_ms) {
    ledsOff();
    strip.setPixelColor(pos, strip.Color(r, g, b));
    if (pos>10) strip.setPixelColor(pos, strip.Color(255, 0, 0));
    strip.show();
    pos = (pos + 1) % NUM_LEDS;
    delay(step_delay_ms);
  }}
  else if (routeid==2){
  while ((millis() - t0) < duration_ms) {
    ledsOff();
    strip.setPixelColor(pos, strip.Color(r, g, b));
    if (pos>45) strip.setPixelColor(pos, strip.Color(0, 255, 0));
    strip.show();
    pos = (pos + 1) % NUM_LEDS;
    delay(step_delay_ms);
  }}
  else{
    ledsOff();
    strip.setPixelColor(pos, strip.Color(r, g, b));
    strip.show();
    pos = (pos + 1) % NUM_LEDS;
    delay(step_delay_ms);
  }
  ledsOff();
}


// ====== セットアップ ======
void setup() {
  // NeoPixel
  strip.begin();
  strip.show();

  // RX LED
  pinMode(RX_LED_PIN, OUTPUT);
  digitalWrite(RX_LED_PIN, LOW);

  // BLE init
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCB());

  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* ch =
    svc->createCharacteristic(CHAR_UUID, NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::WRITE);
  ch->setCallbacks(new RxCB());
  svc->start();

  // setup() の広告設定を以下に差し替え
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();

  // 広告間隔：100～150ms（複数台同時でも拾われやすい）
  adv->setMinInterval(0x00A0);   // ≒100ms
  adv->setMaxInterval(0x00F0);   // ≒150ms

  // Advertising Data（必ず Service UUID を入れる）
  NimBLEAdvertisementData advData;
  advData.setName(DEVICE_NAME);               // 例: "ESP32-A", "ESP32-B"
  advData.addServiceUUID(SERVICE_UUID);       // ← これが無いとUUIDフィルタで見えません
  adv->setAdvertisementData(advData);

  // Scan Response Data（必要最小限）
  NimBLEAdvertisementData srData;
  srData.addServiceUUID(SERVICE_UUID);        // 軽量に
  adv->setScanResponseData(srData);

  // 念のため
  adv->addServiceUUID(SERVICE_UUID);

  // 起動＆切断後に必ず再アドバタイズ
  adv->start();

}


// ====== ループ ======
void loop() {
  // 受信LEDのワンショット点灯処理（非ブロッキング）
  if (rxBlinkReq) {
    rxBlinkReq = false;
    digitalWrite(RX_LED_PIN, HIGH);
    rxLedOffAt = millis() + rxBlinkMs;
  }
  if (rxLedOffAt && (millis() >= rxLedOffAt)) {
    digitalWrite(RX_LED_PIN, LOW);
    rxLedOffAt = 0;
  }

  // 受信コマンド処理
  if (hasCmd) {
    hasCmd = false;

    uint8_t  cmd = cmdBuf[0];
    uint8_t  r   = cmdBuf[1];
    uint8_t  g   = cmdBuf[2];
    uint8_t  b   = cmdBuf[3];
    uint16_t dur = (uint16_t)cmdBuf[4] | ((uint16_t)cmdBuf[5] << 8);
    uint16_t px  = (uint16_t)cmdBuf[6] | ((uint16_t)cmdBuf[7] << 8);
    uint16_t off = (uint16_t)cmdBuf[8] | ((uint16_t)cmdBuf[9] << 8);
    uint8_t  RouteId = cmdBuf[10];

    if (off > 0) delay(off);

    // （必要なら固定色にする）
    // r = 255; g = 50; b = 50;

    if      (cmd == 0x01) solidColor(r, g, b, dur);
    else if (cmd == 0x02) blinkAll  (r, g, b, dur, px);
    else if (cmd == 0x03) chase     (r, g, b, dur, px, RouteId);

    // ---- 任意：処理後に自動切断したい場合は有効化 ----
    // NimBLEServer* srv = NimBLEDevice::getServer();
    // if (lastConnId) { srv->disconnect(lastConnId); lastConnId = 0; }
  }
}
