import Cocoa
import FlutterMacOS
import IOBluetooth

public class FlutterClassicBluetoothPlugin: NSObject, FlutterPlugin {
    private var messenger: FlutterBinaryMessenger!
    private var connections: [Int: BluetoothConnectionWrapper] = [:]
    private var servers: [Int: BluetoothServerWrapper] = [:]
    // Shared id source so client connects and server-accepted clients never collide.
    private var nextConnectionId = 0
    private var nextServerId = 0

    private var inquiry: IOBluetoothDeviceInquiry?
    private var inquiryDelegate: DeviceInquiryDelegate?
    private var discovering = false

    private var pairer: IOBluetoothDevicePair?
    private var pairingDelegate: PairingDelegate?

    // Global event channel handlers.
    private var adapterStateHandler: SnapshotStreamHandler?
    private var bondStateHandler: SnapshotStreamHandler?
    private var discoveryStateHandler: StreamHandler?
    private var discoveryResultsHandler: StreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_classic_bluetooth/methods",
            binaryMessenger: registrar.messenger
        )
        let instance = FlutterClassicBluetoothPlugin()
        instance.messenger = registrar.messenger
        instance.registerEventChannels(registrar.messenger)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private func registerEventChannels(_ messenger: FlutterBinaryMessenger) {
        // Adapter state: emit the current power state on subscribe.
        let adapterHandler = SnapshotStreamHandler { _ in
            if let controller = IOBluetoothHostController.default() {
                return controller.powerState == kBluetoothHCIPowerStateON ? "on" : "off"
            }
            return "unsupported"
        }
        adapterStateHandler = adapterHandler
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/adapter_state",
            binaryMessenger: messenger
        ).setStreamHandler(adapterHandler)

        // Bond state: emit the current pairing state of the requested address.
        let bondHandler = SnapshotStreamHandler { args in
            if let address = (args as? [String: Any])?["address"] as? String,
               let device = IOBluetoothDevice(addressString: address) {
                return device.isPaired() ? "bonded" : "none"
            }
            return "none"
        }
        bondStateHandler = bondHandler
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/bond_state",
            binaryMessenger: messenger
        ).setStreamHandler(bondHandler)

        let discoveryState = StreamHandler()
        discoveryStateHandler = discoveryState
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/discovery_state",
            binaryMessenger: messenger
        ).setStreamHandler(discoveryState)

        let discoveryResults = StreamHandler()
        discoveryResultsHandler = discoveryResults
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/discovery_results",
            binaryMessenger: messenger
        ).setStreamHandler(discoveryResults)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        // macOS reaches Bluetooth Classic through IOBluetooth, which is gated
        // by the com.apple.security.device.bluetooth entitlement at build time
        // rather than by a runtime prompt. There is nothing to request.
        case "checkPermissions", "requestPermissions":
            result("notRequired")

        case "openAppSettings", "openLocationSettings":
            result(false)

        case "isLocationServiceRequired":
            result(false)

        case "isLocationServiceEnabled":
            result(true)

        case "isSupported":
            result(IOBluetoothHostController.default() != nil)

        case "isEnabled":
            if let controller = IOBluetoothHostController.default() {
                result(controller.powerState == kBluetoothHCIPowerStateON)
            } else {
                result(false)
            }

        case "enableBluetooth", "disableBluetooth":
            result(FlutterError(
                code: "unsupported",
                message: "Cannot programmatically \(call.method == "enableBluetooth" ? "enable" : "disable") Bluetooth on macOS",
                details: ["feature": call.method, "platform": "macOS"]
            ))

        case "getAdapterName":
            result(IOBluetoothHostController.default()?.nameAsString())

        case "getAdapterAddress":
            result(IOBluetoothHostController.default()?.addressAsString()?.replacingOccurrences(of: "-", with: ":").uppercased())

        case "startDiscovery":
            handleStartDiscovery(result: result)

        case "stopDiscovery":
            handleStopDiscovery(result: result)

        case "isDiscovering":
            result(discovering)

        case "getPairedDevices":
            handleGetPairedDevices(result: result)

        case "bondDevice":
            guard let address = args?["address"] as? String else {
                result(FlutterError(code: "invalidAddress", message: "Address is required", details: nil))
                return
            }
            handleBondDevice(address: address, result: result)

        case "unbondDevice":
            // IOBluetooth exposes no public API to remove an existing pairing.
            result(FlutterError(
                code: "unsupported",
                message: "Unpairing must be done through macOS System Settings; no public IOBluetooth API removes a pairing.",
                details: ["feature": "unbondDevice", "platform": "macOS"]
            ))

        case "connect":
            guard let address = args?["address"] as? String else {
                result(FlutterError(code: "connectionFailed", message: "Address is required", details: nil))
                return
            }
            let uuid = args?["uuid"] as? String ?? "00001101-0000-1000-8000-00805F9B34FB"
            handleConnect(address: address, uuid: uuid, result: result)

        case "disconnect":
            guard let id = args?["id"] as? Int else {
                result(FlutterError(code: "connectionFailed", message: "Connection ID is required", details: nil))
                return
            }
            handleDisconnect(id: id, result: result)

        case "write":
            guard let id = args?["id"] as? Int,
                  let data = args?["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "writeFailed", message: "Connection ID and data are required", details: nil))
                return
            }
            handleWrite(id: id, data: data, result: result)

        case "getConnectionRssi":
            guard let id = args?["id"] as? Int else {
                result(FlutterError(code: "connectionFailed", message: "Connection ID is required", details: nil))
                return
            }
            guard let conn = connections[id] else {
                result(FlutterError(code: "connectionFailed", message: "Connection not found", details: nil))
                return
            }
            // rawRSSI() returns 127 when no baseband sample is available yet;
            // report that as null rather than a bogus reading.
            let raw = conn.device.rawRSSI()
            result(raw == 127 ? nil : Int(raw))

        case "startServer":
            let uuid = args?["uuid"] as? String ?? "00001101-0000-1000-8000-00805F9B34FB"
            let serviceName = args?["serviceName"] as? String ?? "FlutterBluetooth"
            handleStartServer(uuid: uuid, serviceName: serviceName, result: result)

        case "stopServer":
            guard let id = args?["id"] as? Int else {
                result(FlutterError(code: "connectionFailed", message: "Server ID is required", details: nil))
                return
            }
            handleStopServer(id: id, result: result)

        case "setDiscoverable":
            result(FlutterError(
                code: "unsupported",
                message: "setDiscoverable not available on macOS",
                details: ["feature": "setDiscoverable", "platform": "macOS"]
            ))

        case "getPlatformCapabilities":
            handleGetPlatformCapabilities(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Discovery

    private func handleStartDiscovery(result: @escaping FlutterResult) {
        if discovering {
            result(nil)
            return
        }
        discovering = true
        discoveryStateHandler?.eventSink?(true)

        let delegate = DeviceInquiryDelegate(
            onDeviceFound: { [weak self] device in
                guard let self = self else { return }
                let map = self.deviceToMap(device)
                DispatchQueue.main.async {
                    self.discoveryResultsHandler?.eventSink?(map)
                }
            },
            onComplete: { [weak self] in
                guard let self = self else { return }
                self.discovering = false
                DispatchQueue.main.async {
                    self.discoveryStateHandler?.eventSink?(false)
                }
            })
        inquiryDelegate = delegate

        let inquiry = IOBluetoothDeviceInquiry(delegate: delegate)
        inquiry?.inquiryLength = 8
        inquiry?.updateNewDeviceNames = true
        self.inquiry = inquiry  // retain so it isn't deallocated mid-inquiry
        inquiry?.start()
        result(nil)
    }

    private func handleStopDiscovery(result: @escaping FlutterResult) {
        inquiry?.stop()
        discovering = false
        result(nil)
    }

    // MARK: - Paired Devices

    private func handleGetPairedDevices(result: @escaping FlutterResult) {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let devices = paired.map { deviceToMap($0) }
        result(devices)
    }

    // MARK: - Pairing

    private func handleBondDevice(address: String, result: @escaping FlutterResult) {
        guard let device = IOBluetoothDevice(addressString: address),
              let pair = IOBluetoothDevicePair(device: device) else {
            result(false)
            return
        }
        // Pairing is asynchronous; complete the Dart result from the delegate.
        // It may surface a system pairing prompt for PIN/passkey devices.
        let delegate = PairingDelegate { [weak self] success in
            result(success)
            self?.pairer = nil
            self?.pairingDelegate = nil
        }
        pair.delegate = delegate
        pairingDelegate = delegate
        pairer = pair
        if pair.start() != kIOReturnSuccess {
            result(false)
            pairer = nil
            pairingDelegate = nil
        }
    }

    // MARK: - Connection

    private func handleConnect(address: String, uuid: String, result: @escaping FlutterResult) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            result(FlutterError(code: "connectionFailed", message: "Invalid device address", details: ["address": address]))
            return
        }

        // Resolve the RFCOMM channel from the service UUID, falling back to 1.
        var channelID: BluetoothRFCOMMChannelID = 1
        let sdpUUID = uuidFromString(uuid)
        if let record = device.getServiceRecord(for: sdpUUID) {
            var resolved: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&resolved) == kIOReturnSuccess, resolved != 0 {
                channelID = resolved
            }
        }

        let connId = nextConnectionId
        nextConnectionId += 1

        let wrapper = BluetoothConnectionWrapper(id: connId, device: device, messenger: messenger)
        connections[connId] = wrapper

        // Async open so the platform thread is never blocked.
        wrapper.open(channelID: channelID) { [weak self] success in
            if success {
                result(["id": connId, "address": address])
            } else {
                self?.connections.removeValue(forKey: connId)
                result(FlutterError(code: "connectionFailed", message: "Failed to connect", details: ["address": address]))
            }
        }
    }

    private func handleDisconnect(id: Int, result: @escaping FlutterResult) {
        if let conn = connections.removeValue(forKey: id) {
            conn.close()
        }
        result(nil)
    }

    private func handleWrite(id: Int, data: FlutterStandardTypedData, result: @escaping FlutterResult) {
        guard let conn = connections[id] else {
            result(FlutterError(code: "connectionFailed", message: "Connection not found", details: nil))
            return
        }
        conn.write(data: data.data) { success in
            if success {
                result(nil)
            } else {
                result(FlutterError(code: "writeFailed", message: "Failed to write data", details: nil))
            }
        }
    }

    // MARK: - Server

    private func handleStartServer(uuid: String, serviceName: String, result: @escaping FlutterResult) {
        let serverId = nextServerId
        nextServerId += 1

        let server = BluetoothServerWrapper(
            id: serverId,
            uuid: uuid,
            serviceName: serviceName,
            messenger: messenger,
            allocateConnectionId: { [weak self] in
                guard let self = self else { return -1 }
                let id = self.nextConnectionId
                self.nextConnectionId += 1
                return id
            },
            onConnection: { [weak self] connId, wrapper in
                self?.connections[connId] = wrapper
            })

        if server.start() {
            servers[serverId] = server
            result(["id": serverId])
        } else {
            result(FlutterError(code: "connectionFailed", message: "Failed to start server", details: nil))
        }
    }

    private func handleStopServer(id: Int, result: @escaping FlutterResult) {
        if let server = servers.removeValue(forKey: id) {
            server.stop()
        }
        result(nil)
    }

    // MARK: - Capabilities

    private func handleGetPlatformCapabilities(result: @escaping FlutterResult) {
        result([
            "canEnableBluetooth": false,
            "canDisableBluetooth": false,
            "canDiscoverDevices": true,
            "canGetPairedDevices": true,
            // bondDevice uses IOBluetoothDevicePair (may show a system prompt);
            // there is no public API to remove an existing pairing.
            "canBondDevices": true,
            "canUnbondDevices": false,
            "canCreateServer": true,
            "canSetDiscoverable": false,
            "supportsMultipleConnections": true,
            "supportsSecureConnection": true,
            "supportsInsecureConnection": false,
            "canReadConnectionRssi": true,
            "requiresMfiCertification": false,
            "platformNote": "macOS: Bluetooth Classic via IOBluetooth. Discovery, connect, server, paired-device listing, pairing (IOBluetoothDevicePair) and connection RSSI are supported. Unpairing must be done through System Settings."
        ])
    }

    // MARK: - Helpers

    private func deviceToMap(_ device: IOBluetoothDevice) -> [String: Any?] {
        let uuids = (device.services as? [IOBluetoothSDPServiceRecord])?.compactMap {
            $0.getServiceName()
        } ?? []
        let raw = device.rawRSSI()
        let rssi: Int? = raw != 127 ? Int(raw) : nil  // 127 == not available
        return [
            "address": device.addressString?.replacingOccurrences(of: "-", with: ":").uppercased(),
            "name": device.name,
            "alias": nil,
            "rssi": rssi,
            "type": "classic",
            "bondState": device.isPaired() ? "bonded" : "none",
            "uuids": uuids
        ]
    }

    private func uuidFromString(_ str: String) -> IOBluetoothSDPUUID {
        let cleaned = str.replacingOccurrences(of: "-", with: "")
        var bytes = [UInt8]()
        var index = cleaned.startIndex
        for _ in 0..<(cleaned.count / 2) {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            if let byte = UInt8(cleaned[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return IOBluetoothSDPUUID(bytes: &bytes, length: bytes.count)
    }
}

// MARK: - Device Inquiry Delegate

private class DeviceInquiryDelegate: NSObject, IOBluetoothDeviceInquiryDelegate {
    let onDeviceFound: (IOBluetoothDevice) -> Void
    let onComplete: () -> Void

    init(onDeviceFound: @escaping (IOBluetoothDevice) -> Void, onComplete: @escaping () -> Void) {
        self.onDeviceFound = onDeviceFound
        self.onComplete = onComplete
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let device = device { onDeviceFound(device) }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        onComplete()
    }
}

// MARK: - Pairing Delegate

private class PairingDelegate: NSObject, IOBluetoothDevicePairDelegate {
    let onFinished: (Bool) -> Void

    init(onFinished: @escaping (Bool) -> Void) {
        self.onFinished = onFinished
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        onFinished(error == kIOReturnSuccess)
    }
}

// MARK: - Bluetooth Connection Wrapper

class BluetoothConnectionWrapper: NSObject, IOBluetoothRFCOMMChannelDelegate {
    let id: Int
    let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var messenger: FlutterBinaryMessenger
    private var dataStreamHandler: StreamHandler?
    private var stateStreamHandler: StreamHandler?
    private var openCompletion: ((Bool) -> Void)?

    init(id: Int, device: IOBluetoothDevice, messenger: FlutterBinaryMessenger) {
        self.id = id
        self.device = device
        self.messenger = messenger
        super.init()
        setupEventChannels()
    }

    /// Wraps an already-open incoming RFCOMM channel (server-accepted client).
    init(id: Int, incomingChannel: IOBluetoothRFCOMMChannel, messenger: FlutterBinaryMessenger) {
        self.id = id
        self.device = incomingChannel.getDevice()
        self.messenger = messenger
        super.init()
        setupEventChannels()
        self.channel = incomingChannel
        incomingChannel.setDelegate(self)
        DispatchQueue.main.async { [weak self] in
            self?.stateStreamHandler?.eventSink?("connected")
        }
    }

    private func setupEventChannels() {
        let dataHandler = StreamHandler()
        dataStreamHandler = dataHandler
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/connection/\(id)",
            binaryMessenger: messenger
        ).setStreamHandler(dataHandler)

        let stateHandler = StreamHandler()
        stateStreamHandler = stateHandler
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/connection_state/\(id)",
            binaryMessenger: messenger
        ).setStreamHandler(stateHandler)
    }

    func open(channelID: BluetoothRFCOMMChannelID, completion: @escaping (Bool) -> Void) {
        openCompletion = completion
        var rfcommChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&rfcommChannel, withChannelID: channelID, delegate: self)
        if result != kIOReturnSuccess {
            openCompletion = nil
            completion(false)
        } else {
            channel = rfcommChannel
        }
    }

    func write(data: Data, completion: @escaping (Bool) -> Void) {
        guard let channel = channel else { completion(false); return }
        var mutableData = [UInt8](data)
        // Async write so the platform thread is not blocked. The delegate's
        // rfcommChannelWriteComplete reports the final status.
        let result = channel.writeAsync(&mutableData, length: UInt16(mutableData.count), refcon: nil)
        completion(result == kIOReturnSuccess)
    }

    func close() {
        channel?.close()
        channel = nil
        DispatchQueue.main.async { [weak self] in
            self?.stateStreamHandler?.eventSink?("disconnected")
        }
    }

    // IOBluetoothRFCOMMChannelDelegate: these fire on IOBluetooth's run loop;
    // Flutter event sinks must be invoked on the main thread.

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            channel = rfcommChannel
            DispatchQueue.main.async { [weak self] in
                self?.stateStreamHandler?.eventSink?("connected")
            }
            openCompletion?(true)
        } else {
            openCompletion?(false)
        }
        openCompletion = nil
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        DispatchQueue.main.async { [weak self] in
            self?.dataStreamHandler?.eventSink?(FlutterStandardTypedData(bytes: data))
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        DispatchQueue.main.async { [weak self] in
            self?.stateStreamHandler?.eventSink?("disconnected")
        }
    }
}

// MARK: - Bluetooth Server Wrapper

class BluetoothServerWrapper: NSObject {
    let id: Int
    let uuid: String
    let serviceName: String
    private var messenger: FlutterBinaryMessenger
    private let allocateConnectionId: () -> Int
    private let onConnection: (Int, BluetoothConnectionWrapper) -> Void
    private var sdpRecord: IOBluetoothSDPServiceRecord?
    private var openNotification: IOBluetoothUserNotification?
    private var serverStreamHandler: StreamHandler?

    init(id: Int,
         uuid: String,
         serviceName: String,
         messenger: FlutterBinaryMessenger,
         allocateConnectionId: @escaping () -> Int,
         onConnection: @escaping (Int, BluetoothConnectionWrapper) -> Void) {
        self.id = id
        self.uuid = uuid
        self.serviceName = serviceName
        self.messenger = messenger
        self.allocateConnectionId = allocateConnectionId
        self.onConnection = onConnection
        super.init()

        let handler = StreamHandler()
        serverStreamHandler = handler
        FlutterEventChannel(
            name: "flutter_classic_bluetooth/server/\(id)",
            binaryMessenger: messenger
        ).setStreamHandler(handler)
    }

    func start() -> Bool {
        // Publish an RFCOMM (SPP) service record; macOS assigns a channel.
        let serviceDict: [String: Any] = [
            "0001 - ServiceClassIDList": [uuidDataFromString(uuid)],
            // L2CAP (0x0100) over which RFCOMM (0x0003) runs; macOS assigns the
            // RFCOMM channel number when the record is published.
            "0004 - ProtocolDescriptorList": [
                [IOBluetoothSDPUUID(uuid16: 0x0100)],
                [IOBluetoothSDPUUID(uuid16: 0x0003)]
            ],
            "0100 - ServiceName*": serviceName
        ]
        guard let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: serviceDict) else {
            return false
        }
        sdpRecord = record

        var channelID: BluetoothRFCOMMChannelID = 0
        record.getRFCOMMChannelID(&channelID)

        // Listen for incoming client channels on the assigned RFCOMM channel.
        openNotification = IOBluetoothRFCOMMChannel.register(
            forChannelOpenNotifications: self,
            selector: #selector(rfcommChannelOpened(_:channel:)),
            withChannelID: channelID,
            direction: kIOBluetoothUserNotificationChannelDirectionIncoming)

        return true
    }

    @objc func rfcommChannelOpened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothRFCOMMChannel) {
        let connId = allocateConnectionId()
        if connId < 0 { return }
        let address = channel.getDevice()?.addressString?
            .replacingOccurrences(of: "-", with: ":").uppercased() ?? ""
        let wrapper = BluetoothConnectionWrapper(id: connId, incomingChannel: channel, messenger: messenger)
        DispatchQueue.main.async { [weak self] in
            self?.onConnection(connId, wrapper)
            self?.serverStreamHandler?.eventSink?(["id": connId, "address": address])
        }
    }

    func stop() {
        openNotification?.unregister()
        openNotification = nil
        sdpRecord?.remove()
        sdpRecord = nil
    }

    private func uuidDataFromString(_ str: String) -> IOBluetoothSDPUUID {
        let cleaned = str.replacingOccurrences(of: "-", with: "")
        var bytes = [UInt8]()
        var index = cleaned.startIndex
        for _ in 0..<(cleaned.count / 2) {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            if let byte = UInt8(cleaned[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return IOBluetoothSDPUUID(bytes: &bytes, length: bytes.count)
    }
}

// MARK: - Stream Handlers

private class StreamHandler: NSObject, FlutterStreamHandler {
    var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

/// A stream handler that emits a one-shot snapshot value when a listener
/// subscribes (used for adapter and bond state on macOS).
private class SnapshotStreamHandler: NSObject, FlutterStreamHandler {
    var eventSink: FlutterEventSink?
    private let snapshot: ((Any?) -> Any?)?

    init(snapshot: ((Any?) -> Any?)? = nil) {
        self.snapshot = snapshot
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        if let snapshot = snapshot, let value = snapshot(arguments) {
            events(value)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
