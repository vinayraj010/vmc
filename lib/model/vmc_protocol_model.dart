import 'dart:typed_data';
import 'dart:typed_data';

/// VMC Protocol Constants
class VMCProtocol {
  // Frame sizes
  static const int commandFrameSize = 6;
  static const int responseFrameSize = 5;
  
  // Response status codes
  static const int statusNormal = 0x5D;
  static const int statusAbnormal = 0x5C;
  
  // Product delivery flags
  static const int noProductDelivery = 0x00;
  static const int productDelivered = 0xAA;
  
  // Command codes
  static const int cmdDispenseStart = 0x01;
  static const int cmdDispenseEnd = 0x50;
  static const int cmdSelfCheck = 0x64;
  static const int cmdSlotReset = 0x65;
  static const int cmdSetBeltSlot = 0x68;
  static const int cmdSetSpiralSlot = 0x74;
  static const int cmdSetAllSpiralSlots = 0x75;
  static const int cmdSetAllBeltSlots = 0x76;
  static const int cmdQuerySlotStart = 0x79;
  static const int cmdQuerySlotEnd = 0xC8;
  static const int cmdSetSingleSlot = 0xC9;
  static const int cmdSetDualSlot = 0xCA;
  static const int cmdSetAllSingleSlots = 0xCB;
  static const int cmdTemperatureControl = 0xCC;
  static const int cmdTemperatureMode = 0xCD;
  static const int cmdSetTargetTemperature = 0xCE;
  static const int cmdSetTempReturnDiff = 0xCF;
  static const int cmdSetTempCompensation = 0xD0;
  static const int cmdSetDefrostTime = 0xD1;
  static const int cmdSetWorkingTime = 0xD2;
  static const int cmdSetDowntime = 0xD3;
  static const int cmdGlassHeating = 0xD4;
  static const int cmdReadTemperature = 0xDC;
  static const int cmdLightingControl = 0xDD;
  static const int cmdDoorStatus = 0xDF;
  
  // Drop sensor flags
  static const int withoutDropSensor = 0x55;
  static const int withDropSensor = 0xAA;
  
  // Temperature control flags
  static const int tempControlDisabled = 0x00;
  static const int tempControlEnabled = 0x01;
  static const int heatingMode = 0x00;
  static const int coolingMode = 0x01;
  
  // Lighting control flags
  static const int lightOff = 0x55;
  static const int lightOn = 0xAA;
  
  // Glass heating flags
  static const int glassHeatingOff = 0x00;
  static const int glassHeatingOn = 0x01;
}

/// Base class for all VMC commands
abstract class VMCCommand {
  final int driverBoardNumber;
  
  const VMCCommand({required this.driverBoardNumber});
  
  /// Generate the 6-byte command frame according to protocol
  Uint8List generateFrame();
  
  /// Validate command parameters
  bool validate();
  
  /// Get expected response timeout
  Duration get timeout => const Duration(seconds: 5);
}

/// VMC Response class for parsing driver board responses
class VMCResponse {
  final int driverBoardNumber;
  final bool isSuccess;
  final int errorCode;
  final int productFlag;
  final int checksum;
  final bool isChecksumValid;
  
  const VMCResponse({
    required this.driverBoardNumber,
    required this.isSuccess,
    required this.errorCode,
    required this.productFlag,
    required this.checksum,
    required this.isChecksumValid,
  });
  
  factory VMCResponse.fromBytes(Uint8List bytes) {
    if (bytes.length != VMCProtocol.responseFrameSize) {
      throw ArgumentError('Response must be exactly ${VMCProtocol.responseFrameSize} bytes');
    }
    
    final r1 = bytes[0]; // Driver board number
    final r2 = bytes[1]; // Error code (0x5D normal, 0x5C abnormal)
    final r3 = bytes[2]; // Error parsing code
    final r4 = bytes[3]; // Product delivery flag
    final r5 = bytes[4]; // Checksum
    
    // Verify checksum: R5 = (R1 + R2 + R3 + R4) & 0xFF
    final calculatedChecksum = (r1 + r2 + r3 + r4) & 0xFF;
    final isChecksumValid = calculatedChecksum == r5;
    
    return VMCResponse(
      driverBoardNumber: r1,
      isSuccess: r2 == VMCProtocol.statusNormal,
      errorCode: r3,
      productFlag: r4,
      checksum: r5,
      isChecksumValid: isChecksumValid,
    );
  }
  
  bool get hasProductDelivery => productFlag == VMCProtocol.productDelivered;
  
  String get errorDescription {
    if (isSuccess) return 'Operation successful';
    
    final y = (errorCode >> 4) & 0xF; // Upper nibble - Motor/MOSFET status
    final z = errorCode & 0xF;        // Lower nibble - Sensor status
    
    String motorStatus = _getMotorStatus(y);
    String sensorStatus = _getSensorStatus(z);
    
    return '$motorStatus; $sensorStatus';
  }
  
  String _getMotorStatus(int y) {
    switch (y) {
      case 0: return 'Motor and MOSFET normal';
      case 1: return 'PMOS short circuit';
      case 2: return 'NMOS short circuit';
      case 3: return 'Motor short circuit';
      case 4: return 'Motor open circuit';
      case 5: return 'Motor rotation timeout';
      default: return 'Unknown motor error ($y)';
    }
  }
  
  String _getSensorStatus(int z) {
    switch (z) {
      case 0: return 'Drop sensor normal';
      case 1: return 'Signal output when no emission in drop sensor';
      case 2: return 'No signal output when drop sensor disabled';
      case 3: return 'Signal output when product passing through drop sensor';
      default: return 'Unknown sensor error ($z)';
    }
  }
  
  @override
  String toString() {
    return 'VMCResponse(board: $driverBoardNumber, success: $isSuccess, '
           'error: 0x${errorCode.toRadixString(16).padLeft(2, '0').toUpperCase()}, '
           'product: ${hasProductDelivery ? 'delivered' : 'none'}, '
           'checksum: ${isChecksumValid ? 'valid' : 'invalid'})';
  }
}

/// Dispense command implementation
class DispenseCommand extends VMCCommand {
  final int slotNumber;
  final bool useDropSensor;
  
  const DispenseCommand({
    required super.driverBoardNumber,
    required this.slotNumber,
    this.useDropSensor = true,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && 
           driverBoardNumber <= 255 && 
           slotNumber >= 1 && 
           slotNumber <= 80;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid dispense command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = slotNumber; // 0x01-0x50 for slots 1-80
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = useDropSensor ? VMCProtocol.withDropSensor : VMCProtocol.withoutDropSensor;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
  
  @override
  Duration get timeout => const Duration(seconds: 10); // Dispensing may take longer
}

/// Self-check command implementation
class SelfCheckCommand extends VMCCommand {
  final bool checkDropSensor;
  
  const SelfCheckCommand({
    required super.driverBoardNumber,
    this.checkDropSensor = true,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && driverBoardNumber <= 255;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid self-check command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdSelfCheck;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = checkDropSensor ? VMCProtocol.withDropSensor : VMCProtocol.withoutDropSensor;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Temperature reading command
class ReadTemperatureCommand extends VMCCommand {
  const ReadTemperatureCommand({required super.driverBoardNumber});
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && driverBoardNumber <= 255;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid temperature read command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdReadTemperature;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = 0x55; // Standard parameter for read operations
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Temperature control command
class TemperatureControlCommand extends VMCCommand {
  final bool enableControl;
  final bool coolingMode;
  final int targetTemperature;
  
  const TemperatureControlCommand({
    required super.driverBoardNumber,
    required this.enableControl,
    required this.coolingMode,
    required this.targetTemperature,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && 
           driverBoardNumber <= 255 && 
           targetTemperature >= -50 && 
           targetTemperature <= 100;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid temperature control command parameters');
    }
    
    // This is a composite command that sends multiple frames
    // For simplicity, returning the enable/disable control frame
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdTemperatureControl;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = enableControl ? VMCProtocol.tempControlEnabled : VMCProtocol.tempControlDisabled;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Set target temperature command
class SetTargetTemperatureCommand extends VMCCommand {
  final int temperature;
  
  const SetTargetTemperatureCommand({
    required super.driverBoardNumber,
    required this.temperature,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && 
           driverBoardNumber <= 255 && 
           temperature >= -50 && 
           temperature <= 100;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid set temperature command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdSetTargetTemperature;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = temperature & 0xFF; // Convert to unsigned byte
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Lighting control command
class LightingControlCommand extends VMCCommand {
  final bool turnOn;
  
  const LightingControlCommand({
    required super.driverBoardNumber,
    required this.turnOn,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && driverBoardNumber <= 255;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid lighting control command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdLightingControl;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = turnOn ? VMCProtocol.lightOn : VMCProtocol.lightOff;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Door status command
class DoorStatusCommand extends VMCCommand {
  const DoorStatusCommand({required super.driverBoardNumber});
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && driverBoardNumber <= 255;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid door status command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = VMCProtocol.cmdDoorStatus;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = 0x55; // Standard parameter for read operations
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Slot mode setting command
class SetSlotModeCommand extends VMCCommand {
  final int slotNumber;
  final bool isBeltMode; // true for belt, false for spiral
  
  const SetSlotModeCommand({
    required super.driverBoardNumber,
    required this.slotNumber,
    required this.isBeltMode,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && 
           driverBoardNumber <= 255 && 
           slotNumber >= 1 && 
           slotNumber <= 80;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid slot mode command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = isBeltMode ? VMCProtocol.cmdSetBeltSlot : VMCProtocol.cmdSetSpiralSlot;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = slotNumber;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Slot merge/split command
class SlotMergeCommand extends VMCCommand {
  final int slotNumber;
  final bool isDualSlot; // true for dual, false for single
  
  const SlotMergeCommand({
    required super.driverBoardNumber,
    required this.slotNumber,
    required this.isDualSlot,
  });
  
  @override
  bool validate() {
    return driverBoardNumber >= 0 && 
           driverBoardNumber <= 255 && 
           slotNumber >= 1 && 
           slotNumber <= 80;
  }
  
  @override
  Uint8List generateFrame() {
    if (!validate()) {
      throw ArgumentError('Invalid slot merge command parameters');
    }
    
    final d1 = driverBoardNumber;
    final d2 = (0xFF - d1) & 0xFF;
    final d3 = isDualSlot ? VMCProtocol.cmdSetDualSlot : VMCProtocol.cmdSetSingleSlot;
    final d4 = (0xFF - d3) & 0xFF;
    final d5 = slotNumber;
    final d6 = (0xFF - d5) & 0xFF;
    
    return Uint8List.fromList([d1, d2, d3, d4, d5, d6]);
  }
}

/// Temperature response data
class TemperatureData {
  final int currentTemperature;
  final int standbyTemperature;
  
  const TemperatureData({
    required this.currentTemperature,
    required this.standbyTemperature,
  });
  
  factory TemperatureData.fromResponse(VMCResponse response) {
    return TemperatureData(
      currentTemperature: response.errorCode, // R3 contains current temperature
      standbyTemperature: response.productFlag, // R4 contains standby temperature
    );
  }
  
  @override
  String toString() {
    return 'Temperature: ${currentTemperature}°C, Standby: ${standbyTemperature}°C';
  }
}

/// Door status data
class DoorStatusData {
  final bool isOpen;
  
  const DoorStatusData({required this.isOpen});
  
  factory DoorStatusData.fromResponse(VMCResponse response) {
    return DoorStatusData(isOpen: response.errorCode == 0x01);
  }
  
  @override
  String toString() {
    return 'Door is ${isOpen ? 'OPEN' : 'CLOSED'}';
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
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDeviceInfo &&
          runtimeType == other.runtimeType &&
          address == other.address;
  
  @override
  int get hashCode => address.hashCode;
}