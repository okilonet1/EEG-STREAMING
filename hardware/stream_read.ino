#include <Adafruit_NeoPixel.h>

// --- PIN DEFINITIONS ---
#define DATA_PIN_1 6
#define DATA_PIN_2 7
#define DATA_PIN_3 8
#define DATA_PIN_4 10
#define DATA_PIN_5 11

// --- LED COUNTS ---
#define NUM_LEDS_1 20
#define NUM_LEDS_2 20
#define NUM_LEDS_3 20
#define NUM_LEDS_4 20
#define NUM_LEDS_5 20

// --- STRIP OBJECTS ---
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

// --- STATE TRACKING ---
unsigned long lastDataTime = 0;
bool signalActive = false;
unsigned long lastPrintTime = 0;

// --- Store last RGBs ---
uint8_t lastColors[16][3] = {0};

// --- FUNCTION PROTOTYPES ---
void setRegionColor(BrainRegion region, uint8_t r, uint8_t g, uint8_t b);
bool readSerialRGBArray(uint8_t colors[16][3]);

void setup()
{
    Serial.begin(115200);
    for (int i = 0; i < 5; i++)
    {
        strips[i]->begin();
        strips[i]->show(); // ensure LEDs off
    }
    Serial.println("EEG LED visualization system ready.");
}

void loop()
{
    static uint8_t colors[16][3];

    if (readSerialRGBArray(colors))
    {
        if (!signalActive)
        {
            signalActive = true;
            Serial.println("Signal stream detected.");
        }
        lastDataTime = millis();

        // Update only changed LEDs
        for (int i = 0; i < 16; i++)
        {
            if (colors[i][0] != lastColors[i][0] ||
                colors[i][1] != lastColors[i][1] ||
                colors[i][2] != lastColors[i][2])
            {
                setRegionColor(regions[i], colors[i][0], colors[i][1], colors[i][2]);
                memcpy(lastColors[i], colors[i], 3);
            }
        }

        // Show all strips at once
        for (int s = 0; s < 5; s++)
            strips[s]->show();
    }

    // Stop condition
    if (signalActive && millis() - lastDataTime > 3000)
    {
        Serial.println("Signal stream stopped.");
        signalActive = false;
    }

    // Waiting message
    if (!signalActive && millis() - lastPrintTime > 5000)
    {
        Serial.println("Waiting for signal...");
        lastPrintTime = millis();
    }
}

// --- FUNCTIONS ---
void setRegionColor(BrainRegion region, uint8_t r, uint8_t g, uint8_t b)
{
    Adafruit_NeoPixel *target = strips[region.strip - 1];
    uint32_t color = target->Color(r, g, b);
    for (int i = region.startLED; i <= region.endLED; i++)
    {
        target->setPixelColor(i, color);
    }
}

bool readSerialRGBArray(uint8_t colors[16][3])
{
    static String input = "";

    while (Serial.available() > 0)
    {
        char c = Serial.read();
        if (c == '\r' || c == '\n')
            continue;
        input += c;

        // quick trim old data if something malformed
        if (input.length() > 300)
            input = "";

        if (input.endsWith("]]"))
        {
            int regionIndex = 0, rgbIndex = 0;
            String num = "";
            for (int i = 0; i < input.length(); i++)
            {
                char ch = input[i];
                if (isdigit(ch))
                    num += ch;
                else if (ch == ',' || ch == ']')
                {
                    if (num.length() > 0)
                    {
                        colors[regionIndex][rgbIndex++] = constrain(num.toInt(), 0, 255);
                        num = "";
                        if (rgbIndex == 3)
                        {
                            rgbIndex = 0;
                            regionIndex++;
                            if (regionIndex >= 16)
                                break;
                        }
                    }
                }
            }
            input = "";
            return true;
        }
    }
    return false;
}
