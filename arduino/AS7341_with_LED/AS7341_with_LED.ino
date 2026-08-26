#include <Wire.h>
#include <SPI.h>

#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>

#include "DFRobot_AS7341.h"

/* ===== TFT 引脚 ===== */
#define TFT_CS   10
#define TFT_DC    8
#define TFT_RST   9

Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_RST);

/* ===== AS7341 ===== */
DFRobot_AS7341 as7341;

/* ===== 显示参数 ===== */
#define SCREEN_W 160
#define SCREEN_H 80
#define BAR_COUNT 8
#define BAR_WIDTH (SCREEN_W / BAR_COUNT)
#define BAR_MAX_H 70

/* ===== 光谱颜色（RGB565）===== */
uint16_t bandColors[8] = {
    0x900A, // F1 Violet
    0xF81F, // F2 Indigo
    0x001F, // F3 Blue
    0x7FF5, // F4 Cyan-Green
    0xFEA0, // F5 Green
    0xFBEA, // F6 Yellow
    0xF082, // F7 Orange-Red
    0x8000  // F8 Red
};

/* ===== 光谱数据 ===== */
uint16_t spectrum[8];
uint16_t clearValue = 0;
uint16_t nirValue   = 0;

void setup() {
  Serial.begin(2000000);
  Wire.begin();

  /* TFT 初始化 */
  tft.initR(INITR_MINI160x80_PLUGIN);
  tft.setRotation(3);
  tft.fillScreen(ST77XX_BLACK);

  /* AS7341 初始化 */
  while (as7341.begin() != 0) {
    Serial.println("AS7341 IIC 初始化失败");
    delay(1000);
  }
//Integration time = (ATIME + 1) x (ASTEP + 1) x 2.78µs
  as7341.setAtime(19); //曝光次数(1-255)
  as7341.setAstep(1999);//单次曝光时间(0-65534)
  as7341.setAGAIN(2);//光强增益(0~10对应 X0.5,X1,X2,X4,X8,X16,X32,X64,X128,X256,X512)
  as7341.enableLed(true);//板载LED开关
  as7341.controlLed(1);//板载LED亮度（1-20）(1~20对应电流 4mA,6mA,8mA,10mA,12mA,......,42mA)

  tft.setTextColor(ST77XX_WHITE);
  tft.setTextSize(2);
  tft.setCursor(0, 0);
  tft.println("AS7341");
  tft.println("Spectrum");
  tft.println("Yihao Yang");

}

void loop() {
  readSpectrum();
  drawSpectrum();
  printSpectrumToSerial();
}

/* ===== 读取 AS7341 ===== */
void readSpectrum() {
  DFRobot_AS7341::sModeOneData_t d1;
  DFRobot_AS7341::sModeTwoData_t d2;

  as7341.startMeasure(as7341.eF1F4ClearNIR);
  d1 = as7341.readSpectralDataOne();

  as7341.startMeasure(as7341.eF5F8ClearNIR);
  d2 = as7341.readSpectralDataTwo();

  spectrum[0] = d1.ADF1;
  spectrum[1] = d1.ADF2;
  spectrum[2] = d1.ADF3;
  spectrum[3] = d1.ADF4;
  spectrum[4] = d2.ADF5;
  spectrum[5] = d2.ADF6;
  spectrum[6] = d2.ADF7;
  spectrum[7] = d2.ADF8;

  clearValue = d2.ADCLEAR;
  nirValue   = d2.ADNIR;
}

/* 自动缩放的程序*/
/*
void drawSpectrum() {
  int barWidth = SCREEN_W / BAR_COUNT;

  // 找最大值，用于动态缩放
  uint16_t maxVal = 1;
  for (int i = 0; i < BAR_COUNT; i++) {
    if (spectrum[i] > maxVal) maxVal = spectrum[i];
  }

  for (int i = 0; i < BAR_COUNT; i++) {

    // ===== 反转索引（和你 AS726x 代码一致）=====
    int idx = BAR_COUNT - 1 - i;

    // ===== 高度映射 =====
    uint16_t height = map(
      spectrum[idx],
      0, maxVal,
      0, SCREEN_H
    );

    // ===== 先清整列 =====
    tft.fillRect(
      barWidth * i,
      0,
      barWidth,
      SCREEN_H,
      ST77XX_BLACK
    );

    // ===== 再画新柱（底部对齐）=====
    tft.fillRect(
      barWidth * i,
      SCREEN_H - height,
      barWidth,
      height,
      bandColors[idx]
    );
  }
}
*/
#define SENSOR_MAX 400   // 固定满量程

void drawSpectrum() {
  int barWidth = SCREEN_W / BAR_COUNT;

  tft.setTextSize(1);
  tft.setTextColor(ST77XX_WHITE);
  tft.setTextWrap(false);

  for (int i = 0; i < BAR_COUNT; i++) {

    // ===== 反向索引（保持显示顺序）=====
    int idx = BAR_COUNT - 1 - i;

    // ===== 高度映射 =====
    uint16_t height = map(
      spectrum[idx],
      0, SENSOR_MAX,
      0, BAR_MAX_H
    );

    if (height > BAR_MAX_H) height = BAR_MAX_H;

    // ===== 清整列 =====
    tft.fillRect(
      barWidth * i,
      0,
      barWidth,
      SCREEN_H,
      ST77XX_BLACK
    );

    // ===== 画色柱 =====
    tft.fillRect(
      barWidth * i,
      SCREEN_H - height - 10,   // 给文字留 10px
      barWidth,
      height,
      bandColors[idx]
    );

    // ===== 在柱子下方写 F1~F8 =====
    int textX = barWidth * i + (barWidth / 2) - 6; // 居中微调
    int textY = SCREEN_H - 8;

    tft.setCursor(textX, textY);
    tft.print("F");
    tft.print(idx + 1);
  }
}

/* ===== 串口打印 ===== */
void printSpectrumToSerial() {
  Serial.print("F1(405-425nm):");
  Serial.println(spectrum[0]);
  Serial.print("  F2(435-455nm):");
  Serial.println(spectrum[1]);
  Serial.print("  F3(470-490nm):");
  Serial.println(spectrum[2]);
  Serial.print("  F4(505-525nm):");
  Serial.println(spectrum[3]);

  Serial.print("F5(545-565nm):");
  Serial.println(spectrum[4]);
  Serial.print("  F6(580-600nm):");
  Serial.println(spectrum[5]);
  Serial.print("  F7(620-640nm):");
  Serial.println(spectrum[6]);
  Serial.print("  F8(670-690nm):");
  Serial.println(spectrum[7]);

  Serial.print("Clear:");
  Serial.println(clearValue);
  Serial.print("  NIR:");
  Serial.println(nirValue);

  Serial.println("------------------------------");
}
