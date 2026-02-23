// Team Amorcillo, Lelis, Noseñas / IT10 (11120) / Instructor: Lloyd Ryan Largo

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const GreenhouseApp());
}

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Greenhouse Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black, // Base background
        cardTheme: const CardThemeData(color: Colors.black26),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const GreenhouseMonitorScreen(),
    );
  }
}

class GreenhouseMonitorScreen extends StatefulWidget {
  const GreenhouseMonitorScreen({super.key});

  @override
  State<GreenhouseMonitorScreen> createState() => _GreenhouseMonitorScreenState();
}

class _GreenhouseMonitorScreenState extends State<GreenhouseMonitorScreen> {
  // STATE VARIABLES
  BluetoothConnection? _connection;
  bool _isConnected = false;
  bool _isConnecting = false;
  
  String _dataBuffer = '';
  
  // Parsed data
  String _temperature = '--';
  String _humidity = '--';
  String _status = 'SAFE ZONE';
  String _plant = '--';
  String _maxTemp = '--';
  String _minTemp = '--';
  bool _fanOn = false;
  bool _heaterOn = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    if (_connection != null && _isConnected) {
      _connection!.dispose();
    }
    super.dispose();
  }

  // ==========================================
  // PERMISSIONS
  // ==========================================
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  // ==========================================
  // BLUETOOTH CONNECTION
  // ==========================================
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });

    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(device.address);
      if (!mounted) return;

      setState(() {
        _connection = connection;
        _isConnected = true;
        _isConnecting = false;
      });

      _showSnackBar('Connected to ${device.name ?? device.address}');

      // DATA RECEPTION
      _connection!.input!.listen(_onDataReceived).onDone(() {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _connection = null;
          });
          _showSnackBar('Disconnected');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
         _isConnecting = false;
      });
      _showSnackBar('Connection failed: $e');
    }
  }

  void _disconnect() {
    if (_connection != null) {
      _connection!.dispose();
      _connection = null;
    }
    setState(() {
      _isConnected = false;
    });
    _showSnackBar('Disconnected');
  }

  // ==========================================
  // DATA PARSING
  // ==========================================
  void _onDataReceived(Uint8List data) {
    String dataString = ascii.decode(data);
    _dataBuffer += dataString;

    List<String> lines = _dataBuffer.split('\n');

    if (lines.isEmpty) return;

    if (_dataBuffer.endsWith('\n')) {
      _dataBuffer = '';
    } else {
      _dataBuffer = lines.last;
      lines.removeLast();
    }

    if (lines.isEmpty) return;

    String lastCompleteMessage = '';
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim().isNotEmpty) {
        lastCompleteMessage = lines[i].trim();
        break;
      }
    }

    if (lastCompleteMessage.isNotEmpty) {
      _parseMessage(lastCompleteMessage);
    }
  }

  void _parseMessage(String message) {
    List<String> parts = message.split(',');
    if (parts.length == 8) {
      if (mounted) {
        setState(() {
          _temperature = parts[0].trim();
          _humidity = parts[1].trim();
          _status = parts[2].trim();
          _plant = parts[3].trim();
          _maxTemp = parts[4].trim();
          _minTemp = parts[5].trim();
          _fanOn = parts[6].trim() == '1';
          _heaterOn = parts[7].trim().contains('1');
        });
      }
    }
  }

  // ==========================================
  // SEND COMMANDS
  // ==========================================
  void _sendCommand(String profileCommand) {
    if (_isConnected && _connection != null) {
      _connection!.output.add(ascii.encode(profileCommand));
      _showSnackBar('Sent: Profile $profileCommand');
    } else {
      _showSnackBar('Not connected to any device');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showDeviceListDialog() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      _showSnackBar('Error getting bonded devices.');
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Device', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.grey[900],
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = devices[index];
                return ListTile(
                  title: Text(device.name ?? 'Unknown Device', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(device.address, style: const TextStyle(color: Colors.white70)),
                  onTap: () {
                    Navigator.pop(context);
                    _connectToDevice(device);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Color _getBackgroundColor() {
    switch (_status) {
      case 'SAFE ZONE':
        return const Color(0xFF2E7D32);
      case 'CRITICAL HEAT':
        return const Color(0xFFC62828);
      case 'WARNING COLD':
        return const Color(0xFF1565C0);
      case 'SENSOR ERROR':
        return const Color(0xFFE65100);
      default:
        return Colors.black;
    }
  }

  // ==========================================
  // BUILD UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    Color bgColor = _getBackgroundColor();

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: bgColor,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTitleCard(),
                const SizedBox(height: 16),
                _buildBluetoothCard(),
                const SizedBox(height: 16),
                _buildSensorCard(),
                const SizedBox(height: 16),
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildActuatorCards(),
                const SizedBox(height: 16),
                _buildProfileButtonsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleCard() {
    return const Column(
      children: [
        Icon(Icons.eco, color: Colors.greenAccent, size: 48),
        SizedBox(height: 8),
        Text(
          'GREENHOUSE MONITOR',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        Text(
          'Smart Climate System v2.1',
          style: TextStyle(fontSize: 16, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBluetoothCard() {
    return Card(
      color: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : (_isConnecting ? Colors.orange : Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected' : (_isConnecting ? 'Connecting...' : 'Disconnected'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isConnected || _isConnecting ? null : _showDeviceListDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.blue.withOpacity(0.5),
                  ),
                  child: const Text('Connect', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    disabledBackgroundColor: Colors.red.withOpacity(0.5),
                  ),
                  child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard() {
    return Card(
      color: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Column(
                children: [
                  const Icon(Icons.thermostat, color: Colors.orange, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    '$_temperature°C',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            Container(
              height: 60,
              width: 1,
              color: Colors.white30,
            ),
            Expanded(
              child: Column(
                children: [
                  const Icon(Icons.water_drop, color: Colors.lightBlue, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    '$_humidity%',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    IconData statusIcon;
    Color statusColor;

    switch (_status) {
      case 'CRITICAL HEAT':
        statusIcon = Icons.whatshot;
        statusColor = Colors.redAccent;
        break;
      case 'WARNING COLD':
        statusIcon = Icons.ac_unit;
        statusColor = Colors.lightBlueAccent;
        break;
      case 'SENSOR ERROR':
        statusIcon = Icons.error_outline;
        statusColor = Colors.orangeAccent;
        break;
      case 'SAFE ZONE':
      default:
        statusIcon = Icons.check_circle_outline;
        statusColor = Colors.greenAccent;
        break;
    }

    return Card(
      color: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, color: statusColor, size: 32),
                const SizedBox(width: 8),
                Text(
                  _status,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white30),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.local_florist, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text('Profile: $_plant', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.straighten, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text('Range: $_minTemp°C — $_maxTemp°C', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActuatorCards() {
    return Row(
      children: [
        Expanded(
          child: Card(
            color: _fanOn ? Colors.blue.withOpacity(0.3) : Colors.black26,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.air, color: _fanOn ? Colors.lightBlueAccent : Colors.grey, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'FAN',
                    style: TextStyle(color: _fanOn ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _fanOn ? 'ON' : 'OFF',
                    style: TextStyle(color: _fanOn ? Colors.lightBlueAccent : Colors.grey, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            color: _heaterOn ? Colors.orange.withOpacity(0.3) : Colors.black26,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.local_fire_department, color: _heaterOn ? Colors.orangeAccent : Colors.grey, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'HEATER',
                    style: TextStyle(color: _heaterOn ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _heaterOn ? 'ON' : 'OFF',
                    style: TextStyle(color: _heaterOn ? Colors.orangeAccent : Colors.grey, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileButtonsCard() {
    return Card(
      color: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'SELECT PLANT PROFILE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            _buildProfileButton(
              'Waling-waling',
              '15°C – 35°C',
              'A',
              Colors.purpleAccent,
              Icons.filter_vintage,
            ),
            const SizedBox(height: 8),
            _buildProfileButton(
              'Durian',
              '22°C – 32°C',
              'B',
              Colors.amber,
              Icons.spa,
            ),
            const SizedBox(height: 8),
            _buildProfileButton(
              'Mangosteen',
              '20°C – 30°C',
              'C',
              Colors.tealAccent,
              Icons.grass,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileButton(
    String plantName,
    String range,
    String command,
    Color accentColor,
    IconData iconData,
  ) {
    bool isActive = _plant == plantName;

    return InkWell(
      onTap: () => _sendCommand(command),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? accentColor : Colors.white12,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(iconData, color: accentColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plantName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(range, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            if (isActive) Icon(Icons.check_circle, color: accentColor),
          ],
        ),
      ),
    );
  }
}
