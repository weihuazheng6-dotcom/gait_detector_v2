import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'gait_data.dart';

class CSVExportService {
  static const String headerLine =
      'timestamp,P_first_meta_R,P_Fifth_meta_R,P_heel_R,acc_x_R,acc_y_R,acc_z_R,ave_x_R,ave_y_R,ave_z_R,'
      'ang_x_R,ang_y_R,ang_z_R,P_first_meta_L,P_Fifth_meta_L,P_heel_L,acc_x_L,acc_y_L,acc_z_L,'
      'ave_x_L,ave_y_L,ave_z_L,ang_x_L,ang_y_L,ang_z_L,Label';

  /// 导出数据为CSV文件
  static Future<String?> exportToCSV(List<GaitDataRecord> records) async {
    try {
      if (records.isEmpty) {
        debugPrint('No records to export');
        return null;
      }

      // 生成文件名
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'gait_data_$timestamp.csv';

      // 获取存储路径
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$filename';

      debugPrint('Exporting to: $filePath');

      // 创建文件
      final file = File(filePath);

      // 构建CSV内容
      final buffer = StringBuffer();

      // 写入表头
      buffer.writeln(headerLine);

      // 写入数据行
      for (final record in records) {
        final row = record.toCSVRow();
        buffer.writeln(row.join(','));
      }

      // 写入文件
      await file.writeAsString(buffer.toString());

      debugPrint('Export successful: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error exporting to CSV: $e');
      return null;
    }
  }

  /// 获取默认文档目录路径
  static Future<String> getDocumentPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// 检查文件是否存在
  static Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return file.exists();
  }

  /// 获取文件大小（字节）
  static Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return file.lengthSync();
    }
    return 0;
  }

  /// 删除文件
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('File deleted: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting file: $e');
      return false;
    }
  }

  /// 读取CSV文件
  static Future<List<GaitDataRecord>> readCSV(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File not found: $filePath');
        return [];
      }

      final contents = await file.readAsString();
      final lines = contents.split('\n');

      final records = <GaitDataRecord>[];

      // 跳过头行，开始读取数据
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        try {
          final values = line.split(',');
          if (values.length >= 26) {
            final record = GaitDataRecord(
              timestamp: values[0],
              pFirstMetaR: double.tryParse(values[1]) ?? 0.0,
              pFifthMetaR: double.tryParse(values[2]) ?? 0.0,
              pHeelR: double.tryParse(values[3]) ?? 0.0,
              accXR: double.tryParse(values[4]) ?? 0.0,
              accYR: double.tryParse(values[5]) ?? 0.0,
              accZR: double.tryParse(values[6]) ?? 0.0,
              gyroXR: double.tryParse(values[7]) ?? 0.0,
              gyroYR: double.tryParse(values[8]) ?? 0.0,
              gyroZR: double.tryParse(values[9]) ?? 0.0,
              rollR: double.tryParse(values[10]) ?? 0.0,
              pitchR: double.tryParse(values[11]) ?? 0.0,
              yawR: double.tryParse(values[12]) ?? 0.0,
              pFirstMetaL: double.tryParse(values[13]) ?? 0.0,
              pFifthMetaL: double.tryParse(values[14]) ?? 0.0,
              pHeelL: double.tryParse(values[15]) ?? 0.0,
              accXL: double.tryParse(values[16]) ?? 0.0,
              accYL: double.tryParse(values[17]) ?? 0.0,
              accZL: double.tryParse(values[18]) ?? 0.0,
              gyroXL: double.tryParse(values[19]) ?? 0.0,
              gyroYL: double.tryParse(values[20]) ?? 0.0,
              gyroZL: double.tryParse(values[21]) ?? 0.0,
              rollL: double.tryParse(values[22]) ?? 0.0,
              pitchL: double.tryParse(values[23]) ?? 0.0,
              yawL: double.tryParse(values[24]) ?? 0.0,
              label: values[25],
            );
            records.add(record);
          }
        } catch (e) {
          debugPrint('Error parsing CSV line $i: $e');
        }
      }

      debugPrint('Loaded ${records.length} records from CSV');
      return records;
    } catch (e) {
      debugPrint('Error reading CSV: $e');
      return [];
    }
  }
}

void debugPrint(String message) {
  print(message);
}
