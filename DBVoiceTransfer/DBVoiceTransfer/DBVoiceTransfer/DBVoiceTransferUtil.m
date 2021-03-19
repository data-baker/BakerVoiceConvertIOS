//
//  DBVoiceTransferUtil.m
//  DBBVoiceTransfer
//
//  Created by linxi on 2021/3/18.
//

#import "DBVoiceTransferUtil.h"
#import <DBCommon/DBAudioMicrophone.h>
#import <DBCommon/DBSynthesisPlayer.h>
#import <DBCommon/DBZSocketRocketUtility.h>
#import <DBCommon/DBUncaughtExceptionHandler.h>
#import <DBCommon/DBLogManager.h>

#import "DBTransferModel.h"

#define kAudioFolder @"AudioFolder" // 音频文件夹

static NSString *DBErrorDomain = @"com.BiaoBeri.DBVoiceTransferUtil";
static NSString *DBFileName = @"transferPCMFile";


typedef NS_ENUM(NSUInteger,DBAsrState) {
    DBAsrStateInit  = 0, // 初始化
    DBAsrStateStart = 1, // 开始
    DBAsrStateWillEnd = 2,
    DBAsrStateDidEnd = 3  // 结束
};


@interface DBVoiceTransferUtil ()<DBPCMPlayDelegate,DBAudioMicrophoneDelegate,DBZSocketCallBcakDelegate>

@property(nonatomic,copy)NSString  * clientId;

@property(nonatomic,copy)NSString  * clientSecret;

@property(nonatomic,strong)NSString * accessToken;


@property (strong, nonatomic)DBAudioMicrophone *microphone;

@property(nonatomic,strong)DBSynthesisPlayer * player;

@property(nonatomic,strong)NSMutableDictionary* onlineRecognizeParameters;

@property(nonatomic,strong)DBZSocketRocketUtility * socketManager;

@property (nonatomic,assign) DBAsrState asrState;

@property (nonatomic, strong) NSString * socketURL;

@property (nonatomic, assign) BOOL flag;

/// Yes:需要播放; NO： 不需要播放
@property(nonatomic,assign)BOOL  needPlay;

/// 保存转换后的音频数据
@property(nonatomic,strong)NSFileHandle *  transferPCMFileHandle;

@property (copy ,nonatomic) NSString *audioDir;                 // 录音文件夹路径

@property(nonatomic,strong)NSMutableData * mutableData;

@end


@implementation DBVoiceTransferUtil

+ (instancetype)shareInstance {
    static DBVoiceTransferUtil *transferUtil = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        transferUtil = [[DBVoiceTransferUtil alloc]init];
        DBInstallUncaughtExceptionHandler();
     
    });
    return transferUtil;
}

- (void)setupClientId:(NSString *)clientId clientSecret:(NSString *)clientSecret block:(DBAuthenticationBlock)block {
    NSAssert(block, @"请设置setupClientId回调");
    [DBAuthentication setupClientId:clientId clientSecret:clientSecret block:^(NSString * _Nullable token, NSError * _Nullable error) {
        self.accessToken = token;
        block(token,error);
    }];
}

//----  MARK: 用户按钮的状态控制

- (void)startTransferNeedPlay:(BOOL)needPlay {
    
    [self removeLocalFile];
   
    
    self.needPlay = needPlay;
    [self.mutableData resetBytesInRange:NSMakeRange(0, [self.mutableData length])];
    [self startSocketAndRecognize];
}

- (void)startSocketAndRecognize {
    [self closedAudioResource];
    self.asrState = DBAsrStateStart;
    [self openMicrophone];
    self.socketManager.timeOut = 6;
    if (self.socketURL.length == 0) {
        self.socketURL = @"wss://openapi.data-baker.com/ws/voice_conversion";
    }
    self.asrState = DBAsrStateInit;
    [self.socketManager DBZWebSocketOpenWithURLString:self.socketURL];
    [self logMessage:@"socket开始链接"];
}

- (void)endRecognizeAndCloseSocket {
    self.asrState = DBAsrStateWillEnd;
}

- (void)openMicrophone {
    int sample_rate = 16000;
    self.microphone = [[DBAudioMicrophone alloc] initWithSampleRate:sample_rate numerOfChannel:1];
    self.microphone.delegate = self;
    [self logMessage:@"打开麦克风"];
    NSString *path = [self getSavePath:DBFileName];
    NSLog(@"path:%@,handle:%@",path,self.transferPCMFileHandle);
}

- (void)closedAudioResource {
    NSLog(@"----关闭音频资源----");
    self.asrState = DBAsrStateDidEnd;
    [self.socketManager DBZWebSocketClose];
    [self.microphone stop];
    [self.transferPCMFileHandle closeFile];
    [self logMessage:@"停止识别"];
}

- (void)playTransferData {
    NSLog(@"---开始播放转换后的数据----");
    
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"audio Session error :%@",error);
    }
    NSData *data = [NSData dataWithContentsOfFile:[self getSavePath:DBFileName]];
    [self.player appendData:data totalDatalength:data.length endFlag:YES];
    [self.player startPlay];
    
}



// MARK: Websocket Delegate Methods
- (void)webSocketDidOpenNote {
    [self logMessage:@"socket链接成功"];
    [self.microphone startRecord];
}


- (void)webSocketdidReceiveMessageNote:(id)object {
    [self transferResponseData:object];
}

// MARK: DBAudioMicrophoneDelegate methods
- (void)audioMicrophone:(DBAudioMicrophone *)microphone hasAudioPCMByte:(Byte *)pcmByte audioByteSize:(UInt32)byteSize {
    
    if (self.asrState == DBAsrStateDidEnd) {
        return;
    }
    
    if (self.asrState == DBAsrStateWillEnd) { // 如果准备结束了，不再继续回调数据
        self.asrState = DBAsrStateDidEnd;
        NSData*data = [[NSData alloc]initWithBytes:pcmByte length:byteSize];
        [self webSocketPostData:data];
        return;
    }
    
    NSData*data = [[NSData alloc]initWithBytes:pcmByte length:byteSize];
    [self webSocketPostData:data];
}


- (void)webSocketPostData:(NSData *)audioData {
    
    NSMutableDictionary *parameter = [NSMutableDictionary dictionary];

    if (self.asrState == DBAsrStateDidEnd) {
        parameter[@"lastpkg"] = @(YES);
    }else {
        parameter[@"lastpkg"] = @(NO);
    }
    
    parameter[@"enable_vad"] = @(self.enableVad);
    
    parameter[@"voice_name"] = self.voiceName;
    
    parameter[@"access_token"] = self.accessToken;
    
    NSData *data = [self transferData:parameter audioData:audioData];
    [self.socketManager sendData:data];
    
}

-(void)audioCallBackVoiceGrade:(NSInteger)grade {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(dbValues:)]) {
            [self.delegate dbValues:grade];
        }
    });
   
}

- (NSData *)transferData:(NSDictionary *)dict  audioData:(NSData *)audioData {
    NSLog(@"dict:%@",dict);
    
    NSData *data = [[self dictionaryToJson:dict] dataUsingEncoding:NSUTF8StringEncoding];
    
    Byte *headerData = malloc(4);
    headerData[0] = data.length >> 24 & 0xFF;
    headerData[1] = data.length >> 16 & 0xFF;
    headerData[2] = data.length >> 8  & 0xFF;
    headerData[3] = data.length       & 0xFF;
    
    NSMutableData *joinedData = [NSMutableData dataWithBytes:headerData length:4];
    [joinedData appendData:data];
    [joinedData appendData:audioData];
    return joinedData;
    
}

- (NSDictionary *)transferResponseData:(NSData *)data {
    NSDictionary *dict;
    const uint8_t *resData = [data bytes];
    NSInteger dataLength = (resData[0]<<24) + (resData[1]<<16) + (resData[2]<<8) + resData[3];
    NSData *jsonData = [data subdataWithRange:NSMakeRange(4, dataLength)];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSDictionary *jsonDict = [self dictionaryWithJsonString:jsonString];
    NSLog(@"jsonDict:%@",jsonDict);
    DBTransferModel *model = [[DBTransferModel alloc]init];
    [model setValuesForKeysWithDictionary:jsonDict];
    if (model.errcode == 10002) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(onError:message:)]) {
            [self.delegate onError:model.errcode message:model.errmsg];
        }
    }else {
        NSInteger location = 4 + dataLength;
        if (data.length - location > 0) {
            NSData *subData = [data subdataWithRange:NSMakeRange(location, data.length - location)];
            NSString *path = [self getSavePath:DBFileName];
            self.transferPCMFileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
            [self.transferPCMFileHandle seekToEndOfFile];
            [self.transferPCMFileHandle writeData:subData];
            NSLog(@"path:%@,handle:%@",path,self.transferPCMFileHandle);
            if (self.delegate && [self.delegate respondsToSelector:@selector(transferCallBack:isLast:)]) {
                [self.delegate transferCallBack:subData isLast:model.lastpkg];
            }
        }
     

        if (model.lastpkg) {
            [self closedAudioResource];
            [self playTransferData];
        }
       
    }
    
    // 解析音频数据
    return dict;
}

/// 获取音频保存的路径,转换后的音频数据
-(NSString*)getSavePath:(NSString *)fileName {

    NSString *filePath = [NSString stringWithFormat:@"audio_%@.pcm",fileName];

    NSString* fileUrlString = [self.audioDir stringByAppendingPathComponent:filePath];
    return fileUrlString;
}
- (void)removeLocalFile {
    [self removeLocalDataWithPath:DBFileName];
}

- (BOOL)removeLocalDataWithPath:(NSString *)fileName {
    NSString *filePath = [NSString stringWithFormat:@"audio_%@.pcm",fileName];
    BOOL ret = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    if (ret) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
    self.mutableData = [NSMutableData data];
    [self.mutableData writeToFile:[self getSavePath:DBFileName] atomically:YES];
    return ret;
    
}


- (NSString *)dictionaryToJson:(NSDictionary *)dic {
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:&parseError];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)dictionaryWithJsonString:(NSString *)jsonString {
    if (jsonString == nil) {
        return nil;
    }

    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:NSJSONReadingMutableContainers
                                                          error:&err];
    if (err) {
        [self logMessage:err.description];
    }
    
    return dic;
}
    

// 记录运行日志
- (void)logMessage:(NSString *)string {
    if (self.log) {
        NSLog(@"运行日志:%@",string);
        dispatch_async(dispatch_get_main_queue(), ^{
            [DBLogManager saveCriticalSDKRunData:string];
        });
    }
}
    

- (DBZSocketRocketUtility *)socketManager {
    if (!_socketManager) {
        _socketManager = [DBZSocketRocketUtility instance];
        _socketManager.delegate = self;
    }
    return _socketManager;
}
    
    

- (DBAudioMicrophone *)microphone {
    if (!_microphone) {
        _microphone = [[DBAudioMicrophone alloc]initWithSampleRate:16000 numerOfChannel:1];
        _microphone.delegate = self;
    }
    return _microphone;
}
    
- (DBSynthesisPlayer *)player {
    if (!_player) {
        _player = [[DBSynthesisPlayer alloc] init];
        _player.audioType = DBTTSAudioTypePCM16K;
    }
    return _player;
}


- (NSString *)audioDir {
    if (_audioDir==nil) {
        _audioDir = NSTemporaryDirectory();
        _audioDir = [_audioDir stringByAppendingPathComponent:kAudioFolder];
        BOOL isDir = NO;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL existed = [fileManager fileExistsAtPath:_audioDir isDirectory:&isDir];
        if (!(isDir == YES && existed == YES)){
            [fileManager createDirectoryAtPath:_audioDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return _audioDir;
}

@end
