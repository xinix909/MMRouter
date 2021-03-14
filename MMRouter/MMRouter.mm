//
//  MMRouter.m
//  MicroMessenger
//
//  Created by nix on 2020/12/8.
//  Copyright © 2020 Tencent. All rights reserved.
//

#import "MMRouter.h"

static NSString *const MMSpecialCharacters = @"/?&.";

static NSString *const MMRouterEntityKey = @"MMRouterEntity";

static NSString *const MMRouterParameterURLKey = @"MMRouterParameterURL";

typedef NS_ENUM(NSUInteger, MMRouterType) {
    MMRouterTypeDefault = 0,
};

@implementation NSString (URLRewrite)

- (NSString *)rewriteURLWithProtocol:(NSString *)protocol {
    NSRange colonRange = [self rangeOfString:@":"];
    if (colonRange.location == NSNotFound) {
        return [NSString stringWithFormat:@"%@://%@", protocol, self];
    } else {
        NSString *result = [NSString stringWithFormat:@"%@%@", protocol, [self substringFromIndex:colonRange.location]];
        return result;
    }
}

@end

@interface MMRouterAuthorizer ()

@property (nonatomic, copy) MMRouterHandler handlerBlock;
@property (nonatomic, copy) NSString *routerURL;

@end

@implementation MMRouterAuthorizer

- (instancetype)initWithRouteURL:(NSString *)routerURL handler:(MMRouterHandler)handlerBlock {
    self = [super init];
    if (self) {
        _routerURL = routerURL;
        _handlerBlock = handlerBlock;
    }
    return self;
}

- (AuthProtocalBlock)authProtocol {
    return ^MMRouterAuthorizer *(NSString *authProtocol) {
        [MMRouter registerRouteURL:[self.routerURL rewriteURLWithProtocol:authProtocol] handler:self.handlerBlock];
        return self;
    };
}

- (BatchAuthProtocalBlock)authProtocolList {
    return ^MMRouterAuthorizer *(NSArray<NSString *> *protocolArray) {
        for (NSString *protocol in protocolArray) {
            [MMRouter registerRouteURL:[self.routerURL rewriteURLWithProtocol:protocol] handler:self.handlerBlock];
        }
        return self;
    };
}

@end

@interface MMRouterEntity : NSObject <NSCopying>

@property (nonatomic, copy) MMRouterHandler handlerBlock;
@property (nonatomic, assign) MMRouterType type;

@end

@implementation MMRouterEntity

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    MMRouterEntity *entity = [[MMRouterEntity alloc] init];
    entity.handlerBlock = self.handlerBlock;
    entity.type = self.type;
    return self;
}

@end

@interface MMRouter ()

@property (nonatomic, strong) NSMutableDictionary *routes;
@property (nonatomic, strong) NSMutableArray *routeURLList;

@end

@implementation MMRouter

+ (instancetype)sharedInstance {
    static MMRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (void)registerRouteURL:(NSString *)routeURL handler:(MMRouterHandler)handlerBlock {
    NSLog(@"registerRouteURL:%@", routeURL);
    [[self sharedInstance] addRouteURL:routeURL handler:handlerBlock];
}

+ (BOOL)routeURL:(NSString *)nsURL {
    return [self routeURL:nsURL withParameters:nil];
}

+ (BOOL)routeURL:(NSString *)nsURL withParameters:(NSDictionary<NSString *, id> *)parameters {
    NSLog(@"Route to URL:%@\nwithParameters:%@", nsURL, parameters);
    nsURL = [nsURL stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    NSMutableDictionary *routerParameters = [[self sharedInstance] achieveParametersFromURL:nsURL];
    if (!routerParameters) {
        NSLog(@"Route unregistered URL:%@", nsURL);
        return NO;
    }

    if (routerParameters) {
        MMRouterEntity *routerEntity = routerParameters[MMRouterEntityKey];
        MMRouterHandler handler = routerEntity.handlerBlock;

        if (handler) {
            if (parameters) {
                [routerParameters addEntriesFromDictionary:parameters];
            }
            [routerParameters removeObjectForKey:MMRouterEntityKey];
            handler(routerParameters);
            return YES;
        }
    }
    return NO;
}

+ (BOOL)canRoute:(NSString *)url {
    return [[MMRouter sharedInstance] achieveParametersFromURL:url] ? YES : NO;
}

- (NSMutableDictionary *)achieveParametersFromURL:(NSString *)url {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[MMRouterParameterURLKey] = [url stringByRemovingPercentEncoding];

    NSMutableDictionary *subRoutes = self.routes;
    NSArray *pathComponents = [self pathComponentsFromURL:url];

    NSInteger pathComponentsSurplus = [pathComponents count];

    for (NSString *pathComponent in pathComponents) {
        NSStringCompareOptions comparisonOptions = NSCaseInsensitiveSearch;
        NSArray *subRoutesKeys = [subRoutes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
            return [obj2 compare:obj1 options:comparisonOptions];
        }];

        for (NSString *key in subRoutesKeys) {
            if ([pathComponent isEqualToString:key]) {
                pathComponentsSurplus--;
                subRoutes = subRoutes[key];
                break;
            } else if ([key hasPrefix:@":"] && pathComponentsSurplus == 1) {
                subRoutes = subRoutes[key];
                NSString *newKey = [key substringFromIndex:1];
                NSString *newPathComponent = pathComponent;

                NSCharacterSet *specialCharacterSet = [NSCharacterSet characterSetWithCharactersInString:MMSpecialCharacters];
                NSRange range = [key rangeOfCharacterFromSet:specialCharacterSet];

                if (range.location != NSNotFound) {
                    newKey = [newKey substringToIndex:range.location - 1];
                    NSString *suffixToStrip = [key substringFromIndex:range.location];
                    newPathComponent = [newPathComponent stringByReplacingOccurrencesOfString:suffixToStrip withString:@""];
                }
                parameters[newKey] = newPathComponent;
                break;
            }
        }
    }

    if (!subRoutes[MMRouterEntityKey]) {
        return nil;
    }

    NSArray<NSURLQueryItem *> *queryItems =
    [[NSURLComponents alloc] initWithURL:[[NSURL alloc] initWithString:url] resolvingAgainstBaseURL:false].queryItems;

    for (NSURLQueryItem *item in queryItems) {
        parameters[item.name] = item.value;
    }

    parameters[MMRouterEntityKey] = [subRoutes[MMRouterEntityKey] copy];
    return parameters;
}

#pragma mark - Private Methods
- (void)addRouteURL:(NSString *)routeUrl handler:(MMRouterHandler)handlerBlock {
    if ([self.routeURLList containsObject:routeUrl]) {
        NSLog(@"has register URL:%@", routeUrl);
        return;
    }
    [self.routeURLList addObject:routeUrl];

    NSMutableDictionary *subRoutes = [self addURLPattern:routeUrl];
    if (handlerBlock && subRoutes) {
        MMRouterEntity *routerEntity = [[MMRouterEntity alloc] init];
        routerEntity.handlerBlock = handlerBlock;
        routerEntity.type = MMRouterTypeDefault;
        subRoutes[MMRouterEntityKey] = routerEntity;
    }
}

- (NSMutableDictionary *)addURLPattern:(NSString *)URLPattern {
    NSArray *pathComponents = [self pathComponentsFromURL:URLPattern];

    NSMutableDictionary *subRoutes = self.routes;

    for (NSString *pathComponent in pathComponents) {
        if (![subRoutes objectForKey:pathComponent]) {
            subRoutes[pathComponent] = [[NSMutableDictionary alloc] init];
        }
        subRoutes = subRoutes[pathComponent];
    }
    return subRoutes;
}

- (NSArray *)pathComponentsFromURL:(NSString *)URL {
    NSMutableArray *pathComponents = [NSMutableArray array];
    if ([URL rangeOfString:@"://"].location != NSNotFound) {
        NSArray *pathSegments = [URL componentsSeparatedByString:@"://"];
        [pathComponents addObject:pathSegments[0]];
        for (NSInteger idx = 1; idx < pathSegments.count; idx++) {
            if (idx == 1) {
                URL = [pathSegments objectAtIndex:idx];
            } else {
                URL = [NSString stringWithFormat:@"%@://%@", URL, [pathSegments objectAtIndex:idx]];
            }
        }
    }

    if ([URL hasPrefix:@":"]) {
        if ([URL rangeOfString:@"/"].location != NSNotFound) {
            NSArray *pathSegments = [URL componentsSeparatedByString:@"/"];
            [pathComponents addObject:pathSegments[0]];
        } else {
            [pathComponents addObject:URL];
        }
    } else {
        for (NSString *pathComponent in [[NSURL URLWithString:URL] pathComponents]) {
            if ([pathComponent isEqualToString:@"/"])
                continue;
            if ([[pathComponent substringToIndex:1] isEqualToString:@"?"])
                break;
            [pathComponents addObject:pathComponent];
        }
    }
    return [pathComponents copy];
}

#pragma mark - getter/setter
- (NSMutableDictionary *)routes {
    if (!_routes) {
        _routes = [[NSMutableDictionary alloc] init];
    }
    return _routes;
}

- (NSMutableArray *)routeURLList {
    if (_routeURLList == nil) {
        _routeURLList = [[NSMutableArray alloc] init];
    }
    return _routeURLList;
}

#pragma mark - Auth
+ (MMRouterAuthorizer *)makeRouterAuthorizer:(NSString *)routerRUL handler:(MMRouterHandler)handlerBlock {
    return [[MMRouterAuthorizer alloc] initWithRouteURL:routerRUL handler:handlerBlock];
}

@end
