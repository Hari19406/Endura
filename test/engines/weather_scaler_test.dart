import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/daily/weather_scaler.dart';
import 'package:run_app/services/weather_service.dart';

WeatherSnapshot _w(double tempF, double dewF) => WeatherSnapshot(
  tempC: (tempF - 32) * 5 / 9,
  apparentTempC: (tempF - 32) * 5 / 9,
  humidityPercent: 50,
  dewPointC: (dewF - 32) * 5 / 9,
  condition: WeatherCondition.clear,
  fetchedAt: DateTime(2026, 10, 4),
);

void main() {
  const s = WeatherScaler();

  test('matches the temp + dew point table anchors', () {
    expect(s.slowdownPercent(_w(60, 40)), closeTo(0, 0.01)); // 100
    expect(s.slowdownPercent(_w(70, 50)), closeTo(1.0, 0.01)); // 120
    expect(s.slowdownPercent(_w(80, 60)), closeTo(3.0, 0.01)); // 140
    expect(s.slowdownPercent(_w(90, 70)), closeTo(6.0, 0.01)); // 160
    expect(s.slowdownPercent(_w(100, 80)), closeTo(10.0, 0.01)); // 180
  });

  test('interpolates inside a band and caps at 10%', () {
    expect(s.slowdownPercent(_w(75, 60)), closeTo(2.5, 0.01)); // 135
    expect(s.slowdownPercent(_w(110, 90)), closeTo(10.0, 0.01));
    expect(s.isHardRunningDiscouraged(_w(110, 90)), isTrue);
  });
}
