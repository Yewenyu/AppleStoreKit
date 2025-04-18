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
    
    actor Continuation<T> {
        typealias CheckedType = CheckedContinuation<Result<T, IAPError>, Never>
        var value = [CheckedType]()
        
        func append(_ continuation: CheckedType) async {
            value.append(continuation)
        }
        func removeHandle() async -> [CheckedType]  {
            let temp = value
            value.removeAll()
            return temp
        }
            
    }
    private var purchasesContinuation = Continuation<UnifiedTransaction>()
    private var productsContinuation = Continuation<[UnifiedProduct]>()
    private var restoreContinuation = Continuation<[UnifiedTransaction]>()
    private var receiptContinuation = Continuation<()>()
    
    


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
            Task{
                let count = await self.productsContinuation.value.count
                await self.productsContinuation.append(continuation)
                if count > 0{
                    return
                }
                let request = SKProductsRequest(productIdentifiers: Set(productIDs))
                request.delegate = self
                
                request.start()
            }
            

        }
    }

    func purchase(productID: String) async -> Result<UnifiedTransaction, IAPError> {
        guard let product = products[productID] else {
            return .failure(.productNotFound)
        }

        return await withCheckedContinuation { continuation in
            Task{
                let count = await self.purchasesContinuation.value.count
                await self.purchasesContinuation.append(continuation)
                if count > 0{
                    return
                }
                let payment = SKPayment(product: product)
                SKPaymentQueue.default().add(payment)
            }
            
        }
    }

    // 新增恢复购买方法
    func restorePurchases() async -> Result<[UnifiedTransaction], IAPError> {
        await withCheckedContinuation { continuation in
            Task{
                let count = await self.restoreContinuation.value.count
                await self.restoreContinuation.append(continuation)
                if count > 0{
                    return
                }
                SKPaymentQueue.default().restoreCompletedTransactions()
            }
            
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
        Task{
            guard let receipt = fetchReceipt() else {
                await self.purchasesContinuation.removeHandle().forEach{$0.resume(returning: .failure(.receiptFetchFailed))}
                
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
            await self.purchasesContinuation.removeHandle().forEach{
                $0.resume(returning: .success(unifiedTransaction))
            }
            
        }
        
    }

    private func handleFailed(transaction: SKPaymentTransaction) {
        Task{
            let error = transaction.error ?? NSError(domain: "IAPError", code: -1)
            await self.purchasesContinuation.removeHandle().forEach{
                $0.resume(returning: .failure(.purchaseFailed(error)))
            }
            
            SKPaymentQueue.default().finishTransaction(transaction)
        }
        
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
                Task{
                    let refreshRequest = SKReceiptRefreshRequest()
                    refreshRequest.delegate = self
                    await self.receiptContinuation.append(continuation)
                    refreshRequest.start()
                }
                
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
            await self.restoreContinuation.removeHandle().forEach{
                $0.resume(returning: .success(restoredTransactions))
            }

        }
        
    }
    func requestDidFinish(_ request: SKRequest) {
        if request is SKReceiptRefreshRequest{
            Task{
                await self.receiptContinuation.removeHandle().forEach{
                    $0.resume(returning: .success(()))
                    
                }
            }
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        Task{
            await self.restoreContinuation.removeHandle().forEach{
                $0.resume(returning: .failure(.purchaseFailed(error)))
                
            }
        }

    }
}

// MARK: - SKProductsRequestDelegate

extension StoreKit1Manager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        
        Task{
            self.products = Dictionary(uniqueKeysWithValues: response.products.map { ($0.productIdentifier, $0) })
            let products = response.products.map{
                UnifiedProduct(
                    id: $0.productIdentifier,
                    displayName: $0.localizedTitle,
                    type: $0.subscriptionPeriod == nil ? .consumable : .subscription
                )
            }
            await self.productsContinuation.removeHandle().forEach{
                $0.resume(returning: .success(products))
            }
        }
        
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        Task{
            await self.productsContinuation.removeHandle().forEach{
                $0.resume(returning: .failure(.productFetchFailed(error)))
            }
        }
    }
}

