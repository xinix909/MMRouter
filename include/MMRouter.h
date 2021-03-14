//
//  MMRouter.h
//  MicroMessenger
//
//  Created by nix on 2020/12/8.
//  Copyright © 2020 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@class MMRouterAuthorizer;

typedef void (^MMRouterHandler)(NSDictionary *routerParameters);

@interface MMRouter : NSObject

+ (void)registerRouteURL:(NSString *)routeURL handler:(MMRouterHandler)handlerBlock;

+ (BOOL)routeURL:(NSString *)nsURL;

+ (BOOL)routeURL:(NSString *)nsURL withParameters:(NSDictionary<NSString *, id> *_Nullable)parameters;

+ (BOOL)canRoute:(NSString *)url;

+ (MMRouterAuthorizer *)makeRouterAuthorizer:(NSString *)routerRUL handler:(MMRouterHandler)handlerBlock;

@end

typedef MMRouterAuthorizer *_Nonnull (^AuthProtocalBlock)(NSString *authProtocol);
typedef MMRouterAuthorizer *_Nonnull (^BatchAuthProtocalBlock)(NSArray<NSString *> *protocolArray);

/// 这个类用于将某个routeURL授权给协议（weixin:// 或者 search://），或进行其他函数式编程操作。协议是用来划分功能或权限的。
@interface MMRouterAuthorizer : NSObject

- (AuthProtocalBlock)authProtocol;

- (BatchAuthProtocalBlock)authProtocolList;

@end

NS_ASSUME_NONNULL_END
