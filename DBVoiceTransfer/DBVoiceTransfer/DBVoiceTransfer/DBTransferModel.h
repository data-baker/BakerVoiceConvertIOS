//
//  DBTransferModel.h
//  DBVoiceTransfer
//
//  Created by linxi on 2021/3/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DBTransferModel : NSObject
@property (nonatomic , assign) NSInteger              errcode;
@property (nonatomic , copy) NSString               * errmsg;
@property (nonatomic , assign) NSInteger              lastpkg;
@property (nonatomic , assign) NSInteger              traceid;

@end

NS_ASSUME_NONNULL_END
