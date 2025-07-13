import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import '../models/vmc_protocol_models.dart';

/// Modern Bluetooth service using platform channels and socket communication
class ModernVMCBluetoothService {
  Socket? _socket;
  StreamSubscription<Uint8List>? _dataSubscription;
  final StreamController<VMCResponse> _responseController = 
      StreamController<VMCResponse>.broadcast();
  
  final List<int> _buffer = [];
  Timer? _responseTimeout;
  Completer<VMCResponse>? _pendingResponse;
  
  // Bluetooth device info
  String? _connectedDeviceAddress;
  String? _connectedDeviceName;
  
  bool get isConnected => _socket != null;
  
  Stream<VMCResponse> get responseStream => _responseController.stream;
  
  /// Request necessary permissions for Bluetooth
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final permissions = <Permission>[
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.location,
        Permission.locationWhenInUse,
      ];
      
      final statuses = await permissions.request();
      
      // Check if all permissions are granted
      return statuses.values.every((status) => 
        status == PermissionStatus.granted || 
        status == PermissionStatus.limited
      );
    }
    return true; // iOS handles permissions automatically
  }
  
  /// Get list of paired Bluetooth devices using platform channels
  Future<List<BluetoothDeviceInfo>> getPairedDevices() async {
    try {
      if (Platform.isAndroid) {
        // Use Android specific implementation
        return await _getAndroidPairedDevices();
      } else {
        // iOS implementation would go here
        return [];
      }
    } catch (e) {
      print('Error getting paired devices: $e');
      return [];
    }
  }
  
  /// Android specific method to get paired devices
  Future<List<BluetoothDeviceInfo>> _getAndroidPairedDevices() async {
    // This would use platform channels to get paired devices
    // For now, returning mock data for demonstration
    return [
      BluetoothDeviceInfo(
        name: 'HC-06',
        address: '00:11:22:33:44:55',
        isConnected: false,
      ),
      BluetoothDeviceInfo(
        name: 'linvor',
        address: '00:11:22:33:44:56',
        isConnected: false,
      ),
    ];
  }
  
  /// Connect to Bluetooth device using Socket
  Future<bool> connect(BluetoothDeviceInfo device) async {
    try {
      // Close existing connection if any
      await disconnect();
      
      // Request permissions first
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        throw Exception('Bluetooth permissions not granted');
      }
      
      // For HC-06, we'll use RFCOMM socket connection
      // This is a simplified implementation - actual implementation would use platform channels
      _socket = await _connectToDevice(device.address);
      
      if (_socket != null) {
        _connectedDeviceAddress = device.address;
        _connectedDeviceName = device.name;
        _setupDataListener();
        return true;
      }
      return false;
    } catch (e) {
      print('Error connecting to device: $e');
      return false;
    }
  }
  
  /// Platform-specific socket connection
  Future<Socket?> _connectToDevice(String address) async {
    try {
      // This is a mock implementation
      // Real implementation would use platform channels to create RFCOMM socket
      
      // For demonstration, we'll simulate a connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Create a mock socket-like connection
      return await Socket.connect('127.0.0.1', 8080).catchError((e) {
        // If local connection fails, create a mock successful connection
        return _createMockSocket();
      });
    } catch (e) {
      print('Socket connection error: $e');
      return null;
    }
  }
  
  /// Create a mock socket for demonstration
  Socket _createMockSocket() {
    // This is for demonstration purposes
    // Real implementation would return actual RFCOMM socket
    throw UnimplementedError('Mock socket - replace with actual RFCOMM connection');
  }
  
  /// Disconnect from the device
  Future<void> disconnect() async {
    try {
      _cancelPendingResponse();
      await _dataSubscription?.cancel();
      await _socket?.close();
      _socket = null;
      _connectedDeviceAddress = null;
      _connectedDeviceName = null;
      _buffer.clear();
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }
  
  /// Setup listener for incoming data from VMC
  void _setupDataListener() {
    _dataSubscription = _socket?.listen(
      (Uint8List data) {
        _processIncomingData(data);
      },
      onError: (error) {
        print('Socket data error: $error');
        _handleConnectionError();
      },
      onDone: () {
        print('Socket connection closed');
        _handleConnectionError();
      },
    );
  }
  
  /// Process incoming data and parse VMC responses
  void _processIncomingData(Uint8List data) {
    _buffer.addAll(data);
    
    // Try to parse complete response frames
    while (_buffer.length >= VMCProtocol.responseFrameSize) {
      final frameBytes = Uint8List.fromList(
        _buffer.take(VMCProtocol.responseFrameSize).toList()
      );
      
      try {
        final response = VMCResponse.fromBytes(frameBytes);
        
        // Validate checksum
        if (response.isChecksumValid) {
          _handleValidResponse(response);
          _buffer.removeRange(0, VMCProtocol.responseFrameSize);
        } else {
          // Invalid checksum, try shifting by one byte
          _buffer.removeAt(0);
          print('Invalid checksum, shifting buffer');
        }
      } catch (e) {
        // Parsing failed, try shifting by one byte
        _buffer.removeAt(0);
        print('Frame parsing failed: $e');
      }
    }
  }
  
  /// Handle valid VMC response
  void _handleValidResponse(VMCResponse response) {
    print('Received valid response: $response');
    
    // Cancel timeout timer
    _responseTimeout?.cancel();
    
    // Complete pending response if any
    if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
      _pendingResponse!.complete(response);
      _pendingResponse = null;
    }
    
    // Broadcast to stream listeners
    _responseController.add(response);
  }
  
  /// Handle connection errors
  void _handleConnectionError() {
    _cancelPendingResponse();
  }
  
  /// Cancel pending response with timeout
  void _cancelPendingResponse() {
    _responseTimeout?.cancel();
    if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
      _pendingResponse!.completeError(
        TimeoutException('Response timeout', const Duration(seconds: 5))
      );
      _pendingResponse = null;
    }
  }
  
  /// Send command to VMC and wait for response
  Future<VMCResponse> sendCommand(VMCCommand command) async {
    if (!isConnected) {
      throw Exception('Not connected to any device');
    }
    
    if (_pendingResponse != null) {
      throw Exception('Another command is in progress');
    }
    
    try {
      // Generate command frame
      final commandBytes = command.generateFrame();
      print('Sending command: ${commandBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ')}');
      
      // Setup response handling
      _pendingResponse = Completer<VMCResponse>();
      
      // Setup timeout
      _responseTimeout = Timer(command.timeout, () {
        _cancelPendingResponse();
      });
      
      // Send command via socket
      _socket?.add(commandBytes);
      
      // Wait for response
      return await _pendingResponse!.future;
      
    } catch (e) {
      _cancelPendingResponse();
      rethrow;
    }
  }
  
  /// High-level command methods (same as previous implementation)
  
  /// Dispense product from specified slot
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
  
  /// Perform self-check on the driver board
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
  
  /// Read current temperature from VMC
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
  
  /// Set temperature control parameters
  Future<VMCResponse> setTemperatureControl({
    required int driverBoardNumber,
    required bool enableControl,
    required bool coolingMode,
    required int targetTemperature,
  }) async {
    // Send temperature control enable/disable command
    var command = TemperatureControlCommand(
      driverBoardNumber: driverBoardNumber,
      enableControl: enableControl,
      coolingMode: coolingMode,
      targetTemperature: targetTemperature,
    );
    
    var response = await sendCommand(command);
    if (!response.isSuccess) return response;
    
    // Small delay between commands
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Send target temperature command
    final tempCommand = SetTargetTemperatureCommand(
      driverBoardNumber: driverBoardNumber,
      temperature: targetTemperature,
    );
    
    return await sendCommand(tempCommand);
  }
  
  /// Control lighting
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
  
  /// Read door status
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
  
  /// Set slot mode (belt/spiral)
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
  
  /// Merge or split slots
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
  
  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    // Platform-specific implementation would go here
    return true; // Simplified for demo
  }
  
  /// Enable Bluetooth if disabled
  Future<bool> enableBluetooth() async {
    // Platform-specific implementation would go here
    return true; // Simplified for demo
  }
  
  /// Get current connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'isConnected': isConnected,
      'deviceName': _connectedDeviceName,
      'deviceAddress': _connectedDeviceAddress,
      'bufferSize': _buffer.length,
      'hasPendingResponse': _pendingResponse != null,
    };
  }
  
  /// Clear the input buffer
  void clearBuffer() {
    _buffer.clear();
  }
  
  void dispose() {
    disconnect();
    _responseController.close();
  }
}

/// Bluetooth device information model
class BluetoothDeviceInfo {
  final String name;
  final String address;
  final bool isConnected;
  
  const BluetoothDeviceInfo({
    required this.name,
    required this.address,
    required this.isConnected,
  });
  
  @override
  String toString() {
    return 'BluetoothDevice(name: $name, address: $address, connected: $isConnected)';
  }
}