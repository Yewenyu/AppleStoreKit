//
//  StoreKit2Manager.swift
//  AppleStoreKit
//
//  Created by ye on 2025/4/1.
//

import Foundation
import StoreKit

@available(iOS 15.0, macOS 12.0, *)
class StoreKit2Manager: @unchecked Sendable {
    static let shared = StoreKit2Manager()

    var products = SKValues<Product>()
    var currentTransaction = SKValues<Transaction>()
    var appAccountToken : String = ""
    func finish(){
        Task{
            await currentTransaction.removeHandle().forEach{ t in
                Task{
                    await t.finish()
                }
            }
        }
        
    }
    var isFirstRestore = false
}

// MARK: - Public Methods

@available(iOS 15.0, macOS 12.0, *)
extension StoreKit2Manager {
    func fetchProducts(productIDs: [String]) async -> Result<[UnifiedProduct], IAPError> {
        do {
            let products = try await Product.products(for: productIDs)
            for p in products{
                await self.products.append(p)
            }

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
        let products = await products.value
        guard let product = products.filter({ $0.id == productID}).first else {
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
                await currentTransaction.append(transaction)
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

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
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
            func handle(_ trans:Transaction.Transactions) async throws{
                for await verification in trans {
                    let transaction = try checkVerified(verification)
                    await currentTransaction.append(transaction)
                    unTransactions.append(UnifiedTransaction(
                        productID: transaction.productID,
                        transactionID: String(transaction.id),
                        receipt: nil,
                        jws: verification.jwsRepresentation,
                        purchaseDate: transaction.purchaseDate,
                        transactionType: transaction.productType.toUnifiedType()
                    ))
                }
            }
            if isFirstRestore{
                isFirstRestore = false
                try await handle(Transaction.updates)
            }else{
                try await handle(Transaction.currentEntitlements)
            }
            return unTransactions.count > 0 ? .success(unTransactions) : .failure(.noTransation)
        } catch {
            return .failure(.restoreFailed(error))
        }
    }
}

// MARK: - 类型转换扩展

@available(iOS 15.0, macOS 12.0, *)
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
