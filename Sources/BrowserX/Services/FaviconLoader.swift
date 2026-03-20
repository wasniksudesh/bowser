// FaviconLoader.swift - Favicon Download & Cache Service
// Swift 6.2 Actor for thread-safe favicon management

import Foundation
import AppKit

// =============================================================================
// MARK: - Favicon Loader Actor
// =============================================================================

/// Thread-safe actor for downloading and caching favicons
/// Uses Google's favicon service as fallback when direct URL fails
/// Stores favicon data as Data (Sendable) and converts to NSImage on MainActor
actor FaviconLoader {
    
    /// Shared singleton instance
    static let shared = FaviconLoader()
    
    /// In-memory cache for downloaded favicons (URL string -> Data)
    private var cache: [String: Data] = [:]
    
    /// Active download tasks to prevent duplicate requests
    private var activeTasks: [String: Task<Data?, Never>] = [:]
    
    /// Standard favicon size for sidebar display (points)
    private let standardSize: CGFloat = 32
    
    /// Google favicon service base URL
    private let googleFaviconService = "https://www.google.com/s2/favicons"
    
    /// Disk cache directory for persistent favicon storage
    private let diskCacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("Bowser/FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()
    
    // MARK: - Initialization
    
    private init() {
        // Load disk cache into memory on init
        Task { await loadDiskCache() }
    }
    
    /// Load persisted favicons from disk into memory cache
    private func loadDiskCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "png" {
            if let data = try? Data(contentsOf: file) {
                let key = file.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? file.lastPathComponent
                cache[key] = data
            }
        }
    }
    
    /// Save favicon data to disk cache
    private func saveToDisk(data: Data, forKey key: String) {
        let sanitizedKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let fileURL = diskCacheURL.appendingPathComponent("\(sanitizedKey).png")
        try? data.write(to: fileURL)
    }
    
    // MARK: - Public API
    
    /// Download and cache a favicon from URL
    /// - Parameter url: Direct favicon URL (from CEF OnFaviconURLChange)
    /// - Returns: Favicon Data, or nil on failure
    func downloadFaviconData(from url: URL) async -> Data? {
        let cacheKey = url.absoluteString
        
        // Check cache first
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Check if already downloading
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        // Start new download task
        let task = Task<Data?, Never> {
            do {
                let data = try await performDownload(from: url)
                return data
            } catch {
                print("[FaviconLoader] Failed to download favicon from \(url): \(error)")
                return nil
            }
        }
        
        activeTasks[cacheKey] = task
        let result = await task.value
        activeTasks.removeValue(forKey: cacheKey)
        
        // Cache successful result
        if let data = result {
            cache[cacheKey] = data
        }
        
        return result
    }
    
    /// Download favicon with automatic Google fallback
    /// - Parameters:
    ///   - faviconURL: Direct favicon URL (may be nil if CEF returns empty list)
    ///   - pageURL: The page URL for Google fallback service
    /// - Returns: Favicon Data, or nil on failure
    func downloadFaviconData(from faviconURL: URL?, pageURL: URL) async -> Data? {
        // Try direct URL first if available
        if let directURL = faviconURL {
            if let data = await downloadFaviconData(from: directURL) {
                return data
            }
        }
        
        // Fallback to Google's favicon service
        return await downloadFromGoogleService(for: pageURL)
    }
    
    /// Clear the favicon cache
    func clearCache() {
        cache.removeAll()
    }
    
    /// Remove a specific entry from cache
    func invalidateCache(for url: URL) {
        cache.removeValue(forKey: url.absoluteString)
    }
    
    // MARK: - Private Methods
    
    /// Perform the actual download
    private func performDownload(from url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FaviconError.invalidResponse
        }
        
        // Validate content type (allow common image types)
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            let validTypes = ["image/", "application/octet-stream"]
            guard validTypes.contains(where: { contentType.contains($0) }) else {
                throw FaviconError.invalidContentType(contentType)
            }
        }
        
        // Validate that this is actually image data
        guard NSImage(data: data) != nil else {
            throw FaviconError.invalidImageData
        }
        
        return data
    }
    
    /// Download from Google's favicon service
    private func downloadFromGoogleService(for pageURL: URL) async -> Data? {
        guard let host = pageURL.host else {
            print("[FaviconLoader] Cannot extract host from URL: \(pageURL)")
            return nil
        }
        
        // Build Google favicon service URL
        // Format: https://www.google.com/s2/favicons?domain={hostname}&sz=64
        var components = URLComponents(string: googleFaviconService)
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        
        guard let googleURL = components?.url else {
            print("[FaviconLoader] Failed to build Google favicon URL for: \(host)")
            return nil
        }
        
        let cacheKey = "google:\(host)"
        
        // Check cache
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Download from Google service
        do {
            let (data, response) = try await URLSession.shared.data(from: googleURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("[FaviconLoader] Google service returned non-200 status for: \(host)")
                return nil
            }
            
            guard NSImage(data: data) != nil else {
                print("[FaviconLoader] Invalid image data from Google service for: \(host)")
                return nil
            }
            
            // Cache result (memory + disk)
            cache[cacheKey] = data
            saveToDisk(data: data, forKey: cacheKey)
            
            return data
            
        } catch {
            print("[FaviconLoader] Google favicon service error for \(host): \(error)")
            return nil
        }
    }
    
    // MARK: - Offline Favicon Fetching (For Favorites)
    
    /// Fetch best available favicon data for a URL (for offline/favorites use)
    /// Strategy: Google high-res service (128px) -> favicon.ico fallback
    /// - Parameter url: The website URL to fetch favicon for
    /// - Returns: Favicon image data (Sendable)
    /// - Throws: FaviconError if all strategies fail
    func fetchBestIconData(for url: URL) async throws -> Data {
        guard let host = url.host else {
            throw FaviconError.invalidResponse
        }
        
        let cacheKey = "favorite:\(host)"
        
        // Check memory cache first
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Strategy 1: Google high-res favicon service (128px)
        if let data = await fetchFromGoogleHighRes(host: host) {
            cache[cacheKey] = data
            saveToDisk(data: data, forKey: cacheKey)
            return data
        }
        
        // Strategy 2: Direct favicon.ico request
        if let data = await fetchFaviconICO(from: url) {
            cache[cacheKey] = data
            saveToDisk(data: data, forKey: cacheKey)
            return data
        }
        
        throw FaviconError.downloadFailed(underlying: NSError(domain: "FaviconLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "All favicon strategies failed for \(host)"]))
    }
    
    /// Fetch from Google's high-resolution favicon service
    private func fetchFromGoogleHighRes(host: String) async -> Data? {
        var components = URLComponents(string: googleFaviconService)
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128")
        ]
        
        guard let googleURL = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: googleURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count > 100, // Filter out placeholder icons (typically very small)
                  NSImage(data: data) != nil else {
                return nil
            }
            return data
        } catch {
            print("[FaviconLoader] Google high-res fetch failed for \(host): \(error)")
            return nil
        }
    }
    
    /// Fetch standard favicon.ico from website root
    private func fetchFaviconICO(from url: URL) async -> Data? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        
        guard let faviconURL = components.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: faviconURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  NSImage(data: data) != nil else {
                return nil
            }
            return data
        } catch {
            print("[FaviconLoader] favicon.ico fetch failed for \(url.host ?? "unknown"): \(error)")
            return nil
        }
    }
}

// =============================================================================
// MARK: - Favicon Errors
// =============================================================================

/// Errors that can occur during favicon loading
enum FaviconError: Error, LocalizedError {
    case invalidResponse
    case invalidContentType(String)
    case invalidImageData
    case downloadFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case .invalidContentType(let type):
            return "Invalid content type: \(type)"
        case .invalidImageData:
            return "Could not create image from data"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        }
    }
}

// =============================================================================
// MARK: - MainActor Extension for Image Conversion
// =============================================================================

extension FaviconLoader {
    
    /// Download favicon and convert to NSImage on MainActor
    /// - Parameters:
    ///   - faviconURL: Direct favicon URL from CEF (may be nil)
    ///   - pageURL: The page URL for fallback
    /// - Returns: Resized NSImage suitable for sidebar display, or nil on failure
    @MainActor
    func downloadFavicon(from faviconURL: URL?, pageURL: URL) async -> NSImage? {
        // Download the data on the actor
        let data = await downloadFaviconData(from: faviconURL, pageURL: pageURL)
        
        // Convert to NSImage and resize on MainActor
        guard let data = data,
              let image = NSImage(data: data) else {
            return nil
        }
        
        return resizeImage(image, to: 32)
    }
    
    /// Fetch best favicon for a URL (for favorites/offline use) and convert to NSImage
    /// - Parameter url: The website URL to fetch favicon for
    /// - Returns: NSImage of the favicon, or nil on failure
    @MainActor
    func fetchBestIcon(for url: URL) async -> NSImage? {
        do {
            let data = try await fetchBestIconData(for: url)
            return NSImage(data: data)
        } catch {
            print("[FaviconLoader] fetchBestIcon failed for \(url): \(error)")
            return nil
        }
    }
    
    /// Resize image to standard size while preserving aspect ratio
    /// - Parameters:
    ///   - image: Source image
    ///   - size: Target size in points (will be square)
    /// - Returns: Resized image optimized for retina displays
    @MainActor
    private func resizeImage(_ image: NSImage, to size: CGFloat) -> NSImage? {
        // Create a new image with the target size
        let targetSize = NSSize(width: size, height: size)
        
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Enable high-quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Calculate aspect-fit rectangle
        let sourceSize = image.size
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let ratio = min(widthRatio, heightRatio)
        
        let scaledWidth = sourceSize.width * ratio
        let scaledHeight = sourceSize.height * ratio
        let x = (targetSize.width - scaledWidth) / 2
        let y = (targetSize.height - scaledHeight) / 2
        
        let destRect = NSRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        let sourceRect = NSRect(origin: .zero, size: sourceSize)
        
        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        
        newImage.unlockFocus()
        
        return newImage
    }
}
