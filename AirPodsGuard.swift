import Foundation
import OSLog
import Darwin // For signal handling

enum LogFetchError: Error {
    case logStoreUnavailable
    case entriesFetchFailed
}

// Global variables
var AirPods: [String: [String: [String: Any]]] = [:]
var currentDate = Date()
var fetchInterval = 30.0
var warningThreshold = 120.0
var callbackFormat: String = "echo 'AirPod %{name} is not charging on part %{part}'"

func parseLogString(from input: String) -> [String: Any] {
    let lines = input
        .trimmingCharacters(in: CharacterSet(charactersIn: "{}")) // Remove braces
        .components(separatedBy: .newlines) // Split into lines

    var data: [String: Any] = [:]
    
    for line in lines {
        let trimmedLine = line
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        guard !trimmedLine.isEmpty else { continue } // Skip empty lines

        // print("trimmedLine: \(trimmedLine)")
        
        // Split by `=`
        let components = trimmedLine.components(separatedBy: " = ")
        guard components.count == 2 else { continue } // Skip invalid lines
        
        let key = components[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let value = components[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        // print("key: \(key), value: \(value)")
        
        // Attempt to parse value as a number or keep it as a string
        if let intValue = Int(value) {
            data[key] = intValue
        } else if let doubleValue = Double(value) {
            data[key] = doubleValue
        } else if let boolValue = Bool(value) {
            data[key] = boolValue
        } else {
            data[key] = value
        }
    }

    return data
}

func oneAirPodIsNotCharging(name: String, part: String) {
    let command = NSString(string: callbackFormat)
        .replacingOccurrences(of: "%{name}", with: name.replacingOccurrences(of: "\\U2019", with: "\u{2019}"))
        .replacingOccurrences(of: "%{part}", with: part)
    
    print("Executing command: \(command)")
    
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", command]
    process.launch()
    process.waitUntilExit()
}

func processAirPods(from input: [String: Any]) -> Bool {
    // print("AirPods: \(input)")
    guard let name = input["Name"] as? String else { return false }
    guard let accessoryCategory = input["Accessory Category"] as? String else { return false }
    guard accessoryCategory == "Headset" || accessoryCategory == "Headphone" else { return false }
    guard let transportType = input["Transport Type"] as? String else { return false }
    guard transportType.contains("Bluetooth") else { return false }
    guard let type = input["Type"] as? String else { return false }
    guard type == "Accessory Source" else { return false }
    // guard let accessoryIdentifier = input["Accessory Identifier"] as? String else { return false }
    guard let partIdentifier = input["Part Identifier"] as? String else { return false }
    let otherPart = partIdentifier == "Left" ? "Right" : "Left"
    guard partIdentifier == "Left" || partIdentifier == "Right" else { return false }
    // determine isCharging if Is Charging = 1 OR Power Source State = AC Power
    guard var isChargingRaw = input["Is Charging"] as? Int else { return false }
    guard let powerSourceState = input["Power Source State"] as? String else { return false }
    if powerSourceState == "AC Power" {
        isChargingRaw = 1
    }
    let isCharging = isChargingRaw == 1 ? true : false

    // print("AirPods: \(input)")

    // Check if accessoryIdentifier exists in the AirPods database
    if AirPods[name] == nil {
        AirPods[name] = [:]
        print("[\(currentDate)] New AirPods Found")
        print("\tName: \(name)")
    }
    // check if AirPods.accessoryIdentifier.partIdentifier exists in the AirPods database
    if AirPods[name]?[partIdentifier] == nil {
        AirPods[name]?[partIdentifier] = [:]
        // add input to AirPods.accessoryIdentifier.partIdentifier.lastUpdateData
        AirPods[name]?[partIdentifier]?["lastUpdate"] = input
        AirPods[name]?[partIdentifier]?["lastUpdateCharging"] = isCharging
        AirPods[name]?[partIdentifier]?["lastUpdateDate"] = currentDate
        AirPods[name]?[partIdentifier]?["lastLearnedDate"] = currentDate
        print("[\(currentDate)] New AirPod Found")
        print("\tName: \(name)")
        print("\tPart Identifier: \(partIdentifier)")
        print("\tIs Charging: \(isCharging)")
        return true
    }
    guard let lastUpdateCharging = AirPods[name]?[partIdentifier]?["lastUpdateCharging"] as? Bool else { return true }
    // guard let lastUpdate = AirPods[name]?[partIdentifier]?["lastUpdate"] as? [String: Any] else { return true }
    guard let lastUpdateDate = AirPods[name]?[partIdentifier]?["lastUpdateDate"] as? Date else { return true }
    guard let lastLearnedDate = AirPods[name]?[partIdentifier]?["lastLearnedDate"] as? Date else { return true }
    guard let otherPartData = AirPods[name]?[otherPart] as? [String: Any] else { return true }
    // guard let otherPartUpdate = otherPartData["lastUpdate"] as? [String: Any] else { return true }
    // guard let otherPartUpdateDate = otherPartData["lastUpdateDate"] as? Date else { return true }
    guard let otherPartUpdateCharging = otherPartData["lastUpdateCharging"] as? Bool else { return true }
    // guard let otherPartLastLearnedDate = otherPartData["lastLearnedDate"] as? Date else { return true }
    // Now, we have BOTH parts data available
    
    var doUpdate = false

    if currentDate.timeIntervalSince(lastUpdateDate) > warningThreshold {
        doUpdate = true
    }

    if isCharging != lastUpdateCharging {
        doUpdate = true
    }

    // if lastUpdateDate is older than 5 minutes
    if !isCharging && otherPartUpdateCharging {
        print("[\(currentDate)] One AirPod is not charging: \(name) - \(partIdentifier)")
        if currentDate.timeIntervalSince(lastUpdateDate) > warningThreshold && currentDate.timeIntervalSince(lastLearnedDate) < warningThreshold {
            print("[\(currentDate)] Dispatching callback")
            oneAirPodIsNotCharging(name: name, part: partIdentifier)
        }
    }

    // currentDate = Date()
    if doUpdate {
        // Update the lastUpdateData
        AirPods[name]?[partIdentifier]?["lastUpdate"] = input
        AirPods[name]?[partIdentifier]?["lastUpdateCharging"] = isCharging
        AirPods[name]?[partIdentifier]?["lastUpdateDate"] = currentDate
        print("[\(currentDate)] Updated AirPod Data")
        print("\tName: \(name)")
        print("\tPart Identifier: \(partIdentifier)")
        print("\tIs Charging: \(isCharging)")
        print("\tPrevious Is Charging: \(lastUpdateCharging)")
        print("\tLast Update Date: \(lastUpdateDate)")
    }
    AirPods[name]?[partIdentifier]?["lastLearnedDate"] = currentDate

    return true
}

func processLogEntry(_ entry: OSLogEntryLog) {
    // Replace this with actual processing logic if needed
    // print("[\(entry.date)] [\(entry.category)]")
    currentDate = entry.date
    let entryWithPayload = entry as OSLogEntryWithPayload
    let components = entryWithPayload.components
    for component in components {
        if component.formatSubstring.contains("Found power source:") {
            if let argumentStringValue = component.argumentStringValue {
                do {
                    let batteryInfo = parseLogString(from: argumentStringValue)
                    _ = processAirPods(from: batteryInfo)

                    // print("Battery Info: \(batteryInfo)")
                }
            } else {
                print("Invalid or missing data")
                exit(1)
            }
        }
    }
}

func fetchBatteryCenterLogsContinuously() throws {
    let logPredicate = NSPredicate(format: "subsystem == %@", "com.apple.BatteryCenter")

    while true {
        do {
            // Access the system-wide log store
            guard let logStore = try? OSLogStore.local() else {
                throw LogFetchError.logStoreUnavailable
            }
            let position = logStore.position(date: Date().addingTimeInterval(-fetchInterval))
            let entries = try logStore.getEntries(at: position, matching: logPredicate)

            for entry in entries {
                if let logEntry = entry as? OSLogEntryLog {
                    // Filter by subsystem
                    if logEntry.subsystem == "com.apple.BatteryCenter" {
                        processLogEntry(logEntry)
                    }
                }
            }
        } catch {
            throw LogFetchError.entriesFetchFailed
        }

        // Wait before the next fetch
        Thread.sleep(forTimeInterval: fetchInterval)
    }
}

func parseArguments() {
    let arguments = CommandLine.arguments
    var iterator = arguments.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--interval":
            if let value = iterator.next(), let interval = TimeInterval(value) {
                fetchInterval = interval
            }
        case "--threshold":
            if let value = iterator.next(), let threshold = Double(value) {
                warningThreshold = threshold
            }
        case "--callback":
            if let value = iterator.next() {
                callbackFormat = value
            }
        default:
            continue
        }
    }
}

parseArguments()
print("Fetch Interval: \(fetchInterval)")
print("Warning Threshold: \(warningThreshold)")
print("Callback Command: \(callbackFormat)")

// Run the function continuously
DispatchQueue.global(qos: .background).async {
    do {
        try fetchBatteryCenterLogsContinuously()
    } catch {
        print("An error occurred: \(error)")
    }
}

// handle signals
signal(SIGINT) { _ in
    print("Exiting...")
    exit(0)
}

// Keep the main thread alive
// RunLoop.main.run()
// readline until EOF
while let _ = readLine() {}