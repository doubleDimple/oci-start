import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case serverMessage(String)
    case invalidURL
    case invalidResponse
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "会话已过期，请重新登录"
        case .serverMessage(let msg):
            return msg
        case .invalidURL:
            return "服务器地址无效"
        case .invalidResponse:
            return "服务器响应无效"
        case .decoding(let error):
            return "数据解析失败：\(error.localizedDescription)"
        case .network(let error):
            return "网络错误：\(error.localizedDescription)"
        }
    }
}
