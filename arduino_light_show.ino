// C++ code
//

#include <Adafruit_NeoPixel.h>

// --- PIN DEFINITIONS ---
// Each pin drives a SEPARATE NeoPixel chain.
#define DATA_PIN_1 6  // data line pin 6: RED
#define DATA_PIN_2 7  // data line pin 7 : MAGENTA
#define DATA_PIN_3 8  // data line pin 8: GREEN
#define DATA_PIN_4 10 // data line pin 10: BLUE
#define DATA_PIN_5 11 // data line pin 11: YELLOW

// --- LED COUNT---
#define NUM_LEDS_1 20
#define NUM_LEDS_2 20
#define NUM_LEDS_3 20
#define NUM_LEDS_4 20
#define NUM_LEDS_5 20
#define TOTAL_LEDS (NUM_LEDS_1 + NUM_LEDS_2 + NUM_LEDS_3 + NUM_LEDS_4 + NUM_LEDS_5)

// Initialize FIVE separate strip objects:
Adafruit_NeoPixel strip1(NUM_LEDS_1, DATA_PIN_1, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip2(NUM_LEDS_2, DATA_PIN_2, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip3(NUM_LEDS_3, DATA_PIN_3, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip4(NUM_LEDS_4, DATA_PIN_4, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel strip5(NUM_LEDS_5, DATA_PIN_5, NEO_GRB + NEO_KHZ800);

// --- FUNCTION PROTOTYPE ---
// This tells the compiler what setSolidColor looks like before it's used in loop()
void setSolidColor(Adafruit_NeoPixel &strip, uint32_t color);

// --- SETUP ---
void setup()
{

    // --- 1. DATA LINE RESET (Clears residual data from all five pins) ---
    pinMode(DATA_PIN_1, OUTPUT);
    pinMode(DATA_PIN_2, OUTPUT);
    pinMode(DATA_PIN_3, OUTPUT);
    pinMode(DATA_PIN_4, OUTPUT);
    pinMode(DATA_PIN_5, OUTPUT);

    digitalWrite(DATA_PIN_1, LOW);
    digitalWrite(DATA_PIN_2, LOW);
    digitalWrite(DATA_PIN_3, LOW);
    digitalWrite(DATA_PIN_4, LOW);
    digitalWrite(DATA_PIN_5, LOW);
    delayMicroseconds(300); // Guarantees a data reset signal

    // 2. Initialize all five strip objects
    strip1.begin();
    strip2.begin();
    strip3.begin();
    strip4.begin();
    strip5.begin();

    // 3. Clear all pixels on all strips
    strip1.clear();
    strip1.show();
    strip2.clear();
    strip2.show();
    strip3.clear();
    strip3.show();
    strip4.clear();
    strip4.show();
    strip5.clear();
    strip5.show();
}

// --- MAIN LOOP ---
void loop()
{

    // Cycle 1: Solid Primary Colors
    setSolidColor(strip1, strip1.Color(255, 0, 0));   // RED
    setSolidColor(strip3, strip3.Color(0, 255, 0));   // GREEN
    setSolidColor(strip4, strip4.Color(0, 0, 255));   // BLUE
    setSolidColor(strip5, strip5.Color(255, 255, 0)); // YELLOW (R+G)
    setSolidColor(strip2, strip2.Color(255, 0, 255)); // MAGENTA (R+B)

    delay(1000);
}

// Helper function now takes the strip object as an argument
void setSolidColor(Adafruit_NeoPixel &strip, uint32_t color)
{
    for (int i = 0; i < strip.numPixels(); i++)
    {
        strip.setPixelColor(i, color);
    }
    strip.show();
}