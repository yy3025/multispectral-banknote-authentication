#include "DFRobot_AS7341.h"

DFRobot_AS7341 as7341;

DFRobot_AS7341::sModeOneData_t data1;
DFRobot_AS7341::sModeTwoData_t data2;

void setup() {
  Serial.begin(115200);

  while (as7341.begin() != 0) {
    Serial.println("AS7341 init failed");
    delay(1000);
  }

  // 光谱测量参数（稳定配置）
  as7341.setAtime(29);
  as7341.setAstep(599);
  as7341.setAGAIN(7);   // X64

  // 可选：打开补光
  as7341.enableLed(false);
   as7341.controlLed(2);

  Serial.println("AS7341 spectrum + flicker ready");
}

void loop() {

  /* ---------- 光谱测量 ---------- */

  // F1 ~ F4
  as7341.startMeasure(as7341.eF1F4ClearNIR);
  delay(100);
  data1 = as7341.readSpectralDataOne();

  // F5 ~ F8
  as7341.startMeasure(as7341.eF5F8ClearNIR);
  delay(100);
  data2 = as7341.readSpectralDataTwo();

  Serial.println("Spectrum data:");
  Serial.print("F1(淡紫色): "); Serial.println(data1.ADF1);
  Serial.print("F2(深蓝色): "); Serial.println(data1.ADF2);
  Serial.print("F3(淡蓝色): "); Serial.println(data1.ADF3);
  Serial.print("F4(淡青色): "); Serial.println(data1.ADF4);
  Serial.print("F5(淡绿色): "); Serial.println(data2.ADF5);
  Serial.print("F6(淡黄色): "); Serial.println(data2.ADF6);
  Serial.print("F7(深黄色): "); Serial.println(data2.ADF7);
  Serial.print("F8(深红色): "); Serial.println(data2.ADF8);
  Serial.print("Clear: "); Serial.println(data2.ADCLEAR);
  Serial.print("NIR: ");   Serial.println(data2.ADNIR);

  /* ---------- 频闪检测 ---------- */

  uint8_t freq = as7341.readFlickerData();

  Serial.print("Flicker: ");
  if (freq == 0) {
    Serial.println("No flicker");
  }
  else if (freq == 1) {
    Serial.println("Unknown frequency");
  }
  else {
    Serial.print(freq);
    Serial.println(" Hz");
  }

  Serial.println("-----------------------------");
  delay(1000);   // 每秒输出一组完整数据
}
