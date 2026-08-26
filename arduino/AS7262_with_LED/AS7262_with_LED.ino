#include <Wire.h>
#include "Adafruit_AS726x.h"

#include <Adafruit_GFX.h>    // Core graphics library
#include <Adafruit_ST7735.h> // Hardware-specific library
#include <SPI.h>


// For the breakout, you can use any 2 or 3 pins
// These pins will also work for the 1.8" TFT shield
#define TFT_CS     10
#define TFT_RST    9  // you can also connect this to the Arduino reset
                      // in which case, set this #define pin to -1!
#define TFT_DC     8

#define SENSOR_MAX 2000 //设置这个光柱的最大高度，这个表示颜色强度5000的时候是最大量程
//下面是定义在彩屏上面显示各种光强时候的颜色种类
#define BLACK   0x0000
#define GRAY    0x8410
#define WHITE   0xFFFF
#define RED     0xF800
#define ORANGE  0xFA60
#define YELLOW  0xFFE0  
#define LIME    0x07FF
#define GREEN   0x07E0
#define CYAN    0x07FF
#define AQUA    0x04FF
#define BLUE    0x001F
#define MAGENTA 0xF81F
#define PINK    0xF8FF

uint16_t colors[] = {
  MAGENTA,
  BLUE,
  GREEN,
  YELLOW,
  ORANGE,
  RED
};


Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS,  TFT_DC, TFT_RST);

//create the object
Adafruit_AS726x ams;

//buffer to hold raw values (these aren't used by default in this example)
//uint16_t sensorValues[AS726x_NUM_CHANNELS];

//buffer to hold calibrated values
float calibratedValues[AS726x_NUM_CHANNELS];

uint16_t barWidth;

void setup() {
  
  Serial.begin(2000000);

  tft.initR(INITR_MINI160x80_PLUGIN);   // initialize a ST7735S chip, mini display
  tft.setRotation(3);

  tft.fillScreen(ST7735_BLACK);

  barWidth = tft.width() / AS726x_NUM_CHANNELS;
  
  // initialize digital pin LED_BUILTIN as an output.
  pinMode(LED_BUILTIN, OUTPUT);

  //begin and make sure we can talk to the sensor
  if(!ams.begin()){
    Serial.println("could not connect to sensor! Please check your wiring.");
    while(1);
  }
  
  ams.setConversionType(MODE_2);

  //uncomment this if you want to use the  );
}

void loop() {
uint8_t temp = ams.readTemperature();


  if(ams.dataReady()){
    
    //read the values!
    //ams.readRawValues(sensorValues);
    ams.readCalibratedValues(calibratedValues);
    Serial.print("Temp: "); Serial.println(temp);
Serial.print("450nm MAGENTA:");
Serial.print(calibratedValues[0], 2);
Serial.print(" 500nm BLUE:");
Serial.print(calibratedValues[1], 2);
Serial.print(" 550nm GREEN:");
Serial.print(calibratedValues[2], 2);
Serial.print(" 570nm YELLOW:");
Serial.print(calibratedValues[3], 2);
Serial.print(" 600nm ORANGE:");
Serial.print(calibratedValues[4], 2);
Serial.print(" 650nm RED:");
Serial.println(calibratedValues[5], 2);

    for (int i = 0; i < AS726x_NUM_CHANNELS; i++) {

  int idx = AS726x_NUM_CHANNELS - 1 - i;  // 5 → 0 反转索引

  uint16_t height = map(
    calibratedValues[idx],
    0, SENSOR_MAX,
    0, tft.height()
  );

  // 先清旧柱
  tft.fillRect(
    barWidth * i,
    0,
    barWidth,
    tft.height(),
    ST77XX_BLACK
  );

  // 画新柱
  tft.fillRect(
    barWidth * i,
    tft.height() - height,
    barWidth,
    height,
    colors[idx]
  );
}

  }

}