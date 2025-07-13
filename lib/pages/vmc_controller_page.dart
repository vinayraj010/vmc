import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vmc_vendify/model/vmc_protocol_model.dart';
import 'package:vmc_vendify/services/vmc_bluetooth_services.dart';


class VMCControllerPage extends StatefulWidget {
  const VMCControllerPage({super.key});

  @override
  State<VMCControllerPage> createState() => _VMCControllerPageState();
}

class _VMCControllerPageState extends State<VMCControllerPage> {
  final VMCBluetoothService _bluetoothService = VMCBluetoothService();
  List<BluetoothDeviceInfo> _devices = [];
  BluetoothDeviceInfo? _connectedDevice;
  bool _isConnecting = false;
  bool _isLoading = false;
  bool _bluetoothAvailable = false;
  bool _bluetoothEnabled = false;
  
  final _driverBoardController = TextEditingController(text: '0');
  final _slotNumberController = TextEditingController(text: '1');
  final _temperatureController = TextEditingController(text: '5');
  
  String _lastResponse = '';
  String _connectionStatus = 'Disconnected';
  TemperatureData? _temperatureData;
  DoorStatusData? _doorStatus;
  List<String> _logMessages = [];
  
  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
    _setupResponseListener();
    _setupConnectionLostListener();
  }
  
  @override
  void dispose() {
    _bluetoothService.dispose();
    _driverBoardController.dispose();
    _slotNumberController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }
  
  void _setupResponseListener() {
    _bluetoothService.responseStream.listen((response) {
      setState(() {
        _lastResponse = response.toString();
        _addLogMessage('Response: ${response.toString()}');
      });
    });
  }
  
  void _setupConnectionLostListener() {
    _bluetoothService.connectionLostStream.listen((_) {
      setState(() {
        _connectedDevice = null;
        _connectionStatus = 'Connection lost';
        _addLogMessage('Connection lost unexpectedly');
      });
    });
  }
  
  void _addLogMessage(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _logMessages.insert(0, '[$timestamp] $message');
      if (_logMessages.length > 50) {
        _logMessages.removeLast();
      }
    });
  }
  
  Future<void> _initializeBluetooth() async {
    setState(() => _isLoading = true);
    
    try {
      _bluetoothAvailable = await _bluetoothService.isBluetoothAvailable();
      
      if (!_bluetoothAvailable) {
        _showError('Bluetooth is not available on this device');
        setState(() => _isLoading = false);
        return;
      }
      
      await _requestPermissions();
      
      _bluetoothEnabled = await _bluetoothService.isBluetoothEnabled();
      
      if (!_bluetoothEnabled) {
        _showError('Please enable Bluetooth and restart the app');
        setState(() => _isLoading = false);
        return;
      }
      
      await _loadPairedDevices();
      
    } catch (e) {
      _showError('Error initializing Bluetooth: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationWhenInUse,
    ];
    
    final statuses = await permissions.request();
    
    final denied = statuses.entries
        .where((entry) => entry.value.isDenied || entry.value.isPermanentlyDenied)
        .map((entry) => entry.key.toString())
        .toList();
    
    if (denied.isNotEmpty) {
      _showError('Bluetooth permissions are required for this app to work');
    }
  }
  
  Future<void> _loadPairedDevices() async {
    try {
      final devices = await _bluetoothService.getPairedDevices();
      setState(() {
        _devices = devices;
        _addLogMessage('Found ${devices.length} paired devices');
      });
    } catch (e) {
      _showError('Error loading devices: $e');
    }
  }
  
  Future<void> _connectToDevice(BluetoothDeviceInfo device) async {
    setState(() => _isConnecting = true);
    
    try {
      final success = await _bluetoothService.connect(device);
      
      setState(() {
        _isConnecting = false;
        if (success) {
          _connectedDevice = device;
          _connectionStatus = 'Connected to ${device.name}';
          _addLogMessage('Connected to ${device.name} (${device.address})');
        } else {
          _connectionStatus = 'Failed to connect';
          _addLogMessage('Failed to connect to ${device.name}');
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Connection error: $e';
      });
      _addLogMessage('Connection error: $e');
    }
  }
  
  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();
    setState(() {
      _connectedDevice = null;
      _connectionStatus = 'Disconnected';
      _addLogMessage('Disconnected from device');
    });
  }
  
  int get _driverBoardNumber => int.tryParse(_driverBoardController.text) ?? 0;
  int get _slotNumber => int.tryParse(_slotNumberController.text) ?? 1;
  int get _temperature => int.tryParse(_temperatureController.text) ?? 5;
  
  Future<void> _dispenseProduct() async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Dispensing product from slot $_slotNumber...');
    
    try {
      final response = await _bluetoothService.dispenseProduct(
        driverBoardNumber: _driverBoardNumber,
        slotNumber: _slotNumber,
        useDropSensor: true,
      );
      
      setState(() {
        if (response.isSuccess) {
          _lastResponse = 'Dispensed: ${response.hasProductDelivery ? "Product delivered" : "No product detected"}';
          _addLogMessage('Dispense successful: ${response.hasProductDelivery ? "Product delivered" : "No product detected"}');
        } else {
          _lastResponse = 'Dispense failed: ${response.errorDescription}';
          _addLogMessage('Dispense failed: ${response.errorDescription}');
        }
      });
    } catch (e) {
      _showError('Error dispensing: $e');
      _addLogMessage('Dispense error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _performSelfCheck() async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Performing self-check...');
    
    try {
      final response = await _bluetoothService.performSelfCheck(
        driverBoardNumber: _driverBoardNumber,
        checkDropSensor: true,
      );
      
      setState(() {
        _lastResponse = response.isSuccess 
            ? 'Self-check passed: All systems normal'
            : 'Self-check failed: ${response.errorDescription}';
      });
      
      _addLogMessage('Self-check result: ${response.isSuccess ? "PASSED" : "FAILED - ${response.errorDescription}"}');
    } catch (e) {
      _showError('Error performing self-check: $e');
      _addLogMessage('Self-check error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _readTemperature() async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Reading temperature...');
    
    try {
      final tempData = await _bluetoothService.readTemperature(
        driverBoardNumber: _driverBoardNumber,
      );
      
      setState(() {
        _temperatureData = tempData;
        _lastResponse = tempData.toString();
      });
      
      _addLogMessage('Temperature read: ${tempData.toString()}');
    } catch (e) {
      _showError('Error reading temperature: $e');
      _addLogMessage('Temperature read error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _setTemperature() async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Setting temperature to $_temperature°C...');
    
    try {
      final response = await _bluetoothService.setTemperatureControl(
        driverBoardNumber: _driverBoardNumber,
        enableControl: true,
        coolingMode: true,
        targetTemperature: _temperature,
      );
      
      setState(() {
        _lastResponse = response.isSuccess 
            ? 'Temperature set to $_temperature°C'
            : 'Failed to set temperature: ${response.errorDescription}';
      });
      
      _addLogMessage('Temperature setting: ${response.isSuccess ? "SUCCESS" : "FAILED - ${response.errorDescription}"}');
    } catch (e) {
      _showError('Error setting temperature: $e');
      _addLogMessage('Temperature setting error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _controlLighting(bool turnOn) async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('${turnOn ? "Turning on" : "Turning off"} lighting...');
    
    try {
      final response = await _bluetoothService.controlLighting(
        driverBoardNumber: _driverBoardNumber,
        turnOn: turnOn,
      );
      
      setState(() {
        _lastResponse = response.isSuccess 
            ? 'Lighting ${turnOn ? "turned on" : "turned off"}'
            : 'Failed to control lighting: ${response.errorDescription}';
      });
      
      _addLogMessage('Lighting control: ${response.isSuccess ? "SUCCESS" : "FAILED - ${response.errorDescription}"}');
    } catch (e) {
      _showError('Error controlling lighting: $e');
      _addLogMessage('Lighting control error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _readDoorStatus() async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Reading door status...');
    
    try {
      final doorData = await _bluetoothService.readDoorStatus(
        driverBoardNumber: _driverBoardNumber,
      );
      
      setState(() {
        _doorStatus = doorData;
        _lastResponse = doorData.toString();
      });
      
      _addLogMessage('Door status: ${doorData.toString()}');
    } catch (e) {
      _showError('Error reading door status: $e');
      _addLogMessage('Door status error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _setSlotMode(bool isBeltMode) async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Setting slot $_slotNumber to ${isBeltMode ? "belt" : "spiral"} mode...');
    
    try {
      final response = await _bluetoothService.setSlotMode(
        driverBoardNumber: _driverBoardNumber,
        slotNumber: _slotNumber,
        isBeltMode: isBeltMode,
      );
      
      setState(() {
        _lastResponse = response.isSuccess 
            ? 'Slot $_slotNumber set to ${isBeltMode ? "belt" : "spiral"} mode'
            : 'Failed to set slot mode: ${response.errorDescription}';
      });
      
      _addLogMessage('Slot mode setting: ${response.isSuccess ? "SUCCESS" : "FAILED - ${response.errorDescription}"}');
    } catch (e) {
      _showError('Error setting slot mode: $e');
      _addLogMessage('Slot mode error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _setSlotMerge(bool isDualSlot) async {
    if (!_bluetoothService.isConnected) {
      _showError('Not connected to any device');
      return;
    }
    
    setState(() => _isLoading = true);
    _addLogMessage('Setting slot $_slotNumber to ${isDualSlot ? "dual" : "single"} slot...');
    
    try {
      final response = await _bluetoothService.setSlotMerge(
        driverBoardNumber: _driverBoardNumber,
        slotNumber: _slotNumber,
        isDualSlot: isDualSlot,
      );
      
      setState(() {
        _lastResponse = response.isSuccess 
            ? 'Slot $_slotNumber set to ${isDualSlot ? "dual" : "single"} slot'
            : 'Failed to set slot merge: ${response.errorDescription}';
      });
      
      _addLogMessage('Slot merge setting: ${response.isSuccess ? "SUCCESS" : "FAILED - ${response.errorDescription}"}');
    } catch (e) {
      _showError('Error setting slot merge: $e');
      _addLogMessage('Slot merge error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  void _clearLogs() {
    setState(() {
      _logMessages.clear();
      _addLogMessage('Logs cleared');
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VMC Controller'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          if (_bluetoothService.isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPairedDevices,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBluetoothStatusCard(),
            const SizedBox(height: 16),
            _buildConnectionSection(),
            const SizedBox(height: 16),
            if (_bluetoothService.isConnected) ...[
              _buildSettingsSection(),
              const SizedBox(height: 16),
              _buildControlSection(),
              const SizedBox(height: 16),
              _buildStatusSection(),
              const SizedBox(height: 16),
              _buildLogSection(),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildBluetoothStatusCard() {
    return Card(
      color: _bluetoothEnabled ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              _bluetoothEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
              color: _bluetoothEnabled ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bluetooth Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _bluetoothAvailable 
                        ? (_bluetoothEnabled ? 'Available and Enabled' : 'Available but Disabled')
                        : 'Not Available',
                    style: TextStyle(
                      color: _bluetoothEnabled ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConnectionSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _bluetoothService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: _bluetoothService.isConnected ? Colors.green : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Status',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _connectionStatus,
                        style: TextStyle(
                          color: _bluetoothService.isConnected ? Colors.green : Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!_bluetoothService.isConnected) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Available HC-06 Devices:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'No paired devices found. Please pair your HC-06 device first.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...(_devices.map((device) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.blue.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth, color: Colors.blue),
                    title: Text(device.name),
                    subtitle: Text(device.address),
                    trailing: _isConnecting 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _isConnecting ? null : () => _connectToDevice(device),
                  ),
                ))),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingsSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VMC Settings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _driverBoardController,
                    decoration: const InputDecoration(
                      labelText: 'Driver Board #',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.memory),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _slotNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Slot Number (1-80)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _temperatureController,
                    decoration: const InputDecoration(
                      labelText: 'Temperature (°C)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.thermostat),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VMC Controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Required Commands',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _dispenseProduct,
                          icon: const Icon(Icons.shopping_bag),
                          label: const Text('Dispense'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _performSelfCheck,
                          icon: const Icon(Icons.health_and_safety),
                          label: const Text('Self Check'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonus Features',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _readTemperature,
                          icon: const Icon(Icons.thermostat),
                          label: const Text('Read Temp'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _setTemperature,
                          icon: const Icon(Icons.tune),
                          label: const Text('Set Temp'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _controlLighting(true),
                          icon: const Icon(Icons.lightbulb),
                          label: const Text('Light ON'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _controlLighting(false),
                          icon: const Icon(Icons.lightbulb_outline),
                          label: const Text('Light OFF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _readDoorStatus,
                          icon: const Icon(Icons.door_front_door),
                          label: const Text('Door'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => _setSlotMode(true),
                          child: const Text('Set Belt'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => _setSlotMode(false),
                          child: const Text('Set Spiral'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => _setSlotMerge(false),
                          child: const Text('Single Slot'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => _setSlotMerge(true),
                          child: const Text('Dual Slot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'System Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Last Response:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastResponse.isEmpty ? 'No response yet' : _lastResponse,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                if (_temperatureData != null)
                  Expanded(
                    child: _buildStatusCard(
                      'Temperature',
                      '${_temperatureData!.currentTemperature}°C',
                      Icons.thermostat,
                      Colors.orange,
                    ),
                  ),
                if (_temperatureData != null && _doorStatus != null)
                  const SizedBox(width: 16),
                if (_doorStatus != null)
                  Expanded(
                    child: _buildStatusCard(
                      'Door Status',
                      _doorStatus!.isOpen ? 'OPEN' : 'CLOSED',
                      Icons.door_front_door,
                      _doorStatus!.isOpen ? Colors.red : Colors.green,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLogSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Activity Log',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${_logMessages.length} messages',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _clearLogs,
                      icon: const Icon(Icons.clear_all, size: 20),
                      tooltip: 'Clear logs',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: _logMessages.isEmpty
                  ? const Center(
                      child: Text(
                        'No activity logged yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            _logMessages[index],
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}