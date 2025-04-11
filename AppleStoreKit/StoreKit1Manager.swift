//
//  StoreKit1Manager.swift
//  AppleStoreKit
//
//  Created by ye on 2025/4/1.
//

import Foundation
import StoreKit

class StoreKit1Manager: NSObject {
    typealias PurchaseContinuation = CheckedContinuation<Result<UnifiedTransaction, IAPError>, Never>
    typealias ProductsContinuation = CheckedContinuation<Result<[UnifiedProduct], IAPError>, Never>
    typealias RestoreContinuation = CheckedContinuation<Result<[UnifiedTransaction], IAPError>, Never>
    typealias ReceiptContinuation = CheckedContinuation<Result<(), IAPError>, Never>

    static let shared = StoreKit1Manager()

    var products: [String: SKProduct] = [:]
    private var purchaseContinuation: PurchaseContinuation?
    private var productsContinuation: ProductsContinuation?
    // 添加新的恢复购买续体

    private var restoreContinuation: RestoreContinuation?
    private var receiptContinuation: ReceiptContinuation?


    var currentTransactions : [SKPaymentTransaction] = []
    func finish(){
        currentTransactions.forEach {
            SKPaymentQueue.default().finishTransaction($0)
        }
        currentTransactions.removeAll()
    }
    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }
}

// MARK: - Public Methods

extension StoreKit1Manager {
    func fetchProducts(productIDs: [String]) async -> Result<[UnifiedProduct], IAPError> {
        
        
        await withCheckedContinuation { continuation in
            self.productsContinuation = continuation
            let request = SKProductsRequest(productIdentifiers: Set(productIDs))
            request.delegate = self
            
            request.start()

        }
    }

    func purchase(productID: String) async -> Result<UnifiedTransaction, IAPError> {
        guard let product = products[productID] else {
            return .failure(.productNotFound)
        }

        return await withCheckedContinuation { continuation in
            self.purchaseContinuation = continuation
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(payment)
        }
    }

    // 新增恢复购买方法
    func restorePurchases() async -> Result<[UnifiedTransaction], IAPError> {
        await withCheckedContinuation { continuation in
            self.restoreContinuation = continuation
            SKPaymentQueue.default().restoreCompletedTransactions()
        }
    }
}

// MARK: - SKPaymentTransactionObserver

extension StoreKit1Manager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                handlePurchased(transaction: transaction)
            case .failed:
                handleFailed(transaction: transaction)
            case .restored, .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }

    private func handlePurchased(transaction: SKPaymentTransaction) {
        guard let receipt = fetchReceipt() else {
            purchaseContinuation?.resume(returning: .failure(.receiptFetchFailed))
            return
        }
        let product = products[transaction.payment.productIdentifier]
        let unifiedTransaction = UnifiedTransaction(
            productID: transaction.payment.productIdentifier,
            transactionID: transaction.transactionIdentifier ?? UUID().uuidString,
            receipt: receipt,
            jws: nil,
            purchaseDate: transaction.transactionDate ?? Date(),
            transactionType: product?.subscriptionPeriod == nil ? .consumable : .subscription
        )
        currentTransactions.append(transaction)
        purchaseContinuation?.resume(returning: .success(unifiedTransaction))
    }

    private func handleFailed(transaction: SKPaymentTransaction) {
        let error = transaction.error ?? NSError(domain: "IAPError", code: -1)
        purchaseContinuation?.resume(returning: .failure(.purchaseFailed(error)))
        SKPaymentQueue.default().finishTransaction(transaction)
    }

    private func fetchReceipt() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            return nil
        }
        return receiptData.base64EncodedString()
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        
        Task{
            _ = await withCheckedContinuation { continuation in
                let refreshRequest = SKReceiptRefreshRequest()
                refreshRequest.delegate = self
                self.receiptContinuation = continuation
                refreshRequest.start()
            }
            var restoredTransactions: [UnifiedTransaction] = []
            

            let receipt = fetchReceipt()
            for transaction in queue.transactions {
                guard transaction.transactionState == .restored else {
                    continue
                }
                
                let product = products[transaction.payment.productIdentifier]

                let unifiedTransaction = UnifiedTransaction(
                    productID: transaction.payment.productIdentifier,
                    transactionID: transaction.transactionIdentifier ?? UUID().uuidString,
                    receipt: receipt,
                    jws: nil,
                    purchaseDate: transaction.transactionDate ?? Date(),
                    transactionType: product?.subscriptionPeriod == nil ? .consumable : .subscription
                )

                restoredTransactions.append(unifiedTransaction)
                currentTransactions.append(transaction)
            }

            restoreContinuation?.resume(returning: .success(restoredTransactions))
        }
        
    }
    func requestDidFinish(_ request: SKRequest) {
        if request is SKReceiptRefreshRequest{
            receiptContinuation?.resume(returning: .success(()))
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        restoreContinuation?.resume(returning: .failure(.purchaseFailed(error)))
    }
}

// MARK: - SKProductsRequestDelegate

extension StoreKit1Manager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        
        
        self.products = Dictionary(uniqueKeysWithValues: response.products.map { ($0.productIdentifier, $0) })
        let products = response.products.map{
            UnifiedProduct(
                id: $0.productIdentifier,
                displayName: $0.localizedTitle,
                type: $0.subscriptionPeriod == nil ? .consumable : .subscription
            )
        }
        productsContinuation?.resume(returning: .success(products))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        productsContinuation?.resume(returning: .failure(.productFetchFailed(error)))
    }
}

