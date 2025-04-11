//
//  StoreKit2Manager.swift
//  AppleStoreKit
//
//  Created by ye on 2025/4/1.
//

import Foundation
import StoreKit

@available(iOS 15.0, *)
class StoreKit2Manager: @unchecked Sendable {
    static let shared = StoreKit2Manager()

    var products: [String: Product] = [:]
    var currentTransaction : [Transaction] = []
    var appAccountToken : String = ""
    func finish(){
        currentTransaction.forEach { t in
            Task {
                await t.finish()
            }
        }
        currentTransaction.removeAll()
    }
}

// MARK: - Public Methods

@available(iOS 15.0, *)
extension StoreKit2Manager {
    func fetchProducts(productIDs: [String]) async -> Result<[UnifiedProduct], IAPError> {
        do {
            let products = try await Product.products(for: productIDs)
            self.products = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

            let unifiedProducts = products.map {
                UnifiedProduct(
                    id: $0.id,
                    displayName: $0.displayName,
                    type: $0.type.toUnifiedType()
                )
            }
            return .success(unifiedProducts)
        } catch {
            return .failure(.productFetchFailed(error))
        }
    }

    func purchase(productID: String) async -> Result<UnifiedTransaction, IAPError> {
        guard let product = products[productID] else {
            return .failure(.productNotFound)
        }

        do {
            var opts = Set<Product.PurchaseOption>()
            if let uuid = UUID(uuidString: appAccountToken){
                opts.insert(.appAccountToken(uuid))
            }
            let result = try await product.purchase(options: opts)
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                currentTransaction.append(transaction)
                return .success(UnifiedTransaction(
                    productID: productID,
                    transactionID: String(transaction.id),
                    receipt: nil,
                    jws: verification.jwsRepresentation,
                    purchaseDate: transaction.purchaseDate,
                    transactionType: product.type.toUnifiedType()
                ))

            case .pending:
                return .failure(.purchasePending)
            case .userCancelled:
                return .failure(.userCancelled)
            @unknown default:
                return .failure(.unknownError)
            }
        } catch {
            return .failure(.purchaseFailed(error))
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.verificationFailed
        case let .verified(safe):
            return safe
        }
    }

    // 新增恢复购买方法
    func restorePurchases() async -> Result<[UnifiedTransaction], IAPError> {
        do {
            var unTransactions: [UnifiedTransaction] = []
            for await verification in Transaction.updates {
                let transaction = try checkVerified(verification)
                currentTransaction.append(transaction)
                unTransactions.append(UnifiedTransaction(
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    receipt: nil,
                    jws: verification.jwsRepresentation,
                    purchaseDate: transaction.purchaseDate,
                    transactionType: transaction.productType.toUnifiedType()
                ))
            }

            return unTransactions.count > 0 ? .success(unTransactions) : .failure(.noTransation)
        } catch {
            return .failure(.restoreFailed(error))
        }
    }
}

// MARK: - 类型转换扩展

@available(iOS 15.0, *)
extension Product.ProductType {
    func toUnifiedType() -> UnifiedProduct.ProductType {
        switch self {
        case .consumable: return .consumable
        case .nonConsumable: return .nonConsumable
        case .autoRenewable: return .subscription
        default: return .nonConsumable
        }
    }
}
