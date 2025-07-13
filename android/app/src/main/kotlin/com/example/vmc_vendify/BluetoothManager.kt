package com.example.vmc_controller

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.*

class BluetoothManager : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothSocket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private var isConnected = false
    private var listenThread: Thread? = null
    
    companion object {
        private const val CHANNEL = "vmc_bluetooth"
        private const val TAG = "VMC_Bluetooth"
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        Log.d(TAG, "BluetoothManager attached to engine")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isBluetoothAvailable" -> {
                result.success(bluetoothAdapter != null)
            }
            
            "isBluetoothEnabled" -> {
                result.success(bluetoothAdapter?.isEnabled ?: false)
            }
            
            "getPairedDevices" -> {
                getPairedDevices(result)
            }
            
            "connectToDevice" -> {
                val address = call.argument<String>("address")
                if (address != null) {
                    connectToDevice(address, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device address is required", null)
                }
            }
            
            "disconnect" -> {
                disconnect(result)
            }
            
            "sendData" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    sendData(data, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Data is required", null)
                }
            }
            
            "isConnected" -> {
                result.success(isConnected)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getPairedDevices(result: Result) {
        try {
            if (bluetoothAdapter == null) {
                result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth adapter not available", null)
                return
            }
            
            val pairedDevices = bluetoothAdapter?.bondedDevices
            val deviceList = mutableListOf<Map<String, Any>>()
            
            pairedDevices?.forEach { device ->
                val deviceInfo = mapOf(
                    "name" to (device.name ?: "Unknown Device"),
                    "address" to device.address,
                    "isConnected" to false
                )
                deviceList.add(deviceInfo)
                Log.d(TAG, "Found paired device: ${device.name} - ${device.address}")
            }
            
            result.success(deviceList)
            Log.d(TAG, "Returned ${deviceList.size} paired devices")
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception getting paired devices", e)
            result.error("PERMISSION_DENIED", "Bluetooth permission denied: ${e.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting paired devices", e)
            result.error("BLUETOOTH_ERROR", "Failed to get paired devices: ${e.message}", null)
        }
    }

    private fun connectToDevice(address: String, result: Result) {
        Thread {
            try {
                Log.d(TAG, "Attempting to connect to device: $address")
                
                disconnect()
                
                if (bluetoothAdapter == null) {
                    result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth adapter not available", null)
                    return@Thread
                }
                
                val device: BluetoothDevice? = bluetoothAdapter?.getRemoteDevice(address)
                if (device == null) {
                    result.error("DEVICE_NOT_FOUND", "Device not found: $address", null)
                    return@Thread
                }
                
                Log.d(TAG, "Creating RFCOMM socket to device: ${device.name}")
                
                bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                
                bluetoothAdapter?.cancelDiscovery()
                
                bluetoothSocket?.connect()
                
                inputStream = bluetoothSocket?.inputStream
                outputStream = bluetoothSocket?.outputStream
                
                isConnected = true
                
                startListening()
                
                result.success(true)
                Log.d(TAG, "Successfully connected to device: $address")
                
            } catch (e: IOException) {
                Log.e(TAG, "Connection failed to $address", e)
                disconnect()
                result.error("CONNECTION_FAILED", "Failed to connect: ${e.message}", null)
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception during connection", e)
                disconnect()
                result.error("PERMISSION_DENIED", "Bluetooth permission denied: ${e.message}", null)
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error during connection", e)
                disconnect()
                result.error("BLUETOOTH_ERROR", "Connection error: ${e.message}", null)
            }
        }.start()
    }

    private fun startListening() {
        listenThread = Thread {
            val buffer = ByteArray(1024)
            
            Log.d(TAG, "Started listening for incoming data")
            
            while (isConnected && inputStream != null) {
                try {
                    val bytesRead = inputStream?.read(buffer) ?: 0
                    if (bytesRead > 0) {
                        val data = buffer.copyOf(bytesRead)
                        
                        channel.invokeMethod("onDataReceived", data)
                        
                        Log.d(TAG, "Received ${bytesRead} bytes: ${data.joinToString(" ") { "0x%02x".format(it) }}")
                    }
                } catch (e: IOException) {
                    Log.e(TAG, "Error reading from input stream", e)
                    if (isConnected) {
                        disconnect()
                        channel.invokeMethod("onConnectionLost", null)
                    }
                    break
                }
            }
            Log.d(TAG, "Stopped listening for incoming data")
        }
        listenThread?.start()
    }

    private fun sendData(data: ByteArray, result: Result) {
        if (!isConnected || outputStream == null) {
            result.error("NOT_CONNECTED", "Not connected to any device", null)
            return
        }
        
        Thread {
            try {
                outputStream?.write(data)
                outputStream?.flush()
                result.success(true)
                Log.d(TAG, "Sent ${data.size} bytes: ${data.joinToString(" ") { "0x%02x".format(it) }}")
            } catch (e: IOException) {
                Log.e(TAG, "Error sending data", e)
                result.error("SEND_FAILED", "Failed to send data: ${e.message}", null)
            }
        }.start()
    }

    private fun disconnect(result: Result? = null) {
        try {
            Log.d(TAG, "Disconnecting from device")
            
            isConnected = false
            
            listenThread?.interrupt()
            
            inputStream?.close()
            outputStream?.close()
            bluetoothSocket?.close()
            
            inputStream = null
            outputStream = null
            bluetoothSocket = null
            listenThread = null
            
            result?.success(true)
            Log.d(TAG, "Successfully disconnected from device")
            
        } catch (e: IOException) {
            Log.e(TAG, "Error during disconnect", e)
            result?.error("DISCONNECT_ERROR", "Error during disconnect: ${e.message}", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        disconnect()
        Log.d(TAG, "BluetoothManager detached from engine")
    }
}