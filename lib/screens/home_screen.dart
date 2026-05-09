import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/ble_manager.dart';
import '../services/csv_export.dart';
import '../models/gait_data.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late BLEManager _bleManager;
  Timer? _recordingTimer;
  Timer? _dataUpdateTimer;

  @override
  void initState() {
    super.initState();
    _bleManager = context.read<BLEManager>();
    _requestPermissions();
    _startDataUpdateLoop();
  }

  void _requestPermissions() async {
    await _bleManager.requestPermissions();
  }

  void _startDataUpdateLoop() {
    // 定时录制数据（10Hz = 100ms）
    _dataUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted && _bleManager.isRecording) {
        _bleManager.recordGaitData();
      }
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _dataUpdateTimer?.cancel();
    super.dispose();
  }

  void _navigateToScan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    ).then((_) {
      setState(() {}); // 返回后刷新
    });
  }

  void _toggleRecording() {
    if (_bleManager.isRecording) {
      _bleManager.stopRecording();
      _recordingTimer?.cancel();
      _showSnackBar('录制已停止，共 ${_bleManager.recordedData.length} 条数据');
    } else {
      _bleManager.startRecording();
      _showSnackBar('开始录制');
    }
  }

  void _setLabel(String label) {
    _bleManager.setLabel(label);
    _showSnackBar('标签已设为: $label');
  }

  void _exportCSV() async {
    if (_bleManager.recordedData.isEmpty) {
      _showSnackBar('没有可导出的数据');
      return;
    }

    final filePath = await CSVExportService.exportToCSV(
      _bleManager.recordedData,
    );

    if (filePath != null) {
      _showSnackBar('导出成功: $filePath');
    } else {
      _showSnackBar('导出失败');
    }
  }

  void _disconnectAll() async {
    await _bleManager.disconnectAll();
    _showSnackBar('已断开所有连接');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('步态检测'),
        elevation: 1,
        shadowColor: Colors.grey.withOpacity(0.2),
      ),
      body: Consumer<BLEManager>(
        builder: (context, bleManager, _) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 设备卡片网格
                  const SizedBox(height: 8),
                  const Text(
                    '设备状态',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildDeviceCard(
                        bleManager,
                        SensorRole.leftPressure,
                        '左脚压力',
                      ),
                      _buildDeviceCard(
                        bleManager,
                        SensorRole.rightPressure,
                        '右脚压力',
                      ),
                      _buildDeviceCard(
                        bleManager,
                        SensorRole.leftIMU,
                        '左脚IMU',
                      ),
                      _buildDeviceCard(
                        bleManager,
                        SensorRole.rightIMU,
                        '右脚IMU',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 控制按钮
                  const Text(
                    '控制面板',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 第一行：扫描和断开
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _navigateToScan,
                          icon: const Icon(Icons.bluetooth_searching),
                          label: const Text('扫描设备'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _disconnectAll,
                          icon: const Icon(Icons.link_off),
                          label: const Text('断开全部'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 第二行：录制控制
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _toggleRecording,
                          icon: Icon(
                            bleManager.isRecording ? Icons.stop : Icons.fiber_manual_record,
                          ),
                          label: Text(
                            bleManager.isRecording ? '停止录制' : '开始录制',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: bleManager.isRecording
                                ? Colors.red
                                : const Color(0xFF1565C0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportCSV,
                          icon: const Icon(Icons.download),
                          label: const Text('导出CSV'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 标签选择
                  const Text(
                    '标签 (0-9)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(10, (index) {
                      final label = index.toString();
                      return FilterChip(
                        label: Text(label),
                        selected: bleManager.currentLabel == label,
                        onSelected: (_) => _setLabel(label),
                        backgroundColor: Colors.white,
                        selectedColor: const Color(0xFF1565C0),
                        labelStyle: TextStyle(
                          color: bleManager.currentLabel == label
                              ? Colors.white
                              : const Color(0xFF1565C0),
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  // 统计信息
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '录制信息',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('状态: ${bleManager.isRecording ? '录制中' : '未录制'}'),
                        Text('已录制: ${bleManager.recordedData.length} 条'),
                        Text('当前标签: ${bleManager.currentLabel.isEmpty ? '未设置' : bleManager.currentLabel}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(
    BLEManager bleManager,
    SensorRole role,
    String roleDisplay,
  ) {
    final device = bleManager.getDeviceByRole(role);
    final isPressure =
        role == SensorRole.leftPressure || role == SensorRole.rightPressure;

    return GestureDetector(
      onTap: () {
        if (device == null) {
          _navigateToScan();
        }
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和状态
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      roleDisplay,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1565C0),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusIndicator(device?.status),
                ],
              ),
              const SizedBox(height: 8),

              // 设备名称
              if (device != null)
                Text(
                  device.name,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 8),

              // 数据显示
              if (device != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: isPressure
                        ? _buildPressureDataDisplay(device)
                        : _buildIMUDataDisplay(device),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      '点击连接',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(ConnectionStatus? status) {
    Color color;
    String text;

    switch (status) {
      case ConnectionStatus.connected:
        color = Colors.green;
        text = '已连接';
        break;
      case ConnectionStatus.connecting:
        color = Colors.orange;
        text = '连接中';
        break;
      case ConnectionStatus.failed:
        color = Colors.red;
        text = '失败';
        break;
      default:
        color = Colors.grey;
        text = '未连接';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPressureDataDisplay(BLEDevice device) {
    final data = device.pressureData;
    if (data == null) {
      return Text(
        '等待数据...',
        style: TextStyle(fontSize: 10, color: Colors.grey[400]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'P1: ${data.p1.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11),
        ),
        Text(
          'P2: ${data.p2.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11),
        ),
        Text(
          'P3: ${data.p3.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildIMUDataDisplay(BLEDevice device) {
    final data = device.imuData;
    if (data == null) {
      return Text(
        '等待数据...',
        style: TextStyle(fontSize: 10, color: Colors.grey[400]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acc: ${data.accX.toStringAsFixed(2)}, ${data.accY.toStringAsFixed(2)}, ${data.accZ.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 9),
        ),
        Text(
          'Gyro: ${data.gyroX.toStringAsFixed(1)}, ${data.gyroY.toStringAsFixed(1)}, ${data.gyroZ.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 9),
        ),
        Text(
          'Roll: ${data.roll.toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 9),
        ),
        Text(
          'Pitch: ${data.pitch.toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 9),
        ),
        Text(
          'Yaw: ${data.yaw.toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 9),
        ),
      ],
    );
  }
}
