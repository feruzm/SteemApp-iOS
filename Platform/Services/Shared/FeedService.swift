//
//  FeedService.swift
//  Platform
//
//  Created by Siarhei Suliukou on 5/2/18.
//  Copyright © 2018 mby4boomapps. All rights reserved.
//

import Foundation

enum SteemitFeedServiceError: Error {
    case postRewardError
    case credExtractError
    case postReloadError
}

public enum FeedTypes: String {
    case blog = "BLOG"
    case feed = "FEED"
    case trending = "TRENDING"
    case new = "NEW"
    case hot = "HOT"
    case promoted = "PROMOTED"
}

public protocol FeedService {
    func feed(type: FeedTypes, next: (String, String)?, completion: @escaping (Result<[Post]>) -> Void)
    func post(type: FeedTypes, author: String, permlink: String, completion: @escaping (Result<Post>) -> Void)
    func postReward(completion: @escaping (Result<PostReward>) -> Void)
}

struct SteemitFeedService {
    let networkSvc: NetworkService
    
    init() {
        let userProvider = MoyaProviders.shared.userProvider
        let feedProvider = MoyaProviders.shared.feedProvider
        
        self.networkSvc = SteemitNetworkService(userProvider: userProvider,
                                                        feedProvider: feedProvider)
    }
}

extension SteemitFeedService: FeedService {
    func post(type: FeedTypes, author: String, permlink: String, completion: @escaping (Result<Post>) -> Void) {
        // TODO: refactor with calling post reload (not feed with limit 1)
        feed(type: type, next: (author, permlink), limit: 1) { res in
            switch res {
            case .success(let posts):
                if  let post = posts.first {
                    let successRes = Result<Post>.success(post)
                    completion(successRes)
                } else {
                    let errorRes = Result<Post>.error(SteemitFeedServiceError.postReloadError)
                    completion(errorRes)
                }
            case .error(let err):
                let errorRes = Result<Post>.error(err)
                completion(errorRes)
            }
        }
    }
    
    func postReward(completion: @escaping (Result<PostReward>) -> Void) {
        let dispatchGroup = DispatchGroup()
        var rewardFund: RewardFund? = nil
        var currentMedianPrice: CurrentMedianPrice? = nil
        
        dispatchGroup.enter()
        
        let url = Config.Endpoints.Feed.url
        networkSvc.getRewardFund(url: url, params: ["post"]) { (res: Result<RewardFundRaw>) in
            switch res {
            case .success(let rawRew):
                rewardFund = rawRew.asEntity
                break
            case .error:
                rewardFund = nil
                break
            }
            
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        
        networkSvc.getCurrentMedianHistoryPrice(url: url, params: []) { (res: Result<CurrentMedianPriceRaw>) in
            switch res {
            case .success(let rawMedian):
                currentMedianPrice = rawMedian.asEntity
                break
            case .error:
                currentMedianPrice = nil
                break
            }
            
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: DispatchQueue.main) {
            if let rf = rewardFund, let cmp =  currentMedianPrice {
                let pr = PostReward(reward_balance: rf.reward_balance,
                                    recent_claims: rf.recent_claims,
                                    base: cmp.base)
                let res = Result<PostReward>.success(pr)
                completion(res)
            } else {
                let err = SteemitFeedServiceError.postRewardError
                let res = Result<PostReward>.error(err)
                completion(res)
            }
        }
    }
    
    public func feed(type: FeedTypes, next: (String, String)?, completion: @escaping (Result<[Post]>) -> Void) {
        feed(type: type, next: next, limit: 20, completion: completion)
    }
    
    private func feed(type: FeedTypes, next: (String, String)?, limit: Int, completion: @escaping (Result<[Post]>) -> Void) {
        let url = Config.Endpoints.Feed.url
        let userSvc = ServiceLocator.Application.userService()
        
        let ccl: (Result<[PostRaw]>) -> () = { (res: Result<[PostRaw]>) in
            switch res {
            case .success(let rawPosts):
                let posts = rawPosts.map({ $0.asEntity })
                let result = Result<[Post]>.success(posts)
                completion(result)
                break
            case .error(let err):
                let error = Result<[Post]>.error(err)
                completion(error)
                break
            }
        }
        
        if type == FeedTypes.blog {
            userSvc.logedQ { res in
                if case .success(let someCreds) = res, let cred = someCreds {
                    let params = (tag: cred.username, limit: limit)
                    self.networkSvc.getBlog(url: url, params: params, addparam: next, completion: ccl)
                } else {
                    let error = Result<[Post]>.error(SteemitFeedServiceError.credExtractError)
                    completion(error)
                }
            }
        } else if type == FeedTypes.feed {
            userSvc.logedQ { res in
                if case .success(let someCreds) = res, let cred = someCreds {
                    let params = (tag: cred.username, limit: limit)
                    self.networkSvc.getFeed(url: url, params: params, addparam: next, completion: ccl)
                } else {
                    let error = Result<[Post]>.error(SteemitFeedServiceError.credExtractError)
                    completion(error)
                }
            }
        } else if type == FeedTypes.trending {
            let params = (tag: "", limit: limit)
            networkSvc.getTrending(url: url, params: params, addparam: next, completion: ccl)
        } else if type == FeedTypes.new {
            let params = (tag: "", limit: limit)
            networkSvc.getCreated(url: url, params: params, addparam: next, completion: ccl)
        } else if type == FeedTypes.hot {
            let params = (tag: "", limit: limit)
            networkSvc.getHot(url: url, params: params, addparam: next, completion: ccl)
        } else if type == FeedTypes.promoted {
            let params = (tag: "", limit: limit)
            networkSvc.getPromoted(url: url, params: params, addparam: next, completion: ccl)
        }
        
    }
}
