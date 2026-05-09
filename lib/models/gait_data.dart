import 'package:intl/intl.dart';

/// 压力传感器数据模型
class PressureData {
  final double p1;
  final double p2;
  final double p3;
  final DateTime timestamp;

  PressureData({
    required this.p1,
    required this.p2,
    required this.p3,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory PressureData.empty() {
    return PressureData(p1: 0.0, p2: 0.0, p3: 0.0);
  }

  @override
  String toString() => 'P1:${p1.toStringAsFixed(1)}, P2:${p2.toStringAsFixed(1)}, P3:${p3.toStringAsFixed(1)}';
}

/// IMU传感器数据模型
class IMUData {
  // 加速度 (g)
  final double accX;
  final double accY;
  final double accZ;

  // 角速度 (°/s)
  final double gyroX;
  final double gyroY;
  final double gyroZ;

  // 欧拉角 (°)
  final double roll;
  final double pitch;
  final double yaw;

  final DateTime timestamp;

  IMUData({
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.roll,
    required this.pitch,
    required this.yaw,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory IMUData.empty() {
    return IMUData(
      accX: 0.0,
      accY: 0.0,
      accZ: 0.0,
      gyroX: 0.0,
      gyroY: 0.0,
      gyroZ: 0.0,
      roll: 0.0,
      pitch: 0.0,
      yaw: 0.0,
    );
  }

  /// 从20字节IMU帧解析数据
  static IMUData parseFromFrame(List<int> frame) {
    if (frame.length < 20) {
      return IMUData.empty();
    }

    try {
      // 验证帧头
      if (frame[0] != 0x55 || frame[1] != 0x61) {
        return IMUData.empty();
      }

      // 小端序读取int16
      int16 _readInt16(List<int> data, int offset) {
        return data[offset] | (data[offset + 1] << 8);
      }

      // 修复有符号值
      int _toSigned(int value) {
        if (value >= 32768) {
          return value - 65536;
        }
        return value;
      }

      final accXRaw = _toSigned(_readInt16(frame, 2));
      final accYRaw = _toSigned(_readInt16(frame, 4));
      final accZRaw = _toSigned(_readInt16(frame, 6));

      final gyroXRaw = _toSigned(_readInt16(frame, 8));
      final gyroYRaw = _toSigned(_readInt16(frame, 10));
      final gyroZRaw = _toSigned(_readInt16(frame, 12));

      final rollRaw = _toSigned(_readInt16(frame, 14));
      final pitchRaw = _toSigned(_readInt16(frame, 16));
      final yawRaw = _toSigned(_readInt16(frame, 18));

      // 转换为物理单位
      const accScale = 16.0 / 32768.0;
      const gyroScale = 2000.0 / 32768.0;
      const angleScale = 180.0 / 32768.0;

      return IMUData(
        accX: accXRaw * accScale,
        accY: accYRaw * accScale,
        accZ: accZRaw * accScale,
        gyroX: gyroXRaw * gyroScale,
        gyroY: gyroYRaw * gyroScale,
        gyroZ: gyroZRaw * gyroScale,
        roll: rollRaw * angleScale,
        pitch: pitchRaw * angleScale,
        yaw: yawRaw * angleScale,
      );
    } catch (e) {
      debugPrint('IMU frame parsing error: $e');
      return IMUData.empty();
    }
  }
}

/// 设备角色枚举
enum SensorRole {
  leftPressure,
  rightPressure,
  leftIMU,
  rightIMU,
  unassigned,
}

/// 设备连接状态枚举
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

/// BLE设备模型
class BLEDevice {
  final String deviceId;
  final String name;
  final int rssi;
  SensorRole role;
  ConnectionStatus status;
  PressureData? pressureData;
  IMUData? imuData;

  BLEDevice({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.role = SensorRole.unassigned,
    this.status = ConnectionStatus.disconnected,
  });

  @override
  String toString() => '$name (${role.name})';
}

/// 完整的步态数据记录
class GaitDataRecord {
  final String timestamp;
  final double pFirstMetaR;
  final double pFifthMetaR;
  final double pHeelR;
  final double accXR;
  final double accYR;
  final double accZR;
  final double gyroXR;
  final double gyroYR;
  final double gyroZR;
  final double rollR;
  final double pitchR;
  final double yawR;
  final double pFirstMetaL;
  final double pFifthMetaL;
  final double pHeelL;
  final double accXL;
  final double accYL;
  final double accZL;
  final double gyroXL;
  final double gyroYL;
  final double gyroZL;
  final double rollL;
  final double pitchL;
  final double yawL;
  final String label;

  GaitDataRecord({
    required this.timestamp,
    required this.pFirstMetaR,
    required this.pFifthMetaR,
    required this.pHeelR,
    required this.accXR,
    required this.accYR,
    required this.accZR,
    required this.gyroXR,
    required this.gyroYR,
    required this.gyroZR,
    required this.rollR,
    required this.pitchR,
    required this.yawR,
    required this.pFirstMetaL,
    required this.pFifthMetaL,
    required this.pHeelL,
    required this.accXL,
    required this.accYL,
    required this.accZL,
    required this.gyroXL,
    required this.gyroYL,
    required this.gyroZL,
    required this.rollL,
    required this.pitchL,
    required this.yawL,
    required this.label,
  });

  /// 转换为CSV行
  List<String> toCSVRow() {
    return [
      timestamp,
      pFirstMetaR.toStringAsFixed(1),
      pFifthMetaR.toStringAsFixed(1),
      pHeelR.toStringAsFixed(1),
      accXR.toStringAsFixed(3),
      accYR.toStringAsFixed(3),
      accZR.toStringAsFixed(3),
      gyroXR.toStringAsFixed(1),
      gyroYR.toStringAsFixed(1),
      gyroZR.toStringAsFixed(1),
      rollR.toStringAsFixed(1),
      pitchR.toStringAsFixed(1),
      yawR.toStringAsFixed(1),
      pFirstMetaL.toStringAsFixed(1),
      pFifthMetaL.toStringAsFixed(1),
      pHeelL.toStringAsFixed(1),
      accXL.toStringAsFixed(3),
      accYL.toStringAsFixed(3),
      accZL.toStringAsFixed(3),
      gyroXL.toStringAsFixed(1),
      gyroYL.toStringAsFixed(1),
      gyroZL.toStringAsFixed(1),
      rollL.toStringAsFixed(1),
      pitchL.toStringAsFixed(1),
      yawL.toStringAsFixed(1),
      label,
    ];
  }
}

// 为了兼容性，添加这个空函数
void debugPrint(String message) {
  print(message);
}
