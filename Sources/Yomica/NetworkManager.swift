import Foundation
import Combine

class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    /// 获取当前配置下的 URLSession
    func getSession() -> URLSession {
        return URLSession.shared
    }
    
    /// 封装一个简单的网络请求方法示例
    func fetchData(from url: URL) async throws -> Data {
        let session = getSession()
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}
