//
//  RefundManager.swift
//  AppleStoreKit
//
//  Created by ye on 2025/4/24.
//

import StoreKit
import Combine


@available(iOS 15.0, *)
public class RefundManager {
    public static let shared = RefundManager()
    
    public func currentTransactions() async -> [Transaction] {
        var transactions: [Transaction] = []
        for await t in Transaction.currentEntitlements {
            let transaction = try? StoreKit2Manager.shared.checkVerified(t)
            transaction.map{transactions.append($0)}
        }
        return transactions
            
    }
    public func requestRefund(for transaction: Transaction) async -> Result<Void, Error> {
        do {
            if let scene = await UIApplication.shared.currentWindowScene {
                let result = try await transaction.beginRefundRequest(in: scene)
                print("退款请求已成功发送。")
                return .success(())
            }
            return .failure(NSError(domain: "RefundManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取当前窗口场景"]))
            
        } catch {
            return .failure(error)
        }
    }

    
}


extension UIApplication {
    var currentWindowScene: UIWindowScene? {
        connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene
    }
}
