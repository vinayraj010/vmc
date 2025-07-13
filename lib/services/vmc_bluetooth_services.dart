import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vmc_vendify/model/vmc_protocol_model.dart';

class VMCBluetoothService {
  static const MethodChannel _channel = MethodChannel('vmc_bluetooth');
  
  final StreamController<VMCResponse> _responseController = 
      StreamController<VMCResponse>.broadcast();
  final StreamController<void> _connectionController = 
      StreamController<void>.broadcast();
  
  final List<int> _buffer = [];
  Timer? _responseTimeout;
  Completer<VMCResponse>? _pendingResponse;
  
  String? _connectedDeviceAddress;
  String? _connectedDeviceName;
  bool _isConnected = false;
  
  Stream<VMCResponse> get responseStream => _responseController.stream;
  Stream<void> get connectionLostStream => _connectionController.stream;
  
  bool get isConnected => _isConnected;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get connectedDeviceAddress => _connectedDeviceAddress;
  
  VMCBluetoothService() {
    _setupMethodCallHandler();
  }
  
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDataReceived':
          final data = call.arguments as Uint8List;
          _processIncomingData(data);
          break;
          
        case 'onConnectionLost':
          _handleConnectionLost();
          break;
      }
    });
  }
  
  void _processIncomingData(Uint8List data) {
    _buffer.addAll(data);
    
    while (_buffer.length >= VMCProtocol.responseFrameSize) {
      final frameBytes = Uint8List.fromList(
        _buffer.take(VMCProtocol.responseFrameSize).toList()
      );
      
      try {
        final response = VMCResponse.fromBytes(frameBytes);
        
        if (response.isChecksumValid) {
          _handleValidResponse(response);
          _buffer.removeRange(0, VMCProtocol.responseFrameSize);
        } else {
          _buffer.removeAt(0);
          print('Invalid checksum, shifting buffer');
        }
      } catch (e) {
        _buffer.removeAt(0);
        print('Frame parsing failed: $e');
      }
    }
  }
  
  void _handleValidResponse(VMCResponse response) {
    print('Received valid response: $response');
    
    _responseTimeout?.cancel();
    
    if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
      _pendingResponse!.complete(response);
      _pendingResponse = null;
    }
    
    _responseController.add(response);
  }
  
  void _handleConnectionLost() {
    print('Bluetooth connection lost');
    _isConnected = false;
    _connectedDeviceAddress = null;
    _connectedDeviceName = null;
    _cancelPendingResponse();
    _buffer.clear();
    _connectionController.add(null);
  }
  
  void _cancelPendingResponse() {
    _responseTimeout?.cancel();
    if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
      _pendingResponse!.completeError(
        TimeoutException('Response timeout', const Duration(seconds: 5))
      );
      _pendingResponse = null;
    }
  }
  
  Future<bool> requestPermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationWhenInUse,
    ];
    
    final statuses = await permissions.request();
    
    return statuses.values.every((status) => 
      status == PermissionStatus.granted || 
      status == PermissionStatus.limited
    );
  }
  
  Future<bool> isBluetoothAvailable() async {
    try {
      final result = await _channel.invokeMethod('isBluetoothAvailable');
      return result as bool;
    } catch (e) {
      print('Error checking Bluetooth availability: $e');
      return false;
    }
  }
  
  Future<bool> isBluetoothEnabled() async {
    try {
      final result = await _channel.invokeMethod('isBluetoothEnabled');
      return result as bool;
    } catch (e) {
      print('Error checking Bluetooth status: $e');
      return false;
    }
  }
  
  Future<List<BluetoothDeviceInfo>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod('getPairedDevices');
      final List<dynamic> deviceList = result as List<dynamic>;
      
      return deviceList.map((device) {
        final Map<String, dynamic> deviceMap = Map<String, dynamic>.from(device);
        return BluetoothDeviceInfo(
          name: deviceMap['name'] as String,
          address: deviceMap['address'] as String,
          isConnected: deviceMap['isConnected'] as bool,
        );
      }).toList();
    } catch (e) {
      print('Error getting paired devices: $e');
      return [];
    }
  }
  
  Future<bool> connect(BluetoothDeviceInfo device) async {
    try {
      _buffer.clear();
      _cancelPendingResponse();
      
      final result = await _channel.invokeMethod('connectToDevice', {
        'address': device.address,
      });
      
      if (result as bool) {
        _isConnected = true;
        _connectedDeviceAddress = device.address;
        _connectedDeviceName = device.name;
        return true;
      }
      return false;
    } catch (e) {
      print('Error connecting to device: $e');
      return false;
    }
  }
  
  Future<bool> disconnect() async {
    try {
      _cancelPendingResponse();
      _buffer.clear();
      
      final result = await _channel.invokeMethod('disconnect');
      
      if (result as bool) {
        _isConnected = false;
        _connectedDeviceAddress = null;
        _connectedDeviceName = null;
        return true;
      }
      return false;
    } catch (e) {
      print('Error disconnecting: $e');
      return false;
    }
  }
  
  Future<bool> _sendData(Uint8List data) async {
    if (!_isConnected) {
      throw Exception('Not connected to any device');
    }
    
    try {
      final result = await _channel.invokeMethod('sendData', {
        'data': data,
      });
      return result as bool;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }
  
  Future<VMCResponse> sendCommand(VMCCommand command) async {
    if (!isConnected) {
      throw Exception('Not connected to any device');
    }
    
    if (_pendingResponse != null) {
      throw Exception('Another command is in progress');
    }
    
    try {
      final commandBytes = command.generateFrame();
      print('Sending command: ${commandBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ')}');
      
      _pendingResponse = Completer<VMCResponse>();
      
      _responseTimeout = Timer(command.timeout, () {
        _cancelPendingResponse();
      });
      
      final success = await _sendData(commandBytes);
      if (!success) {
        _cancelPendingResponse();
        throw Exception('Failed to send command');
      }
      
      return await _pendingResponse!.future;
      
    } catch (e) {
      _cancelPendingResponse();
      rethrow;
    }
  }
  
  Future<VMCResponse> dispenseProduct({
    required int driverBoardNumber,
    required int slotNumber,
    bool useDropSensor = true,
  }) async {
    final command = DispenseCommand(
      driverBoardNumber: driverBoardNumber,
      slotNumber: slotNumber,
      useDropSensor: useDropSensor,
    );
    
    return await sendCommand(command);
  }
  
  Future<VMCResponse> performSelfCheck({
    required int driverBoardNumber,
    bool checkDropSensor = true,
  }) async {
    final command = SelfCheckCommand(
      driverBoardNumber: driverBoardNumber,
      checkDropSensor: checkDropSensor,
    );
    
    return await sendCommand(command);
  }
  
  Future<TemperatureData> readTemperature({
    required int driverBoardNumber,
  }) async {
    final command = ReadTemperatureCommand(driverBoardNumber: driverBoardNumber);
    final response = await sendCommand(command);
    
    if (!response.isSuccess) {
      throw Exception('Failed to read temperature: ${response.errorDescription}');
    }
    
    return TemperatureData.fromResponse(response);
  }
  
  Future<VMCResponse> setTemperatureControl({
    required int driverBoardNumber,
    required bool enableControl,
    required bool coolingMode,
    required int targetTemperature,
  }) async {
    var command = TemperatureControlCommand(
      driverBoardNumber: driverBoardNumber,
      enableControl: enableControl,
      coolingMode: coolingMode,
      targetTemperature: targetTemperature,
    );
    
    var response = await sendCommand(command);
    if (!response.isSuccess) return response;
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    final tempCommand = SetTargetTemperatureCommand(
      driverBoardNumber: driverBoardNumber,
      temperature: targetTemperature,
    );
    
    return await sendCommand(tempCommand);
  }
  
  Future<VMCResponse> controlLighting({
    required int driverBoardNumber,
    required bool turnOn,
  }) async {
    final command = LightingControlCommand(
      driverBoardNumber: driverBoardNumber,
      turnOn: turnOn,
    );
    
    return await sendCommand(command);
  }
  
  Future<DoorStatusData> readDoorStatus({
    required int driverBoardNumber,
  }) async {
    final command = DoorStatusCommand(driverBoardNumber: driverBoardNumber);
    final response = await sendCommand(command);
    
    if (!response.isSuccess) {
      throw Exception('Failed to read door status: ${response.errorDescription}');
    }
    
    return DoorStatusData.fromResponse(response);
  }
  
  Future<VMCResponse> setSlotMode({
    required int driverBoardNumber,
    required int slotNumber,
    required bool isBeltMode,
  }) async {
    final command = SetSlotModeCommand(
      driverBoardNumber: driverBoardNumber,
      slotNumber: slotNumber,
      isBeltMode: isBeltMode,
    );
    
    return await sendCommand(command);
  }
  
  Future<VMCResponse> setSlotMerge({
    required int driverBoardNumber,
    required int slotNumber,
    required bool isDualSlot,
  }) async {
    final command = SlotMergeCommand(
      driverBoardNumber: driverBoardNumber,
      slotNumber: slotNumber,
      isDualSlot: isDualSlot,
    );
    
    return await sendCommand(command);
  }
  
  Future<bool> checkConnection() async {
    try {
      final result = await _channel.invokeMethod('isConnected');
      _isConnected = result as bool;
      return _isConnected;
    } catch (e) {
      print('Error checking connection: $e');
      _isConnected = false;
      return false;
    }
  }
  
  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': isConnected,
      'deviceName': connectedDeviceName,
      'deviceAddress': connectedDeviceAddress,
      'bufferSize': _buffer.length,
      'hasPendingResponse': _pendingResponse != null,
    };
  }
  
  void clearBuffer() {
    _buffer.clear();
  }
  
  void dispose() {
    _cancelPendingResponse();
    _responseController.close();
    _connectionController.close();
  }
}