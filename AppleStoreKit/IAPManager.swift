//
//  IAPManager.swift
//  AppleStoreKit
//
//  Created by ye on 2025/4/1.
//

import Foundation
import StoreKit

public class IAPManager {
    public static let shared = IAPManager()
    private init() {}
    
    private lazy var storeKit1Manager = StoreKit1Manager.shared
    @available(iOS 15.0, *)
    private var storeKit2Manager: StoreKit2Manager { StoreKit2Manager.shared }
    
    public var useV2 = true
    
    public func appAccountToken(_ token:String){
        if #available(iOS 15.0, *){
            storeKit2Manager.appAccountToken = token
        }else{
            storeKit1Manager.appAccountToken = token
        }
    }
    
}

// MARK: - Public Interface
extension IAPManager {
    public func fetchProducts(productIDs: [String]) async -> Result<[UnifiedProduct], IAPError> {
        if #available(iOS 15.0, *),useV2 {
            return await storeKit2Manager.fetchProducts(productIDs: productIDs)
        } else {
            return await storeKit1Manager.fetchProducts(productIDs: productIDs)
        }
    }
    
    public func purchase(productID: String) async -> Result<UnifiedTransaction, IAPError> {
        if #available(iOS 15.0, *),useV2 {
            return await storeKit2Manager.purchase(productID: productID)
        } else {
            return await storeKit1Manager.purchase(productID: productID)
        }
    }
    public func restore() async -> Result<[UnifiedTransaction],IAPError>{
        if #available(iOS 15.0, *),useV2 {
            return await storeKit2Manager.restorePurchases()
        } else {
            return await storeKit1Manager.restorePurchases()
        }
    }
    public func finishTransactions(){
        if #available(iOS 15.0, *),useV2 {
            storeKit2Manager.finish()
        } else {
            storeKit1Manager.finish()
        }
    }
}

// MARK: - 统一数据模型
public enum IAPError: Error {
    case productNotFound
    case productFetchFailed(Error)
    case purchaseFailed(Error)
    case receiptFetchFailed
    case verificationFailed
    case purchasePending
    case userCancelled
    case unknownError
    case noTransation
    case restoreFailed(Error)
}

public struct UnifiedProduct {
    public let id: String
    public var price: Decimal?{
        
        if #available(iOS 15, *){
            return product?.price
        }
       
        return (skProduct?.price as? Decimal)
    }
    public var introductoryPrice : Decimal?{
        if #available(iOS 15, *){
            return product?.subscription?.introductoryOffer?.price
        }
       
        return (skProduct?.introductoryPrice?.price as? Decimal)
    }
    public var displayPrice : String?{
        if #available(iOS 15, *){
            return product?.displayPrice
        }
        return skProduct?.priceLocale.description
    }
    public var discountPrice : Decimal?{
        if #available(iOS 15, *){
            return product?.subscription?.promotionalOffers.first?.price
        }
        return (skProduct?.discounts.first?.price as? Decimal)
    }
    public var currencySymbol : String?{
        if #available(iOS 15, *){
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product?.priceFormatStyle.locale

            // 设置货币代码
            formatter.currencyCode = product?.priceFormatStyle.currencyCode
            
            return formatter.currencySymbol
        }
        return skProduct?.priceLocale.currencySymbol
    }
    public var currencyCode : String?{
        if #available(iOS 15, *){
            return product?.priceFormatStyle.currencyCode
        }
        return skProduct?.priceLocale.currencyCode
    }
    public let displayName: String
    public let type: ProductType
    
    public enum ProductType {
        case consumable
        case nonConsumable
        case subscription
    }
}

public struct UnifiedTransaction {
    public let productID: String
    public let transactionID: String
    public let receipt: String?
    public let jws: String?
    public let purchaseDate: Date
    public let transactionType: UnifiedProduct.ProductType
    
}


extension UnifiedTransaction{
    public var skProduct : SKProduct?{
        return GetSKValues.getValues(StoreKit1Manager.shared.products).filter{$0.productIdentifier == productID}.first
    }
    
}

@available(iOS 15.0, *)
extension UnifiedTransaction{
    public var product : Product?{
        
        let p = GetSKValues.getValues(StoreKit2Manager.shared.products).filter{$0.id == productID}.first
        return p
    }
    public var v2Transaction : Transaction?{
        return GetSKValues.getValues(StoreKit2Manager.shared.currentTransaction).filter {
            String($0.id) == self.transactionID
        }.first
    }
}
extension UnifiedProduct{
    public var skProduct : SKProduct?{
        return GetSKValues.getValues(StoreKit1Manager.shared.products).filter{$0.productIdentifier == id}.first
    }
}

@available(iOS 15.0, *)
extension UnifiedProduct{
    public var product : Product?{
        let p = GetSKValues.getValues(StoreKit2Manager.shared.products).filter{$0.id == id}.first
        return p
    }
}

class GetSKValues<T>{
    
    static func getValues(_ vs : SKValues<T>) -> [T]{
        let group = DispatchGroup()
        group.enter()
        var v = [T]()
        Task{
            v = await vs.value
            group.leave()
        }
        group.wait()
        return v
    }
}

actor SKValues<T>{
    var value = [T]()
    func append(_ continuation: T) async {
        value.append(continuation)
    }
    func removeHandle() async -> [T]  {
        let temp = value
        value.removeAll()
        return temp
    }
}
