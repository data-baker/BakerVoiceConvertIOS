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

#define kAudioFolder @"AudioFolder" // 音频文件夹

static NSString *DBErrorDomain = @"com.BiaoBeri.DBVoiceTransferUtil";
static NSString *DBFileName = @"transferPCMFile";

typedef NS_ENUM(NSUInteger,DBAsrState) {
    DBAsrStateInit  = 0, // 初始化
    DBAsrStateStart = 1, // 开始
    DBAsrStateWillEnd = 2,
    DBAsrStateDidEnd = 3  // 结束
};


@interface DBVoiceTransferUtil ()<DBSynthesisPlayerDelegate,DBAudioMicrophoneDelegate,DBZSocketCallBcakDelegate>

@property(nonatomic,copy)NSString  * clientId;

@property(nonatomic,copy)NSString  * clientSecret;

@property(nonatomic,strong)NSString * accessToken;

@property (strong, nonatomic)DBAudioMicrophone *microphone;

@property(nonatomic,strong)DBSynthesisPlayer * player;

@property(nonatomic,strong)NSMutableDictionary* onlineRecognizeParameters;

@property(nonatomic,strong)DBZSocketRocketUtility * socketManager;

@property (nonatomic,assign) DBAsrState asrState;

@property (nonatomic, strong) NSString * socketURL;

@property (nonatomic, assign) BOOL firstFlag;

/// Yes:需要播放; NO： 不需要播放
@property(nonatomic,assign)BOOL  needPlay;

/// 保存转换后的音频数据
@property(nonatomic,strong)NSFileHandle *  transferPCMFileHandle;

@property (copy ,nonatomic) NSString *audioDir;                 // 录音文件夹路径


/// isFileTransfer: Yes: 文件转换， NO: 非文件转换
@property(nonatomic,assign)BOOL isFileTransfer;

@property(nonatomic,copy)NSString * filePath;
@property (nonatomic) NSUInteger hasReadFileSize;
@property (nonatomic) int sizeToRead;
@property (nonatomic, retain) NSFileHandle *fileHandle;
@property (nonatomic, retain) NSThread *fileReadThread;


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
    [self startTransferNeedPlay:needPlay isFileTransfer:NO];
}

- (void)fileTransferNeedPlay:(BOOL)needPlay {
    [self startTransferNeedPlay:needPlay isFileTransfer:YES];
}

- (void)startTransferNeedPlay:(BOOL)needPlay isFileTransfer:(BOOL)isFileTransfer {
    [self removeLocalDataWithPath:DBFileName];
    self.needPlay = needPlay;
    self.firstFlag = YES;
    self.isFileTransfer = isFileTransfer;
    [self startSocketAndRecognize];
}

- (void)startSocketAndRecognize {
    [self closedAudioResource];
    self.socketManager.timeOut = 6;
    if (self.socketURL.length == 0) {
        self.socketURL = @"wss://openapi.data-baker.com/ws/voice_conversion";
    }
    self.asrState = DBAsrStateInit;
    [self.socketManager DBZWebSocketOpenWithURLString:self.socketURL];
    [self logMessage:@"socket开始链接"];
}

- (void)endTransferAndCloseSocket {
    self.asrState = DBAsrStateWillEnd;
}

-(void)endFileTransferAndCloseSocket {
    [self resetRecognizer];
    [self.socketManager DBZWebSocketClose];
}

// MARK: ------ 开启文件识别 ---------

- (void)startTransferWithFilePath:(NSString *)filePath needPaley:(BOOL)needPlay {
    self.filePath = filePath;
    self.isFileTransfer = YES;
    self.sizeToRead = 16000 * 0.1 * 16 / 8;
    self.hasReadFileSize = 0;
    [self fileTransferNeedPlay:needPlay];
}

- (void)resetRecognizer
{
    self.hasReadFileSize = 0;
    if (self.fileReadThread) {
        [self.fileReadThread cancel];
        while (self.fileReadThread && ![self.fileReadThread isFinished])
        {
            [NSThread sleepForTimeInterval:0.1];
        }
    }
}

- (void)openMicrophone {
    int sample_rate = 16000;
    self.microphone = [[DBAudioMicrophone alloc] initWithSampleRate:sample_rate numerOfChannel:1];
    self.microphone.delegate = self;
    [self logMessage:@"打开麦克风"];
}

- (void)closedAudioResource {
    [self logMessage:@"----关闭音频资源----"];
    self.asrState = DBAsrStateDidEnd;
    [self.socketManager DBZWebSocketClose];
    [self.microphone stop];
    [self.transferPCMFileHandle closeFile];
}

- (void)playTransferData {
    
    [self logMessage:@"---开始播放转换后的数据----"];

    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        [self logMessage:[NSString stringWithFormat:@"audio Session error :%@",error]];

    }
    NSData *data = [NSData dataWithContentsOfFile:[self getSavePath:DBFileName]];
    
    [self.player stopPlay];
    self.player = nil;
    [self.player appendData:data totalDatalength:data.length endFlag:YES];
    [self.player startPlay];
    
}

// MARK: Player的播放回调

/// 准备好了，可以开始播放了，回调
- (void)readlyToPlay {
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(readlyToPlay)]) {
        [self.delegate readlyToPlay];
    }
}

/// 播放完成回调
- (void)playFinished {
    if (self.delegate && [self.delegate respondsToSelector:@selector(playFinished)]) {
        [self.delegate playFinished];
    }
    
}



// MARK: Websocket Delegate Methods
- (void)webSocketDidOpenNote {
    [self logMessage:@"socket链接成功"];
    self.asrState = DBAsrStateStart;
    if (self.isFileTransfer) {
        NSThread *fileReadThread = [[NSThread alloc] initWithTarget:self
                                                           selector:@selector(fileReadThreadFunc)
                                                             object:nil];
        self.fileReadThread = fileReadThread;
        [self.fileReadThread start];
        
    }else {
        BOOL grant = [self reuestMicroGrant];
        
        if (!grant) {
            [self logMessage:@"未获取麦克风权限"];
            [self delegateErrorCode:DBErrorStateMicrophoneNoGranted message:@"没有麦克风权限"];
            [self closedAudioResource];
            return;
        }
        
        [self delegateReadyToTransfer];
        [self openMicrophone];
        [self.microphone startRecord];
        
        
        
    }
    
}

- (void)fileReadThreadFunc
{
    while ([self.fileReadThread isCancelled] == NO) {
        //间隔一定时长获取语音，模拟人的正常语速
        [NSThread sleepForTimeInterval:0.01];
        self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
        if (!self.fileHandle) {
            [self logMessage:self.filePath];
            [self logMessage:@"打开本地文件失败"];
            [self.fileReadThread cancel];
            [self delegateErrorCode:DBErrorStateFileReadFailed message:@"本地文件打开失败"];
            return;
        }
        [self.fileHandle seekToFileOffset:self.hasReadFileSize];
        NSData* data = [self.fileHandle readDataOfLength:self.sizeToRead];
        [self.fileHandle closeFile];
        self.hasReadFileSize += [data length];
        if ([data length] == 0) {
            self.asrState = DBAsrStateDidEnd;
            [self webSocketPostData:data];
            break;
        }else {
            [self webSocketPostData:data];

        }
    }
}


- (void)webSocketdidReceiveMessageNote:(id)object {
    [self transferResponseData:object];
}

- (void)webSocketDidCloseNote:(id)object {
    [self logMessage:@"服务器连接关闭"];
}


- (void)webSocketdidConnectFailed:(id)object {
    [self logMessage:@"服务器连接关闭"];
}


// MARK: DBAudioMicrophoneDelegate methods
- (void)audioMicrophone:(DBAudioMicrophone *)microphone hasAudioPCMByte:(Byte *)pcmByte audioByteSize:(UInt32)byteSize {
    NSData*data = [[NSData alloc]initWithBytes:pcmByte length:byteSize];

    if (self.asrState == DBAsrStateDidEnd) {
        return;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(microphoneAudioData:isLast:)]) {
        if (self.asrState == DBAsrStateWillEnd) {
            [self.delegate microphoneAudioData:data isLast:YES];
        }else {
            [self.delegate microphoneAudioData:data isLast:NO];
        }
    }
    
    if (self.asrState == DBAsrStateWillEnd) { // 如果准备结束了，不再继续回调数据
        self.asrState = DBAsrStateDidEnd;
        NSData*data = [[NSData alloc]initWithBytes:pcmByte length:byteSize];
        [self webSocketPostData:data];
        return;
    }
    
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

// MARK: --- 开始转换数据 ----
- (void)transferResponseData:(NSData *)data {
    if (data.length < 4 ) {
        [self delegateErrorCode:DBErrorStateParsing message:@"网络数据解析失败"];
        return;
    }
    const uint8_t *resData = [data bytes];
    NSInteger dataLength = (resData[0]<<24) + (resData[1]<<16) + (resData[2]<<8) + resData[3];
    NSData *jsonData = [data subdataWithRange:NSMakeRange(4, dataLength)];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSDictionary *jsonDict = [self dictionaryWithJsonString:jsonString];
    DBTransferModel *model = [[DBTransferModel alloc]init];
    [model setValuesForKeysWithDictionary:jsonDict];
    if (model.errcode != 0) {
        [self delegateErrorCode:model.errcode message:model.errmsg];
        return ;
    }
    
    
    NSInteger location = 4 + dataLength;
    if (data.length - location > 0) {
        NSData *subData = [data subdataWithRange:NSMakeRange(location, data.length - location)];
        if (self.firstFlag) {
            [subData writeToFile:[self getSavePath:DBFileName] atomically:YES];
            self.firstFlag = NO;
        }else {
            NSString *path = [self getSavePath:DBFileName];
            self.transferPCMFileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
            [self.transferPCMFileHandle seekToEndOfFile];
            [self.transferPCMFileHandle writeData:subData];
            [self logMessage:[NSString stringWithFormat:@"path:%@",path]];
        }
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(transferCallBack:isLast:)]) {
            [self.delegate transferCallBack:subData isLast:model.lastpkg];
        }
    }
    
    if (model.lastpkg) {
        [self closedAudioResource];
        if (self.needPlay) {
            [self playTransferData];
        }
    }
}
    // 解析音频数据


/// 获取音频保存的路径,转换后的音频数据
-(NSString*)getSavePath:(NSString *)fileName {
    
    NSString *filePath = [NSString stringWithFormat:@"audio_%@.pcm",fileName];
    NSString* fileUrlString = [self.audioDir stringByAppendingPathComponent:filePath];
    return fileUrlString;
}

- (BOOL)removeLocalDataWithPath:(NSString *)fileName {
    NSString *path = [self getSavePath:DBFileName];
    BOOL ret = [[NSFileManager defaultManager] fileExistsAtPath:path];
    if (ret) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
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
    
- (void)delegateErrorCode:(NSInteger)code message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(onError:message:)]) {
            [self.delegate onError:code message:message];
        }
    });
 
}

- (void)delegateReadyToTransfer {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(readyToTransfer)]) {
            [self.delegate readyToTransfer];
        }
    });
    
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
        _player.delegate = (id)self;
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

- (BOOL)reuestMicroGrant {
    
    dispatch_semaphore_t waitMicrophonePermission = dispatch_semaphore_create(0);
    
    __block BOOL hasMicrophonePermission = true;
       if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
           [[AVAudioSession sharedInstance] performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
               hasMicrophonePermission = granted;
               dispatch_semaphore_signal(waitMicrophonePermission);
            
           }];
           
           dispatch_semaphore_wait(waitMicrophonePermission, DISPATCH_TIME_FOREVER);
       }
    return hasMicrophonePermission;
}


@end