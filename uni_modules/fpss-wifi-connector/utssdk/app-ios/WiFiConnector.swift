import Foundation
import NetworkExtension

public class WiFiConnector {
    public static let shared = WiFiConnector()
    public init() {}

    public enum WiFiError: Error {
        case notSupported
        case invalidParameters
        case userDenied
        case alreadyConnected
        case systemError(Error)
    }

    // MARK: - 连接 WPA/WPA2/WPA3 或开放网络
    public func connect(
        ssid: String,
        passphrase: String? = nil,
        isWEP: Bool = false,
        joinOnce: Bool = false,
        completion: @escaping (Result<Void, WiFiError>) -> Void
    ) {
        guard #available(iOS 11.0, *) else {
            completion(.failure(.notSupported)); return
        }
        guard !ssid.isEmpty else {
            completion(.failure(.invalidParameters)); return
        }

        let config: NEHotspotConfiguration
        if let pwd = passphrase, !pwd.isEmpty {
            config = NEHotspotConfiguration(ssid: ssid, passphrase: pwd, isWEP: isWEP)
        } else {
            config = NEHotspotConfiguration(ssid: ssid)
        }
        config.joinOnce = joinOnce

        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                self.handleHotspotResult(error: error, completion: completion)
            }
        }
    }

    // MARK: - 连接企业/EAP 网络
    public func connectEAP(
        ssid: String,
        username: String,
        password: String,
        outerIdentity: String? = nil,
        trustedServerNames: [String]? = nil,
        joinOnce: Bool = false,
        completion: @escaping (Result<Void, WiFiError>) -> Void
    ) {
        guard #available(iOS 11.0, *) else {
            completion(.failure(.notSupported)); return
        }
        guard !ssid.isEmpty, !username.isEmpty, !password.isEmpty else {
            completion(.failure(.invalidParameters)); return
        }

        let eap = NEHotspotEAPSettings()
        eap.supportedEAPTypes = [
            NSNumber(value: NEHotspotEAPSettings.EAPType.EAPTTLS.rawValue),
            NSNumber(value: NEHotspotEAPSettings.EAPType.EAPPEAP.rawValue)
        ]
        eap.username = username
        eap.password = password
        if let outer = outerIdentity { eap.outerIdentity = outer }
        if let servers = trustedServerNames { eap.trustedServerNames = servers }

        let config = NEHotspotConfiguration(ssid: ssid, eapSettings: eap)
        config.joinOnce = joinOnce

        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                self.handleHotspotResult(error: error, completion: completion)
            }
        }
    }

    // MARK: - 移除已保存配置
    public func removeConfiguration(ssid: String) {
        guard #available(iOS 11.0, *) else { return }
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    // MARK: - 获取已保存的 SSID 列表
    public func getConfiguredSSIDs(completion: @escaping ([String]) -> Void) {
        guard #available(iOS 11.0, *) else { completion([]); return }
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { ssids in
            DispatchQueue.main.async { completion(ssids) }
        }
    }

    // MARK: - 错误处理统一方法
    private func handleHotspotResult(
        error: Error?,
        completion: @escaping (Result<Void, WiFiError>) -> Void
    ) {
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NEHotspotConfigurationErrorDomain,
               let code = NEHotspotConfigurationError(rawValue: nsError.code) {
                switch code {
                case .userDenied:
                    completion(.failure(.userDenied))
                case .alreadyAssociated:
                    completion(.success(()))
                default:
                    completion(.failure(.systemError(error)))
                }
            } else {
                completion(.failure(.systemError(error)))
            }
        } else {
            completion(.success(()))
        }
    }
}
