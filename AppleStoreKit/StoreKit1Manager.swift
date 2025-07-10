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

    var products = SKValues<SKProduct>()
    
    typealias CheckedType<T> = CheckedContinuation<Result<T, IAPError>, Never>
    
    private var purchasesContinuation = SKValues<CheckedType<UnifiedTransaction>>()
    private var productsContinuation = SKValues<CheckedType<[UnifiedProduct]>>()
    private var restoreContinuation = SKValues<CheckedType<[UnifiedTransaction]>>()
    private var receiptContinuation = SKValues<CheckedType<()>>()
    
    var appAccountToken : String?
    
  
    var currentTransactions = SKValues<SKPaymentTransaction>()
    func finish(){
        Task{
            await currentTransactions.removeHandle().forEach {
                SKPaymentQueue.default().finishTransaction($0)
            }
        }
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
        guard let product = (await products.value).filter({$0.productIdentifier == productID}).first else {
            return .failure(.productNotFound)
        }

        return await withCheckedContinuation { continuation in
            Task{
                let count = await self.purchasesContinuation.value.count
                await self.purchasesContinuation.append(continuation)
                if count > 0{
                    return
                }
                let payment = SKMutablePayment(product: product)
                payment.applicationUsername = appAccountToken
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
        
        Task{
            let count = await self.restoreContinuation.value.count
            if count > 0{
                handleRestore(transactions)
                return
            }
            for transaction in transactions {
                switch transaction.transactionState {
                case .purchased,.restored:
                    handlePurchased(transaction: transaction)
                case .failed,.deferred:
                    handleFailed(transaction: transaction)
                 default:
                    break
                }
            }
        }
        
    }

    private func handlePurchased(transaction: SKPaymentTransaction) {
        Task{
            await requestReceipt()
            guard let receipt = fetchReceipt() else {
                await self.purchasesContinuation.removeHandle().forEach{$0.resume(returning: .failure(.receiptFetchFailed))}
                
                return
            }
            let product = (await products.value).filter{$0.productIdentifier == transaction.payment.productIdentifier}.first
            let unifiedTransaction = UnifiedTransaction(
                productID: transaction.payment.productIdentifier,
                transactionID: transaction.transactionIdentifier ?? UUID().uuidString,
                receipt: receipt,
                jws: nil,
                purchaseDate: transaction.transactionDate ?? Date(),
                transactionType: product?.subscriptionPeriod == nil ? .consumable : .subscription
            )
            await currentTransactions.append(transaction)
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

    func requestReceipt() async{
        _ = await withCheckedContinuation { continuation in
            Task{
                let refreshRequest = SKReceiptRefreshRequest()
                refreshRequest.delegate = self
                await self.receiptContinuation.append(continuation)
                refreshRequest.start()
            }
        }
    }
    func handleRestore(_ transactions:[SKPaymentTransaction]){
        Task{
            await requestReceipt()
            var restoredTransactions: [UnifiedTransaction] = []
            

            let receipt = fetchReceipt()
            for transaction in transactions {
                guard transaction.transactionState == .restored else {
                    continue
                }
                
                let product = (await products.value).filter{$0.productIdentifier == transaction.payment.productIdentifier}.first

                let unifiedTransaction = UnifiedTransaction(
                    productID: transaction.payment.productIdentifier,
                    transactionID: transaction.transactionIdentifier ?? UUID().uuidString,
                    receipt: receipt,
                    jws: nil,
                    purchaseDate: transaction.transactionDate ?? Date(),
                    transactionType: product?.subscriptionPeriod == nil ? .consumable : .subscription
                )

                restoredTransactions.append(unifiedTransaction)
                await currentTransactions.append(transaction)
            }
            await self.restoreContinuation.removeHandle().forEach{
                $0.resume(returning: .success(restoredTransactions))
            }

        }
    }
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        
        handleRestore(queue.transactions)
        
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
            for p in response.products{
                await self.products.append(p)
            }
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

