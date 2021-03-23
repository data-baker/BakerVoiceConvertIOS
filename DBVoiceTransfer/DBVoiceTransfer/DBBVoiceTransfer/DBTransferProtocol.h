//
//  DBTransferProtocol.h
//  DBBVoiceTransfer
//
//  Created by linxi on 2021/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^Handler)(NSArray * array, BOOL isLast);

@protocol DBTransferProtocol <NSObject>


/// 回调麦克风录制的数据 ,isLast: yes,最后一包，NO,非最后一包
- (void)microphoneAudioData:(NSData *)data isLast:(BOOL)isLast;

/// 识别结果回调
- (void)transferCallBack:(NSData *)data isLast:(BOOL)isLast;

/// 识别错误回调
-(void)transferErrorCallBack:(NSError *)error;

/// token获取回调,log为yes为初始化成功,可以开始识别
- (void)initializationResult:(BOOL)log;

/// 已经与后台连接,可以传入音频流
- (void)onReady;

/// 错误回调 code:错误码  message:错误信息
- (void)onError:(NSInteger)code message:(NSString *)message;
/// 麦克风获取的音频分贝值回调
- (void)dbValues:(NSInteger)db;

@optional
/// 每句话识别的TraceID，用于追溯识别结果
/// @param traceId 追溯Id
- (void)resultTraceId:(NSString *)traceId;




/// 准备好了，可以开始播放了，回调
- (void)readlyToPlay;

/// 播放完成回调
- (void)playFinished;




@end

NS_ASSUME_NONNULL_END
