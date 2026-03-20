// VMConfiguration.swift
// Configuration settings for the VM

import Foundation

/// VM configuration settings
struct VMConfiguration {
    /// CPU configuration
    var cpuCount: Int = 2
    
    /// Memory size in bytes (default: 2GB)
    var memorySize: UInt64 = 2 * 1024 * 1024 * 1024
    
    /// mem0.img size in GB (default: 5GB)
    var dataImageSizeGB: UInt64 = 5
    
    /// Enable debug console output
    var enableDebugConsole: Bool = false
    
    /// Static configuration
    static let `default` = VMConfiguration()
    
    /// Load from UserDefaults
    static func load() -> VMConfiguration {
        var config = VMConfiguration()
        
        let defaults = UserDefaults.standard
        
        if let cpuCount = defaults.object(forKey: "vm.cpuCount") as? Int {
            config.cpuCount = cpuCount
        }
        
        if let memoryGB = defaults.object(forKey: "vm.memoryGB") as? Int {
            config.memorySize = UInt64(memoryGB) * 1024 * 1024 * 1024
        }
        
        if let dataImageSizeGB = defaults.object(forKey: "vm.dataImageSizeGB") as? Int {
            config.dataImageSizeGB = UInt64(dataImageSizeGB)
        }
        
        config.enableDebugConsole = defaults.bool(forKey: "vm.enableDebugConsole")
        
        return config
    }
    
    /// Save to UserDefaults
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(cpuCount, forKey: "vm.cpuCount")
        defaults.set(Int(memorySize / (1024 * 1024 * 1024)), forKey: "vm.memoryGB")
        defaults.set(Int(dataImageSizeGB), forKey: "vm.dataImageSizeGB")
        defaults.set(enableDebugConsole, forKey: "vm.enableDebugConsole")
    }
}
