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
    
    companion object {
        private const val CHANNEL = "vmc_bluetooth"
        private const val TAG = "VMC_Bluetooth"
        // Standard RFCOMM UUID for SPP (Serial Port Profile)
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
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
            val pairedDevices = bluetoothAdapter?.bondedDevices
            val deviceList = mutableListOf<Map<String, Any>>()
            
            pairedDevices?.forEach { device ->
                deviceList.add(
                    mapOf(
                        "name" to (device.name ?: "Unknown"),
                        "address" to device.address,
                        "isConnected" to false
                    )
                )
            }
            
            result.success(deviceList)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting paired devices", e)
            result.error("BLUETOOTH_ERROR", "Failed to get paired devices: ${e.message}", null)
        }
    }

    private fun connectToDevice(address: String, result: Result) {
        Thread {
            try {
                // Disconnect any existing connection
                disconnect()
                
                val device: BluetoothDevice? = bluetoothAdapter?.getRemoteDevice(address)
                if (device == null) {
                    result.error("DEVICE_NOT_FOUND", "Device not found", null)
                    return@Thread
                }
                
                // Create RFCOMM socket
                bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                
                // Cancel discovery to improve connection performance
                bluetoothAdapter?.cancelDiscovery()
                
                // Connect to the device
                bluetoothSocket?.connect()
                
                // Get input and output streams
                inputStream = bluetoothSocket?.inputStream
                outputStream = bluetoothSocket?.outputStream
                
                isConnected = true
                
                // Start listening for incoming data
                startListening()
                
                result.success(true)
                Log.d(TAG, "Connected to device: $address")
                
            } catch (e: IOException) {
                Log.e(TAG, "Connection failed", e)
                disconnect()
                result.error("CONNECTION_FAILED", "Failed to connect: ${e.message}", null)
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error during connection", e)
                disconnect()
                result.error("BLUETOOTH_ERROR", "Connection error: ${e.message}", null)
            }
        }.start()
    }

    private fun startListening() {
        Thread {
            val buffer = ByteArray(1024)
            
            while (isConnected && inputStream != null) {
                try {
                    val bytesRead = inputStream?.read(buffer) ?: 0
                    if (bytesRead > 0) {
                        val data = buffer.copyOf(bytesRead)
                        
                        // Send data back to Flutter
                        channel.invokeMethod("onDataReceived", data)
                        
                        Log.d(TAG, "Received ${bytesRead} bytes")
                    }
                } catch (e: IOException) {
                    Log.e(TAG, "Error reading from input stream", e)
                    if (isConnected) {
                        // Connection lost
                        disconnect()
                        channel.invokeMethod("onConnectionLost", null)
                    }
                    break
                }
            }
        }.start()
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
                Log.d(TAG, "Sent ${data.size} bytes")
            } catch (e: IOException) {
                Log.e(TAG, "Error sending data", e)
                result.error("SEND_FAILED", "Failed to send data: ${e.message}", null)
            }
        }.start()
    }

    private fun disconnect(result: Result? = null) {
        try {
            isConnected = false
            
            inputStream?.close()
            outputStream?.close()
            bluetoothSocket?.close()
            
            inputStream = null
            outputStream = null
            bluetoothSocket = null
            
            result?.success(true)
            Log.d(TAG, "Disconnected from device")
            
        } catch (e: IOException) {
            Log.e(TAG, "Error during disconnect", e)
            result?.error("DISCONNECT_ERROR", "Error during disconnect: ${e.message}", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        disconnect()
    }
}