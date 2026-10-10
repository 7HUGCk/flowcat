import AppKit
import CoreWLAN
import CoreLocation

final class NetworkDetector: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private var requested = false
    var onAuthorizationChange: (() -> Void)?
    override init() { super.init(); location.delegate = self }
    func requestIfNeeded() {
        guard !requested, location.authorizationStatus == .notDetermined else { return }
        requested = true
        NSApp.activate(ignoringOtherApps: true)
        // The OS prompt can be declined. No coordinates are requested or recorded.
        location.requestWhenInUseAuthorization()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onAuthorizationChange?() }
    func current() -> NetworkContext {
        if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
            return NetworkContext(key: "__all__", name: "全部网络", identified: false)
        }
        let client = CWWiFiClient.shared()
        for name in client.interfaceNames() ?? [] {
            if let ssid = client.interface(withName: name)?.ssid(), !ssid.isEmpty {
                return NetworkContext(key: "wifi:" + ssid, name: ssid, identified: true)
            }
        }
        requestIfNeeded()
        return NetworkContext(key: "__all__", name: "全部网络", identified: false)
    }
}
