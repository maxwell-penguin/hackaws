/*
 * fridge_cam.ino
 *
 * Board: Freenove ESP32-WROVER-CAM (AI-Thinker-compatible pinout, has PSRAM).
 * Arduino IDE settings:
 *   - Board: "AI Thinker ESP32-CAM"
 *   - Partition Scheme: "Huge APP (3MB No OTA/1MB SPIFFS)"
 *   - PSRAM: "Enabled"
 * Flashing: connect GPIO0 to GND before power-up/reset to enter flash mode,
 * upload, then disconnect GPIO0 from GND and press reset to run normally.
 * This board has no onboard USB — you need an FTDI/USB-to-serial adapter
 * wired to U0T/U0R/GND/5V.
 *
 * Wiring:
 *   - Trigger button: one leg to GPIO13, the other to GND. Internal pull-up
 *     is enabled in software, so no external resistor is needed.
 *   - Onboard flash LED is already wired to GPIO4 — nothing to connect.
 */

#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include "esp_camera.h"

// ======================= EDIT ME: WiFi credentials =======================
#define WIFI_SSID     "CONNECT-IT"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
// ===========================================================================

// ================ EDIT ME PER BOARD: this camera's fridge zone ================
#define ZONE_ID "top-shelf"
// ===========================================================================

// ======================= EDIT ME: backend endpoint =======================
#define ENDPOINT_URL "http://192.168.1.100:3000/api/fridge-photos"
// ===========================================================================

// DEMO_MODE true  -> capture is triggered by the button on BUTTON_PIN.
// DEMO_MODE false -> capture instead fires on a fixed timer (CAPTURE_INTERVAL_MS),
// for unattended "production" operation.
#define DEMO_MODE true

#define BUTTON_PIN    13
#define FLASH_LED_PIN 4

static const uint32_t CAPTURE_INTERVAL_MS = 12UL * 60UL * 60UL * 1000UL; // 12 hours

// ----------------- AI-Thinker ESP32-CAM camera pin map -----------------
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22
// -------------------------------------------------------------------------

bool buttonWasPressed = false;
bool wifiWasConnected = false;
uint32_t lastCaptureMillis = 0;

void connectWiFi() {
  Serial.print("[WIFI] Connecting to ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  uint32_t attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    attempts++;
    if (attempts % 40 == 0) { // ~20s of silence — let the user know it's still trying
      Serial.println();
      Serial.println("[WIFI] Still trying to connect...");
    }
  }

  WiFi.setSleep(false); // avoid modem-sleep latency hurting the POST
  wifiWasConnected = true;

  Serial.println();
  Serial.print("[WIFI] Connected! IP address: ");
  Serial.println(WiFi.localIP());
}

// Call before any HTTP send. Blocks briefly to retry, but always returns
// rather than hanging or resetting the board.
bool ensureWiFiConnected() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.println("[WIFI] Not connected, attempting to reconnect...");
  WiFi.reconnect();

  uint8_t attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) { // ~10s
    delay(500);
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WIFI] Reconnected, IP: ");
    Serial.println(WiFi.localIP());
    return true;
  }

  Serial.println("[WIFI] Reconnect failed — will retry next cycle");
  return false;
}

// Logs only on connect/disconnect transitions so the serial log isn't spammed.
void logWiFiTransitions() {
  bool nowConnected = (WiFi.status() == WL_CONNECTED);
  if (nowConnected != wifiWasConnected) {
    Serial.println(nowConnected ? "[WIFI] Connection restored" : "[WIFI] Connection lost");
    wifiWasConnected = nowConnected;
  }
}

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  // If your installed "esp32" board package is new enough to reject
  // pin_sscb_sda/pin_sscb_scl, rename both to pin_sccb_sda/pin_sccb_scl —
  // the field was renamed upstream to fix a long-standing typo.
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

  if (psramFound()) {
    config.frame_size = FRAMESIZE_UXGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.grab_mode = CAMERA_GRAB_LATEST;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
    config.fb_location = CAMERA_FB_IN_DRAM;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[CAMERA] Init failed with error 0x%x\n", err);
    return false;
  }

  Serial.println("[CAMERA] Initialized successfully");
  return true;
}

void sendPhoto(camera_fb_t *fb) {
  if (!ensureWiFiConnected()) {
    Serial.println("[HTTP] Skipping send — no WiFi connection");
    return;
  }

  String boundary = "FridgeCamBoundary7MA4YWxkTrZu0gW";

  String head = "--" + boundary + "\r\n"
                "Content-Disposition: form-data; name=\"zoneId\"\r\n\r\n" +
                String(ZONE_ID) + "\r\n" +
                "--" + boundary + "\r\n"
                "Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n"
                "Content-Type: image/jpeg\r\n\r\n";

  String tail = "\r\n--" + boundary + "--\r\n";

  size_t totalLen = head.length() + fb->len + tail.length();

  // Prefer PSRAM for this scratch buffer since JPEGs at UXGA can be sizeable;
  // ps_malloc returns null (not a crash) if PSRAM is unavailable, so fall
  // back to regular heap.
  uint8_t *body = (uint8_t *)ps_malloc(totalLen);
  if (!body) body = (uint8_t *)malloc(totalLen);
  if (!body) {
    Serial.println("[HTTP] Failed to allocate send buffer, skipping this capture");
    return;
  }

  size_t pos = 0;
  memcpy(body + pos, head.c_str(), head.length());
  pos += head.length();
  memcpy(body + pos, fb->buf, fb->len);
  pos += fb->len;
  memcpy(body + pos, tail.c_str(), tail.length());
  pos += tail.length();

  HTTPClient http;
  WiFiClient client;
  http.begin(client, ENDPOINT_URL);
  http.addHeader("Content-Type", "multipart/form-data; boundary=" + boundary);

  Serial.printf("[HTTP] POSTing %u bytes to %s\n", (unsigned)totalLen, ENDPOINT_URL);
  int httpCode = http.POST(body, totalLen);

  if (httpCode > 0) {
    Serial.printf("[HTTP] Response code: %d\n", httpCode);
    Serial.println("[HTTP] Response body: " + http.getString());
  } else {
    Serial.printf("[HTTP] POST failed: %s\n", http.errorToString(httpCode).c_str());
  }

  http.end();
  free(body);
}

void captureAndSend() {
  Serial.println("[CAPTURE] Starting capture sequence");

  digitalWrite(FLASH_LED_PIN, HIGH);
  delay(150); // let the flash illuminate the scene before grabbing the frame

  camera_fb_t *fb = esp_camera_fb_get();

  digitalWrite(FLASH_LED_PIN, LOW);

  if (!fb) {
    Serial.println("[CAPTURE] Failed — esp_camera_fb_get() returned null");
    return;
  }

  Serial.printf("[CAPTURE] Success — %u bytes\n", (unsigned)fb->len);

  sendPhoto(fb);

  esp_camera_fb_return(fb);
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); // camera's current draw can trip brownout detection

  Serial.begin(115200);
  Serial.setDebugOutput(true);
  delay(1000);
  Serial.println();
  Serial.println("[BOOT] Fridge cam starting...");
  Serial.printf("[BOOT] Zone: %s | Mode: %s\n", ZONE_ID, DEMO_MODE ? "DEMO (button)" : "PRODUCTION (12h timer)");

  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, LOW);

  if (DEMO_MODE) {
    pinMode(BUTTON_PIN, INPUT_PULLUP);
  }

  connectWiFi();

  if (!initCamera()) {
    Serial.println("[BOOT] Camera init failed — halting. Check wiring/board selection and reset.");
    while (true) delay(1000);
  }

  lastCaptureMillis = millis();
  Serial.println("[BOOT] Setup complete, entering main loop");
}

void loop() {
  logWiFiTransitions();

  if (DEMO_MODE) {
    bool pressed = (digitalRead(BUTTON_PIN) == LOW);
    if (pressed && !buttonWasPressed) {
      delay(50); // debounce
      if (digitalRead(BUTTON_PIN) == LOW) {
        Serial.println("[BUTTON] Press detected");
        captureAndSend();
      }
    }
    buttonWasPressed = pressed;
  } else {
    if (millis() - lastCaptureMillis >= CAPTURE_INTERVAL_MS) {
      Serial.println("[TIMER] 12-hour interval elapsed, triggering capture");
      captureAndSend();
      lastCaptureMillis = millis();
    }
  }

  delay(20);
}
