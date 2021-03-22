//
//  DBVoiceTransferUtil.h
//  DBBVoiceTransfer
//
//  Created by linxi on 2021/3/18.
//

#import <Foundation/Foundation.h>
#import "DBTransferProtocol.h"
#import <DBCommon/DBSynthesisPlayer.h>
#import <DBCommon/DBAuthentication.h>
#import "DBTransferEnum.h"
#import "DBTransferModel.h"


NS_ASSUME_NONNULL_BEGIN


@interface DBVoiceTransferUtil : NSObject

/// 回调代理对象
@property(nonatomic,weak)id <DBTransferProtocol> delegate;

/// 1.打印日志 0:不打印日志(打印日志会在沙盒中保存一份text,方便我们查看,上线前要置为NO);
@property (nonatomic, assign) BOOL log;

@property(nonatomic,assign)BOOL enableVad;
@property(nonatomic,copy)NSString * voiceName;


+ (instancetype)shareInstance;
/// 获取token
- (void)setupClientId:(NSString *)clientId clientSecret:(NSString *)clientSecret block:(DBAuthenticationBlock)block;

/// 开始转换，是否需要播放
/// @param needPlay True: 需要播放； Flase:不需要播放
- (void)startTransferNeedPlay:(BOOL)needPlay;

/// 结束识别,结束识别并且关闭socket与麦克风
- (void)endRecognizeAndCloseSocket;


/// 本地文件转换，读取本地文件
/// @param needPlay True: 需要播放； Flase:不需要播放
- (void)startTransferWithFilePath:(NSString *)filePath needPaley:(BOOL)needPlay;

/// 结束文件变声转换并且关闭服务端连接
- (void)endFileTransferAndCloseSocket;


/// 默认保存在Temp文件夹下
/// @param fileName 文件名称
- (NSString *)getSavePath:(NSString *)fileName;


@end

NS_ASSUME_NONNULL_END
