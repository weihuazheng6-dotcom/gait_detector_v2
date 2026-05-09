import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'gait_data.dart';

typedef ScanResultCallback = void Function(List<BLEDevice> devices);
typedef ConnectionStatusCallback = void Function(String deviceId, ConnectionStatus status);
typedef DataCallback = void Function(String deviceId, dynamic data);

class BLEManager extends ChangeNotifier {
  static final FlutterBluePlus _flutterBlue = FlutterBluePlus();

  // 设备管理
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, BLEDevice> _discoveredDevices = {};
  final Map<String, BLEDevice> _assignedDevices = {};

  // 数据管理
  final Map<String, PressureData> _pressureDataMap = {};
  final Map<String, IMUData> _imuDataMap = {};
  final Map<String, List<int>> _imuFrameBuffer = {};
  final Map<String, StringBuffer> _pressureBufferMap = {};

  // 轮询定时器
  final Map<String, Timer?> _imuPollingTimers = {};

  // 录制数据
  bool isRecording = false;
  String currentLabel = '';
  final List<GaitDataRecord> recordedData = [];

  // 回调
  ScanResultCallback? onScanResultsChanged;
  ConnectionStatusCallback? onConnectionStatusChanged;
  DataCallback? onDataReceived;

  // 扫描状态
  bool isScanning = false;
  StreamSubscription? _scanSubscription;

  BLEManager() {
    _initialize();
  }

  void _initialize() {
    _flutterBlue.adapterState.listen((state) {
      debugPrint('Bluetooth adapter state: ${state.name}');
    });
  }

  /// 请求蓝牙相关权限
  Future<bool> requestPermissions() async {
    try {
      final permissions = <Permission>[
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ];

      final statuses = await permissions.request();
      debugPrint('Permission statuses: $statuses');

      return statuses.values.every((status) => status.isGranted);
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  /// 开始扫描BLE设备
  Future<void> startScan({Duration duration = const Duration(seconds: 12)}) async {
    try {
      if (isScanning) {
        debugPrint('Scan already in progress');
        return;
      }

      _discoveredDevices.clear();
      isScanning = true;
      notifyListeners();

      debugPrint('Starting BLE scan...');

      _scanSubscription?.cancel();
      _scanSubscription = _flutterBlue.onScanResults.listen(
        (results) {
          for (var result in results) {
            final deviceId = result.device.remoteId.str;
            final name = result.device.advName.isEmpty ? 'Unknown' : result.device.advName;

            if (!_discoveredDevices.containsKey(deviceId)) {
              final bleDevice = BLEDevice(
                deviceId: deviceId,
                name: name,
                rssi: result.rssi,
              );
              _discoveredDevices[deviceId] = bleDevice;
              debugPrint('Discovered device: $name ($deviceId) - RSSI: ${result.rssi}');
            }
          }

          onScanResultsChanged?.call(_discoveredDevices.values.toList());
          notifyListeners();
        },
        onError: (e) {
          debugPrint('Scan error: $e');
        },
      );

      await _flutterBlue.startScan(timeout: duration);

      // 扫描结束后
      await Future.delayed(duration);
      await stopScan();
    } catch (e) {
      debugPrint('Error starting scan: $e');
      isScanning = false;
      notifyListeners();
    }
  }

  /// 停止扫描
  Future<void> stopScan() async {
    try {
      await _flutterBlue.stopScan();
      isScanning = false;
      _scanSubscription?.cancel();
      debugPrint('Scan stopped');
      notifyListeners();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  /// 连接设备并分配角色
  Future<bool> connectDevice(String deviceId, SensorRole role) async {
    try {
      if (_connectedDevices.containsKey(deviceId)) {
        debugPrint('Device already connected: $deviceId');
        return true;
      }

      final device = _discoveredDevices[deviceId];
      if (device == null) {
        debugPrint('Device not found: $deviceId');
        return false;
      }

      device.status = ConnectionStatus.connecting;
      device.role = role;
      onConnectionStatusChanged?.call(deviceId, device.status);
      notifyListeners();

      final bluetoothDevice = _flutterBlue.getDeviceById(deviceId);
      if (bluetoothDevice == null) {
        debugPrint('Cannot get bluetooth device: $deviceId');
        return false;
      }

      debugPrint('Connecting to ${device.name}...');
      await bluetoothDevice.connect(timeout: const Duration(seconds: 10));

      _connectedDevices[deviceId] = bluetoothDevice;
      _assignedDevices[deviceId] = device;
      _imuFrameBuffer[deviceId] = [];
      _pressureBufferMap[deviceId] = StringBuffer();

      device.status = ConnectionStatus.connected;
      onConnectionStatusChanged?.call(deviceId, device.status);

      debugPrint('Connected: ${device.name}');

      // 根据设备类型初始化数据处理
      _initializeDataHandling(deviceId, role);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error connecting device $deviceId: $e');
      final device = _discoveredDevices[deviceId];
      if (device != null) {
        device.status = ConnectionStatus.failed;
        onConnectionStatusChanged?.call(deviceId, device.status);
      }
      notifyListeners();
      return false;
    }
  }

  /// 初始化数据处理（根据设备类型）
  void _initializeDataHandling(String deviceId, SensorRole role) {
    if (role == SensorRole.leftPressure || role == SensorRole.rightPressure) {
      _setupPressureSensor(deviceId, role);
    } else if (role == SensorRole.leftIMU || role == SensorRole.rightIMU) {
      _setupIMUSensor(deviceId, role);
    }
  }

  /// 设置压力传感器（Notify模式）
  void _setupPressureSensor(String deviceId, SensorRole role) {
    try {
      final device = _connectedDevices[deviceId];
      if (device == null) return;

      // 搜索FFE0服务和FFE1特征
      device.discoverServices().then((services) {
        for (var service in services) {
          if (service.uuid.str.toUpperCase() == 'FFE0' ||
              service.uuid.str.toUpperCase().endsWith('FFE0')) {
            for (var characteristic in service.characteristics) {
              if (characteristic.uuid.str.toUpperCase() == 'FFE1' ||
                  characteristic.uuid.str.toUpperCase().endsWith('FFE1')) {
                debugPrint('Found pressure service for $deviceId, setting up notify...');

                // 订阅Notify
                characteristic.onValueReceived.listen((value) {
                  _handlePressureData(deviceId, value);
                });

                // 启用Notify
                characteristic.setNotifyValue(true).catchError((e) {
                  debugPrint('Error setting notify: $e');
                });
              }
            }
          }
        }
      }).catchError((e) {
        debugPrint('Error discovering services for pressure sensor: $e');
      });
    } catch (e) {
      debugPrint('Error setting up pressure sensor: $e');
    }
  }

  /// 设置IMU传感器（轮询模式）
  void _setupIMUSensor(String deviceId, SensorRole role) {
    try {
      final device = _connectedDevices[deviceId];
      if (device == null) return;

      device.discoverServices().then((services) {
        BluetoothCharacteristic? readChar;

        for (var service in services) {
          // 查找0000FFE5服务
          if (service.uuid.str.toUpperCase().contains('FFE5')) {
            for (var characteristic in service.characteristics) {
              // 查找0000FFE4特征（Read/Notify）
              if (characteristic.uuid.str.toUpperCase().contains('FFE4')) {
                readChar = characteristic;
                break;
              }
            }
          }
        }

        if (readChar != null) {
          debugPrint('Found IMU service for $deviceId, starting polling...');

          // 启用Notify作为备选
          readChar!.setNotifyValue(true).catchError((e) {
            debugPrint('Error setting notify for IMU: $e');
          });

          // 订阅Notify数据
          readChar!.onValueReceived.listen((value) {
            _handleIMUData(deviceId, value);
          });

          // 启动轮询定时器（100ms间隔）
          final timer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
            try {
              if (_connectedDevices.containsKey(deviceId)) {
                final data = await readChar!.read();
                _handleIMUData(deviceId, data);
              } else {
                timer.cancel();
                _imuPollingTimers.remove(deviceId);
              }
            } catch (e) {
              debugPrint('Error reading IMU data: $e');
            }
          });

          _imuPollingTimers[deviceId] = timer;
        }
      }).catchError((e) {
        debugPrint('Error discovering services for IMU sensor: $e');
      });
    } catch (e) {
      debugPrint('Error setting up IMU sensor: $e');
    }
  }

  /// 处理压力传感器数据
  void _handlePressureData(String deviceId, List<int> rawData) {
    try {
      final buffer = _pressureBufferMap[deviceId];
      if (buffer == null) return;

      // 将原始字节转换为字符串
      final str = String.fromCharCodes(rawData);
      buffer.write(str);

      final fullString = buffer.toString();
      final frameStart = fullString.indexOf('\$');
      final frameEnd = fullString.indexOf(';');

      if (frameStart != -1 && frameEnd != -1 && frameStart < frameEnd) {
        final frame = fullString.substring(frameStart + 1, frameEnd);
        final values = frame.split(',');

        if (values.length >= 3) {
          try {
            final p1 = double.parse(values[0].trim());
            final p2 = double.parse(values[1].trim());
            final p3 = double.parse(values[2].trim());

            final pressureData = PressureData(p1: p1, p2: p2, p3: p3);
            _pressureDataMap[deviceId] = pressureData;

            onDataReceived?.call(deviceId, pressureData);
            notifyListeners();

            debugPrint('Pressure data [$deviceId]: ${pressureData.toString()}');

            // 清空已处理的部分
            _pressureBufferMap[deviceId] = StringBuffer(fullString.substring(frameEnd + 1));
          } catch (e) {
            debugPrint('Error parsing pressure values: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error handling pressure data: $e');
    }
  }

  /// 处理IMU数据
  void _handleIMUData(String deviceId, List<int> rawData) {
    try {
      final buffer = _imuFrameBuffer[deviceId];
      if (buffer == null) return;

      // 将新数据添加到缓冲区
      buffer.addAll(rawData);

      // 查找完整的帧（0x55 0x61开头，20字节）
      while (buffer.length >= 20) {
        // 查找帧头0x55
        int frameStart = -1;
        for (int i = 0; i < buffer.length - 1; i++) {
          if (buffer[i] == 0x55 && buffer[i + 1] == 0x61) {
            frameStart = i;
            break;
          }
        }

        if (frameStart == -1) {
          // 没有找到帧头，清空缓冲区前面的垃圾数据
          if (buffer.isNotEmpty) {
            buffer.removeAt(0);
          }
          break;
        }

        if (frameStart > 0) {
          // 移除帧头前的数据
          buffer.removeRange(0, frameStart);
        }

        if (buffer.length < 20) {
          break; // 数据不足
        }

        // 提取20字节帧
        final frame = buffer.sublist(0, 20);
        buffer.removeRange(0, 20);

        // 解析IMU数据
        final imuData = IMUData.parseFromFrame(frame);
        _imuDataMap[deviceId] = imuData;

        onDataReceived?.call(deviceId, imuData);
        notifyListeners();

        debugPrint(
          'IMU data [$deviceId]: Acc=(${imuData.accX.toStringAsFixed(3)}, ${imuData.accY.toStringAsFixed(3)}, ${imuData.accZ.toStringAsFixed(3)}) '
          'Gyro=(${imuData.gyroX.toStringAsFixed(1)}, ${imuData.gyroY.toStringAsFixed(1)}, ${imuData.gyroZ.toStringAsFixed(1)}) '
          'Angle=(${imuData.roll.toStringAsFixed(1)}, ${imuData.pitch.toStringAsFixed(1)}, ${imuData.yaw.toStringAsFixed(1)})',
        );
      }
    } catch (e) {
      debugPrint('Error handling IMU data: $e');
    }
  }

  /// 获取指定角色的设备
  BLEDevice? getDeviceByRole(SensorRole role) {
    for (var device in _assignedDevices.values) {
      if (device.role == role) {
        return device;
      }
    }
    return null;
  }

  /// 获取所有已连接设备
  List<BLEDevice> getConnectedDevices() {
    return _assignedDevices.values.toList();
  }

  /// 获取所有已发现设备
  List<BLEDevice> getDiscoveredDevices() {
    return _discoveredDevices.values.toList();
  }

  /// 断开指定设备
  Future<void> disconnectDevice(String deviceId) async {
    try {
      // 停止IMU轮询
      _imuPollingTimers[deviceId]?.cancel();
      _imuPollingTimers.remove(deviceId);

      // 断开连接
      final device = _connectedDevices[deviceId];
      if (device != null) {
        await device.disconnect();
        _connectedDevices.remove(deviceId);
      }

      _assignedDevices.remove(deviceId);
      _pressureDataMap.remove(deviceId);
      _imuDataMap.remove(deviceId);
      _imuFrameBuffer.remove(deviceId);
      _pressureBufferMap.remove(deviceId);

      debugPrint('Disconnected: $deviceId');
      notifyListeners();
    } catch (e) {
      debugPrint('Error disconnecting device: $e');
    }
  }

  /// 断开所有设备
  Future<void> disconnectAll() async {
    final deviceIds = List<String>.from(_connectedDevices.keys);
    for (final deviceId in deviceIds) {
      await disconnectDevice(deviceId);
    }
  }

  /// 开始录制
  void startRecording() {
    isRecording = true;
    recordedData.clear();
    currentLabel = '';
    notifyListeners();
    debugPrint('Recording started');
  }

  /// 停止录制
  void stopRecording() {
    isRecording = false;
    notifyListeners();
    debugPrint('Recording stopped. Total records: ${recordedData.length}');
  }

  /// 更新当前标签
  void setLabel(String label) {
    currentLabel = label;
    notifyListeners();
  }

  /// 记录步态数据
  void recordGaitData() {
    if (!isRecording) return;

    try {
      final rightPressure = getDeviceByRole(SensorRole.rightPressure);
      final leftPressure = getDeviceByRole(SensorRole.leftPressure);
      final rightIMU = getDeviceByRole(SensorRole.rightIMU);
      final leftIMU = getDeviceByRole(SensorRole.leftIMU);

      final rPressure = rightPressure != null && rightPressure.pressureData != null
          ? rightPressure.pressureData!
          : PressureData.empty();
      final lPressure = leftPressure != null && leftPressure.pressureData != null
          ? leftPressure.pressureData!
          : PressureData.empty();
      final rIMU = rightIMU != null && rightIMU.imuData != null
          ? rightIMU.imuData!
          : IMUData.empty();
      final lIMU = leftIMU != null && leftIMU.imuData != null
          ? leftIMU.imuData!
          : IMUData.empty();

      final record = GaitDataRecord(
        timestamp: DateTime.now().toIso8601String(),
        pFirstMetaR: rPressure.p1,
        pFifthMetaR: rPressure.p2,
        pHeelR: rPressure.p3,
        accXR: rIMU.accX,
        accYR: rIMU.accY,
        accZR: rIMU.accZ,
        gyroXR: rIMU.gyroX,
        gyroYR: rIMU.gyroY,
        gyroZR: rIMU.gyroZ,
        rollR: rIMU.roll,
        pitchR: rIMU.pitch,
        yawR: rIMU.yaw,
        pFirstMetaL: lPressure.p1,
        pFifthMetaL: lPressure.p2,
        pHeelL: lPressure.p3,
        accXL: lIMU.accX,
        accYL: lIMU.accY,
        accZL: lIMU.accZ,
        gyroXL: lIMU.gyroX,
        gyroYL: lIMU.gyroY,
        gyroZL: lIMU.gyroZ,
        rollL: lIMU.roll,
        pitchL: lIMU.pitch,
        yawL: lIMU.yaw,
        label: currentLabel,
      );

      recordedData.add(record);
    } catch (e) {
      debugPrint('Error recording gait data: $e');
    }
  }

  /// 获取录制的数据
  List<GaitDataRecord> getRecordedData() {
    return List.from(recordedData);
  }

  /// 清空录制数据
  void clearRecordedData() {
    recordedData.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnectAll();
    for (final timer in _imuPollingTimers.values) {
      timer?.cancel();
    }
    _imuPollingTimers.clear();
    _scanSubscription?.cancel();
    super.dispose();
  }
}
