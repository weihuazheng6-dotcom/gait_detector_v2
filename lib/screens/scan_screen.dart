import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_manager.dart';
import '../models/gait_data.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late BLEManager _bleManager;
  SensorRole? _selectedRole;

  @override
  void initState() {
    super.initState();
    _bleManager = context.read<BLEManager>();
    _startScanning();
  }

  void _startScanning() async {
    await _bleManager.startScan(duration: const Duration(seconds: 12));
    setState(() {});
  }

  void _showRoleSelectionDialog(BLEDevice device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择设备角色'),
          content: const Text('请选择此设备的用途:'),
          actions: [
            _buildRoleButton(device, SensorRole.leftPressure, '左脚压力'),
            _buildRoleButton(device, SensorRole.rightPressure, '右脚压力'),
            _buildRoleButton(device, SensorRole.leftIMU, '左脚IMU'),
            _buildRoleButton(device, SensorRole.rightIMU, '右脚IMU'),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleButton(BLEDevice device, SensorRole role, String label) {
    return TextButton(
      onPressed: () {
        Navigator.pop(context);
        _connectDevice(device.deviceId, role);
      },
      child: Text(label),
    );
  }

  void _connectDevice(String deviceId, SensorRole role) async {
    _showLoadingDialog();

    final success = await _bleManager.connectDevice(deviceId, role);

    if (mounted) {
      Navigator.pop(context); // 关闭加载对话框

      if (success) {
        _showSnackBar('${_bleManager.getDeviceByRole(role)?.name ?? '设备'} 连接成功');
      } else {
        _showSnackBar('连接失败，请重试');
      }
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('连接中...'),
            ],
          ),
        );
      },
    );
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
        title: const Text('扫描设备'),
        actions: [
          if (_bleManager.isScanning)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _startScanning,
              child: const Text('重新扫描'),
            ),
        ],
      ),
      body: Consumer<BLEManager>(
        builder: (context, bleManager, _) {
          final devices = bleManager.getDiscoveredDevices();

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    bleManager.isScanning ? '扫描中...' : '未发现设备',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _startScanning,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新扫描'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // 已连接设备列表
              if (bleManager.getConnectedDevices().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFFF5F5F5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '已连接设备',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...bleManager.getConnectedDevices().map((device) {
                        return Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      device.role.toString().split('.').last,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),

              // 可用设备列表
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '可用设备',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...devices.map((device) {
                      return _buildDeviceListItem(device);
                    }).toList(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceListItem(BLEDevice device) {
    final rssiColor = _getRSSIColor(device.rssi);

    return GestureDetector(
      onTap: () => _showRoleSelectionDialog(device),
      onLongPress: () => _showRoleSelectionDialog(device),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.bluetooth,
                color: rssiColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      device.deviceId,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${device.rssi} dBm',
                    style: TextStyle(
                      fontSize: 12,
                      color: rssiColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildSignalBars(device.rssi),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignalBars(int rssi) {
    int bars;
    if (rssi > -50) {
      bars = 4;
    } else if (rssi > -60) {
      bars = 3;
    } else if (rssi > -70) {
      bars = 2;
    } else {
      bars = 1;
    }

    return Row(
      children: List.generate(
        4,
        (index) => Container(
          width: 2,
          height: 8 + (index * 2).toDouble(),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: index < bars ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Color _getRSSIColor(int rssi) {
    if (rssi > -50) {
      return Colors.green;
    } else if (rssi > -70) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  @override
  void dispose() {
    _bleManager.stopScan();
    super.dispose();
  }
}
