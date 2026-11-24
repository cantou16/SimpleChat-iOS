import XCTest
@testable import SimpleChat

/// 模拟“挂了系统代理 / VPN”的环境：CFNetwork 曾经在初始化转义路径时崩
/// （-[__NSCFNumber length]: unrecognized selector）。这里把代理指到一个不可用端口，
/// 断言请求只会失败（或超时），进程不能崩。
final class ProxyEnvironmentTests: XCTestCase {

    /// URLSession + 系统代理字典：不应崩溃，只应返回错误。
    func testURLSessionWithBrokenProxyDoesNotCrash() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": 9,
            "HTTPSEnable": true,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": 9,
        ]
        configuration.timeoutIntervalForRequest = 5

        let session = URLSession(configuration: configuration)
        let done = expectation(description: "request finished without crashing")
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let task = session.dataTask(with: request) { data, response, error in
            // 走到这里就说明没有崩：代理不可用应当报错，而不是让进程退出。
            XCTAssertTrue(error != nil || response != nil, "expected error or response, got neither (data=\(String(describing: data?.count)))")
            done.fulfill()
        }
        task.resume()
        wait(for: [done], timeout: 15)
        session.invalidateAndCancel()
    }

}
