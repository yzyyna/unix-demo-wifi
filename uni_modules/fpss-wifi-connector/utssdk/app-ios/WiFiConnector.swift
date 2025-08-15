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

    // MARK: - 连接 WPA/WPA2/WPA3 或开放网络（回调 String）
    public func connect(
        ssid: String,
        passphrase: String? = nil,
        isWEP: Bool = false,
        joinOnce: Bool = false,
        completion: @escaping (String) -> Void
    ) {
        guard #available(iOS 11.0, *) else {
            completion("失败：系统不支持（需 iOS 11+）")
            return
        }
        guard !ssid.isEmpty else {
            completion("失败：参数错误（SSID 不能为空）")
            return
        }

        let config: NEHotspotConfiguration
        if let pwd = passphrase, !pwd.isEmpty {
            config = NEHotspotConfiguration(ssid: ssid, passphrase: pwd, isWEP: isWEP)
        } else {
            config = NEHotspotConfiguration(ssid: ssid)  // 开放网络
        }
        config.joinOnce = joinOnce
        // 如连接隐藏网络，可视需要开启：config.hidden = true

        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                if let e = error as NSError? {
                    // 映射为语义化描述
                    completion(self.describeHotspotError(nsError: e, ssid: ssid))
                } else {
                    // 无错误：成功提交/已连接
                    completion("成功：已连接或已提交连接请求（\(ssid)）")
                }
            }
        }
    }

    // MARK: - 错误语义化（兼容现在 SDK）
    private func describeHotspotError(nsError: NSError, ssid: String) -> String {
        // 仅当属于热点配置错误域时，进一步细分原因
        if nsError.domain == NEHotspotConfigurationErrorDomain,
            let errorCode = NEHotspotConfigurationError(rawValue: nsError.code)
        {

            switch errorCode {
            case .userDenied:
                return "失败：用户取消了连接（\(ssid)）"
            case .alreadyAssociated:
                return "成功：已连接到目标网络（\(ssid)）"
            case .invalid:
                return "失败：配置无效（\(ssid)）"
            case .invalidSSID:
                return "失败：SSID 无效（\(ssid)）"
            case .invalidWPAPassphrase:
                return "失败：WPA 密码无效（\(ssid)）"
            case .invalidWEPPassphrase:
                return "失败：WEP 密码无效（\(ssid)）"
            case .applicationIsNotInForeground:
                return "失败：应用未在前台，无法发起连接（\(ssid)）"
            @unknown default:
                return "失败：未知错误（\(ssid)），\(nsError.localizedDescription)"
            }
        }
        // 非热点配置错误域，直接回传系统文案
        return "失败：\(nsError.localizedDescription)（\(ssid)）"
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
            completion(.failure(.notSupported))
            return
        }
        guard !ssid.isEmpty, !username.isEmpty, !password.isEmpty else {
            completion(.failure(.invalidParameters))
            return
        }

        let eap = NEHotspotEAPSettings()
        eap.supportedEAPTypes = [
            NSNumber(value: NEHotspotEAPSettings.EAPType.EAPTTLS.rawValue),
            NSNumber(value: NEHotspotEAPSettings.EAPType.EAPPEAP.rawValue),
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
        guard #available(iOS 11.0, *) else {
            completion([])
            return
        }
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
                let code = NEHotspotConfigurationError(rawValue: nsError.code)
            {
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
