#include <Arduino.h>
#include <Adafruit_NeoPixel.h>
#include "BluetoothSerial.h"

// --------------------------
// BLUETOOTH SPP
// --------------------------
#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error "Bluetooth is not enabled! Enable it in menuconfig or use a core with BT support."
#endif

BluetoothSerial SerialBT;
#define BT_DEVICE_NAME "EEG-ESP32"

// --------------------------
// LED + REGION SETUP
// (Use safe GPIOs, avoid 6–11 on ESP32)
// --------------------------
#define DATA_PIN_1 13
#define DATA_PIN_2 14
#define DATA_PIN_3 15
#define DATA_PIN_4 16
#define DATA_PIN_5 17

#define NUM_LEDS_1 20
#define NUM_LEDS_2 20
#define NUM_LEDS_3 20
#define NUM_LEDS_4 20
#define NUM_LEDS_5 20

Adafruit_NeoPixel strip1(NUM_LEDS_1, DATA_PIN_1, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip2(NUM_LEDS_2, DATA_PIN_2, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip3(NUM_LEDS_3, DATA_PIN_3, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip4(NUM_LEDS_4, DATA_PIN_4, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip5(NUM_LEDS_5, DATA_PIN_5, NEO_GRB + NEO_KHZ800);

struct BrainRegion
{
    const char *name;
    uint8_t strip;
    uint8_t startLED;
    uint8_t endLED;
};

// --- DEFINE 16 REGIONS ---
BrainRegion regions[16] = {
    {"Left Frontal", 1, 0, 5},
    {"Right Frontal", 1, 6, 11},
    {"Midline Frontal", 1, 12, 17},
    {"Left FC", 2, 0, 4},
    {"Right FC", 2, 5, 9},
    {"Left Central", 2, 0, 5},
    {"Right Central", 3, 6, 11},
    {"Midline Central", 2, 10, 11},
    {"Left Parietal", 4, 0, 5},
    {"Right Parietal", 4, 6, 11},
    {"Midline Parietal", 4, 12, 13},
    {"Left Temporal", 5, 0, 5},
    {"Right Temporal", 5, 6, 11},
    {"Left Occipital", 5, 12, 15},
    {"Right Occipital", 5, 16, 17},
    {"Midline Occipital", 5, 18, 19}};

Adafruit_NeoPixel *strips[5] = {&strip1, &strip2, &strip3, &strip4, &strip5};

// --------------------------
// FRAME STATE
// --------------------------
const int N_REGIONS = 16;
const int BYTES_PER_FRAME = N_REGIONS * 3; // 48 bytes

uint8_t buffer[BYTES_PER_FRAME];
int bufIndex = 0;

uint8_t lastColors[16][3] = {0};
unsigned long lastFrameTime = 0;
bool signalActive = false;
bool lastBTConnected = false; // for connect/disconnect logging

// --------------------------
// HELPERS
// --------------------------
void setRegionColor(const BrainRegion &region, uint8_t r, uint8_t g, uint8_t b)
{
    Adafruit_NeoPixel *target = strips[region.strip - 1];
    uint32_t color = target->Color(r, g, b);
    for (int i = region.startLED; i <= (int)region.endLED; i++)
    {
        target->setPixelColor(i, color);
    }
}

void printFrameRGB(const uint8_t *buf)
{
    Serial.println("=== New RGB frame received ===");
    int k = 0;
    for (int i = 0; i < N_REGIONS; i++)
    {
        uint8_t r = buf[k++];
        uint8_t g = buf[k++];
        uint8_t bl = buf[k++];

        Serial.print("Region ");
        Serial.print(i);
        Serial.print(" (");
        Serial.print(regions[i].name);
        Serial.print("): R=");
        Serial.print(r);
        Serial.print(" G=");
        Serial.print(g);
        Serial.print(" B=");
        Serial.println(bl);
    }
    Serial.println("=== End of frame ===");
}

// --------------------------
// SETUP
// --------------------------
void setup()
{
    Serial.begin(115200);
    delay(1000);

    // Startup banner (your requested prints)
    Serial.println("ESP32 EEG LED + RGB frame debugger (Bluetooth SPP + USB debug)");
    Serial.println("Expecting 48 bytes (16x3) + '\\n' from MATLAB over Bluetooth.");

    if (!SerialBT.begin(BT_DEVICE_NAME))
    {
        Serial.println("❌ Failed to start Bluetooth SPP!");
        while (true)
        {
            delay(1000);
        }
    }
    Serial.print("✅ Bluetooth SPP started as '");
    Serial.print(BT_DEVICE_NAME);
    Serial.println("'.");

    // Init LED strips (all off)
    for (int s = 0; s < 5; s++)
    {
        strips[s]->begin();
        strips[s]->clear();
        strips[s]->show();
    }
}

// --------------------------
// LOOP
// --------------------------
void loop()
{
    // --- 1) Log BT connect / disconnect events ---
    bool btConnected = SerialBT.hasClient();
    if (btConnected != lastBTConnected)
    {
        if (btConnected)
        {
            Serial.println("🔗 Bluetooth client connected.");
        }
        else
        {
            Serial.println("❌ Bluetooth client disconnected.");
        }
        lastBTConnected = btConnected;
    }

    // --- 2) Read bytes from Bluetooth and assemble frames ---
    while (SerialBT.available() > 0)
    {
        uint8_t b = SerialBT.read();

        if (b == '\n')
        {
            // End of frame
            if (bufIndex == BYTES_PER_FRAME)
            {
                // Debug: print the frame contents
                printFrameRGB(buffer);

                // Apply frame to LEDs
                int k = 0;
                for (int i = 0; i < N_REGIONS; i++)
                {
                    uint8_t r = buffer[k++];
                    uint8_t g = buffer[k++];
                    uint8_t bl = buffer[k++];

                    if (r != lastColors[i][0] ||
                        g != lastColors[i][1] ||
                        bl != lastColors[i][2])
                    {

                        setRegionColor(regions[i], r, g, bl);
                        lastColors[i][0] = r;
                        lastColors[i][1] = g;
                        lastColors[i][2] = bl;
                    }
                }
                // Push to all strips
                for (int s = 0; s < 5; s++)
                {
                    strips[s]->show();
                }

                signalActive = true;
                lastFrameTime = millis();
            }
            // Reset buffer for next frame regardless
            bufIndex = 0;
        }
        else
        {
            if (bufIndex < BYTES_PER_FRAME)
            {
                buffer[bufIndex++] = b;
            }
            else
            {
                // Too many bytes before newline → discard
                bufIndex = 0;
            }
        }
    }

    // --- 3) Optional: detect when stream stops ---
    if (signalActive && (millis() - lastFrameTime > 3000))
    {
        signalActive = false;
        Serial.println("⚠ No frames for > 3s (stream idle).");
        // You can clear LEDs here if you want:
        // for (int s = 0; s < 5; s++) { strips[s]->clear(); strips[s]->show(); }
    }

    delay(1);
}
